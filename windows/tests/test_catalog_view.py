"""Model catalogue: one card per entry, filtering, copy and apply."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import pytest
from PySide6.QtWidgets import QApplication, QDialog

from deepl_ofm.controller import AppController
from deepl_ofm.core.catalog import ModelCatalog
from deepl_ofm.core.languages import AppLanguage
from deepl_ofm.core.providers import Provider
from deepl_ofm.core.settings import AppSettings
from deepl_ofm.i18n import set_language
from deepl_ofm.services.history import HistoryStore
from deepl_ofm.ui.catalog_view import CatalogView
from deepl_ofm.ui.theme import Theme


class MemorySecrets:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    def read(self, account: str) -> str:
        return self.values.get(account, "")

    def write(self, account: str, value: str) -> None:
        if value:
            self.values[account] = value
        else:
            self.values.pop(account, None)

    def delete(self, account: str) -> None:
        self.values.pop(account, None)

    def backend_name(self) -> str:
        return "plain"


@pytest.fixture(autouse=True)
def reset_language():
    set_language(AppLanguage.EN)
    yield
    set_language(AppLanguage.EN)


@pytest.fixture(scope="module", autouse=True)
def themed(qapp):
    Theme.apply(qapp, dark=False)
    yield
    Theme.set_dark(None)


@pytest.fixture
def controller(qapp, tmp_path: Path):
    settings = AppSettings(tmp_path / "settings.json", secrets=MemorySecrets())
    controller = AppController(
        settings=settings, history=HistoryStore(tmp_path / "history.json")
    )
    yield controller
    controller.deleteLater()


def _show(controller: AppController) -> CatalogView:
    view = CatalogView(controller)
    view.show()
    QApplication.processEvents()
    return view


def test_one_card_per_catalog_entry(qapp, controller: AppController) -> None:
    view = _show(controller)
    assert len(view.cards) == len(ModelCatalog.ENTRIES)
    assert [card.entry.model_id for card in view.cards] == [
        entry.model_id for entry in ModelCatalog.ENTRIES
    ]
    assert all(card.use_button.text() for card in view.cards)
    view.close()


def test_provider_and_text_filters_hide_cards(qapp, controller: AppController) -> None:
    view = _show(controller)
    index = view.provider_filter.findData(Provider.OPEN_ROUTER.value)
    assert index >= 0
    view.provider_filter.setCurrentIndex(index)
    qapp.processEvents()

    visible = view.visible_cards()
    assert visible
    assert all(card.entry.provider is Provider.OPEN_ROUTER for card in visible)
    assert len(visible) < len(view.cards)

    view.search.setText("gemma")
    qapp.processEvents()
    narrowed = view.visible_cards()
    assert narrowed
    assert all(
        "gemma" in (card.entry.name + card.entry.model_id).casefold() for card in narrowed
    )

    view.search.setText("nothing at all")
    qapp.processEvents()
    assert view.visible_cards() == []
    assert view.stack.currentWidget() is view.empty_state
    view.close()


def test_copy_install_command_uses_the_clipboard(
    qapp, controller: AppController
) -> None:
    view = _show(controller)
    card = next(card for card in view.cards if card.entry.install_command)
    assert card.command_box is not None

    card.command_box.copy_button.click()
    qapp.processEvents()

    assert qapp.clipboard().text() == card.entry.install_command
    view.close()


def test_use_model_applies_the_entry_and_closes(
    qapp, controller: AppController
) -> None:
    view = _show(controller)
    applied: list[object] = []
    controller.apply_catalog_entry = applied.append  # type: ignore[method-assign]

    card = next(
        card for card in view.cards if card.entry.provider is Provider.OPEN_ROUTER
    )
    card.use_button.click()
    qapp.processEvents()

    assert applied == [card.entry]
    assert view.result() == QDialog.DialogCode.Accepted
    assert not view.isVisible()


def test_retranslate_refreshes_labels(qapp, controller: AppController) -> None:
    view = _show(controller)
    view.retranslate_ui()
    qapp.processEvents()
    assert view.title_label.text() == "Model catalog"
    assert view.search.placeholderText()
    assert len(view.cards) == len(ModelCatalog.ENTRIES)
    view.close()
