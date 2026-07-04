from pathlib import Path
from unittest.mock import Mock

from PyQt6.QtGui import QCloseEvent

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


# --- Bug 2: closing the wizard mid-run must stop any active runner(s) ---


def test_close_event_stops_active_runner_on_pages_that_have_one(qapp):
    wizard = build_wizard()
    migrate_page = wizard.page(MIGRATE_PAGE_ID)
    secureboot_page = wizard.page(SECUREBOOT_PAGE_ID)

    mock_migrate_runner = Mock()
    mock_secureboot_runner = Mock()
    migrate_page.runner = mock_migrate_runner
    secureboot_page.runner = mock_secureboot_runner

    wizard.closeEvent(QCloseEvent())

    mock_migrate_runner.stop.assert_called_once()
    mock_secureboot_runner.stop.assert_called_once()


def test_close_event_does_not_crash_when_no_runner_is_active(qapp):
    wizard = build_wizard()
    # No page has a runner set (fresh wizard, nothing started). Must not raise.
    wizard.closeEvent(QCloseEvent())


def test_close_event_ignores_pages_with_runner_set_to_none(qapp):
    wizard = build_wizard()
    migrate_page = wizard.page(MIGRATE_PAGE_ID)
    assert migrate_page.runner is None
    # Must not raise even though runner is None (not merely absent).
    wizard.closeEvent(QCloseEvent())


def test_close_event_stops_active_splash_runner_on_done_page(qapp):
    # DonePage's "Reboot to BIOS" handler runs its apply-splash HelperRunner
    # in self._splash_runner (DonePage doesn't inherit _RunnerPage, so it
    # has no self.runner). closeEvent() must stop this runner too, not just
    # the self.runner-based ones on _RunnerPage subclasses.
    wizard = build_wizard()
    done_page = wizard.page(DONE_PAGE_ID)

    mock_splash_runner = Mock()
    done_page._splash_runner = mock_splash_runner

    wizard.closeEvent(QCloseEvent())

    mock_splash_runner.stop.assert_called_once()
