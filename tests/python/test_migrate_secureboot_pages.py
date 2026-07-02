import os
from unittest.mock import patch

from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
OK = os.path.join(FIXTURE_DIR, "fake_helper_migrate_ok.sh")
FAIL = os.path.join(FIXTURE_DIR, "fake_helper_migrate_fail.sh")
SECUREBOOT_OK = os.path.join(FIXTURE_DIR, "fake_helper_secureboot_ok.sh")
SECUREBOOT_ALREADY_ACTIVE = os.path.join(FIXTURE_DIR, "fake_helper_secureboot_already_active.sh")
SECUREBOOT_ERROR = os.path.join(FIXTURE_DIR, "fake_helper_secureboot_error.sh")
RAW_OUTPUT_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_raw_output.sh")


def test_migrate_page_completes_on_migrate_done(qtbot):
    page = MigratePage(helper_path=OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert "Migration to Limine complete." in page.log.toPlainText()


def test_migrate_page_stays_incomplete_and_shows_error_on_failure(qtbot):
    page = MigratePage(helper_path=FAIL, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is False
    assert "could not be verified" in page.log.toPlainText()


def test_secureboot_page_shows_reboot_popup_and_completes_when_reboot_needed(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)

    with patch.object(page, "_show_reboot_required_popup") as mock_popup:
        page.initializePage()
        with qtbot.waitSignal(page.runner.finished, timeout=2000):
            pass

    mock_popup.assert_called_once_with("Secure Boot setup complete.")
    assert page.isComplete() is True


def test_secureboot_page_completes_without_popup_when_already_active(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_ALREADY_ACTIVE, use_pkexec=False)
    qtbot.addWidget(page)

    with patch.object(page, "_show_reboot_required_popup") as mock_reboot_popup, \
            patch.object(page, "_show_error_popup") as mock_error_popup:
        page.initializePage()
        with qtbot.waitSignal(page.runner.finished, timeout=2000):
            pass

    mock_reboot_popup.assert_not_called()
    mock_error_popup.assert_not_called()
    assert page.isComplete() is True


def test_secureboot_page_shows_error_popup_on_failure(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_ERROR, use_pkexec=False)
    qtbot.addWidget(page)

    with patch.object(page, "_show_error_popup") as mock_popup:
        page.initializePage()
        with qtbot.waitSignal(page.runner.finished, timeout=2000):
            pass

    mock_popup.assert_called_once_with(
        "Setup Mode is not active. Reboot into UEFI firmware settings and clear "
        "all Secure Boot keys (PK, KEK, db, dbx) before running this again."
    )
    assert page.isComplete() is False


def test_secureboot_page_reboot_button_triggers_firmware_reboot(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.secureboot_page.QMessageBox") as mock_message_box_cls, \
            patch("xsb_gui.pages.secureboot_page.QProcess") as mock_qprocess_cls:
        mock_box = mock_message_box_cls.return_value
        reboot_button = object()
        mock_box.addButton.side_effect = [object(), reboot_button]
        mock_box.clickedButton.return_value = reboot_button

        page._show_reboot_required_popup("Secure Boot setup complete.")

        mock_qprocess_cls.startDetached.assert_called_once_with(
            "systemctl", ["reboot", "--firmware-setup"]
        )


def test_secureboot_page_uses_enable_secureboot_subcommand(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)
    assert page._subcommand == "enable-secureboot"


def test_migrate_page_shows_retry_and_stays_incomplete_when_process_fails_to_start(qtbot):
    page = MigratePage(helper_path="/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.error_occurred, timeout=2000):
        pass

    assert page.isComplete() is False
    assert page.retry_button.isVisible() is True
    assert "[ERROR]" in page.log.toPlainText()


def test_migrate_page_shows_raw_output_when_non_json_line_received(qtbot):
    page = MigratePage(helper_path=RAW_OUTPUT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert "[RAW] pkexec: /usr/lib/xsb-gui/xsb-helper: No such file or directory" in page.log.toPlainText()
