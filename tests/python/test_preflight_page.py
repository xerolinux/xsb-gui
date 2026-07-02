import os
from xsb_gui.pages.preflight_page import PreflightPage

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper.sh")
RAW_OUTPUT_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper_raw_output.sh")


def test_preflight_page_becomes_complete_after_preflight_result(qtbot):
    page = PreflightPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    assert page.isComplete() is False

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page.result.bootloader == "grub"


def test_preflight_page_shows_error_and_stays_incomplete_when_process_fails_to_start(qtbot):
    page = PreflightPage(helper_path="/nonexistent/does-not-exist.sh", use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.error_occurred, timeout=2000):
        pass

    assert page.isComplete() is False
    assert page._status_label.text() != "Running checks..."


def test_preflight_page_shows_raw_output_when_non_json_line_received(qtbot):
    page = PreflightPage(helper_path=RAW_OUTPUT_FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert "pkexec: /usr/lib/xsb-gui/xsb-helper: No such file or directory" in page._status_label.text()
