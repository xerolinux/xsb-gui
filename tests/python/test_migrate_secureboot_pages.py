import os

from PyQt6.QtWidgets import QWizard

from xsb_gui.pages.confirm_page import SECUREBOOT_ERROR_PAGE_ID, SECUREBOOT_PAGE_ID
from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage
from xsb_gui.pages.secureboot_error_page import SecureBootErrorPage

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


class FakeWizard:
    def __init__(self):
        self.next_called = False

    def next(self):
        self.next_called = True


def test_secureboot_page_completes_and_needs_reboot_when_reboot_required(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard()

    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page._needs_reboot is True
    assert page._had_error is False
    assert page._outcome_message == "Secure Boot setup complete."


def test_secureboot_page_completes_without_reboot_when_already_active(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_ALREADY_ACTIVE, use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard()

    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page._needs_reboot is False
    assert page._had_error is False


def test_secureboot_page_records_error_and_navigates_to_error_page(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_ERROR, use_pkexec=False)
    qtbot.addWidget(page)
    fake_wizard = FakeWizard()
    page.wizard = lambda: fake_wizard

    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is False
    assert page._had_error is True
    assert page._error_message == (
        "Setup Mode is not active. Reboot into UEFI firmware settings and clear "
        "all Secure Boot keys (PK, KEK, db, dbx) before running this again."
    )
    assert fake_wizard.next_called is True
    assert page.nextId() == SECUREBOOT_ERROR_PAGE_ID


def test_secureboot_page_resets_state_on_retry_via_initialize_page(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_ERROR, use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard()

    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass
    assert page._had_error is True

    page._helper_path = SECUREBOOT_OK
    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page._had_error is False
    assert page._needs_reboot is True


def test_secureboot_page_real_wizard_navigates_to_error_page_despite_incomplete(qtbot):
    # Empirical check that QWizard.next() called from within an event handler
    # actually advances the wizard even while isComplete() is False for the
    # current page (the Next button being logically disabled does not gate
    # programmatic .next() calls).
    wizard = QWizard()
    qtbot.addWidget(wizard)
    page = SecureBootPage(helper_path=SECUREBOOT_ERROR, use_pkexec=False)
    error_page = SecureBootErrorPage()
    wizard.setPage(SECUREBOOT_PAGE_ID, page)
    wizard.setPage(SECUREBOOT_ERROR_PAGE_ID, error_page)
    wizard.setStartId(SECUREBOOT_PAGE_ID)
    wizard.show()
    qtbot.waitExposed(wizard)

    qtbot.waitUntil(lambda: page._had_error is True, timeout=2000)
    qtbot.waitUntil(lambda: wizard.currentId() == SECUREBOOT_ERROR_PAGE_ID, timeout=2000)

    assert page.isComplete() is False
    assert wizard.currentId() == SECUREBOOT_ERROR_PAGE_ID


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
