"""Application state and background orchestration for DeepL-oFM for Windows.

Ported from ``Sources/HyMT/AppState.swift`` (state, debounce, history, hotkeys,
progress) without any SwiftUI/AppKit dependency: the controller is a plain
``QObject`` that owns the settings, the history store and the worker jobs, and
exposes everything the views need through signals.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path
from typing import Any, Callable

from PySide6.QtCore import QMimeData, QObject, QRunnable, QThreadPool, QTimer, Signal
from PySide6.QtGui import QGuiApplication

from .core.languages import (
    AppLanguage,
    Language,
    LanguageTable,
    detect_language,
    get_language,
)
from .core.prompts import TranslationStyle, TranslationTone
from .core.settings import AppSettings
from .i18n import set_language, t
from .services.documents import DocumentError, DocumentTranslator, DocumentKind, OpenedDocument
from .services.history import HistoryEntry, HistoryStore
from .services.translation import (
    TranslationCancelled,
    TranslationError,
    TranslationOutput,
    Translator,
)

log = logging.getLogger(__name__)

TABS = ("translate", "files", "write", "history")
RESULT_VIEWS = ("preview", "text", "markdown")


class _JobSignals(QObject):
    """Signals for one background job (created in the GUI thread, emitted from a worker)."""

    progress = Signal(int, int)
    partial = Signal(str)
    finished = Signal(object)
    failed = Signal(object)


class _Job(QRunnable):
    """Runs ``fn(signals)`` in the global thread pool."""

    def __init__(self, fn: Callable[[_JobSignals], Any], signals: _JobSignals | None = None) -> None:
        super().__init__()
        self.signals = signals or _JobSignals()
        self._fn = fn
        self.setAutoDelete(True)

    def run(self) -> None:  # noqa: D401 - QRunnable API
        try:
            result = self._fn(self.signals)
        except BaseException as exc:  # noqa: BLE001 - transported to the GUI thread
            self.signals.failed.emit(exc)
        else:
            self.signals.finished.emit(result)


class AppController(QObject):
    """Owns application state; views read attributes and call the command methods."""

    # --- state notifications -------------------------------------------------
    sourceTextChanged = Signal(str)
    translatedTextChanged = Signal(str)
    progressChanged = Signal(int, int)
    translatingChanged = Signal(bool)
    warningCountChanged = Signal(int)
    errorRaised = Signal(str)
    detectedLanguageChanged = Signal(str)
    languagesChanged = Signal(str, str)
    styleChanged = Signal(str)
    toneChanged = Signal(str)
    resultViewChanged = Signal(str)
    backendStatusChanged = Signal(str)
    probeMessageChanged = Signal(str)
    modelsChanged = Signal(list)
    fallbackModelsChanged = Signal(list)
    modelsLoadingChanged = Signal(bool)
    fallbackModelsLoadingChanged = Signal(bool)
    modelsErrorChanged = Signal(str)
    fallbackModelsErrorChanged = Signal(str)
    settingsChanged = Signal()
    interfaceLanguageChanged = Signal(str)
    tabChanged = Signal(str)
    historyChanged = Signal()
    fileJobChanged = Signal(dict)
    speakingChanged = Signal(str)
    copyFeedback = Signal(str)
    writeFinished = Signal(str)
    writeStateChanged = Signal(bool)
    windowRequested = Signal()
    hotkeyStatusChanged = Signal(str, str)  # action, message
    metricsChanged = Signal()

    def __init__(
        self,
        settings: AppSettings | None = None,
        history: HistoryStore | None = None,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.settings = settings or AppSettings()
        self.history = history or HistoryStore()
        self.translator = Translator()
        self.pool = QThreadPool.globalInstance()

        # --- tab / panes -----------------------------------------------------
        self.tab: str = "translate"
        self.source_text: str = ""
        self.translated_text: str = ""

        # --- translation state ----------------------------------------------
        self.is_translating: bool = False
        self.completed: int = 0
        self.total: int = 0
        self.warning_count: int = 0
        self.error_message: str | None = None
        self.tokens_per_second: float | None = None
        self.last_duration_ms: int | None = None
        self.using_fallback: bool = False

        # --- languages -------------------------------------------------------
        self.source_language: Language = get_language(self.settings.last_source_code) or LanguageTable.AUTO
        self.target_language: Language = get_language(self.settings.last_target_code) or get_language("en")
        self.detected_language: Language | None = None

        # --- style -----------------------------------------------------------
        self.style: TranslationStyle = self.settings.last_style
        self.tone: TranslationTone = self.settings.last_tone
        self.result_view: str = self.settings.result_view if self.settings.result_view in RESULT_VIEWS else "preview"

        # --- backend ---------------------------------------------------------
        self.backend_status: str = "unknown"
        self.probe_message: str = ""
        self.provider_models: list[str] = []
        self.models_loading: bool = False
        self.models_error: str | None = None
        self.fallback_models: list[str] = []
        self.fallback_models_loading: bool = False
        self.fallback_models_error: str | None = None

        # --- hotkeys / speech ------------------------------------------------
        self.hotkey_message: str = ""
        self.selection_hotkey_message: str = ""
        self.speaking: str = ""

        # --- files -----------------------------------------------------------
        self.file_job: dict[str, Any] | None = None
        self._file_document: OpenedDocument | None = None
        self._file_output: Path | None = None

        # --- write -----------------------------------------------------------
        self.write_in_progress: bool = False
        self.write_output: str = ""
        self.write_error: str | None = None
        self.write_warning_count: int = 0

        # --- internals -------------------------------------------------------
        self._generation = 0
        self._cancel = threading.Event()
        self._file_cancel = threading.Event()
        self._write_cancel = threading.Event()
        self._booted = False
        self._last_completed_key: tuple[str, str, str] | None = None
        self._suppress_auto = False

        self._detect_timer = QTimer(self)
        self._detect_timer.setSingleShot(True)
        self._detect_timer.setInterval(300)
        self._detect_timer.timeout.connect(self._run_detection)

        self._auto_timer = QTimer(self)
        self._auto_timer.setSingleShot(True)
        self._auto_timer.timeout.connect(lambda: self.translate(force=False))

        set_language(self.settings.interface_language)

    # ------------------------------------------------------------------ utils
    def _emit_error(self, message: str) -> None:
        self.error_message = message
        self.errorRaised.emit(message)

    def _set_backend_status(self, status: str, message: str = "") -> None:
        self.backend_status = status
        self.backendStatusChanged.emit(status)
        if message or self.probe_message:
            self.probe_message = message
            self.probeMessageChanged.emit(message)

    def _language_name(self, language: Language | None) -> str:
        if language is None:
            return ""
        return language.display_name(self.settings.interface_language)

    def _engine_label(self) -> str:
        config = self.settings.snapshot()
        model = config.model or "?"
        return f"{self.settings.provider.title} · {model}"

    # -------------------------------------------------------------- lifecycle
    def bootstrap(self) -> None:
        """First run: probe the backend and optionally warm up the model."""
        if self._booted:
            return
        self._booted = True
        self._set_backend_status("checking", t("Connecting…"))
        self.check_connection()
        if self.settings.warm_up_on_launch:
            self._warm_up()

    def _warm_up(self) -> None:
        config = self.settings.snapshot()
        if not config.model:
            return

        def job(signals: _JobSignals) -> bool:
            return self.translator.warm_up(config)

        self._run_job(job, on_done=self._warm_up_done, on_error=lambda exc: self._set_backend_status("failed", str(exc)))

    def _warm_up_done(self, ok: bool) -> None:
        if ok:
            self._set_backend_status("connected", t("Connected"))

    # --------------------------------------------------------------- language
    def set_source_language(self, code: str) -> None:
        language = get_language(code)
        if language is None or language.code == self.source_language.code:
            return
        self.source_language = language
        self.settings.last_source_code = language.code
        self.settings.save()
        self.languagesChanged.emit(self.source_language.code, self.target_language.code)
        self._schedule_translation()

    def set_target_language(self, code: str) -> None:
        language = get_language(code)
        if language is None or language.code == self.target_language.code:
            return
        self.target_language = language
        self.settings.last_target_code = language.code
        self.settings.save()
        self.languagesChanged.emit(self.source_language.code, self.target_language.code)
        self._schedule_translation()

    def swap_languages(self) -> None:
        source = self.source_language
        target = self.target_language
        if source.is_auto:
            detected = self.detected_language or detect_language(self.source_text)
            if detected is None:
                return
            source = detected
        if source.code == target.code:
            return
        self.source_language = target
        self.target_language = source
        self.settings.last_source_code = self.source_language.code
        self.settings.last_target_code = self.target_language.code
        self.settings.save()
        self.languagesChanged.emit(self.source_language.code, self.target_language.code)
        self.translate(force=True)

    def _schedule_detection(self) -> None:
        self._detect_timer.start()

    def _run_detection(self) -> None:
        if not self.source_language.is_auto:
            return
        detected = detect_language(self.source_text, self.settings.interface_language)
        self.detected_language = detected
        self.detectedLanguageChanged.emit(detected.code if detected else "")

    def _resolved_source(self) -> Language:
        if not self.source_language.is_auto:
            return self.source_language
        return self.detected_language or detect_language(self.source_text) or get_language("en")

    # ------------------------------------------------------------- text state
    def set_source_text(self, text: str, *, from_user: bool = True) -> None:
        if text == self.source_text:
            return
        self.source_text = text
        if not text.strip():
            self.translated_text = ""
            self.translatedTextChanged.emit("")
            self.warning_count = 0
            self.warningCountChanged.emit(0)
            self.completed = self.total = 0
            self.progressChanged.emit(0, 0)
        self.sourceTextChanged.emit(text)
        if self.source_language.is_auto:
            self._schedule_detection()
        if from_user:
            self._schedule_translation()

    def _schedule_translation(self) -> None:
        if self._suppress_auto or not self.settings.auto_translate:
            return
        if not self.source_text.strip():
            return
        self._auto_timer.setInterval(max(80, int(self.settings.debounce * 1000)))
        self._auto_timer.start()

    def clear_source(self) -> None:
        self.set_source_text("")
        self.error_message = None
        self.completed = self.total = 0
        self.progressChanged.emit(0, 0)

    def set_result_view(self, mode: str) -> None:
        if mode not in RESULT_VIEWS or mode == self.result_view:
            return
        self.result_view = mode
        self.settings.result_view = mode
        self.settings.save()
        self.resultViewChanged.emit(mode)

    def set_style(self, style: TranslationStyle | str) -> None:
        value = TranslationStyle(style)
        if value == self.style:
            return
        self.style = value
        self.settings.last_style = value
        self.settings.save()
        self.styleChanged.emit(value.value)

    def set_tone(self, tone: TranslationTone | str) -> None:
        value = TranslationTone(tone)
        if value == self.tone:
            return
        self.tone = value
        self.settings.last_tone = value
        self.settings.save()
        self.toneChanged.emit(value.value)

    def set_tab(self, tab: str) -> None:
        if tab not in TABS or tab == self.tab:
            return
        self.tab = tab
        self.tabChanged.emit(tab)

    # ------------------------------------------------------------- translation
    def translate(self, force: bool = False) -> None:
        text = self.source_text
        if not text.strip():
            return
        if self.is_translating and not force:
            return

        source = self._resolved_source()
        target = self.target_language
        if source.code == target.code:
            target = self._alternative_target(source)
        config = self.settings.snapshot()
        if not config.model:
            self._emit_error(t("Choose a model in Settings."))
            return

        key = (text, source.code, target.code)
        if not force and key == self._last_completed_key and self.translated_text:
            return

        self._generation += 1
        generation = self._generation
        self._cancel = threading.Event()
        cancel = self._cancel
        self.is_translating = True
        self.translatingChanged.emit(True)
        self.error_message = None
        self.warning_count = 0
        self.warningCountChanged.emit(0)
        self.completed = self.total = 0
        self.progressChanged.emit(0, 0)
        self.using_fallback = False

        style, tone = self.style, self.tone
        fallback = self.settings.fallback_config()
        if fallback is not None and fallback.uses_same_endpoint(config):
            fallback = None  # retrying the same endpoint would just fail twice
        translator = self.translator

        def job(signals: _JobSignals) -> TranslationOutput:
            return translator.translate(
                text,
                source=source,
                target=target,
                style=style,
                tone=tone,
                config=config,
                fallback=fallback,
                on_progress=lambda done, total: signals.progress.emit(done, total),
                on_partial=lambda partial: signals.partial.emit(partial),
                cancel=cancel,
            )

        def done(result: TranslationOutput) -> None:
            if generation != self._generation:
                return
            self._finish_translation(result, text, source, target)

        def failed(exc: BaseException) -> None:
            if generation != self._generation:
                return
            self._fail_translation(exc)

        self._run_job(job, on_done=done, on_error=failed, on_progress=self._on_progress)

    def _alternative_target(self, source: Language) -> Language:
        interface = self.settings.interface_language.resolved
        if interface.value not in (source.code, "system"):
            candidate = get_language(interface.value)
            if candidate is not None:
                return candidate
        return get_language("en") if source.code != "en" else get_language("uk")

    def _on_progress(self, completed: int, total: int) -> None:
        self.completed, self.total = completed, total
        self.progressChanged.emit(completed, total)

    def _finish_translation(
        self, result: TranslationOutput, text: str, source: Language, target: Language
    ) -> None:
        self.is_translating = False
        self.translatingChanged.emit(False)
        self.translated_text = result.text
        self.translatedTextChanged.emit(result.text)
        self.warning_count = result.warnings
        self.warningCountChanged.emit(result.warnings)
        self.tokens_per_second = result.tokens_per_second
        self.last_duration_ms = result.duration_ms
        self.using_fallback = result.used_fallback
        self.metricsChanged.emit()
        self.completed = self.total
        self.progressChanged.emit(self.completed, self.total)
        self._last_completed_key = (text, source.code, target.code)
        if result.warnings:
            self._emit_error(
                t("Some paragraphs are still in the original language (%d).") % result.warnings
            )
        if self.settings.keep_history and result.text.strip():
            self.history.add(
                HistoryEntry(
                    source_text=text,
                    translated_text=result.text,
                    source_code=source.code,
                    target_code=target.code,
                    style=self.style.value,
                    tone=self.tone.value,
                    engine=self._engine_label(),
                    duration_ms=result.duration_ms or 0,
                )
            )
            self.historyChanged.emit()

    def _fail_translation(self, exc: BaseException) -> None:
        self.is_translating = False
        self.translatingChanged.emit(False)
        if isinstance(exc, TranslationCancelled):
            self.completed = self.total = 0
            self.progressChanged.emit(0, 0)
            return
        if isinstance(exc, TranslationError):
            self._emit_error(exc.message(self.settings.interface_language))
        else:  # pragma: no cover - unexpected
            log.exception("translation failed", exc_info=exc)
            self._emit_error(str(exc))

    def cancel(self) -> None:
        if not self.is_translating:
            return
        self._cancel.set()
        self._generation += 1
        self.is_translating = False
        self.translatingChanged.emit(False)
        self.completed = self.total = 0
        self.progressChanged.emit(0, 0)

    # --------------------------------------------------------------- clipboard
    def copy_translation(self) -> None:
        self._copy_text(self.translated_text, t("Translation copied"))

    def copy_source(self) -> None:
        self._copy_text(self.source_text, t("Source text copied"))

    def _copy_text(self, markdown: str, feedback: str) -> None:
        if not markdown.strip():
            return
        clipboard = QGuiApplication.clipboard()
        mime = QMimeData()
        mime.setText(markdown)
        try:
            try:
                from .ui.markdown_view import markdown_to_html, markdown_to_rtf
            except ImportError:  # private aliases while the renderer evolves
                from .ui.markdown_view import _document_html as markdown_to_html
                from .ui.markdown_view import _document_rtf as markdown_to_rtf

            mime.setHtml(markdown_to_html(markdown))
            mime.setData("text/rtf", markdown_to_rtf(markdown).encode("latin-1", "replace"))
        except Exception:  # noqa: BLE001 - rich formats are a bonus
            log.debug("rich clipboard formats unavailable", exc_info=True)
        clipboard.setMimeData(mime)
        self.copyFeedback.emit(feedback)

    def translate_clipboard(self) -> None:
        text = QGuiApplication.clipboard().text()
        if not text.strip():
            self._emit_error(t("The clipboard is empty."))
            return
        self.windowRequested.emit()
        self._suppress_auto = True
        self.set_source_text(text)
        self._suppress_auto = False
        self.translate(force=True)

    def translate_selection(self) -> None:
        """Copy the selection of the foreground app, then translate it."""
        self.windowRequested.emit()
        text = _capture_selection()
        if not text.strip():
            self._emit_error(t("Selected text does not copy"))
            return
        self._suppress_auto = True
        self.set_source_text(text)
        self._suppress_auto = False
        self.translate(force=True)

    # ------------------------------------------------------------------ speech
    def speak(self, target: str) -> None:
        try:
            from .services.speech import Speaker
        except Exception:  # noqa: BLE001
            return
        speaker = getattr(self, "_speaker", None)
        if speaker is None:
            speaker = Speaker(self)
            speaker.started.connect(self._on_speaking_started)
            speaker.finished.connect(self._on_speaking_finished)
            self._speaker = speaker
        text = self.source_text if target == "source" else self.translated_text
        if not text.strip():
            return
        language = self._resolved_source() if target == "source" else self.target_language
        speaker.speak(
            text,
            self.settings.speech_voice_id,
            target,
            language_code=language.code if language is not None else "",
        )

    def stop_speaking(self) -> None:
        speaker = getattr(self, "_speaker", None)
        if speaker is not None:
            speaker.stop()

    def _on_speaking_started(self, target: str) -> None:
        self.speaking = target
        self.speakingChanged.emit(target)

    def _on_speaking_finished(self, target: str) -> None:
        if self.speaking == target:
            self.speaking = ""
            self.speakingChanged.emit("")

    # ---------------------------------------------------------------- backend
    def check_connection(self) -> None:
        config = self.settings.snapshot()

        def job(_signals: _JobSignals) -> list[str]:
            return self.translator.list_models(config)

        self._set_backend_status("checking", t("Connecting…"))
        self._run_job(job, on_done=self._connection_ok, on_error=self._connection_failed)

    def _connection_ok(self, models: list[str]) -> None:
        self._set_backend_status("connected", t("Connected"))
        if models and not self.provider_models:
            self.provider_models = models
            self.modelsChanged.emit(models)

    def _connection_failed(self, exc: BaseException) -> None:
        message = exc.message(self.settings.interface_language) if isinstance(exc, TranslationError) else str(exc)
        self._set_backend_status("failed", message)

    def connect_and_load_models(self) -> None:
        config = self.settings.snapshot()
        self.models_loading = True
        self.models_error = None
        self.modelsLoadingChanged.emit(True)
        self.modelsErrorChanged.emit("")

        def job(_signals: _JobSignals) -> list[str]:
            return self.translator.list_models(config)

        def done(models: list[str]) -> None:
            self.models_loading = False
            self.modelsLoadingChanged.emit(False)
            self.provider_models = models
            self.modelsChanged.emit(models)
            self._set_backend_status("connected", t("Connected"))
            if not models:
                self.models_error = t("The server returned no models.")
                self.modelsErrorChanged.emit(self.models_error)

        def failed(exc: BaseException) -> None:
            self.models_loading = False
            self.modelsLoadingChanged.emit(False)
            message = exc.message(self.settings.interface_language) if isinstance(exc, TranslationError) else str(exc)
            self.models_error = message
            self.modelsErrorChanged.emit(message)
            self._set_backend_status("failed", message)

        self._run_job(job, on_done=done, on_error=failed)

    def load_fallback_models(self) -> None:
        config = self.settings.fallback_probe_config()
        self.fallback_models_loading = True
        self.fallbackModelsLoadingChanged.emit(True)
        self.fallbackModelsErrorChanged.emit("")

        def job(_signals: _JobSignals) -> list[str]:
            return self.translator.list_models(config)

        def done(models: list[str]) -> None:
            self.fallback_models_loading = False
            self.fallbackModelsLoadingChanged.emit(False)
            self.fallback_models = models
            self.fallbackModelsChanged.emit(models)

        def failed(exc: BaseException) -> None:
            self.fallback_models_loading = False
            self.fallbackModelsLoadingChanged.emit(False)
            message = exc.message(self.settings.interface_language) if isinstance(exc, TranslationError) else str(exc)
            self.fallback_models_error = message
            self.fallbackModelsErrorChanged.emit(message)

        self._run_job(job, on_done=done, on_error=failed)

    def apply_catalog_entry(self, entry: Any) -> None:
        self.settings.apply_catalog_entry(entry)
        self.settings.save()
        self.settingsChanged.emit()
        self.connect_and_load_models()

    # --------------------------------------------------------------- settings
    def save_settings(self) -> None:
        self.settings.save()
        self.settingsChanged.emit()
        if self.settings.auto_translate:
            self._schedule_translation()

    def set_interface_language(self, language: AppLanguage | str) -> None:
        value = language if isinstance(language, AppLanguage) else AppLanguage(str(language))
        if value == self.settings.interface_language:
            return
        self.settings.interface_language = value
        self.settings.save()
        set_language(value)
        self.interfaceLanguageChanged.emit(value.value)

    # ---------------------------------------------------------------- history
    def load_history_entry(self, entry_id: str) -> None:
        entry = next((item for item in self.history.entries if item.id == entry_id), None)
        if entry is None:
            return
        self._suppress_auto = True
        self.set_source_text(entry.source_text)
        self._suppress_auto = False
        self.translated_text = entry.translated_text
        self.translatedTextChanged.emit(entry.translated_text)
        source = get_language(entry.source_code)
        target = get_language(entry.target_code)
        if source is not None:
            self.source_language = source
        if target is not None:
            self.target_language = target
        self.languagesChanged.emit(self.source_language.code, self.target_language.code)
        self.style = TranslationStyle(entry.style) if entry.style in TranslationStyle._value2member_map_ else self.style
        self.tone = TranslationTone(entry.tone) if entry.tone in TranslationTone._value2member_map_ else self.tone
        self._last_completed_key = (entry.source_text, entry.source_code, entry.target_code)
        self.set_tab("translate")
        self.windowRequested.emit()

    # ------------------------------------------------------------------ files
    def start_file_translation(self, path: Path, target_code: str | None = None) -> None:
        path = Path(path)
        target = get_language(target_code) if target_code else self.target_language
        if target is None:
            target = self.target_language
        config = self.settings.snapshot()
        if not config.model:
            self._emit_error(t("Choose a model in Settings."))
            return

        self._file_cancel = threading.Event()
        cancel = self._file_cancel
        self.file_job = {
            "path": str(path),
            "name": path.name,
            "kind": (DocumentKind.from_path(path).value if DocumentKind.from_path(path) else ""),
            "state": "reading",
            "completed": 0,
            "total": 0,
            "percent": 0,
            "output": None,
            "message": None,
            "result_name": None,
            "warnings": 0,
        }
        self._file_document = None
        self._file_output = None
        self._publish_file_job()

        translator = self.translator
        style, tone = self.style, self.tone
        fallback = self.settings.fallback_config()
        source = self.source_language
        settings = self.settings

        def translate_paragraph(text: str) -> str:
            result = translator.translate(
                text,
                source=source,
                target=target,
                style=style,
                tone=tone,
                config=config,
                fallback=fallback,
                cancel=cancel,
            )
            return result.text

        def job(signals: _JobSignals) -> Path:
            document = DocumentTranslator.read(path)
            self._file_document = document
            self._update_file_job(state="translating")
            out_path = DocumentTranslator.suggested_path(path, target)
            DocumentTranslator.write(
                document,
                out_path,
                translate_paragraph,
                on_progress=lambda done, total: signals.progress.emit(done, total),
                cancel=cancel,
            )
            return out_path

        def done(out_path: Path) -> None:
            self._file_output = out_path
            self._update_file_job(
                state="done",
                percent=100,
                output=str(out_path),
                result_name=out_path.name,
            )

        def failed(exc: BaseException) -> None:
            if isinstance(exc, TranslationCancelled):
                self._update_file_job(state="cancelled", message=t("Cancelled"))
                return
            if isinstance(exc, (DocumentError, TranslationError)):
                message = exc.message(settings.interface_language)
            else:
                log.exception("file translation failed", exc_info=exc)
                message = str(exc)
            self._update_file_job(state="failed", message=message)

        self._run_job(job, on_done=done, on_error=failed, on_progress=self._on_file_progress)

    def _on_file_progress(self, completed: int, total: int) -> None:
        percent = int(round(completed * 100 / total)) if total else 0
        self._update_file_job(completed=completed, total=total, percent=percent)

    def _update_file_job(self, **changes: Any) -> None:
        if self.file_job is None:
            return
        self.file_job.update(changes)
        if "completed" in changes and changes.get("total"):
            self.file_job["percent"] = int(round(changes["completed"] * 100 / changes["total"]))
        self._publish_file_job()

    def _publish_file_job(self) -> None:
        self.fileJobChanged.emit(dict(self.file_job) if self.file_job else {})

    def cancel_file_translation(self) -> None:
        self._file_cancel.set()

    def save_translated_file(self, destination: Path) -> None:
        if self._file_output is None:
            self._emit_error(t("The file could not be translated."))
            return
        try:
            destination = Path(destination)
            destination.write_bytes(self._file_output.read_bytes())
        except OSError as exc:
            log.exception("could not save translated file")
            self._emit_error(str(exc))
            return
        self._update_file_job(output=str(destination), result_name=destination.name)
        self.copyFeedback.emit(t("Saved"))

    def clear_file_job(self) -> None:
        self.file_job = None
        self._file_document = None
        self._file_output = None
        self._publish_file_job()

    # ------------------------------------------------------------------ write
    def write_text(self, text: str, target_code: str) -> None:
        if not text.strip() or self.write_in_progress:
            return
        config = self.settings.snapshot()
        if not config.model:
            self._emit_error(t("Choose a model in Settings."))
            return
        target = get_language(target_code) or self.target_language
        self._write_cancel = threading.Event()
        cancel = self._write_cancel
        self.write_in_progress = True
        self.write_output = ""
        self.write_error = None
        self.write_warning_count = 0
        self.writeStateChanged.emit(True)
        translator = self.translator
        fallback = self.settings.fallback_config()

        def job(_signals: _JobSignals) -> TranslationOutput:
            return translator.rewrite(text, target=target, config=config, fallback=fallback, cancel=cancel)

        def done(result: TranslationOutput) -> None:
            self.write_output = result.text
            self.write_warning_count = result.warnings
            self.write_in_progress = False
            self.writeStateChanged.emit(False)
            # Deliberately not translatedTextChanged: the Write tab has its own
            # pane, and reusing the translate signal would overwrite it.
            self.writeFinished.emit(result.text)

        def failed(exc: BaseException) -> None:
            self.write_in_progress = False
            if isinstance(exc, TranslationCancelled):
                self.write_error = None
                self.writeStateChanged.emit(False)
                return
            self.write_error = exc.message(self.settings.interface_language) if isinstance(exc, TranslationError) else str(exc)
            self.writeStateChanged.emit(False)
            self._emit_error(self.write_error)

        self._run_job(job, on_done=done, on_error=failed)

    def cancel_write(self) -> None:
        self._write_cancel.set()
        if self.write_in_progress:
            self.write_in_progress = False
            self.writeStateChanged.emit(False)

    # -------------------------------------------------------------- shutdown
    def shutdown(self, timeout_ms: int = 3000) -> None:
        """Cancel running work and wait briefly for the workers to unwind."""
        for event in (self._cancel, self._file_cancel, self._write_cancel):
            event.set()
        self._auto_timer.stop()
        self._detect_timer.stop()
        try:
            self.pool.waitForDone(timeout_ms)
        except Exception:  # noqa: BLE001 - shutdown must never raise
            log.debug("thread pool did not drain cleanly", exc_info=True)
        speaker = getattr(self, "_speaker", None)
        if speaker is not None:
            try:
                speaker.stop()
            except Exception:  # noqa: BLE001
                pass

    # ------------------------------------------------------------------ jobs
    def _run_job(
        self,
        fn: Callable[[_JobSignals], Any],
        *,
        on_done: Callable[[Any], None],
        on_error: Callable[[BaseException], None],
        on_progress: Callable[[int, int], None] | None = None,
    ) -> _JobSignals:
        # Parenting the signal holder to the controller keeps the QObject alive
        # for the whole job: a Python-only reference would be collected while the
        # worker thread is still running and the queued signals would be lost.
        signals = _JobSignals(self)
        signals.finished.connect(on_done)
        signals.failed.connect(on_error)
        if on_progress is not None:
            signals.progress.connect(on_progress)
        self.pool.start(_Job(fn, signals))
        return signals


# --------------------------------------------------------------------------
# Selected-text capture (Windows: send Ctrl+C to the foreground window)
# --------------------------------------------------------------------------
def _capture_selection() -> str:
    """Copy the current selection of the foreground application to the clipboard."""
    if os.name != "nt":
        return ""
    try:
        import ctypes

        user32 = ctypes.windll.user32
        keybd_event = user32.keybd_event
        VK_CONTROL, VK_C, KEYEVENTF_KEYUP = 0x11, 0x43, 0x0002
        keybd_event(VK_CONTROL, 0, 0, 0)
        keybd_event(VK_C, 0, 0, 0)
        keybd_event(VK_C, 0, KEYEVENTF_KEYUP, 0)
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)
        time.sleep(0.12)
    except Exception:  # noqa: BLE001 - best effort
        log.debug("selection capture failed", exc_info=True)
    app = QGuiApplication.instance()
    if app is None:
        return ""
    return QGuiApplication.clipboard().text()
