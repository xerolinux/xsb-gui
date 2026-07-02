from PyQt6.QtCore import Qt

from xsb_gui.pages.welcome_page import CAUTION_TEXT, WelcomePage


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
    assert page.caution_label.text() == CAUTION_TEXT
    assert "background-color: #c0392b" in page.caution_label.styleSheet()


def test_welcome_page_checkbox_is_last_layout_item(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    assert layout.itemAt(layout.count() - 1).widget() is page.understand_checkbox


def test_welcome_page_caution_pill_comes_after_the_explanation_paragraph(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    layout = page.layout()
    widgets = [layout.itemAt(i).widget() for i in range(layout.count()) if layout.itemAt(i).widget()]
    assert widgets.index(page.caution_label) > 0
    explanation_label = widgets[0]
    assert explanation_label is not page.caution_label
    assert widgets.index(page.caution_label) < widgets.index(page.understand_checkbox)
