from xsb_gui.pages.confirm_page import ConfirmPage
from xsb_gui.parsing import PreflightResult


class FakePreflightPage:
    def __init__(self, result):
        self.result = result


class FakeWizard:
    def __init__(self, preflight_page):
        self._preflight_page = preflight_page

    def page(self, _page_id):
        return self._preflight_page


def test_confirm_page_shows_summary_from_preflight_result(qtbot):
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )
    page = ConfirmPage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))

    page.initializePage()

    assert "Windows Boot Manager" in page.summary_label.text()
    assert page.isComplete() is True
    assert page.secureboot_warning_label.isVisible() is False


def test_confirm_page_blocks_when_secureboot_already_enabled(qtbot):
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="enabled", esp_size_bytes=1073741824,
    )
    page = ConfirmPage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))

    page.initializePage()

    assert page.isComplete() is False
    assert page.secureboot_warning_label.isVisible() is True
