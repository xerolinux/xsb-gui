from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import parse_preflight_result


class PreflightPage(QWizardPage):
    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self.setTitle("Checking your system")
        self.setSubTitle("Detecting your current bootloader, partition layout, and Secure Boot state.")
        self._status_label = QLabel("Running checks...")
        self._status_label.setWordWrap(True)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)
        layout.addWidget(self._status_label)
        layout.addStretch()

        self.result = None
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self.runner = None

    def initializePage(self):
        self.result = None
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.error_occurred.connect(self._on_process_error)
        self.runner.raw_output_received.connect(self._on_raw_output)
        self.runner.start("preflight")

    def _on_event(self, event):
        if event["event"] == "preflight_result":
            self.result = parse_preflight_result(event)
            self._status_label.setText("Checks complete.")
            self.completeChanged.emit()
        elif event["event"] == "error":
            self._status_label.setText(event["message"])
            self.completeChanged.emit()

    def _on_finished(self, _exit_code):
        if self.result is None and self._status_label.text() == "Running checks...":
            self._status_label.setText("Preflight checks did not complete.")
            self.completeChanged.emit()

    def _on_process_error(self, message):
        self._status_label.setText(message)
        self.completeChanged.emit()

    def _on_raw_output(self, line):
        self._status_label.setText(f"{self._status_label.text()}\n{line}")

    def isComplete(self):
        return self.result is not None
