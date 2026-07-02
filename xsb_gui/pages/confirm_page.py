from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.parsing import build_summary_text

WELCOME_PAGE_ID = 0
PREFLIGHT_PAGE_ID = 1
CONFIRM_PAGE_ID = 2
MIGRATE_PAGE_ID = 3
SECUREBOOT_PAGE_ID = 4
DONE_PAGE_ID = 5
SECUREBOOT_ERROR_PAGE_ID = 6

SECUREBOOT_ALREADY_ENABLED_WARNING = (
    "Secure Boot is already enabled in your firmware. Migrating now would leave an "
    "unsigned, unbootable Limine after reboot. Reboot into UEFI firmware settings and "
    "disable Secure Boot first. This wizard will safely re-enable it at the end, "
    "once Limine is properly signed."
)


class ConfirmPage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("Confirm migration")
        self.setSubTitle("Review what will happen before continuing.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)
        self.summary_label = QLabel("")
        self.summary_label.setWordWrap(True)
        layout.addWidget(self.summary_label)
        self.secureboot_warning_label = QLabel(SECUREBOOT_ALREADY_ENABLED_WARNING)
        self.secureboot_warning_label.setWordWrap(True)
        self.secureboot_warning_label.setStyleSheet(
            "background-color: #c0392b; color: white; border-radius: 12px; padding: 12px;"
        )
        self.secureboot_warning_label.setVisible(False)
        layout.addWidget(self.secureboot_warning_label)
        layout.addStretch()
        self._blocked = False

    def initializePage(self):
        preflight_page = self.wizard().page(PREFLIGHT_PAGE_ID)
        result = preflight_page.result
        self.summary_label.setText(build_summary_text(result))
        self._blocked = result.secureboot_state == "enabled"
        self.secureboot_warning_label.setVisible(self._blocked)
        self.completeChanged.emit()

    def isComplete(self):
        return not self._blocked
