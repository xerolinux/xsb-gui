from PyQt6.QtWidgets import (
    QDialog, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton, QVBoxLayout,
)

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import format_event_line

INTRO_TEXT = (
    "<b>Revert to GRUB.</b> This reinstalls GRUB from the backup taken during "
    "migration, restores your original configuration, and removes Limine. It "
    "only works if you migrated with this tool (so a backup exists) and Secure "
    "Boot is currently disabled."
)
CHECKING_TEXT = "Checking whether a revert is possible..."
PREVIEW_TEXT = "This is what a revert would do. Nothing has changed yet - press Apply to revert to GRUB."
APPLYING_TEXT = "Reverting to GRUB..."
DONE_TEXT = "Revert complete. Reboot to boot GRUB again."
FAILED_TEXT = "Revert did not complete."


class RevertDialog(QDialog):
    """Restore the pre-migration GRUB setup and remove Limine.

    Runs xsb-helper's "revert --dry-run" first so the user sees the full ordered
    plan (and any refusal, e.g. no backup or Secure Boot still enabled), and only
    changes anything after an explicit Apply.
    """

    def __init__(self, helper_path, use_pkexec, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Revert to GRUB")
        self.setModal(True)
        self.setMinimumSize(560, 420)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self._applying = False
        self._errored = False
        self._would_change = 0

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        intro = QLabel(INTRO_TEXT)
        intro.setWordWrap(True)
        layout.addWidget(intro)

        self.status_label = QLabel(CHECKING_TEXT)
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)

        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        layout.addWidget(self.log)

        buttons = QHBoxLayout()
        buttons.addStretch(1)
        self.apply_button = QPushButton("Apply Revert")
        self.apply_button.setEnabled(False)
        self.apply_button.clicked.connect(self._on_apply_clicked)
        buttons.addWidget(self.apply_button)
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        buttons.addWidget(self.close_button)
        layout.addLayout(buttons)

        self._runner = None
        self._start("revert", "--dry-run")

    def _start(self, *args):
        self._runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self._runner.event_received.connect(self._on_event)
        self._runner.error_occurred.connect(self._on_error)
        self._runner.finished.connect(self._on_finished)
        self._runner.start(*args)

    def _on_event(self, event):
        name = event.get("event", "")
        if name == "would_run":
            self._would_change += 1
        elif name == "error":
            self._errored = True
            self.status_label.setText(event.get("message", "Revert could not run."))
        self.log.appendPlainText(format_event_line(event))

    def _on_error(self, message):
        self._errored = True
        self.status_label.setText(f"Could not run revert: {message}")

    def _on_finished(self, exit_code):
        if self._errored:
            return
        if self._applying:
            self.status_label.setText(DONE_TEXT if exit_code == 0 else FAILED_TEXT)
            self.apply_button.setEnabled(False)
            return
        # Dry-run finished.
        if exit_code != 0:
            self.status_label.setText(FAILED_TEXT)
        elif self._would_change > 0:
            self.status_label.setText(PREVIEW_TEXT)
            self.apply_button.setEnabled(True)
        else:
            self.status_label.setText(FAILED_TEXT)

    def _on_apply_clicked(self):
        self._applying = True
        self.apply_button.setEnabled(False)
        self.status_label.setText(APPLYING_TEXT)
        self.log.appendPlainText("")
        self._start("revert")

    def done(self, result):
        if self._runner is not None:
            self._runner.stop()
        super().done(result)
