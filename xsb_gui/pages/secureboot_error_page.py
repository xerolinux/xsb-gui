from pathlib import Path

from PyQt6.QtWidgets import QFileDialog, QLabel, QPushButton, QVBoxLayout, QWizardPage

from xsb_gui.pages.confirm_page import SECUREBOOT_PAGE_ID

ERROR_REASSURANCE_TEXT = (
    "<p><b>Your system is safe.</b> Nothing has been removed or changed that would "
    "stop your system from booting normally right now.</p>"
    "<p>Limine is your current, verified-working bootloader. It was checked and "
    "confirmed working before anything else was touched, so this failure does not "
    "leave your system without a working boot path.</p>"
    "<p>Secure Boot enforcement itself was never turned on during this process, so "
    "an unsigned or partially-signed Limine installation still boots fine as-is.</p>"
    "<p><b>Do not enable Secure Boot in firmware</b> until this is fixed and the "
    "Secure Boot step is re-run successfully.</p>"
)


class SecureBootErrorPage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("Secure Boot Setup Failed")
        self.setSubTitle("Your system is safe and still bootable. See details below.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        reassurance_label = QLabel(ERROR_REASSURANCE_TEXT)
        reassurance_label.setWordWrap(True)
        layout.addWidget(reassurance_label)

        self.error_message_label = QLabel("")
        self.error_message_label.setWordWrap(True)
        self.error_message_label.setStyleSheet(
            "background-color: #c0392b; color: white; border-radius: 12px; padding: 12px;"
        )
        layout.addWidget(self.error_message_label)

        self.save_log_button = QPushButton("Save Detailed Log...")
        self.save_log_button.clicked.connect(self._save_log)
        layout.addWidget(self.save_log_button)

        layout.addStretch()

        self._log_text = ""

    def initializePage(self):
        secureboot_page = self.wizard().page(SECUREBOOT_PAGE_ID)
        self.error_message_label.setText(secureboot_page._error_message)
        self._log_text = secureboot_page.log.toPlainText()

    def _save_log(self):
        path, _filter = QFileDialog.getSaveFileName(
            self, "Save Detailed Log", "xsb-gui-error.log", "Log Files (*.log);;All Files (*)"
        )
        if not path:
            return
        Path(path).write_text(self._log_text)

    def nextId(self):
        return -1
