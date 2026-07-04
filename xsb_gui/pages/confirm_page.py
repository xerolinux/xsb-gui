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

RESUME_AT_SECUREBOOT_NOTICE = (
    "Limine is already installed and GRUB has been removed. The migration step will "
    "be skipped - continuing straight to Secure Boot setup."
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
        self.resume_notice_label = QLabel(RESUME_AT_SECUREBOOT_NOTICE)
        self.resume_notice_label.setWordWrap(True)
        self.resume_notice_label.setStyleSheet(
            "background-color: #2980b9; color: white; border-radius: 12px; padding: 12px;"
        )
        self.resume_notice_label.setVisible(False)
        layout.addWidget(self.resume_notice_label)
        self.secureboot_warning_label = QLabel(SECUREBOOT_ALREADY_ENABLED_WARNING)
        self.secureboot_warning_label.setWordWrap(True)
        self.secureboot_warning_label.setStyleSheet(
            "background-color: #c0392b; color: white; border-radius: 12px; padding: 12px;"
        )
        self.secureboot_warning_label.setVisible(False)
        layout.addWidget(self.secureboot_warning_label)
        layout.addStretch()
        self._blocked = False
        self._skip_migrate = False

    def initializePage(self):
        preflight_page = self.wizard().page(PREFLIGHT_PAGE_ID)
        result = preflight_page.result
        self._skip_migrate = result.bootloader == "limine"
        self.summary_label.setText(build_summary_text(result, migrating=not self._skip_migrate))
        self._blocked = result.secureboot_state == "enabled"
        self.secureboot_warning_label.setVisible(self._blocked)
        self.resume_notice_label.setVisible(self._skip_migrate)
        self.completeChanged.emit()

    def isComplete(self):
        return not self._blocked

    def nextId(self):
        if self._skip_migrate:
            return SECUREBOOT_PAGE_ID
        return super().nextId()
