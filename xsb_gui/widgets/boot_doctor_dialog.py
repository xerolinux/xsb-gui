from PyQt6.QtWidgets import QDialog, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton, QVBoxLayout

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import format_event_line

CHECKING_TEXT = "Running boot diagnostics..."
FAILED_TEXT = "Boot diagnostics did not complete."

_SUMMARY_STYLE = "background: {color}; color: white; border-radius: 8px; padding: 10px; font-size: 10.5pt;"
_LEVEL_COLORS = {
    "ok": "#27ae60",
    "warning": "#e67e22",
    "error": "#c0392b",
}


class BootDoctorDialog(QDialog):
    """Read-only boot health check: runs xsb-helper's "doctor" subcommand and
    shows every check it performs, plus an overall ok/warning/error summary.

    Never mutates anything - "doctor" is purely diagnostic - so unlike
    CleanupDialog there is no dry-run/apply distinction; it just runs once,
    with a "Run Again" button to repeat it.
    """

    def __init__(self, helper_path, use_pkexec, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Boot Diagnostics")
        self.setModal(True)
        self.setMinimumSize(560, 420)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        self.summary_label = QLabel(CHECKING_TEXT)
        self.summary_label.setWordWrap(True)
        layout.addWidget(self.summary_label)

        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        layout.addWidget(self.log)

        buttons = QHBoxLayout()
        buttons.addStretch(1)
        self.rerun_button = QPushButton("Run Again")
        self.rerun_button.setEnabled(False)
        self.rerun_button.clicked.connect(self._on_rerun_clicked)
        buttons.addWidget(self.rerun_button)
        close_button = QPushButton("Close")
        close_button.clicked.connect(self.accept)
        buttons.addWidget(close_button)
        layout.addLayout(buttons)

        self._runner = None
        self._start()

    def _start(self):
        self.summary_label.setStyleSheet("")
        self.summary_label.setText(CHECKING_TEXT)
        self.log.clear()
        self.rerun_button.setEnabled(False)
        self._runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self._runner.event_received.connect(self._on_event)
        self._runner.error_occurred.connect(self._on_error)
        self._runner.finished.connect(self._on_finished)
        self._runner.start("doctor")

    def _on_event(self, event):
        if event.get("event") == "doctor_done":
            level = event.get("level", "ok")
            color = _LEVEL_COLORS.get(level, "#7f8c8d")
            self.summary_label.setStyleSheet(_SUMMARY_STYLE.format(color=color))
            self.summary_label.setText(event.get("message", ""))
        self.log.appendPlainText(format_event_line(event))

    def _on_error(self, message):
        self.summary_label.setStyleSheet(_SUMMARY_STYLE.format(color=_LEVEL_COLORS["error"]))
        self.summary_label.setText(f"Could not run diagnostics: {message}")
        self.rerun_button.setEnabled(True)

    def _on_finished(self, exit_code):
        # A process that exits nonzero without a doctor_done event (e.g. a
        # cancelled/failed pkexec auth) would otherwise leave this dialog
        # stuck on "Running boot diagnostics..." forever.
        if exit_code != 0 and self.summary_label.text() == CHECKING_TEXT:
            self.summary_label.setStyleSheet(_SUMMARY_STYLE.format(color=_LEVEL_COLORS["error"]))
            self.summary_label.setText(FAILED_TEXT)
        self.rerun_button.setEnabled(True)

    def _on_rerun_clicked(self):
        self._start()

    def done(self, result):
        if self._runner is not None:
            self._runner.stop()
        super().done(result)
