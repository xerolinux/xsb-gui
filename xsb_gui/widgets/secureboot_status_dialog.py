from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QDialog, QLabel, QPushButton, QVBoxLayout

from xsb_gui.helper_runner import HelperRunner

CHECKING_TEXT = "Checking current status..."

BOOTLOADER_LABELS = {
    "grub": "GRUB",
    "limine": "Limine",
    "none": "Not detected",
}

# Flat gray read as a dull green against the app's dark theme. Uses the same
# pink/blue pair as the welcome page's caution pill (marching_ants_frame.py's
# FILL_PINK/FILL_BLUE) at the same low alpha, so it blends darker against
# this dialog's background instead of sitting fully opaque.
_UNKNOWN_GRADIENT = (
    "qlineargradient(x1:0, y1:0, x2:1, y2:1,"
    " stop:0 rgba(150, 40, 100, 90), stop:1 rgba(40, 70, 150, 90))"
)

# label, accent color/gradient per xsb-helper's detect_secureboot_state() states
SECUREBOOT_LABELS = {
    "enabled": ("Enabled", "#27ae60"),
    "disabled": ("Disabled", "#c0392b"),
    "setup_mode": ("Setup Mode (not yet enabled)", "#e67e22"),
    "unsupported": ("Unknown / not available", _UNKNOWN_GRADIENT),
}

_PANEL_STYLE = "background: {color}; color: white; border-radius: 12px; padding: 14px; font-size: 11pt;"


class SecureBootStatusDialog(QDialog):
    """Modal popup with a quick Secure Boot + bootloader status check.

    Runs xsb-helper's lightweight "status" subcommand (not the full
    preflight) since it only needs the two fields this dialog displays.
    """

    def __init__(self, helper_path, use_pkexec, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Secure Boot Status")
        self.setModal(True)
        self.setMinimumWidth(400)
        self.setMinimumHeight(170)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(16)

        self.status_label = QLabel(CHECKING_TEXT)
        self.status_label.setWordWrap(True)
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.status_label)

        close_button = QPushButton("Close")
        close_button.clicked.connect(self.accept)
        layout.addWidget(close_button, alignment=Qt.AlignmentFlag.AlignHCenter)

        self._runner = HelperRunner(helper_path=helper_path, use_pkexec=use_pkexec)
        self._runner.event_received.connect(self._on_event)
        self._runner.error_occurred.connect(self._on_error)
        self._runner.finished.connect(self._on_finished)
        self._runner.start("status")

    def _on_event(self, event):
        if event.get("event") != "status_result":
            return
        data = event.get("data", {})
        bootloader = data.get("bootloader", "unknown")
        secureboot_state = data.get("secureboot_state", "unknown")
        bootloader_label = BOOTLOADER_LABELS.get(bootloader, bootloader)
        sb_label, sb_color = SECUREBOOT_LABELS.get(secureboot_state, (secureboot_state, _UNKNOWN_GRADIENT))
        self.status_label.setStyleSheet(_PANEL_STYLE.format(color=sb_color))
        self.status_label.setText(
            f"<p><b>Current bootloader:</b> {bootloader_label}</p>"
            f"<p><b>Secure Boot:</b> {sb_label}</p>"
        )
        self.adjustSize()

    def _on_error(self, message):
        self.status_label.setStyleSheet(_PANEL_STYLE.format(color="#c0392b"))
        self.status_label.setText(f"Could not check status: {message}")
        self.adjustSize()

    def _on_finished(self, exit_code):
        # A cancelled/failed pkexec auth exits nonzero without emitting an
        # error_occurred (that's only for QProcess-level failures like
        # FailedToStart) or a status_result event, which would otherwise
        # leave this dialog stuck on "Checking current status..." forever.
        if exit_code != 0 and self.status_label.text() == CHECKING_TEXT:
            self.status_label.setStyleSheet(_PANEL_STYLE.format(color="#c0392b"))
            self.status_label.setText("Status check did not complete.")
            self.adjustSize()

    def done(self, result):
        self._runner.stop()
        super().done(result)
