from xsb_gui.pages.confirm_page import SECUREBOOT_ERROR_PAGE_ID
from xsb_gui.pages.migrate_page import _RunnerPage


class SecureBootPage(_RunnerPage):
    _subcommand = "enable-secureboot"
    _done_event = "secureboot_needs_reboot"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Enabling Secure Boot")
        self.setSubTitle("Creating and enrolling Secure Boot keys, then signing boot files.")
        self._needs_reboot = False
        self._had_error = False
        self._outcome_message = ""
        self._error_message = ""

    def initializePage(self):
        self._needs_reboot = False
        self._had_error = False
        self._outcome_message = ""
        self._error_message = ""
        super().initializePage()

    def _on_event(self, event):
        super()._on_event(event)
        event_name = event.get("event", "")
        if event_name == "secureboot_already_active":
            self._complete = True
            self._needs_reboot = False
            self.completeChanged.emit()
        elif event_name == "secureboot_needs_reboot":
            self._complete = True
            self._needs_reboot = True
            self._outcome_message = event.get("message", "")
            self.completeChanged.emit()
        elif event_name == "error":
            self._had_error = True
            self._error_message = event.get("message", "")
            self.wizard().next()

    def nextId(self):
        if self._had_error:
            return SECUREBOOT_ERROR_PAGE_ID
        return super().nextId()
