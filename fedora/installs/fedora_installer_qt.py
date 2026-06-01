#!/usr/bin/env python3
"""
Fedora Post-Install Manager - PyQt6 GUI
Manages NVIDIA driver installation, application installs, and VirtualBox setup.
"""

from __future__ import annotations
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from PyQt6.QtCore import (
    Qt,
    QThread,
    pyqtSignal,
)
from PyQt6.QtGui import (
    QFont,
    QKeySequence,
    QShortcut,
)
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent.resolve()
STATE_FILE = Path.home() / ".fedora_install_state.json"
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
APPS_SCRIPT = SCRIPT_DIR / "3_install_fedora_apps_after_nvidia.sh"


def _fn_name_to_label(fn_name: str) -> str:
    """Convert a bash function name to a human-readable label.

    E.g. ``system_add_sudoers`` → ``System: Add Sudoers``
    """
    prefixes = ("system_", "install_", "remove_", "configure_", "refresh_")
    for prefix in prefixes:
        if fn_name.startswith(prefix):
            category = prefix.rstrip("_").capitalize()
            rest = fn_name[len(prefix) :].replace("_", " ").title()
            return f"{category}: {rest}"
    return fn_name.replace("_", " ").title()


def _parse_all_functions(script_path: Path) -> list[tuple[str, str]]:
    """Parse the ALL_FUNCTIONS array from the bash script.

    Returns a list of ``(function_name, label)`` tuples, skipping
    commented-out entries.
    """
    text = script_path.read_text(encoding="utf-8")

    # Extract the ALL_FUNCTIONS=( ... ) block
    match = re.search(
        r"ALL_FUNCTIONS=\(\s*\n(.*?)\)",
        text,
        re.DOTALL,
    )
    if not match:
        return []

    functions: list[tuple[str, str]] = []
    for line in match.group(1).splitlines():
        stripped = line.strip()
        # Skip empty lines and commented-out entries
        if not stripped or stripped.startswith("#"):
            continue
        fn_name = stripped
        functions.append((fn_name, _fn_name_to_label(fn_name)))
    return functions


APPS_FUNCTIONS = _parse_all_functions(APPS_SCRIPT)

DEFAULT_STATE = {
    "nvidia_installed": False,
    "nvidia_verified": False,
    "apps": {},
    "all_apps_completed": False,
    "virtualbox_installed": False,
    "virtualbox_verified": False,
}

# ---------------------------------------------------------------------------
# Status icon helpers
# ---------------------------------------------------------------------------

_ICON_PENDING = "\u25cb"  # gray circle ○
_ICON_RUNNING = "\u25c9"  # blue fisheye ◉
_ICON_SUCCESS = "\u2713"  # green check ✓
_ICON_FAILED = "\u2717"  # red cross ✗


def _add_cancel_and_log(
    widget: QWidget,
    btn_layout: QHBoxLayout,
    layout: QVBoxLayout,
    *,
    btn_height: int = 40,
    log_height: int = 250,
    log_stretch: int = 0,
) -> tuple[QPushButton, QPlainTextEdit]:
    """Add a Cancel button to *btn_layout* and a log widget to *layout*."""
    btn_cancel = QPushButton("Cancel")
    btn_cancel.setMinimumHeight(btn_height)
    btn_cancel.setEnabled(False)
    btn_cancel.clicked.connect(widget.cancel)
    btn_layout.addWidget(btn_cancel)

    layout.addLayout(btn_layout)

    log = QPlainTextEdit()
    log.setReadOnly(True)
    log.setFont(QFont("Monospace", 9))
    log.setMinimumHeight(log_height)
    layout.addWidget(log, stretch=log_stretch)
    return btn_cancel, log


def _status_label(status: str) -> str:
    """Return a rich-text snippet for the given status."""
    if status == "completed":
        return f'<span style="color:#2ecc71;font-size:16px;">{_ICON_SUCCESS}</span>'
    if status == "failed":
        return f'<span style="color:#e74c3c;font-size:16px;">{_ICON_FAILED}</span>'
    if status == "running":
        return f'<span style="color:#3498db;font-size:16px;">{_ICON_RUNNING}</span>'
    # pending
    return f'<span style="color:#95a5a6;font-size:16px;">{_ICON_PENDING}</span>'


