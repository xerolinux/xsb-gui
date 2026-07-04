import os
from unittest.mock import patch

from PyQt6.QtCore import QProcess
from PyQt6.QtWidgets import QWizard, QWizardPage

from xsb_gui.pages.confirm_page import (
    CONFIRM_PAGE_ID, MIGRATE_PAGE_ID, SECUREBOOT_PAGE_ID, ConfirmPage,
)

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper.sh")
LIMINE_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_preflight_limine.sh")
ERROR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_preflight_error.sh")
RAW_OUTPUT_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_raw_output.sh")
SMALL_ESP_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_small_esp.sh")
SLOW_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_slow.sh")


def test_confirm_page_becomes_complete_and_shows_summary_after_preflight_result(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    assert page.isComplete() is False

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page.result.bootloader == "grub"
    assert "EFI system partition" in page.summary_label.text()
    assert page.resume_notice_label.isVisible() is False


def test_confirm_page_refuses_and_stays_incomplete_when_preflight_hard_stops(qtbot):
    page = ConfirmPage(helper_path=ERROR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is False
    assert "not by this tool" in page.summary_label.text()


def test_confirm_page_shows_resume_notice_and_skips_migrate_when_limine_already_installed(qtbot):
    # Also proves the already-migrated, Secure-Boot-already-enabled
    # combination is NOT blocked here: cmd_preflight itself only hard-stops
    # "Secure Boot enabled" when GRUB is still active, so a valid
    # preflight_result with secureboot_state=enabled can only mean Limine
    # is already active (the re-sign scenario) - never something to refuse.
    page = ConfirmPage(helper_path=LIMINE_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page.resume_notice_label.isVisible() is True
    assert page.nextId() == SECUREBOOT_PAGE_ID


def test_confirm_page_does_not_show_resume_notice_when_grub_detected(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.resume_notice_label.isVisible() is False


def test_confirm_page_next_id_defaults_to_migrate_page_when_grub_detected(qtbot):
    wizard = QWizard()
    qtbot.addWidget(wizard)
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    wizard.setPage(CONFIRM_PAGE_ID, page)
    wizard.setPage(MIGRATE_PAGE_ID, QWizardPage())
    wizard.setStartId(CONFIRM_PAGE_ID)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.nextId() == MIGRATE_PAGE_ID


def test_confirm_page_shows_error_and_stays_incomplete_when_process_fails_to_start(qtbot):
    page = ConfirmPage(helper_path="/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.error_occurred, timeout=2000):
        pass

    assert page.isComplete() is False
    assert page.summary_label.text() != "Running checks..."


def test_confirm_page_stays_incomplete_and_warns_when_esp_too_small(qtbot):
    page = ConfirmPage(helper_path=SMALL_ESP_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.confirm_page.show_esp_too_small_popup") as mock_popup:
        page.initializePage()
        with qtbot.waitSignal(page.runner.finished, timeout=2000):
            pass

    mock_popup.assert_called_once_with(page, 524288000)
    assert page.isComplete() is False
    assert page.summary_label.text() == "EFI system partition is too small."


def test_confirm_page_shows_raw_output_when_non_json_line_received(qtbot):
    page = ConfirmPage(helper_path=RAW_OUTPUT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert "pkexec: /usr/lib/xsb-gui/xsb-helper: No such file or directory" in page.summary_label.text()


def test_reentering_page_stops_previous_runner(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    old_runner = page.runner
    with patch.object(old_runner, "stop") as mock_stop:
        page.initializePage()

    mock_stop.assert_called_once()


def test_cleanup_page_stops_active_runner(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()
    runner = page.runner

    with patch.object(runner, "stop") as mock_stop:
        page.cleanupPage()

    mock_stop.assert_called_once()


def test_back_then_next_kills_previous_real_process_not_just_mock(qtbot):
    # Proves an actual QProcess started by a prior page entry is terminated,
    # not merely that a mocked method was called. Simulates: user is on the
    # page mid-run (slow fixture still sleeping), clicks Back (cleanupPage),
    # then Next again (initializePage) re-entering the same page instance.
    page = ConfirmPage(helper_path=SLOW_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()
    old_runner = page.runner

    qtbot.waitUntil(
        lambda: old_runner._process.state() == QProcess.ProcessState.Running, timeout=2000
    )

    # Back
    page.cleanupPage()
    qtbot.waitUntil(
        lambda: old_runner._process.state() == QProcess.ProcessState.NotRunning, timeout=3000
    )
    assert old_runner._process.state() == QProcess.ProcessState.NotRunning

    # Next (re-enter same page)
    page.initializePage()
    new_runner = page.runner
    assert new_runner is not old_runner
    qtbot.waitUntil(
        lambda: new_runner._process.state() == QProcess.ProcessState.Running, timeout=2000
    )
    assert old_runner._process.state() == QProcess.ProcessState.NotRunning


def test_reentering_page_without_prior_run_does_not_crash(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    # No prior initializePage() call: self.runner is None. Must not raise.
    page.cleanupPage()
    page.initializePage()
    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass
    assert page.isComplete() is True


def test_stale_runner_result_does_not_overwrite_fresh_result_after_reentry(qtbot):
    # The actual bug this guards against: without disconnecting the old
    # runner's signals, a stale preflight_result arriving late from a first
    # (still-running) helper process could land on top of - or race with -
    # the fresh result from a second initializePage() call (e.g. user goes
    # Back then Next again before the first run finished).
    page = ConfirmPage(helper_path=SLOW_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()
    old_runner = page.runner

    qtbot.waitUntil(
        lambda: old_runner._process.state() == QProcess.ProcessState.Running, timeout=2000
    )

    # Simulate the second (fresh) entry actually completing quickly, so we
    # can assert on its result without waiting out the slow fixture's sleep.
    page._helper_path = FIXTURE
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page.result.bootloader == "grub"


def test_next_button_disables_immediately_on_reentry_before_fresh_run_completes(qtbot):
    # The actual bug this guards against: initializePage() resets state to
    # incomplete but, without an explicit completeChanged emission, QWizard
    # never re-evaluates isComplete() until some later event happens to
    # fire it - leaving the Next button clickable during the reset window
    # and letting the user proceed to MigratePage while result is None.
    wizard = QWizard()
    qtbot.addWidget(wizard)
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    wizard.setPage(0, page)
    wizard.setPage(1, QWizardPage())
    wizard.setStartId(0)
    wizard.show()
    wizard.restart()
    next_button = wizard.button(QWizard.WizardButton.NextButton)

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass
    assert next_button.isEnabled() is True

    page._helper_path = SLOW_FIXTURE
    page.initializePage()

    assert next_button.isEnabled() is False
    page.runner.stop()


def test_on_event_handles_missing_event_key_without_crashing(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page._on_event({"foo": "bar"})
    assert page.isComplete() is False
    assert page.result is None


def test_on_event_handles_error_event_missing_message_key(qtbot):
    page = ConfirmPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    page._on_event({"event": "error"})
    assert page.isComplete() is False
    assert page.summary_label.text() == ""
