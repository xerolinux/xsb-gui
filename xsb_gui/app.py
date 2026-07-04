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
from xsb_gui.distro_check import maybe_warn_unsupported_distro


def _resolve_helper_path():
    local_helper = Path(__file__).resolve().parent.parent / "xsb-helper"
    if local_helper.exists():
        return str(local_helper)
    return "/usr/lib/xsb-gui/xsb-helper"


HELPER_PATH = _resolve_helper_path()
ICON_PATH = Path(__file__).resolve().parent / "assets" / "xsb-gui.png"


class _Wizard(QWizard):
    """Stops any in-flight privileged helper process before the window
    closes, so closing mid-run doesn't leave an orphaned root process.

    Enumerates pages via pageIds()/page() and duck-types on a "runner"
    attribute instead of importing specific page classes, so this keeps
    working as more runner-backed pages are added. DonePage isn't a
    _RunnerPage (its "Reboot to BIOS" handler is a one-off action), so it
    uses "_splash_runner" instead - both attribute names are checked.
    """

    def closeEvent(self, event):
        for page_id in self.pageIds():
            page = self.page(page_id)
            for attr_name in ("runner", "_splash_runner"):
                runner = getattr(page, attr_name, None)
                if runner is not None and hasattr(runner, "stop"):
                    runner.stop()
        super().closeEvent(event)


def build_wizard(helper_path=HELPER_PATH, use_pkexec=True):
    wizard = _Wizard()
    wizard.setWindowTitle("XeroLinux Limine/SecureBoot Enabler")
    wizard.setMinimumSize(720, 520)
    if ICON_PATH.exists():
        icon = QIcon(str(ICON_PATH))
        wizard.setWindowIcon(icon)
        wizard.setPixmap(QWizard.WizardPixmap.LogoPixmap, icon.pixmap(48, 48))
    wizard.setPage(WELCOME_PAGE_ID, WelcomePage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(PREFLIGHT_PAGE_ID, PreflightPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(CONFIRM_PAGE_ID, ConfirmPage())
    wizard.setPage(MIGRATE_PAGE_ID, MigratePage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(SECUREBOOT_PAGE_ID, SecureBootPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(SECUREBOOT_ERROR_PAGE_ID, SecureBootErrorPage())
    wizard.setPage(DONE_PAGE_ID, DonePage(helper_path=helper_path, use_pkexec=use_pkexec))
    # QWizardPage.sizeHint() overestimates height for pages with wrapped
    # rich-text QLabels (Qt heightForWidth quirk), which makes QWizard
    # auto-size the window far taller than the content needs. Pin an
    # explicit size instead of trusting sizeHint.
    wizard.resize(720, 680)
    return wizard


def main():
    app = QApplication(sys.argv)
    wizard = build_wizard()
    wizard.show()
    maybe_warn_unsupported_distro(wizard)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
