from unittest.mock import patch

from PyQt6.QtCore import Qt

from xsb_gui.pages.welcome_page import CAUTION_TEXT, WelcomePage
from xsb_gui.widgets.marching_ants_frame import MarchingAntsFrame


def _row_index_containing(layout, widget):
    """Index of the top-level layout row whose nested layout holds `widget`."""
    for i in range(layout.count()):
        item = layout.itemAt(i)
        sub = item.layout()
        if sub is not None and sub.indexOf(widget) != -1:
            return i
    return -1


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


def test_utility_buttons_sit_in_a_row_between_the_caution_pill_and_checkbox(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    positions = {}
    for i in range(layout.count()):
        w = layout.itemAt(i).widget()
        if w is page.caution_label:
            positions["caution"] = i
        elif w is page.understand_checkbox:
            positions["checkbox"] = i
    row_idx = _row_index_containing(layout, page.check_status_button)
    assert row_idx != -1
    assert positions["caution"] < row_idx < positions["checkbox"]
    # All utility buttons share the same row.
    assert _row_index_containing(layout, page.cleanup_button) == row_idx
    assert _row_index_containing(layout, page.revert_button) == row_idx


def test_clicking_check_status_button_opens_the_status_dialog(qtbot):
    page = WelcomePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.welcome_page.SecureBootStatusDialog") as mock_dialog_cls:
        page.check_status_button.click()

    mock_dialog_cls.assert_called_once_with("/fake/helper", False, page)
    mock_dialog_cls.return_value.exec.assert_called_once()


def test_clicking_cleanup_button_opens_the_cleanup_dialog(qtbot):
    page = WelcomePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.welcome_page.CleanupDialog") as mock_dialog_cls:
        page.cleanup_button.click()

    mock_dialog_cls.assert_called_once_with("/fake/helper", False, page)
    mock_dialog_cls.return_value.exec.assert_called_once()


def test_clicking_revert_button_opens_the_revert_dialog(qtbot):
    page = WelcomePage(helper_path="/fake/helper", use_pkexec=False)
    qtbot.addWidget(page)

    with patch("xsb_gui.pages.welcome_page.RevertDialog") as mock_dialog_cls:
        page.revert_button.click()

    mock_dialog_cls.assert_called_once_with("/fake/helper", False, page)
    mock_dialog_cls.return_value.exec.assert_called_once()
