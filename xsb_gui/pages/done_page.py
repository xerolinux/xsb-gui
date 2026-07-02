from PyQt6.QtCore import QProcess
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget, QWizardPage

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.pages.confirm_page import SECUREBOOT_PAGE_ID

DONE_TEXT = (
    "<p><b>Done.</b> Reboot your system now.</p>"
    "<p>If your firmware was in Setup Mode, enter UEFI firmware settings after "
    "rebooting and enable Secure Boot, then save and boot normally.</p>"
    "<p>Tip: <code>systemctl reboot --firmware-setup</code></p>"
    "<p><b>MSI motherboards:</b> most MSI boards have no Setup Mode. Instead, set "
    "Secure Boot Mode to <b>Custom</b> and select the <b>maximum security</b> "
    "compatibility option in Key Management before enabling Secure Boot.</p>"
    "<p><b>ASUS / Gigabyte motherboards:</b> also usually lack Setup Mode. Go to "
    "Boot &gt; Secure Boot, set Secure Boot Mode to <b>Custom</b>, then use "
    "Key Management &gt; <b>Delete all Secure Boot Variables</b> instead.</p>"
    "<p><b>ASUS, enabling Secure Boot afterward:</b> some ASUS boards have no "
    "separate on/off toggle. Set <b>OS Type</b> to <b>Windows UEFI Mode</b>, not "
    "\"Other OS\" - Other OS silently disables Secure Boot regardless of any "
    "other setting. Path: Boot &gt; Secure Boot &gt; OS Type = Windows UEFI Mode, "
    "Secure Boot Mode = Custom.</p>"
)

DONE_ALREADY_ACTIVE_TEXT = (
    "<p><b>Done.</b> Secure Boot was already active and your boot files have been "
    "freshly signed. No further action is needed. You can close this wizard.</p>"
)


class DonePage(QWizardPage):
    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self.setTitle("All done")
        self.setSubTitle("Your system has been migrated to Limine.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        self.label = QLabel(DONE_TEXT)
        self.label.setWordWrap(True)
        layout.addWidget(self.label)

        self.button_row = QWidget()
        button_layout = QHBoxLayout(self.button_row)
        button_layout.setContentsMargins(0, 0, 0, 0)
        self.reboot_button = QPushButton("Reboot to BIOS")
        self.later_button = QPushButton("Later")
        button_layout.addWidget(self.reboot_button)
        button_layout.addWidget(self.later_button)
        layout.addWidget(self.button_row)

        self.reboot_button.clicked.connect(self._on_reboot_clicked)
        self.later_button.clicked.connect(self._on_later_clicked)

        layout.addStretch()

        self._splash_runner = None

    def initializePage(self):
        secureboot_page = self.wizard().page(SECUREBOOT_PAGE_ID)
        needs_reboot = secureboot_page._needs_reboot
        if needs_reboot:
            self.label.setText(DONE_TEXT)
        else:
            self.label.setText(DONE_ALREADY_ACTIVE_TEXT)
        self.button_row.setVisible(needs_reboot)
        self.reboot_button.setEnabled(True)
        self.later_button.setEnabled(True)
        self.reboot_button.setText("Reboot to BIOS")

    def _on_later_clicked(self):
        self.button_row.setVisible(False)

    def _on_reboot_clicked(self):
        self.reboot_button.setEnabled(False)
        self.later_button.setEnabled(False)
        self.reboot_button.setText("Applying boot splash...")
        self._splash_runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self._splash_runner.finished.connect(self._on_splash_finished)
        self._splash_runner.error_occurred.connect(self._on_splash_error)
        self._splash_runner.start("apply-splash")

    def _on_splash_finished(self, _exit_code):
        self._reboot_to_firmware_setup()

    def _on_splash_error(self, _message):
        self._reboot_to_firmware_setup()

    def _reboot_to_firmware_setup(self):
        QProcess.startDetached("systemctl", ["reboot", "--firmware-setup"])
