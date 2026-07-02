from unittest.mock import patch

from xsb_gui.pages.secureboot_error_page import SecureBootErrorPage


class FakeLog:
    def __init__(self, text):
        self._text = text

    def toPlainText(self):
        return self._text


class FakeSecureBootPage:
    def __init__(self, error_message, log_text):
        self._error_message = error_message
        self.log = FakeLog(log_text)


class FakeWizard:
    def __init__(self, secureboot_page):
        self._secureboot_page = secureboot_page

    def page(self, _page_id):
        return self._secureboot_page


def test_initialize_page_pulls_error_message_and_log_from_secureboot_page(qtbot):
    fake_secureboot_page = FakeSecureBootPage(
        error_message="Setup Mode is not active.",
        log_text="[INFO] Signing EFI binaries and kernels\n[ERROR] Setup Mode is not active.",
    )
    page = SecureBootErrorPage()
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(fake_secureboot_page)

    page.initializePage()

    assert page.error_message_label.text() == "Setup Mode is not active."
    assert "Signing EFI binaries" in page._log_text


def test_save_log_writes_full_log_text_when_path_selected(qtbot, tmp_path):
    fake_secureboot_page = FakeSecureBootPage(
        error_message="boom",
        log_text="full accumulated log contents",
    )
    page = SecureBootErrorPage()
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(fake_secureboot_page)
    page.initializePage()

    target = tmp_path / "xsb-gui-error.log"
    with patch(
        "xsb_gui.pages.secureboot_error_page.QFileDialog.getSaveFileName",
        return_value=(str(target), "Log Files (*.log)"),
    ):
        page._save_log()

    assert target.read_text() == "full accumulated log contents"


def test_save_log_does_nothing_when_dialog_cancelled(qtbot, tmp_path):
    fake_secureboot_page = FakeSecureBootPage(error_message="boom", log_text="some log")
    page = SecureBootErrorPage()
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(fake_secureboot_page)
    page.initializePage()

    with patch(
        "xsb_gui.pages.secureboot_error_page.QFileDialog.getSaveFileName",
        return_value=("", ""),
    ):
        page._save_log()

    assert list(tmp_path.iterdir()) == []


def test_next_id_is_terminal(qtbot):
    page = SecureBootErrorPage()
    qtbot.addWidget(page)
    assert page.nextId() == -1
