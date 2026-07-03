import re
from pathlib import Path

from PyQt6.QtWidgets import QMessageBox

XEROLINUX_ID = "xerolinux"
OS_RELEASE_PATH = Path("/etc/os-release")

UNSUPPORTED_DISTRO_TITLE = "Unsupported Distro"
UNSUPPORTED_DISTRO_TEXT = (
    '<p align="justify">You\'re on <b>{distro_name}</b>, not <b>XeroLinux</b>. This '
    "tool was built and tested for XeroLinux only, so consider this uncharted "
    "territory.</p>"
    '<p align="justify">It\'ll probably run fine, but if something breaks, that\'s on '
    "you: no support for this distro. Proceed at your own risk.</p>"
)


def _parse_os_release(text):
    fields = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        fields[key.strip()] = value.strip().strip('"').strip("'")
    return fields


def detect_distro(os_release_text=None):
    """Returns (distro_id, display_name) parsed from os-release content.

    Falls back to ("unknown", "an unknown distro") if os_release_text is None
    and /etc/os-release can't be read, or if the ID field is missing.
    """
    if os_release_text is None:
        try:
            os_release_text = OS_RELEASE_PATH.read_text()
        except OSError:
            return "unknown", "an unknown distro"

    fields = _parse_os_release(os_release_text)
    distro_id = fields.get("ID", "unknown").lower()
    display_name = fields.get("PRETTY_NAME") or fields.get("NAME") or distro_id
    display_name = re.sub(r"\s+Linux$", "", display_name, flags=re.IGNORECASE)
    return distro_id, display_name


def maybe_warn_unsupported_distro(parent, os_release_text=None):
    """Shows a dismissable warning popup if the running distro isn't XeroLinux.

    Never blocks progress: the dialog has a single acknowledgement button.
    Returns True if the warning was shown, False if the distro is XeroLinux.
    """
    distro_id, display_name = detect_distro(os_release_text)
    if distro_id == XEROLINUX_ID:
        return False

    box = QMessageBox(parent)
    box.setIcon(QMessageBox.Icon.Warning)
    box.setWindowTitle(UNSUPPORTED_DISTRO_TITLE)
    box.setText(UNSUPPORTED_DISTRO_TEXT.format(distro_name=display_name))
    understand_button = box.addButton("I Understand", QMessageBox.ButtonRole.AcceptRole)
    box.setDefaultButton(understand_button)
    box.exec()
    return True
