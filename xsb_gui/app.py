import sys
from pathlib import Path

from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QApplication, QWizard

from xsb_gui.pages.welcome_page import WelcomePage
from xsb_gui.pages.preflight_page import PreflightPage
from xsb_gui.pages.confirm_page import (
    ConfirmPage, WELCOME_PAGE_ID, PREFLIGHT_PAGE_ID, CONFIRM_PAGE_ID,
    MIGRATE_PAGE_ID, SECUREBOOT_PAGE_ID, DONE_PAGE_ID, SECUREBOOT_ERROR_PAGE_ID,
)
from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage
from xsb_gui.pages.secureboot_error_page import SecureBootErrorPage
from xsb_gui.pages.done_page import DonePage


def _resolve_helper_path():
    local_helper = Path(__file__).resolve().parent.parent / "xsb-helper"
    if local_helper.exists():
        return str(local_helper)
    return "/usr/lib/xsb-gui/xsb-helper"


HELPER_PATH = _resolve_helper_path()
ICON_PATH = Path(__file__).resolve().parent / "assets" / "xsb-gui.png"


def build_wizard(helper_path=HELPER_PATH, use_pkexec=True):
    wizard = QWizard()
    wizard.setWindowTitle("XeroLinux Limine/SecureBoot Enabler")
    wizard.setMinimumSize(720, 520)
    if ICON_PATH.exists():
        icon = QIcon(str(ICON_PATH))
        wizard.setWindowIcon(icon)
        wizard.setPixmap(QWizard.WizardPixmap.LogoPixmap, icon.pixmap(48, 48))
    wizard.setPage(WELCOME_PAGE_ID, WelcomePage())
    wizard.setPage(PREFLIGHT_PAGE_ID, PreflightPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(CONFIRM_PAGE_ID, ConfirmPage())
    wizard.setPage(MIGRATE_PAGE_ID, MigratePage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(SECUREBOOT_PAGE_ID, SecureBootPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(SECUREBOOT_ERROR_PAGE_ID, SecureBootErrorPage())
    wizard.setPage(DONE_PAGE_ID, DonePage(helper_path=helper_path, use_pkexec=use_pkexec))
    return wizard


def main():
    app = QApplication(sys.argv)
    wizard = build_wizard()
    wizard.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
