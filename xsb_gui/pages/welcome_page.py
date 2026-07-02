from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QCheckBox, QLabel, QSizePolicy, QVBoxLayout, QWizardPage

CAUTION_TEXT = (
    '<p align="center">⚠ USE AT YOUR OWN RISK ⚠</p>'
    '<p align="justify">This tool replaces your bootloader and changes Secure Boot '
    "enrollment at the firmware level. Turn Secure Boot off and clear any existing keys "
    "before proceeding. If interrupted or misconfigured, your system can become unbootable "
    "and may need manual recovery from a live USB. Backups are strongly recommended in case "
    "something goes wrong.</p>"
)

WARNING_TEXT = (
    "<p>GRUB currently has known compatibility issues with UEFI Secure Boot on "
    "Arch-based systems and is not recommended if you want Secure Boot enabled. "
    "This wizard migrates you to Limine, which supports Secure Boot more reliably.</p>"
    "<p>This will <b>permanently remove GRUB</b> and related packages (grub, grub-hooks, "
    "update-grub, os-prober) and their files from this system, install Limine and "
    "limine-mkinitcpio-hook, and set Limine up as the bootloader.</p>"
    "<p>If your firmware's Secure Boot Setup Mode is active, Secure Boot keys will also be "
    "created and enrolled.</p>"
    "<p><b>This cannot be undone</b> without manual recovery.</p>"
)


class WelcomePage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("XeroLinux Limine/SecureBoot Enabler")
        self.setSubTitle("Please read carefully before continuing.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        label = QLabel(WARNING_TEXT)
        label.setWordWrap(True)
        layout.addWidget(label)

        self.caution_label = QLabel(CAUTION_TEXT)
        self.caution_label.setWordWrap(True)
        self.caution_label.setStyleSheet(
            "background-color: #c0392b; color: white; border-radius: 20px; "
            "padding: 14px 28px; font-weight: bold; font-size: 14pt;"
        )
        layout.addWidget(self.caution_label, 0, Qt.AlignmentFlag.AlignHCenter)

        layout.addStretch()

        self.understand_checkbox = QCheckBox("I understand, and want to proceed")
        self.understand_checkbox.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.understand_checkbox.toggled.connect(self.completeChanged)
        layout.addWidget(self.understand_checkbox)

    def isComplete(self):
        return self.understand_checkbox.isChecked()
