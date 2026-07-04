import os

from xsb_gui.widgets.secureboot_status_dialog import SecureBootStatusDialog

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
STATUS_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_status.sh")
RAW_OUTPUT_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_raw_output.sh")


def test_shows_bootloader_and_secureboot_state_from_real_process(qtbot):
    dialog = SecureBootStatusDialog(STATUS_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "GRUB" in dialog.status_label.text()
    assert "Disabled" in dialog.status_label.text()


def test_shows_error_message_when_process_fails_to_start(qtbot):
    dialog = SecureBootStatusDialog("/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.error_occurred, timeout=2000):
        pass

    assert "Could not check status" in dialog.status_label.text()


def test_shows_generic_message_when_process_exits_nonzero_without_reporting_anything(qtbot):
    # Simulates a cancelled/failed pkexec auth: process exits nonzero
    # without emitting error_occurred (that's QProcess-level only) or a
    # status_result event.
    dialog = SecureBootStatusDialog(RAW_OUTPUT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == "Status check did not complete."


def test_closing_the_dialog_stops_the_runner(qtbot):
    dialog = SecureBootStatusDialog(STATUS_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    from unittest.mock import patch
    with patch.object(dialog._runner, "stop") as mock_stop:
        dialog.done(0)

    mock_stop.assert_called_once()
