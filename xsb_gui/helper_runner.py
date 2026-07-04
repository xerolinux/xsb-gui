import json

from PyQt6.QtCore import QObject, QProcess, pyqtSignal


class HelperRunner(QObject):
    event_received = pyqtSignal(dict)
    finished = pyqtSignal(int)
    error_occurred = pyqtSignal(str)
    raw_output_received = pyqtSignal(str)

    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self._buffer = ""
        self._process = QProcess(self)
        self._process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._process.readyReadStandardOutput.connect(self._on_ready_read)
        self._process.finished.connect(self._on_finished)
        self._process.errorOccurred.connect(self._on_error)

    def start(self, *args):
        program, prog_args = self._build_command(args)
        self._process.start(program, prog_args)

    def stop(self):
        """Terminate the process: SIGTERM first, SIGKILL if it lingers.

        Best-effort only: under pkexec, the QProcess we control is pkexec
        itself, not the privileged xsb-helper it spawns. Qt can't signal
        descendants, so the already-authorized xsb-helper child may keep
        running under polkit even after pkexec is gone - no clean way to
        reach it from here (no shared process group, no signal forwarding).
        """
        if self._process.state() == QProcess.ProcessState.NotRunning:
            return
        self._process.terminate()
        if not self._process.waitForFinished(2000):
            self._process.kill()
            self._process.waitForFinished(1000)

    def _build_command(self, args):
        if self._use_pkexec:
            return "pkexec", [self._helper_path, *args]
        return self._helper_path, list(args)

    def _on_ready_read(self):
        data = bytes(self._process.readAllStandardOutput()).decode("utf-8", "replace")
        self._buffer += data
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                self.raw_output_received.emit(line)
                continue
            self.event_received.emit(event)

    def _on_finished(self, exit_code, _exit_status):
        self.finished.emit(exit_code)

    def _on_error(self, error):
        if error == QProcess.ProcessError.FailedToStart:
            target = self._helper_path if not self._use_pkexec else "pkexec"
            message = f"Failed to start: {target} not found or not executable"
        else:
            message = f"Process error: {error}"
        self.error_occurred.emit(message)
