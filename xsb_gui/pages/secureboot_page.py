from PyQt6.QtCore import QProcess
from PyQt6.QtWidgets import QMessageBox

from xsb_gui.pages.migrate_page import _RunnerPage

REBOOT_REQUIRED_EXPLANATION = (
    "Secure Boot keys have been created and signed, but Secure Boot itself is "
    "still OFF in your firmware. This step is required to finish protecting "
    "your system with Secure Boot.\n\n"
)


class SecureBootPage(_RunnerPage):
    _subcommand = "enable-secureboot"
    _done_event = "secureboot_needs_reboot"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Enabling Secure Boot")
        self.setSubTitle("Creating and enrolling Secure Boot keys, then signing boot files.")

    def _on_event(self, event):
        super()._on_event(event)
        event_name = event["event"]
        if event_name == "secureboot_already_active":
            self._complete = True
            self.completeChanged.emit()
        elif event_name == "secureboot_needs_reboot":
            self._show_reboot_required_popup(event["message"])
        elif event_name == "error":
            self._show_error_popup(event["message"])

    def _show_reboot_required_popup(self, message):
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Warning)
        box.setWindowTitle("Secure Boot Setup Complete")
        box.setText(REBOOT_REQUIRED_EXPLANATION + message)
        later_button = box.addButton("Later", QMessageBox.ButtonRole.RejectRole)
        reboot_button = box.addButton("Reboot to BIOS", QMessageBox.ButtonRole.AcceptRole)
        box.setDefaultButton(reboot_button)
        box.exec()
        if box.clickedButton() == reboot_button:
            self._trigger_firmware_reboot()

    def _show_error_popup(self, message):
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Critical)
        box.setWindowTitle("Secure Boot Setup Failed")
        box.setText(message)
        box.exec()

    def _trigger_firmware_reboot(self):
        QProcess.startDetached("systemctl", ["reboot", "--firmware-setup"])
