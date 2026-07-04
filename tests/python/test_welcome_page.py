from unittest.mock import patch

from PyQt6.QtCore import Qt

from xsb_gui.pages.welcome_page import CAUTION_TEXT, WelcomePage
from xsb_gui.widgets.marching_ants_frame import MarchingAntsFrame


def test_welcome_page_blocks_next_until_checkbox_is_checked(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    assert page.isComplete() is False

    qtbot.mouseClick(page.understand_checkbox, Qt.MouseButton.LeftButton)

    assert page.isComplete() is True


def test_welcome_page_shows_caution_pill(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    assert isinstance(page.caution_label, MarchingAntsFrame)
    assert page.caution_label.label.text() == CAUTION_TEXT


def test_welcome_page_checkbox_is_last_widget(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    widgets = [layout.itemAt(i).widget() for i in range(layout.count()) if layout.itemAt(i).widget()]
    assert widgets[-1] is page.understand_checkbox


def test_welcome_page_caution_pill_comes_after_the_explanation_paragraph(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    widgets = [layout.itemAt(i).widget() for i in range(layout.count()) if layout.itemAt(i).widget()]
    assert widgets.index(page.caution_label) > 0
    explanation_label = widgets[0]
    assert explanation_label is not page.caution_label
    assert widgets.index(page.caution_label) < widgets.index(page.understand_checkbox)


def test_check_status_button_sits_between_the_caution_pill_and_checkbox(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    widgets = [layout.itemAt(i).widget() for i in range(layout.count()) if layout.itemAt(i).widget()]
    assert widgets.index(page.caution_label) < widgets.index(page.check_status_button)
    assert widgets.index(page.check_status_button) < widgets.index(page.understand_checkbox)


def test_clicking_check_status_button_opens_the_status_dialog(qtbot):
    page = WelcomePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.welcome_page.SecureBootStatusDialog") as mock_dialog_cls:
        page.check_status_button.click()

    mock_dialog_cls.assert_called_once_with("/fake/helper", False, page)
    mock_dialog_cls.return_value.exec.assert_called_once()
