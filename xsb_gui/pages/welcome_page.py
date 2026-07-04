from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QCheckBox, QHBoxLayout, QLabel, QPushButton, QSizePolicy, QVBoxLayout, QWizardPage,
)

from xsb_gui.widgets.marching_ants_frame import MarchingAntsFrame
from xsb_gui.widgets.secureboot_status_dialog import SecureBootStatusDialog
from xsb_gui.widgets.cleanup_dialog import CleanupDialog
from xsb_gui.widgets.repair_limine_dialog import RepairLimineDialog
from xsb_gui.widgets.boot_doctor_dialog import BootDoctorDialog

CAUTION_TEXT = (
    '<p align="center">⚠ USE AT YOUR OWN RISK ⚠</p>'
    '<p align="justify">Pop quiz: what beats a fresh Limine and Secure Boot setup? A backup '
    "of your data, taken about five minutes ago. Before you hit Next: open your firmware "
    "setup, turn Secure Boot off, and clear out any old keys sitting in there. Skip that "
    "prep and a hiccup mid-migration means a live-USB repair job instead of a quick "
    "reboot.</p>"
)

WARNING_TEXT = (
    "<p>GRUB has known Secure Boot compatibility issues on Arch-based systems. This "
    "wizard migrates you to Limine, which supports Secure Boot reliably - and works "
    "the same with or without it enabled.</p>"
    "<p>This <b>permanently removes GRUB</b> and related packages, installs Limine, "
    "and sets it up as your bootloader. If Secure Boot Setup Mode is active, keys "
    "are created and enrolled too.</p>"
    "<p><b>This cannot be undone</b> without manual recovery. If something breaks, "
    "try disabling Secure Boot and clearing its keys in firmware settings first - "
    "if that doesn't help, a system reinstall may be required.</p>"
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

        # Equal stretch above and below the troubleshooting group centres it in
        # the space between the caution pill and the checkbox.
        layout.addStretch(2)

        self.troubleshooting_title = QLabel("<b>Troubleshooting</b>")
        self.troubleshooting_title.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        layout.addWidget(self.troubleshooting_title)

        layout.addSpacing(8)

        self.check_status_button = QPushButton("Check SecureBoot Status")
        self.check_status_button.clicked.connect(self._on_check_status_clicked)
        self.cleanup_button = QPushButton("Clean up ESP")
        self.cleanup_button.clicked.connect(self._on_cleanup_clicked)
        self.repair_button = QPushButton("Repair Limine")
        self.repair_button.clicked.connect(self._on_repair_clicked)
        self.doctor_button = QPushButton("Boot Diagnostics")
        self.doctor_button.clicked.connect(self._on_doctor_clicked)
        # Give every button the same fixed width (the widest one's natural
        # width, so no label is truncated) so both rows align visually.
        self._utility_buttons = (
            self.check_status_button, self.cleanup_button, self.repair_button, self.doctor_button,
        )
        uniform_width = max(b.sizeHint().width() for b in self._utility_buttons)
        for button in self._utility_buttons:
            button.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
            button.setFixedWidth(uniform_width)

        top_row = QHBoxLayout()
        top_row.addStretch(1)
        top_row.addWidget(self.check_status_button)
        top_row.addStretch(1)
        layout.addLayout(top_row)

        layout.addSpacing(10)

        bottom_row = QHBoxLayout()
        bottom_row.setSpacing(28)
        bottom_row.addStretch(1)
        bottom_row.addWidget(self.cleanup_button)
        bottom_row.addWidget(self.repair_button)
        bottom_row.addWidget(self.doctor_button)
        bottom_row.addStretch(1)
        layout.addLayout(bottom_row)

        layout.addStretch(2)

        self.understand_checkbox = QCheckBox("I understand, and want to proceed")
        self.understand_checkbox.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.understand_checkbox.toggled.connect(self.completeChanged)
        layout.addWidget(self.understand_checkbox)

    def _on_check_status_clicked(self):
        dialog = SecureBootStatusDialog(self._helper_path, self._use_pkexec, self)
        dialog.exec()

    def _on_cleanup_clicked(self):
        dialog = CleanupDialog(self._helper_path, self._use_pkexec, self)
        dialog.exec()

    def _on_repair_clicked(self):
        dialog = RepairLimineDialog(self._helper_path, self._use_pkexec, self)
        dialog.exec()

    def _on_doctor_clicked(self):
        dialog = BootDoctorDialog(self._helper_path, self._use_pkexec, self)
        dialog.exec()

    def isComplete(self):
        return self.understand_checkbox.isChecked()
