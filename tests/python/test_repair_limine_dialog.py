import os

from xsb_gui.widgets.repair_limine_dialog import RepairLimineDialog, PREVIEW_TEXT, DONE_TEXT

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
REPAIR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_repair.sh")
REPAIR_ERROR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_repair_error.sh")


def test_dryrun_previews_the_plan_and_enables_apply(qtbot):
    dialog = RepairLimineDialog(REPAIR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == PREVIEW_TEXT
    assert dialog.apply_button.isEnabled()
    assert "Reinstalling Limine packages" in dialog.log.toPlainText()


def test_apply_runs_the_real_repair_and_reports_done(qtbot):
    dialog = RepairLimineDialog(REPAIR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass
    assert dialog.apply_button.isEnabled()

    dialog.apply_button.click()
    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == DONE_TEXT
    assert not dialog.apply_button.isEnabled()


def test_refusal_shows_message_and_never_offers_apply(qtbot):
    dialog = RepairLimineDialog(REPAIR_ERROR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "Limine is not the active bootloader" in dialog.status_label.text()
    assert not dialog.apply_button.isEnabled()


def test_shows_error_message_when_process_fails_to_start(qtbot):
    dialog = RepairLimineDialog("/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.error_occurred, timeout=2000):
        pass

    assert "Could not run repair" in dialog.status_label.text()


def test_closing_the_dialog_stops_the_runner(qtbot):
    from unittest.mock import patch

    dialog = RepairLimineDialog(REPAIR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with patch.object(dialog._runner, "stop") as mock_stop:
        dialog.done(0)

    mock_stop.assert_called_once()
