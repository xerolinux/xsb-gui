from unittest.mock import MagicMock, patch

from xsb_gui.pages.done_page import DONE_ALREADY_ACTIVE_TEXT, DONE_TEXT, DonePage


class FakeSecureBootPage:
    def __init__(self, needs_reboot):
        self._needs_reboot = needs_reboot


class FakeWizard:
    def __init__(self, secureboot_page):
        self._secureboot_page = secureboot_page
        self.buttons = {}

    def page(self, _page_id):
        return self._secureboot_page

    def button(self, wizard_button):
        return self.buttons.setdefault(wizard_button, MagicMock())


def test_constructor_stores_helper_path_and_use_pkexec(qtbot):
    page = DonePage(helper_path="/custom/helper", use_pkexec=False)
    qtbot.addWidget(page)
    assert page._helper_path == "/custom/helper"
    assert page._use_pkexec is False


def test_constructor_defaults_match_other_pages(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    assert page._helper_path == "/usr/lib/xsb-gui/xsb-helper"
    assert page._use_pkexec is True


def test_initialize_page_shows_done_text_and_buttons_when_reboot_needed(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=True))

    page.initializePage()

    assert page.label.text() == DONE_TEXT
    assert page.button_row.isVisible() is True
    assert page.footer_separator.isVisible() is True


def test_initialize_page_shows_already_active_text_and_hides_buttons(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=False))

    page.initializePage()

    assert page.label.text() == DONE_ALREADY_ACTIVE_TEXT
    assert page.button_row.isVisible() is False
    assert page.footer_separator.isVisible() is False


def test_later_button_hides_row_without_spawning_anything(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=True))
    page.initializePage()

    with patch("xsb_gui.pages.done_page.HelperRunner") as mock_runner_cls, \
            patch("xsb_gui.pages.done_page.QProcess") as mock_qprocess_cls:
        page.later_button.click()

    mock_runner_cls.assert_not_called()
    mock_qprocess_cls.startDetached.assert_not_called()
    assert page.button_row.isVisible() is False
    assert page.footer_separator.isVisible() is False


def test_reboot_button_runs_apply_splash_then_reboots_on_success(qtbot):
    page = DonePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=True))
    page.initializePage()

    with patch("xsb_gui.pages.done_page.HelperRunner") as mock_runner_cls, \
            patch("xsb_gui.pages.done_page.QProcess") as mock_qprocess_cls:
        mock_runner = mock_runner_cls.return_value

        page.reboot_button.click()

        mock_runner_cls.assert_called_once_with(helper_path="/fake/helper", use_pkexec=False)
        mock_runner.start.assert_called_once_with("apply-splash")
        assert page.reboot_button.isEnabled() is False
        assert page.later_button.isEnabled() is False

        finished_callback = mock_runner.finished.connect.call_args[0][0]
        finished_callback(0)

        mock_qprocess_cls.startDetached.assert_called_once_with(
            "systemctl", ["reboot", "--firmware-setup"]
        )


def test_reboot_button_reboots_even_on_nonzero_exit_code(qtbot):
    page = DonePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=True))
    page.initializePage()

    with patch("xsb_gui.pages.done_page.HelperRunner") as mock_runner_cls, \
            patch("xsb_gui.pages.done_page.QProcess") as mock_qprocess_cls:
        mock_runner = mock_runner_cls.return_value

        page.reboot_button.click()

        finished_callback = mock_runner.finished.connect.call_args[0][0]
        finished_callback(1)

        mock_qprocess_cls.startDetached.assert_called_once_with(
            "systemctl", ["reboot", "--firmware-setup"]
        )


def test_button_row_and_separator_are_the_last_two_layout_items(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    layout = page.layout()
    count = layout.count()
    assert layout.itemAt(count - 2).widget() is page.footer_separator
    assert layout.itemAt(count - 1).widget() is page.button_row


def test_next_id_returns_no_page_terminal_value(qtbot):
    page = DonePage()
    qtbot.addWidget(page)
    assert page.nextId() == -1


def test_initialize_page_hides_standard_wizard_navigation_buttons(qtbot):
    from PyQt6.QtWidgets import QWizard

    page = DonePage()
    qtbot.addWidget(page)
    fake_wizard = FakeWizard(FakeSecureBootPage(needs_reboot=True))
    page.wizard = lambda: fake_wizard

    page.initializePage()

    for wizard_button in (
        QWizard.WizardButton.BackButton,
        QWizard.WizardButton.NextButton,
        QWizard.WizardButton.FinishButton,
        QWizard.WizardButton.CancelButton,
    ):
        fake_wizard.buttons[wizard_button].setVisible.assert_called_once_with(False)


def test_reboot_button_reboots_even_when_helper_fails_to_start(qtbot):
    page = DonePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(FakeSecureBootPage(needs_reboot=True))
    page.initializePage()

    with patch("xsb_gui.pages.done_page.HelperRunner") as mock_runner_cls, \
            patch("xsb_gui.pages.done_page.QProcess") as mock_qprocess_cls:
        mock_runner = mock_runner_cls.return_value

        page.reboot_button.click()

        error_callback = mock_runner.error_occurred.connect.call_args[0][0]
        error_callback("Failed to start: pkexec not found or not executable")

        mock_qprocess_cls.startDetached.assert_called_once_with(
            "systemctl", ["reboot", "--firmware-setup"]
        )
