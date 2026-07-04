from PyQt6.QtWidgets import QWizard, QWizardPage

from xsb_gui.pages.confirm_page import (
    CONFIRM_PAGE_ID, MIGRATE_PAGE_ID, SECUREBOOT_PAGE_ID, ConfirmPage,
)
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


def test_confirm_page_shows_resume_notice_and_skips_migrate_when_limine_already_installed(qtbot):
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="limine",
        luks=False, mkinitcpio_hook="none", other_os=[],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )
    page = ConfirmPage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))

    page.initializePage()

    assert page.isComplete() is True
    assert page.resume_notice_label.isVisible() is True
    assert page.secureboot_warning_label.isVisible() is False
    assert page.nextId() == SECUREBOOT_PAGE_ID


def test_confirm_page_does_not_show_resume_notice_when_grub_detected(qtbot):
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=[],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )
    page = ConfirmPage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))

    page.initializePage()

    assert page.resume_notice_label.isVisible() is False


def test_confirm_page_next_id_defaults_to_migrate_page_when_grub_detected(qtbot):
    # Real QWizard so super().nextId()'s default (currentId()+1) resolves
    # against actual page registration, not the lightweight FakeWizard used
    # for the preflight-result lookup inside initializePage()/nextId().
    wizard = QWizard()
    qtbot.addWidget(wizard)
    page = ConfirmPage()
    wizard.setPage(CONFIRM_PAGE_ID, page)
    wizard.setPage(MIGRATE_PAGE_ID, QWizardPage())
    wizard.setStartId(CONFIRM_PAGE_ID)

    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=[],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))
    page.initializePage()

    assert page.nextId() == MIGRATE_PAGE_ID