# ---------------------------------------------------------------------------
# State management
# ---------------------------------------------------------------------------


def load_state() -> dict:
    """Load persisted state from disk, merging with defaults."""
    state = dict(DEFAULT_STATE)
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, encoding="utf-8") as fh:
                saved = json.load(fh)
            state.update(saved)
        except json.JSONDecodeError, OSError:
            pass
    return state


def save_state(state: dict) -> None:
    """Persist state to disk."""
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2)
    except OSError as exc:
        print(f"Warning: could not save state: {exc}", file=sys.stderr)


# ---------------------------------------------------------------------------
# ScriptRunner - QThread wrapper around subprocess
# ---------------------------------------------------------------------------


class ScriptRunner(QThread):
    """Run a shell command in a background thread, emitting output line by line."""

    output_line = pyqtSignal(str)
    finished = pyqtSignal(int)  # exit code

    def __init__(self, command: list[str], parent=None):
        super().__init__(parent)
        self._command = command
        self._process: subprocess.Popen | None = None
        self._cancelled = False

    # -- public API --

    def cancel(self) -> None:
        """Request cancellation. Sends SIGTERM to the subprocess."""
        self._cancelled = True
        if self._process and self._process.poll() is None:
            try:
                self._process.terminate()
            except OSError:
                pass

    # -- thread entry --

    def run(self) -> None:
        try:
            self._process = subprocess.Popen(  # noqa: S603
                self._command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            for line in self._process.stdout:
                if self._cancelled:
                    break
                clean = ANSI_ESCAPE_RE.sub("", line).rstrip("\n")
                self.output_line.emit(clean)
            self._process.wait()
            exit_code = self._process.returncode if not self._cancelled else -1
        except FileNotFoundError:
            self.output_line.emit("ERROR: command not found")
            exit_code = 127
        except Exception as exc:
            self.output_line.emit(f"ERROR: {exc}")
            exit_code = 1
        self.finished.emit(exit_code)


# ---------------------------------------------------------------------------
# ProcessWatcher - watches a subprocess.Popen in a thread
# ---------------------------------------------------------------------------


class _ProcessWatcher(QThread):
    """Watch a subprocess.Popen and emit when it finishes."""

    finished_signal = pyqtSignal(int)

    def __init__(self, process: subprocess.Popen, parent: QWidget | None = None):
        super().__init__(parent)
        self._process = process

    def run(self) -> None:
        self._process.wait()
        self.finished_signal.emit(self._process.returncode)


# ---------------------------------------------------------------------------
# Tab base - shared Install/Verify UI for NVIDIA and VirtualBox
# ---------------------------------------------------------------------------


class _InstallVerifyTab(QWidget):
    """Base tab for install-then-verify workflows (NVIDIA, VirtualBox)."""

    state_changed = pyqtSignal()

    def __init__(
        self,
        state: dict,
        *,
        title: str,
        install_label: str,
        verify_label: str,
        install_script: Path,
        verify_script: Path,
        installed_key: str,
        verified_key: str,
        success_marker: str,
        success_msg: str,
        parent=None,
    ):
        super().__init__(parent)
        self._state = state
        self._runner: ScriptRunner | None = None
        self._install_watcher: _ProcessWatcher | None = None
        self._install_script = install_script
        self._verify_script = verify_script
        self._installed_key = installed_key
        self._verified_key = verified_key
        self._success_marker = success_marker
        self._success_msg = success_msg
        self._title = title
        self._install_label = install_label
        self._verify_label = verify_label
        self._init_ui()
        self._sync_ui()

    def _init_ui(self) -> None:
        layout = QVBoxLayout(self)

        header = QLabel(f"<h2>{self._title}</h2>")
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(header)

        # Status area
        status_frame = QFrame()
        status_frame.setFrameShape(QFrame.Shape.StyledPanel)
        status_layout = QHBoxLayout(status_frame)

        self._install_status = QLabel()
        self._install_status.setTextFormat(Qt.TextFormat.RichText)
        status_layout.addWidget(QLabel("Install:"))
        status_layout.addWidget(self._install_status)
        status_layout.addSpacing(30)

        self._verify_status = QLabel()
        self._verify_status.setTextFormat(Qt.TextFormat.RichText)
        status_layout.addWidget(QLabel("Verification:"))
        status_layout.addWidget(self._verify_status)
        status_layout.addStretch()

        layout.addWidget(status_frame)

        # Reboot notice
        self._reboot_label = QLabel(
            '<span style="color:#e67e22;font-weight:bold;">Reboot required. After reboot, click Verify.</span>'
        )
        self._reboot_label.setTextFormat(Qt.TextFormat.RichText)
        self._reboot_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._reboot_label.setVisible(False)
        layout.addWidget(self._reboot_label)

        # Buttons
        btn_layout = QHBoxLayout()

        self._btn_install = QPushButton(self._install_label)
        self._btn_install.setMinimumHeight(40)
        self._btn_install.clicked.connect(self._on_install)
        btn_layout.addWidget(self._btn_install)

        self._btn_verify = QPushButton(self._verify_label)
        self._btn_verify.setMinimumHeight(40)
        self._btn_verify.clicked.connect(self._on_verify)
        btn_layout.addWidget(self._btn_verify)

        self._btn_cancel, self._log = _add_cancel_and_log(self, btn_layout, layout)

    def _sync_ui(self) -> None:
        installed = self._state.get(self._installed_key, False)
        verified = self._state.get(self._verified_key, False)

        self._install_status.setText(_status_label("completed") if installed else _status_label("pending"))
        self._verify_status.setText(_status_label("completed") if verified else _status_label("pending"))

        self._reboot_label.setVisible(installed and not verified)

        if installed and not verified:
            self._btn_verify.setStyleSheet(
                "QPushButton { background-color: #e67e22; color: white; font-weight: bold; }"
            )
        else:
            self._btn_verify.setStyleSheet("")

    def _on_install(self) -> None:
        if not self._install_script.exists():
            QMessageBox.critical(self, "Error", f"Script not found:\n{self._install_script}")
            return

        self._log.clear()
        self._log.appendPlainText(f"Launching {self._title.lower()} in interactive terminal...")
        self._log.appendPlainText("A Konsole window will open. Follow the prompts to set your MOK password.")

        konsole_bin = shutil.which("konsole")
        if not konsole_bin:
            QMessageBox.critical(self, "Error", "Could not find konsole. Is it installed?")
            return
        try:
            process = subprocess.Popen(  # noqa: S603
                [konsole_bin, "-e", "sudo", "bash", str(self._install_script)]
            )
        except FileNotFoundError:
            QMessageBox.critical(self, "Error", "Could not launch konsole. Is it installed?")
            return

        self._btn_install.setEnabled(False)
        self._btn_verify.setEnabled(False)
        self._log.appendPlainText("Waiting for installer to finish...")

        self._install_watcher = _ProcessWatcher(process, self)
        self._install_watcher.finished_signal.connect(self._on_install_done)
        self._install_watcher.start()

    def _on_install_done(self, _exit_code: int) -> None:
        self._btn_install.setEnabled(True)
        self._btn_verify.setEnabled(True)

        self._state[self._installed_key] = True
        save_state(self._state)
        self._sync_ui()
        self.state_changed.emit()

        self._log.appendPlainText("")
        self._log.appendPlainText(f"{self._title} finished. Reboot required. After reboot, click Verify.")

    def _on_verify(self) -> None:
        if not self._verify_script.exists():
            QMessageBox.critical(self, "Error", f"Script not found:\n{self._verify_script}")
            return

        self._log.clear()
        self._set_running(True)

        self._runner = ScriptRunner(["sudo", "bash", str(self._verify_script)])
        self._verify_output_lines: list[str] = []
        self._runner.output_line.connect(self._on_verify_line)
        self._runner.finished.connect(self._on_verify_done)
        self._runner.start()

    def _on_verify_line(self, line: str) -> None:
        self._log.appendPlainText(line)
        self._verify_output_lines.append(line)
        sb = self._log.verticalScrollBar()
        sb.setValue(sb.maximum())

    def _on_verify_done(self, _exit_code: int) -> None:
        self._set_running(False)

        full_output = "\n".join(self._verify_output_lines)
        if self._success_marker in full_output:
            self._state[self._verified_key] = True
            save_state(self._state)
            self._sync_ui()
            self.state_changed.emit()
            self._log.appendPlainText("")
            self._log.appendPlainText(f"=== {self._title} verification PASSED ===")
            QMessageBox.information(self, "Success", self._success_msg)
        else:
            self._log.appendPlainText("")
            self._log.appendPlainText(f"=== {self._title} verification FAILED ===")
            QMessageBox.warning(
                self,
                "Verification Failed",
                f"{self._title} verification did not pass.\n"
                "Check the log output for details.\n"
                "You may need to reboot first.",
            )

    def cancel(self) -> None:
        if self._runner and self._runner.isRunning():
            self._runner.cancel()

    def _set_running(self, running: bool) -> None:
        self._btn_install.setEnabled(not running)
        self._btn_verify.setEnabled(not running)
        self._btn_cancel.setEnabled(running)


# ---------------------------------------------------------------------------
# Tab 2 - Apps
# ---------------------------------------------------------------------------


class AppsTab(QWidget):
    """Application installation tab with per-function checkboxes."""

    apps_state_changed = pyqtSignal()

    def __init__(self, state: dict, parent=None):
        super().__init__(parent)
        self._state = state
        self._runner: ScriptRunner | None = None
        self._queue: list[tuple[str, str]] = []
        self._current_fn: str | None = None
        self._total_to_run = 0
        self._completed_count = 0
        self._rows: dict[str, dict] = {}  # fn_name -> {checkbox, status_label}
        self._init_ui()
        self._sync_ui()

    # -- UI --

    def _init_ui(self) -> None:
        layout = QVBoxLayout(self)

        header = QLabel("<h2>Application Installation</h2>")
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(header)

        # Scrollable function list
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll_widget = QWidget()
        self._grid = QGridLayout(scroll_widget)
        self._grid.setColumnStretch(2, 1)

        for row_idx, (fn_name, label) in enumerate(APPS_FUNCTIONS):
            status_lbl = QLabel(_status_label("pending"))
            status_lbl.setTextFormat(Qt.TextFormat.RichText)
            status_lbl.setFixedWidth(24)
            self._grid.addWidget(status_lbl, row_idx, 0)

            cb = QCheckBox(label)
            cb.setChecked(True)
            self._grid.addWidget(cb, row_idx, 1)

            self._rows[fn_name] = {"checkbox": cb, "status_label": status_lbl}

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll, stretch=3)

        # Progress bar
        self._progress = QProgressBar()
        self._progress.setMinimum(0)
        self._progress.setMaximum(len(APPS_FUNCTIONS))
        self._progress.setValue(0)
        self._progress.setFormat("%v / %m completed")
        layout.addWidget(self._progress)

        # Buttons
        btn_layout = QHBoxLayout()

        self._btn_run_all = QPushButton("Run All Pending")
        self._btn_run_all.setMinimumHeight(36)
        self._btn_run_all.clicked.connect(self._on_run_all_pending)
        btn_layout.addWidget(self._btn_run_all)

        self._btn_run_selected = QPushButton("Run Selected")
        self._btn_run_selected.setMinimumHeight(36)
        self._btn_run_selected.clicked.connect(self._on_run_selected)
        btn_layout.addWidget(self._btn_run_selected)

        self._btn_cancel, self._log = _add_cancel_and_log(
            self, btn_layout, layout, btn_height=36, log_height=180, log_stretch=2
        )

    # -- state sync --

    def _sync_ui(self) -> None:
        apps = self._state.get("apps", {})
        completed_count = 0
        for fn_name, _label in APPS_FUNCTIONS:
            status = apps.get(fn_name, "pending")
            row = self._rows[fn_name]
            row["status_label"].setText(_status_label(status))
            if status == "completed":
                row["checkbox"].setChecked(False)
                completed_count += 1
            elif status == "failed":
                row["checkbox"].setChecked(True)  # allow retry
        self._progress.setValue(completed_count)

    # -- slots --

    def _on_run_all_pending(self) -> None:
        apps = self._state.get("apps", {})
        queue = []
        for fn_name, label in APPS_FUNCTIONS:
            if apps.get(fn_name) != "completed":
                queue.append((fn_name, label))
                self._rows[fn_name]["checkbox"].setChecked(True)
        if not queue:
            QMessageBox.information(self, "Info", "All functions are already completed.")
            return
        self._start_queue(queue)

    def _on_run_selected(self) -> None:
        queue = []
        for fn_name, label in APPS_FUNCTIONS:
            if self._rows[fn_name]["checkbox"].isChecked():
                queue.append((fn_name, label))
        if not queue:
            QMessageBox.information(self, "Info", "No functions selected.")
            return
        self._start_queue(queue)

    def _start_queue(self, queue: list[tuple[str, str]]) -> None:
        if not APPS_SCRIPT.exists():
            QMessageBox.critical(
                self,
                "Error",
                f"Apps script not found at:\n{APPS_SCRIPT}",
            )
            return

        self._queue = list(queue)
        self._total_to_run = len(queue)
        self._completed_count = 0
        self._log.clear()
        self._set_running(True)
        self._run_next()

    def _run_next(self) -> None:
        if not self._queue:
            self._finish_queue()
            return

        fn_name, label = self._queue.pop(0)
        self._current_fn = fn_name

        # Mark running
        self._rows[fn_name]["status_label"].setText(_status_label("running"))

        self._log.appendPlainText(f"\n{'=' * 60}")
        self._log.appendPlainText(f"  Running: {label}  ({fn_name})")
        self._log.appendPlainText(f"{'=' * 60}\n")

        self._runner = ScriptRunner(["bash", "-c", f'source "{APPS_SCRIPT}" && {fn_name}'])
        self._runner.output_line.connect(self._on_output)
        self._runner.finished.connect(self._on_fn_finished)
        self._runner.start()

    def _on_output(self, line: str) -> None:
        self._log.appendPlainText(line)
        sb = self._log.verticalScrollBar()
        sb.setValue(sb.maximum())

    def _on_fn_finished(self, exit_code: int) -> None:
        fn_name = self._current_fn
        if fn_name is None:
            return

        if exit_code == 0:
            status = "completed"
            self._rows[fn_name]["status_label"].setText(_status_label("completed"))
            self._rows[fn_name]["checkbox"].setChecked(False)
            self._log.appendPlainText(f"\n>>> {fn_name}: COMPLETED (exit 0)\n")
        elif exit_code == -1:
            status = "failed"
            self._rows[fn_name]["status_label"].setText(_status_label("failed"))
            self._log.appendPlainText(f"\n>>> {fn_name}: CANCELLED\n")
            # Stop queue on cancellation
            self._queue.clear()
        else:
            status = "failed"
            self._rows[fn_name]["status_label"].setText(_status_label("failed"))
            self._log.appendPlainText(f"\n>>> {fn_name}: FAILED (exit {exit_code})\n")

        # Persist individual function status
        if "apps" not in self._state:
            self._state["apps"] = {}
        self._state["apps"][fn_name] = status
        save_state(self._state)

        self._completed_count += 1
        # Update progress: count all completed in state
        total_completed = sum(1 for fn, _ in APPS_FUNCTIONS if self._state["apps"].get(fn) == "completed")
        self._progress.setValue(total_completed)

        self._current_fn = None
        self._run_next()

    def _finish_queue(self) -> None:
        self._set_running(False)

        # Check if all completed
        apps = self._state.get("apps", {})
        all_done = all(apps.get(fn_name) == "completed" for fn_name, _ in APPS_FUNCTIONS)
        if all_done:
            self._state["all_apps_completed"] = True
            save_state(self._state)
            self.apps_state_changed.emit()
            self._log.appendPlainText("\n=== ALL FUNCTIONS COMPLETED ===")
            QMessageBox.information(
                self,
                "All Done",
                "All application installs completed!\nTab 3 (VirtualBox) is now unlocked.",
            )
        else:
            failed = [fn for fn, _ in APPS_FUNCTIONS if apps.get(fn) == "failed"]
            if failed:
                self._log.appendPlainText(
                    f"\n{len(failed)} function(s) failed. You can retry them by clicking 'Run Selected'."
                )
            self.apps_state_changed.emit()

    def cancel(self) -> None:
        self._queue.clear()
        if self._runner and self._runner.isRunning():
            self._runner.cancel()

    def _set_running(self, running: bool) -> None:
        self._btn_run_all.setEnabled(not running)
        self._btn_run_selected.setEnabled(not running)
        self._btn_cancel.setEnabled(running)
        # Disable checkboxes while running
        for row in self._rows.values():
            row["checkbox"].setEnabled(not running)


