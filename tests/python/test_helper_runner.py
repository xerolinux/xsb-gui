import os

from PyQt6.QtCore import QProcess

from xsb_gui.helper_runner import HelperRunner

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper.sh")
RAW_OUTPUT_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper_raw_output.sh")
STDERR_OUTPUT_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper_stderr_output.sh")
SLOW_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper_slow.sh")


def test_helper_runner_emits_parsed_events_and_finishes(qtbot):
    runner = HelperRunner(helper_path=FIXTURE, use_pkexec=False)
    events = []
    runner.event_received.connect(events.append)

    with qtbot.waitSignal(runner.finished, timeout=2000) as blocker:
        runner.start("preflight")

    assert blocker.args == [0]
    assert [e["event"] for e in events] == ["preflight_step", "preflight_result"]
    assert events[1]["data"]["bootloader"] == "grub"


def test_helper_runner_uses_pkexec_when_enabled():
    runner = HelperRunner(helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True)
    program, args = runner._build_command(("migrate",))
    assert program == "pkexec"
    assert args == ["/usr/lib/xsb-gui/xsb-helper", "migrate"]


def test_helper_runner_emits_error_occurred_when_process_fails_to_start(qtbot):
    runner = HelperRunner(helper_path="/nonexistent/does-not-exist.sh", use_pkexec=False)

    with qtbot.waitSignal(runner.error_occurred, timeout=2000) as blocker:
        runner.start("preflight")

    assert len(blocker.args) == 1
    message = blocker.args[0]
    assert isinstance(message, str)
    assert message != ""


def test_helper_runner_emits_raw_output_received_for_non_json_lines(qtbot):
    runner = HelperRunner(helper_path=RAW_OUTPUT_FIXTURE, use_pkexec=False)
    events = []
    raw_lines = []
    runner.event_received.connect(events.append)
    runner.raw_output_received.connect(raw_lines.append)

    with qtbot.waitSignal(runner.finished, timeout=2000):
        runner.start("preflight")

    assert [e["event"] for e in events] == ["preflight_step"]
    assert raw_lines == ["pkexec: /usr/lib/xsb-gui/xsb-helper: No such file or directory"]


def test_helper_runner_captures_stderr_output_via_raw_output_received(qtbot):
    runner = HelperRunner(helper_path=STDERR_OUTPUT_FIXTURE, use_pkexec=False)
    raw_lines = []
    runner.raw_output_received.connect(raw_lines.append)

    with qtbot.waitSignal(runner.finished, timeout=2000) as blocker:
        runner.start("preflight")

    assert blocker.args == [1]
    assert raw_lines == ["some diagnostic text"]


def test_helper_runner_stop_is_a_noop_when_not_running():
    runner = HelperRunner(helper_path=FIXTURE, use_pkexec=False)
    # Never started: state is NotRunning. Should not raise.
    runner.stop()
    assert runner._process.state() == QProcess.ProcessState.NotRunning


def test_helper_runner_stop_terminates_a_running_process(qtbot):
    runner = HelperRunner(helper_path=SLOW_FIXTURE, use_pkexec=False)
    runner.start("migrate")

    qtbot.waitUntil(
        lambda: runner._process.state() == QProcess.ProcessState.Running, timeout=2000
    )

    runner.stop()

    qtbot.waitUntil(
        lambda: runner._process.state() == QProcess.ProcessState.NotRunning, timeout=3000
    )
    assert runner._process.state() == QProcess.ProcessState.NotRunning
