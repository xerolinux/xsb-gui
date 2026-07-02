from pathlib import Path

from PyQt6.QtWidgets import QApplication

from xsb_gui import app as app_module
from xsb_gui.app import HELPER_PATH, build_wizard
from xsb_gui.pages.confirm_page import (
    WELCOME_PAGE_ID, PREFLIGHT_PAGE_ID, CONFIRM_PAGE_ID, MIGRATE_PAGE_ID,
    SECUREBOOT_PAGE_ID, DONE_PAGE_ID,
)


def test_build_wizard_registers_all_pages_in_order(qapp):
    wizard = build_wizard()
    assert wizard.page(WELCOME_PAGE_ID) is not None
    assert wizard.page(PREFLIGHT_PAGE_ID) is not None
    assert wizard.page(CONFIRM_PAGE_ID) is not None
    assert wizard.page(MIGRATE_PAGE_ID) is not None
    assert wizard.page(SECUREBOOT_PAGE_ID) is not None
    assert wizard.page(DONE_PAGE_ID) is not None


def test_build_wizard_has_icon_and_minimum_size(qapp):
    wizard = build_wizard()
    assert wizard.windowIcon().isNull() is False
    assert wizard.minimumSize().width() >= 720
    assert wizard.minimumSize().height() >= 520


def test_helper_path_resolves_to_local_repo_script_in_dev_clone():
    # This repo checkout genuinely has xsb-helper at its root, so importing
    # xsb_gui.app from this git clone should resolve HELPER_PATH to it
    # rather than falling back to the packaged install path.
    repo_root = Path(__file__).resolve().parents[2]
    expected_local_helper = repo_root / "xsb-helper"
    assert expected_local_helper.exists(), (
        "sanity check: this test relies on xsb-helper existing at the repo root"
    )
    assert HELPER_PATH == str(expected_local_helper)


def test_resolve_helper_path_falls_back_to_packaged_path_when_local_missing(monkeypatch):
    monkeypatch.setattr(Path, "exists", lambda self: False)
    assert app_module._resolve_helper_path() == "/usr/lib/xsb-gui/xsb-helper"