# ---------------------------------------------------------------------------
# Main Window
# ---------------------------------------------------------------------------


class FedoraInstallManager(QMainWindow):
    """Main application window with three tabs."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Fedora Post-Install Manager")
        self.setMinimumSize(900, 700)

        self._state = load_state()

        # Central widget
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)

        # Tab widget
        self._tabs = QTabWidget()
        main_layout.addWidget(self._tabs)

        # Tab 1 - NVIDIA
        self._nvidia_tab = _InstallVerifyTab(
            self._state,
            title="NVIDIA Driver Installation",
            install_label="Install NVIDIA Drivers",
            verify_label="Verify NVIDIA",
            install_script=SCRIPT_DIR / "1_nvidia_install_fedora_secureboot_mok.sh",
            verify_script=SCRIPT_DIR / "2_verify_nvidia_installation_secureboot_mok.sh",
            installed_key="nvidia_installed",
            verified_key="nvidia_verified",
            success_marker="NVIDIA is FULLY WORKING!",
            success_msg="NVIDIA is fully working! Tab 2 (Apps) is now unlocked.",
        )
        self._nvidia_tab.state_changed.connect(self._update_tab_locks)
        self._tabs.addTab(self._nvidia_tab, "NVIDIA")

        # Tab 2 - Apps
        self._apps_tab = AppsTab(self._state)
        self._apps_tab.apps_state_changed.connect(self._update_tab_locks)
        self._tabs.addTab(self._apps_tab, "Apps")

        # Tab 3 - VirtualBox
        self._vbox_tab = _InstallVerifyTab(
            self._state,
            title="VirtualBox Installation",
            install_label="Install VirtualBox",
            verify_label="Verify VirtualBox",
            install_script=SCRIPT_DIR / "4_virtualbox" / "1_install_virtualbox_secureboot_mok.sh",
            verify_script=SCRIPT_DIR / "4_virtualbox" / "2_verification_virtualbox_secureboot_mok.sh",
            installed_key="virtualbox_installed",
            verified_key="virtualbox_verified",
            success_marker="VirtualBox is FULLY WORKING!",
            success_msg="VirtualBox is fully working!",
        )
        self._vbox_tab.state_changed.connect(self._update_tab_locks)
        self._tabs.addTab(self._vbox_tab, "VirtualBox")

        # Apply tab locking
        self._update_tab_locks()

        # Escape key cancels running process
        shortcut = QShortcut(QKeySequence(Qt.Key.Key_Escape), self)
        shortcut.activated.connect(self._on_escape)

    def _update_tab_locks(self) -> None:
        """Enable/disable tabs based on state."""
        nvidia_verified = self._state.get("nvidia_verified", False)
        all_apps = self._state.get("all_apps_completed", False)

        # Tab 2 disabled until NVIDIA verified
        self._tabs.setTabEnabled(1, nvidia_verified)
        if not nvidia_verified:
            self._tabs.setTabToolTip(1, "Complete NVIDIA verification first")
        else:
            self._tabs.setTabToolTip(1, "")

        # Tab 3 disabled until all apps completed
        self._tabs.setTabEnabled(2, all_apps)
        if not all_apps:
            self._tabs.setTabToolTip(2, "Complete all app installations first")
        else:
            self._tabs.setTabToolTip(2, "")

    def _on_escape(self) -> None:
        """Cancel any running process when Escape is pressed."""
        current = self._tabs.currentWidget()
        if isinstance(current, (_InstallVerifyTab, AppsTab)):
            current.cancel()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    # Ensure the GUI does not run as root
    if os.geteuid() == 0:
        print(
            "ERROR: Do not run this GUI as root.\nIndividual scripts will use sudo internally as needed.",
            file=sys.stderr,
        )
        sys.exit(1)

    app = QApplication(sys.argv)
    app.setApplicationName("Fedora Post-Install Manager")

    window = FedoraInstallManager()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
