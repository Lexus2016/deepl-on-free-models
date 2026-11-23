"""Model catalogue dialog.

Port of ``Sources/HyMT/Views/ModelCatalogView.swift``: one card per curated
model with its identifier, provider, size, languages, note and install command,
plus provider/search filters and a single-click "Use this model" action.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from PySide6.QtCore import QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QGuiApplication, QPainter
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QScrollArea,
    QSizePolicy,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from ..core.catalog import ModelCatalog
from ..core.providers import Provider
from ..i18n import t
from . import icons
from .components import (
    Card,
    Divider,
    EmptyState,
    IconButton,
    Pill,
    SearchField,
    SecondaryButton,
)
from .theme import Theme

if TYPE_CHECKING:  # pragma: no cover - typing only
    from ..controller import AppController


class _RoleLabel(QLabel):
    """QLabel tinted with a palette role and refreshed on theme changes."""

    def __init__(
        self,
        text: str = "",
        role: str = "text",
        size: int = 12,
        weight: int = 400,
        parent: QWidget | None = None,
        *,
        mono: bool = False,
    ) -> None:
        super().__init__(text, parent)
        self._role = role
        self.setFont(Theme.font(size, weight, mono=mono))
        Theme.changed.connect(self._sync_colour)
        self._sync_colour()

    def _sync_colour(self, *_args: object) -> None:
        colour = getattr(Theme.palette(), self._role, Theme.palette().text)
        self.setStyleSheet(f"color: {colour};")


class _CommandBox(QWidget):
    """Rounded, selectable install command with a copy button."""

    def __init__(self, command: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 5, 5, 5)
        layout.setSpacing(6)

        self.command_label = _RoleLabel(command, "muted", 10, parent=self, mono=True)
        self.command_label.setWordWrap(True)
        self.command_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self.command_label.setSizePolicy(
            QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred
        )
        layout.addWidget(self.command_label, 1)

        self.copy_button = IconButton(
            "copy", t("Copy install command"), self, size=26, icon_size=13
        )
        layout.addWidget(self.copy_button, 0, Qt.AlignmentFlag.AlignTop)

    def paintEvent(self, event: object) -> None:  # noqa: N802 - Qt API
        palette = Theme.palette()
        painter = QPainter(self)
        try:
            painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
            rect = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
            painter.setBrush(QColor(palette.card_hover))
            painter.setPen(QColor(palette.border))
            painter.drawRoundedRect(rect, 7.0, 7.0)
        finally:
            painter.end()


class _CatalogCard(Card):
    """One curated model, rendered as a calm rounded surface."""

    useRequested = Signal(object)
    copyRequested = Signal(object)

    def __init__(self, entry: object, parent: QWidget | None = None) -> None:
        super().__init__("", parent=parent, padding=14, spacing=8)
        self.entry = entry
        self.setObjectName("catalogCard")

        header_row = QWidget(self)
        top = QHBoxLayout(header_row)
        top.setContentsMargins(0, 0, 0, 0)
        top.setSpacing(7)

        self.name_label = _RoleLabel(entry.name, "text", 14, 600, header_row)
        top.addWidget(self.name_label)

        self.provider_label = Pill(t(entry.provider.title), "muted", header_row)
        top.addWidget(self.provider_label)

        self.size_label = Pill(t(entry.size) if entry.size else "", "muted", header_row)
        self.size_label.setVisible(bool(entry.size))
        top.addWidget(self.size_label)

        self.languages_label = Pill(
            t(entry.languages) if entry.languages else "", "muted", header_row
        )
        self.languages_label.setVisible(bool(entry.languages))
        top.addWidget(self.languages_label)

        self.free_label = Pill(t("Free"), "success", header_row)
        self.free_label.setVisible(":free" in (entry.model_id or ""))
        top.addWidget(self.free_label)

        top.addStretch(1)

        self.use_button = SecondaryButton(t("Use this model"), header_row)
        self.use_button.setObjectName("useModelButton")
        self.use_button.setAccessibleName(t("Use this model"))
        self.use_button.clicked.connect(lambda: self.useRequested.emit(entry))
        top.addWidget(self.use_button, 0, Qt.AlignmentFlag.AlignTop)
        self.add(header_row)

        self.model_label = _RoleLabel(entry.model_id, "faint", 11, parent=self, mono=True)
        self.model_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self.add(self.model_label)

        self.note_label = _RoleLabel(t(entry.note), "muted", 12, parent=self)
        self.note_label.setWordWrap(True)
        self.add(self.note_label)

        self.command_box: _CommandBox | None = None
        self.copy_button: IconButton | None = None
        self.command_label: QLabel | None = None
        if entry.install_command:
            self.command_box = _CommandBox(entry.install_command, self)
            self.copy_button = self.command_box.copy_button
            self.command_label = self.command_box.command_label
            self.command_box.copy_button.clicked.connect(
                lambda: self.copyRequested.emit(entry)
            )
            self.add(self.command_box)

    # -- feedback -----------------------------------------------------------
    def show_copied(self) -> None:
        if self.command_box is None:
            return
        self.command_box.copy_button.set_icon_name("check")
        QTimer.singleShot(1200, self._reset_copy_icon)

    def _reset_copy_icon(self) -> None:
        try:
            if self.command_box is not None:
                self.command_box.copy_button.set_icon_name("copy")
        except RuntimeError:  # the dialog closed in the meantime
            pass

    def retranslate_ui(self) -> None:
        self.provider_label.setText(t(self.entry.provider.title))
        self.size_label.setText(t(self.entry.size) if self.entry.size else "")
        self.size_label.setVisible(bool(self.entry.size))
        self.languages_label.setText(
            t(self.entry.languages) if self.entry.languages else ""
        )
        self.languages_label.setVisible(bool(self.entry.languages))
        self.free_label.setText(t("Free"))
        self.free_label.setVisible(":free" in (self.entry.model_id or ""))
        self.note_label.setText(t(self.entry.note))
        self.use_button.setText(t("Use this model"))
        self.use_button.setAccessibleName(t("Use this model"))
        if self.command_box is not None:
            self.command_box.copy_button.set_tooltip(t("Copy install command"))


class CatalogView(QDialog):
    """A searchable, provider-filtered gallery of ready-to-use translators."""

    def __init__(self, controller: "AppController", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.controller = controller
        self.cards: list[_CatalogCard] = []
        self.setWindowTitle(t("Model catalog"))
        self.setWindowIcon(icons.icon("translate", size=64))
        self.setObjectName("catalogView")
        self.setMinimumSize(640, 480)
        self.resize(760, 620)
        self.setSizeGripEnabled(True)

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)
        root.addWidget(self._build_header())
        root.addWidget(Divider("horizontal", self))
        root.addWidget(self._build_controls())
        root.addWidget(Divider("horizontal", self))
        root.addWidget(self._build_content(), 1)
        root.addWidget(Divider("horizontal", self))
        root.addWidget(self._build_footer())

        self._populate_cards()
        self._apply_filters()
        self.retranslate_ui()
        Theme.changed.connect(self._apply_theme)

    # -- construction -------------------------------------------------------
    def _build_header(self) -> QWidget:
        self.header = QWidget(self)
        self.header.setObjectName("catalogHeader")
        layout = QHBoxLayout(self.header)
        layout.setContentsMargins(22, 16, 22, 15)
        layout.setSpacing(12)

        column = QVBoxLayout()
        column.setContentsMargins(0, 0, 0, 0)
        column.setSpacing(3)
        self.title_label = _RoleLabel(t("Model catalog"), "text", 18, 600, self.header)
        column.addWidget(self.title_label)
        self.subtitle_label = _RoleLabel(
            t("Ready translators for local use and cloud options with free tiers."),
            "muted",
            12,
            parent=self.header,
        )
        self.subtitle_label.setWordWrap(True)
        column.addWidget(self.subtitle_label)
        layout.addLayout(column, 1)

        self.count_label = _RoleLabel("0", "faint", 12, parent=self.header, mono=True)
        layout.addWidget(self.count_label, 0, Qt.AlignmentFlag.AlignTop)
        return self.header

    def _build_controls(self) -> QWidget:
        controls = QWidget(self)
        controls.setObjectName("catalogControls")
        layout = QHBoxLayout(controls)
        layout.setContentsMargins(22, 12, 22, 12)
        layout.setSpacing(10)

        self.provider_filter = QComboBox(controls)
        self.provider_filter.setObjectName("catalogProviderFilter")
        self.provider_filter.setMinimumHeight(34)
        self.provider_filter.setMinimumWidth(190)
        self.provider_filter.setMaximumWidth(230)
        self.provider_filter.setAccessibleName(t("Provider"))
        layout.addWidget(self.provider_filter)

        self.search = SearchField(t("Search model"), controls)
        self.search.setObjectName("catalogSearch")
        self.search.textChanged.connect(self._apply_filters)
        layout.addWidget(self.search, 1)

        self.provider_filter.currentIndexChanged.connect(self._apply_filters)
        return controls

    def _build_content(self) -> QWidget:
        self.stack = QStackedWidget(self)
        self.stack.setObjectName("catalogStack")
        self.scroll = QScrollArea(self.stack)
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self._cards_host = QWidget(self.scroll)
        self._cards_layout = QVBoxLayout(self._cards_host)
        self._cards_layout.setContentsMargins(20, 16, 20, 18)
        self._cards_layout.setSpacing(10)
        self._cards_layout.addStretch(1)
        self.scroll.setWidget(self._cards_host)
        self.stack.addWidget(self.scroll)

        self.empty_state = EmptyState(
            "search",
            t("Nothing found"),
            t("Try another query."),
            self.stack,
        )
        self.stack.addWidget(self.empty_state)
        return self.stack

    def _build_footer(self) -> QWidget:
        self.footer = QWidget(self)
        self.footer.setObjectName("catalogFooter")
        layout = QHBoxLayout(self.footer)
        layout.setContentsMargins(22, 10, 16, 10)
        layout.setSpacing(8)

        self.footer_icon = QLabel(self.footer)
        self.footer_icon.setFixedSize(15, 18)
        layout.addWidget(self.footer_icon, 0, Qt.AlignmentFlag.AlignTop)

        self.footer_label = _RoleLabel(
            t(
                "Need another model? Type its ID into the Model field — any model "
                "your server supports will work."
            ),
            "faint",
            11,
            parent=self.footer,
        )
        self.footer_label.setWordWrap(True)
        layout.addWidget(self.footer_label, 1)

        self.close_button = SecondaryButton(t("Close"), self.footer)
        self.close_button.setObjectName("closeCatalogButton")
        self.close_button.clicked.connect(self.reject)
        layout.addWidget(self.close_button, 0, Qt.AlignmentFlag.AlignBottom)
        return self.footer

    def _populate_cards(self) -> None:
        while self._cards_layout.count():
            item = self._cards_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()
        self.cards = []

        providers: list[Provider] = []
        for entry in ModelCatalog.ENTRIES:
            if entry.provider not in providers:
                providers.append(entry.provider)
        self._providers = providers

        for entry in ModelCatalog.ENTRIES:
            card = _CatalogCard(entry, self._cards_host)
            card.useRequested.connect(self._use_entry)
            card.copyRequested.connect(self._copy_command)
            self._cards_layout.addWidget(card)
            self.cards.append(card)
        self._cards_layout.addStretch(1)
        self._rebuild_provider_filter()

    def _rebuild_provider_filter(self) -> None:
        previous = self.provider_filter.currentData() if self.provider_filter.count() else ""
        blocked = self.provider_filter.blockSignals(True)
        try:
            self.provider_filter.clear()
            self.provider_filter.addItem(t("All providers"), "")
            for provider in self._providers:
                self.provider_filter.addItem(t(provider.title), provider.value)
            index = self.provider_filter.findData(previous)
            self.provider_filter.setCurrentIndex(max(0, index))
        finally:
            self.provider_filter.blockSignals(blocked)

    # -- filtering ----------------------------------------------------------
    def _matches(self, card: _CatalogCard, needle: str, provider: str) -> bool:
        if provider and card.entry.provider.value != provider:
            return False
        if not needle:
            return True
        haystack = " ".join(
            (
                card.entry.name,
                card.entry.model_id,
                card.entry.provider.title,
                card.entry.size,
                card.entry.languages,
                t(card.entry.note),
            )
        ).casefold()
        return needle in haystack

    def _apply_filters(self, *_args: object) -> None:
        needle = (self.search.text() or "").strip().casefold()
        provider = str(self.provider_filter.currentData() or "")
        visible = 0
        for card in self.cards:
            match = self._matches(card, needle, provider)
            card.setVisible(match)
            if match:
                visible += 1
        total = len(self.cards)
        self.count_label.setText(f"{visible} / {total}" if needle or provider else str(total))
        self.stack.setCurrentWidget(self.scroll if visible else self.empty_state)
        if not visible:
            self.empty_state.set_title(t("Nothing found"))
            self.empty_state.set_subtitle(t("Try another query."))
            self.empty_state.retranslate_ui()

    def visible_cards(self) -> list[_CatalogCard]:
        return [card for card in self.cards if not card.isHidden()]

    # -- actions ------------------------------------------------------------
    def _copy_command(self, entry: object) -> None:
        if not entry.install_command:
            return
        QGuiApplication.clipboard().setText(entry.install_command)
        for card in self.cards:
            if card.entry is entry:
                card.show_copied()
                break

    def _use_entry(self, entry: object) -> None:
        self.controller.apply_catalog_entry(entry)
        self.accept()

    # -- theme / i18n -------------------------------------------------------
    def _apply_theme(self) -> None:
        palette = Theme.palette()
        self.header.setStyleSheet(
            f"QWidget#catalogHeader {{ background: {palette.panel}; }}"
        )
        self.footer.setStyleSheet(
            f"QWidget#catalogFooter {{ background: {palette.panel}; }}"
        )
        self.footer_icon.setPixmap(icons.pixmap("info", palette.faint, 13))
        self.setStyleSheet(
            f"QDialog#catalogView {{ background: {palette.bg}; }}"
        )

    def retranslate_ui(self) -> None:
        self.setWindowTitle(t("Model catalog"))
        self.title_label.setText(t("Model catalog"))
        self.subtitle_label.setText(
            t("Ready translators for local use and cloud options with free tiers.")
        )
        self.search.set_placeholder(t("Search model"))
        self.provider_filter.setAccessibleName(t("Provider"))
        self.footer_label.setText(
            t(
                "Need another model? Type its ID into the Model field — any model "
                "your server supports will work."
            )
        )
        self.close_button.setText(t("Close"))
        for card in self.cards:
            card.retranslate_ui()
        self._rebuild_provider_filter()
        self._apply_filters()
        self._apply_theme()

    def showEvent(self, event: object) -> None:  # noqa: N802
        self._apply_theme()
        super().showEvent(event)
