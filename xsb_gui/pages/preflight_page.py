from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.esp_size_check import is_esp_too_small, show_esp_too_small_popup
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
        self._esp_too_small = False
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self.runner = None

    def initializePage(self):
        self._stop_runner()
        self.result = None
        self._esp_too_small = False
        # Without this, re-entering the page (e.g. Back then Next) leaves
        # the Next button stuck enabled from the PRIOR completed run until
        # some later event happens to emit completeChanged - letting the
        # user click through to ConfirmPage while self.result is still
        # None, which crashes there.
        self.completeChanged.emit()
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.error_occurred.connect(self._on_process_error)
        self.runner.raw_output_received.connect(self._on_raw_output)
        self.runner.start("preflight")

    def cleanupPage(self):
        # QWizard calls this when navigating away (e.g. Back). Stop any
        # in-flight helper run so it can't keep running concurrently with
        # a later re-entry.
        self._stop_runner()

    def _stop_runner(self):
        """Stop the current runner (if any), detached from this page.

        Disconnects signals first so a delayed emission from the process
        being torn down isn't mistaken for state from a fresh run (e.g. a
        stale preflight_result after Back then Next re-triggers this page).
        """
        if self.runner is None:
            return
        for signal, slot in (
            (self.runner.event_received, self._on_event),
            (self.runner.finished, self._on_finished),
            (self.runner.error_occurred, self._on_process_error),
            (self.runner.raw_output_received, self._on_raw_output),
        ):
            try:
                signal.disconnect(slot)
            except TypeError:
                pass
        self.runner.stop()

    def _on_event(self, event):
        event_name = event.get("event", "")
        if event_name == "preflight_result":
            self.result = parse_preflight_result(event)
            if is_esp_too_small(self.result.esp_size_bytes):
                self._esp_too_small = True
                self._status_label.setText("EFI system partition is too small.")
                self.completeChanged.emit()
                show_esp_too_small_popup(self, self.result.esp_size_bytes)
                return
            self._status_label.setText("Checks complete.")
            self.completeChanged.emit()
        elif event_name == "error":
            self._status_label.setText(event.get("message", ""))
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
        return self.result is not None and not self._esp_too_small
