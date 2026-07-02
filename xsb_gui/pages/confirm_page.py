from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.parsing import build_summary_text

WELCOME_PAGE_ID = 0
PREFLIGHT_PAGE_ID = 1
CONFIRM_PAGE_ID = 2
MIGRATE_PAGE_ID = 3
SECUREBOOT_PAGE_ID = 4
DONE_PAGE_ID = 5


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
        layout.addStretch()

    def initializePage(self):
        preflight_page = self.wizard().page(PREFLIGHT_PAGE_ID)
        self.summary_label.setText(build_summary_text(preflight_page.result))

    def isComplete(self):
        return True
