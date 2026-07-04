import os

from xsb_gui.widgets.cleanup_dialog import (
    CleanupDialog, PREVIEW_TEXT, NOTHING_TEXT, DONE_TEXT,
)

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
CLEANUP_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_cleanup.sh")
CLEANUP_NOTHING_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_cleanup_nothing.sh")
CLEANUP_ERROR_FIXTURE = os.path.join(FIXTURE_DIR, "fake_helper_cleanup_error.sh")


def test_dryrun_previews_removals_and_enables_apply(qtbot):
    dialog = CleanupDialog(CLEANUP_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == PREVIEW_TEXT
    assert dialog.apply_button.isEnabled()
    # The would-be-removed files appear in the log.
    assert "limine.conf.old" in dialog.log.toPlainText()


def test_dryrun_reports_nothing_to_clean_and_keeps_apply_disabled(qtbot):
    dialog = CleanupDialog(CLEANUP_NOTHING_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == NOTHING_TEXT
    assert not dialog.apply_button.isEnabled()


def test_apply_runs_the_real_cleanup_and_reports_done(qtbot):
    dialog = CleanupDialog(CLEANUP_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass
    assert dialog.apply_button.isEnabled()

    # Clicking Apply starts a second (real) helper run; wait for it to finish.
    dialog.apply_button.click()
    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert dialog.status_label.text() == DONE_TEXT
    assert not dialog.apply_button.isEnabled()


def test_shows_helper_error_and_never_offers_apply(qtbot):
    dialog = CleanupDialog(CLEANUP_ERROR_FIXTURE, use_pkexec=False)
    qtbot.addWidget(dialog)

    with qtbot.waitSignal(dialog._runner.finished, timeout=2000):
        pass

    assert "not the active bootloader" in dialog.status_label.text()
    assert not dialog.apply_button.isEnabled()
