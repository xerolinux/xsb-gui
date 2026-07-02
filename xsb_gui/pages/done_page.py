from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

DONE_TEXT = (
    "<p><b>Done.</b> Reboot your system now.</p>"
    "<p>If your firmware was in Setup Mode, enter UEFI firmware settings after "
    "rebooting and enable Secure Boot, then save and boot normally.</p>"
    "<p>Tip: <code>systemctl reboot --firmware-setup</code></p>"
)


class DonePage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("All done")
        self.setSubTitle("Your system has been migrated to Limine.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)
        label = QLabel(DONE_TEXT)
        label.setWordWrap(True)
        layout.addWidget(label)
        layout.addStretch()
