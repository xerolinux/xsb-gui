from PyQt6.QtWidgets import QCheckBox, QLabel, QSizePolicy, QVBoxLayout, QWizardPage

WARNING_TEXT = (
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
        self.understand_checkbox = QCheckBox("I understand, and want to proceed")
        self.understand_checkbox.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.understand_checkbox.toggled.connect(self.completeChanged)
        layout.addWidget(self.understand_checkbox)
        layout.addStretch()

    def isComplete(self):
        return self.understand_checkbox.isChecked()
