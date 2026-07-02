from PyQt6.QtCore import Qt

from xsb_gui.pages.welcome_page import WelcomePage


def test_welcome_page_blocks_next_until_checkbox_is_checked(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    assert page.isComplete() is False

    qtbot.mouseClick(page.understand_checkbox, Qt.MouseButton.LeftButton)

    assert page.isComplete() is True
