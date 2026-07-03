from PyQt6.QtCore import QSize
from PyQt6.QtWidgets import QApplication, QMessageBox, QStyle

ESP_MIN_SIZE_BYTES = 1024 * 1024 * 1024  # 1024 MiB

ESP_TOO_SMALL_TITLE = "EFI Partition Too Small"
ESP_TOO_SMALL_TEXT = (
    '<p align="justify">Your EFI system partition is only <b>{size_mib}&nbsp;MiB</b>. '
    "This tool needs at least <b>1024&nbsp;MiB</b> to safely fit multiple signed "
    "kernels, Limine, and the boot splash.</p>"
    '<p align="justify">You\'ll need a bigger EFI partition before this tool can be '
    "used. Resizing isn't something we handle here, and it isn't always possible in "
    "the first place.</p>"
)


def is_esp_too_small(esp_size_bytes):
    """Returns True only when we have a real, positive size reading below the
    floor. A size of 0 (or missing) means detection failed rather than the ESP
    genuinely being 0 bytes, so it's treated as unknown and not flagged.
    """
    return bool(esp_size_bytes) and esp_size_bytes < ESP_MIN_SIZE_BYTES


def show_esp_too_small_popup(parent, esp_size_bytes):
    """Hard-stop popup: the only button quits the whole application, since
    there's nothing else the wizard can usefully do with too small an ESP.
    """
    size_mib = esp_size_bytes // (1024 * 1024)

    box = QMessageBox(parent)
    box.setIcon(QMessageBox.Icon.Critical)
    box.setWindowTitle(ESP_TOO_SMALL_TITLE)
    box.setText(ESP_TOO_SMALL_TEXT.format(size_mib=size_mib))
    # Render the standard icon directly at the target size instead of
    # upscaling QMessageBox's own (small, raster) icon pixmap, which
    # produced visible pixelation.
    icon = box.style().standardIcon(QStyle.StandardPixmap.SP_MessageBoxCritical)
    box.setIconPixmap(icon.pixmap(QSize(40, 40)))
    # QMessageBox's icon cell spans both the text row and the button row, so
    # true vertical centering pulls it down past the text into the button
    # area. Keep it top-anchored (the standard messagebox convention) but
    # nudge it down a bit so it lines up with the first line of text instead
    # of sitting flush against the very top edge.
    box.setStyleSheet(
        "QLabel#qt_msgbox_label{ padding-right: 18px; } "
        "QLabel#qt_msgboxex_icon_label{ margin: 16px; margin-top: 20px; }"
    )
    quit_button = box.addButton("Dang It, Ok !", QMessageBox.ButtonRole.AcceptRole)
    box.setDefaultButton(quit_button)
    box.exec()

    app = QApplication.instance()
    if app is not None:
        app.quit()
