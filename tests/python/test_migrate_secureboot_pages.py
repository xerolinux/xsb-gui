import os
from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
OK = os.path.join(FIXTURE_DIR, "fake_helper_migrate_ok.sh")
FAIL = os.path.join(FIXTURE_DIR, "fake_helper_migrate_fail.sh")
SECUREBOOT_OK = os.path.join(FIXTURE_DIR, "fake_helper_secureboot_ok.sh")
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


def test_secureboot_page_completes_on_secureboot_done(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True


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
