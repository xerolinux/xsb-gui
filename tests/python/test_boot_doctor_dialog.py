import os
from unittest.mock import patch

from xsb_gui.widgets.boot_doctor_dialog import BootDoctorDialog, CHECKING_TEXT, FAILED_TEXT

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
OK_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_doctor_ok.sh")
WARNING_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_doctor_warning.sh")
ERROR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_doctor_error.sh")
RAW_OUTPUT_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_raw_output.sh")


def test_shows_ok_summary_and_full_check_log(qtbot):
    dialog = BootDoctorDialog(OK_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "no issues found" in dialog.summary_label.text()
    assert "Limine deployment" in dialog.log.toPlainText()
    assert "Bootable kernel" in dialog.log.toPlainText()
    assert dialog.rerun_button.isEnabled()


def test_shows_warning_summary_when_a_check_flags_a_potential_issue(qtbot):
    dialog = BootDoctorDialog(WARNING_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "potential issues found" in dialog.summary_label.text()
    assert "does not match the active Limine install" in dialog.log.toPlainText()


def test_shows_error_summary_when_a_real_problem_is_found(qtbot):
    dialog = BootDoctorDialog(ERROR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "stopped early" in dialog.summary_label.text()


def test_shows_generic_message_when_process_exits_nonzero_without_reporting_anything(qtbot):
    dialog = BootDoctorDialog(RAW_OUTPUT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.summary_label.text() == FAILED_TEXT


def test_shows_error_message_when_process_fails_to_start(qtbot):
    dialog = BootDoctorDialog("/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.error_occurred, timeout=2000):
        pass

    assert "Could not run diagnostics" in dialog.summary_label.text()
    assert dialog.rerun_button.isEnabled()


def test_run_again_restarts_the_check(qtbot):
    dialog = BootDoctorDialog(OK_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass
    assert "no issues found" in dialog.summary_label.text()

    dialog.rerun_button.click()
    assert dialog.summary_label.text() == CHECKING_TEXT
    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass
    assert "no issues found" in dialog.summary_label.text()


def test_closing_the_dialog_stops_the_runner(qtbot):
    dialog = BootDoctorDialog(OK_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with patch.object(dialog._runner, "stop") as mock_stop:
        dialog.done(0)

    mock_stop.assert_called_once()
