from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.esp_size_check import is_esp_too_small, show_esp_too_small_popup
from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import build_summary_text, parse_preflight_result

WELCOME_PAGE_ID = 0
CONFIRM_PAGE_ID = 1
MIGRATE_PAGE_ID = 2
SECUREBOOT_PAGE_ID = 3
DONE_PAGE_ID = 4
SECUREBOOT_ERROR_PAGE_ID = 5

CHECKING_TEXT = "Running checks..."

RESUME_AT_SECUREBOOT_NOTICE = (
    "Limine is already installed and GRUB has been removed. The migration step will "
    "be skipped - continuing straight to Secure Boot setup."
)

_PILL_STYLE = "background: {color}; color: white; border-radius: 12px; padding: 16px; font-size: 13pt;"
_INFO_COLOR = "#2980b9"
_ERROR_COLOR = "#c0392b"
_SUCCESS_COLOR = "#27ae60"

ALREADY_CONFIGURED_TEXT = (
    "Limine and Secure Boot are both enabled and running successfully - nothing "
    "needs to be done. If you run into issues, use the Repair Limine button on "
    "the previous page."
)


class ConfirmPage(QWizardPage):
    """Runs xsb-helper's preflight checks itself (merged from the former,
    separate PreflightPage - one fewer page for the user to click through)
    and shows the resulting summary. isComplete() blocks "Next" until a
    result actually arrives; most hard-refusals from preflight itself (no
    ESP, existing foreign Secure Boot keys, GRUB+Secure-Boot-already-on,
    etc.) surface via the "error" event. "preflight_already_configured" is
    also a refusal (blocks Next) but a positive one - Limine and Secure
    Boot are already fully set up - so it gets its own event, styling, and
    wording instead of being lumped in with genuine problems.
    """

    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self.setTitle("Checking your system")
        self.setSubTitle("Detecting your current bootloader, partition layout, and Secure Boot state.")
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)
        layout.addStretch(1)
        self.summary_label = QLabel(CHECKING_TEXT)
        self.summary_label.setWordWrap(True)
        layout.addWidget(self.summary_label)
        self.resume_notice_label = QLabel(RESUME_AT_SECUREBOOT_NOTICE)
        self.resume_notice_label.setWordWrap(True)
        self.resume_notice_label.setStyleSheet(_PILL_STYLE.format(color=_INFO_COLOR))
        self.resume_notice_label.setVisible(False)
        layout.addWidget(self.resume_notice_label)
        layout.addStretch(1)

        self.result = None
        self._esp_too_small = False
        self._skip_migrate = False
        self.runner = None

    def initializePage(self):
        self._stop_runner()
        self.result = None
        self._esp_too_small = False
        self._skip_migrate = False
        self._set_summary(CHECKING_TEXT)
        self.resume_notice_label.setVisible(False)
        # Without this, re-entering the page (e.g. Back then Next) leaves
        # the Next button stuck enabled from the PRIOR completed run until
        # some later event happens to emit completeChanged - letting the
        # user click through to MigratePage while self.result is still None.
        self.completeChanged.emit()
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.error_occurred.connect(self._on_process_error)
        self.runner.raw_output_received.connect(self._on_raw_output)
        self.runner.start("preflight")

    def _set_summary(self, text, color=None):
        self.summary_label.setText(text)
        self.summary_label.setStyleSheet(_PILL_STYLE.format(color=color) if color else "")

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
                self._set_summary("EFI system partition is too small.", _ERROR_COLOR)
                self.completeChanged.emit()
                show_esp_too_small_popup(self, self.result.esp_size_bytes)
                return
            self._skip_migrate = self.result.bootloader == "limine"
            self._set_summary(build_summary_text(self.result, migrating=not self._skip_migrate), _INFO_COLOR)
            self.resume_notice_label.setVisible(self._skip_migrate)
            self.completeChanged.emit()
        elif event_name == "preflight_already_configured":
            # Positive status, not a problem - still blocks Next (nothing
            # left for the wizard to do), but styled/worded to match.
            self._set_summary(ALREADY_CONFIGURED_TEXT, _SUCCESS_COLOR)
            self.completeChanged.emit()
        elif event_name == "error":
            self._set_summary(event.get("message", ""), _ERROR_COLOR)
            self.completeChanged.emit()

    def _on_finished(self, _exit_code):
        if self.result is None and self.summary_label.text() == CHECKING_TEXT:
            self._set_summary("Preflight checks did not complete.", _ERROR_COLOR)
            self.completeChanged.emit()

    def _on_process_error(self, message):
        self._set_summary(message, _ERROR_COLOR)
        self.completeChanged.emit()

    def _on_raw_output(self, line):
        self.summary_label.setText(f"{self.summary_label.text()}\n{line}")

    def isComplete(self):
        return self.result is not None and not self._esp_too_small

    def nextId(self):
        if self._skip_migrate:
            return SECUREBOOT_PAGE_ID
        return super().nextId()
