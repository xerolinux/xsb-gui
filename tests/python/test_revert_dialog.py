import os

from xsb_gui.widgets.revert_dialog import RevertDialog, PREVIEW_TEXT, DONE_TEXT

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
REVERT_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_revert.sh")
REVERT_ERROR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_revert_error.sh")


def test_dryrun_previews_the_plan_and_enables_apply(qtbot):
    dialog = RevertDialog(REVERT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == PREVIEW_TEXT
    assert dialog.apply_button.isEnabled()
    assert "Reinstalling GRUB packages" in dialog.log.toPlainText()


def test_apply_runs_the_real_revert_and_reports_done(qtbot):
    dialog = RevertDialog(REVERT_FIXTURE, use_pkexec=False)
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
    dialog = RevertDialog(REVERT_ERROR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "No pre-migration GRUB backup" in dialog.status_label.text()
    assert not dialog.apply_button.isEnabled()
