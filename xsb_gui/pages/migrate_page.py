from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import QPlainTextEdit, QPushButton, QVBoxLayout, QWizardPage

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import format_event_line


class _RunnerPage(QWizardPage):
    _subcommand = None
    _done_event = None

    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self._complete = False
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        monospace_font = QFont("monospace")
        monospace_font.setStyleHint(QFont.StyleHint.Monospace)
        self.log.setFont(monospace_font)
        self.retry_button = QPushButton("Retry")
        self.retry_button.setVisible(False)
        self.retry_button.clicked.connect(self.retry)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)
        layout.addWidget(self.log)
        layout.addWidget(self.retry_button)
        self.runner = None

    def initializePage(self):
        self._stop_runner()
        self._complete = False
        self.retry_button.setVisible(False)
        self.log.clear()
        # Without this, re-entering the page (e.g. Back then Next) leaves
        # the Next button stuck enabled from the PRIOR completed run until
        # some later event happens to emit completeChanged.
        self.completeChanged.emit()
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.error_occurred.connect(self._on_process_error)
        self.runner.raw_output_received.connect(self._on_raw_output)
        self.runner.start(self._subcommand)

    def cleanupPage(self):
        # QWizard calls this when navigating away (e.g. Back). Stop any
        # in-flight helper run so it can't keep mutating the system
        # concurrently with a later re-entry into this page.
        self._stop_runner()

    def _stop_runner(self):
        """Stop the current runner (if any), detached from this page.

        Disconnects signals first so a delayed emission from the process
        being torn down isn't mistaken for state from a fresh run.
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

    def retry(self):
        self.initializePage()

    def _on_event(self, event):
        self.log.appendPlainText(format_event_line(event))
        if event.get("event", "") == self._done_event:
            self._complete = True
            self.completeChanged.emit()

    def _on_finished(self, exit_code):
        if exit_code != 0 and not self._complete:
            self.retry_button.setVisible(True)
        self.completeChanged.emit()

    def _on_process_error(self, message):
        self.log.appendPlainText(f"[ERROR] {message}")
        self.retry_button.setVisible(True)
        self.completeChanged.emit()

    def _on_raw_output(self, line):
        self.log.appendPlainText(f"[RAW] {line}")

    def isComplete(self):
        return self._complete


class MigratePage(_RunnerPage):
    _subcommand = "migrate"
    _done_event = "migrate_done"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Migrating to Limine")
        self.setSubTitle("Installing Limine and configuring your bootloader. This may take a few minutes.")
