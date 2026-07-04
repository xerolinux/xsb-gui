from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QCheckBox, QLabel, QPushButton, QSizePolicy, QVBoxLayout, QWizardPage

from xsb_gui.widgets.marching_ants_frame import MarchingAntsFrame
from xsb_gui.widgets.secureboot_status_dialog import SecureBootStatusDialog

CAUTION_TEXT = (
    '<p align="center">⚠ USE AT YOUR OWN RISK ⚠</p>'
    '<p align="justify">Pop quiz: what beats a fresh Limine and Secure Boot setup? A backup '
    "of your data, taken about five minutes ago. Before you hit Next: open your firmware "
    "setup, turn Secure Boot off, and clear out any old keys sitting in there. Skip that "
    "prep and a hiccup mid-migration means a live-USB repair job instead of a quick "
    "reboot.</p>"
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
    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self.setTitle("XeroLinux Limine/SecureBoot Enabler")
        self.setSubTitle("Please read carefully before continuing.")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        label = QLabel(WARNING_TEXT)
        label.setWordWrap(True)
        layout.addWidget(label)

        layout.addStretch(1)

        self.caution_label = MarchingAntsFrame(CAUTION_TEXT)
        layout.addWidget(self.caution_label)

        layout.addSpacing(10)

        self.check_status_button = QPushButton("Check SecureBoot Status")
        self.check_status_button.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.check_status_button.clicked.connect(self._on_check_status_clicked)
        layout.addWidget(self.check_status_button, alignment=Qt.AlignmentFlag.AlignHCenter)

        layout.addStretch(3)

        self.understand_checkbox = QCheckBox("I understand, and want to proceed")
        self.understand_checkbox.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.understand_checkbox.toggled.connect(self.completeChanged)
        layout.addWidget(self.understand_checkbox)

    def _on_check_status_clicked(self):
        dialog = SecureBootStatusDialog(self._helper_path, self._use_pkexec, self)
        dialog.exec()

    def isComplete(self):
        return self.understand_checkbox.isChecked()
