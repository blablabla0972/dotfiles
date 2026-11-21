"""Exercise the real calculator QML and process lifecycle under Quickshell."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


LAUNCHER = (Path(__file__).resolve().parents[1]
            / "config/quickshell/rice-shell/launcher")


@unittest.skipUnless(shutil.which("qs") and os.environ.get("WAYLAND_DISPLAY"),
                     "requires Quickshell and a live Wayland session")
class LauncherCalculatorTests(unittest.TestCase):
    def run_calculator(self, source, directory, **overrides):
        path = Path(directory) / "calculator-test.qml"
        (Path(directory) / "launcher").symlink_to(LAUNCHER, target_is_directory=True)
        path.write_text(source)
        result = subprocess.run([shutil.which("qs"), "--no-color", "-p", str(path)],
                                env={**os.environ, **overrides},
                                capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("CALC_PASS", output)

    def test_new_query_invalidates_pending_copy_and_old_process_result(self):
        with tempfile.TemporaryDirectory() as directory:
            qalc = Path(directory) / "qalc"
            qalc.write_text("#!/bin/sh\nfor expr do :; done\n"
                            "if [ \"$expr\" = old ]; then sleep 0.4; fi\n"
                            "printf '%s\\n' \"$expr\"\n")
            qalc.chmod(0o755)
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherCalculator { id: calc; active: true; expression: "old" }
    Connections {
        target: calc
        function onResultChanged() {
            if (calc.expression === "new" && calc.result.value === "old") Qt.exit(4);
        }
    }
    Timer {
        interval: 280; running: true
        onTriggered: {
            calc.expression = "new";
            if (calc.result.value !== undefined) Qt.exit(2);
        }
    }
    Timer {
        interval: 750; running: true
        onTriggered: {
            if (calc.result.value !== "new") Qt.exit(3);
            else { console.log("CALC_PASS"); Qt.quit(); }
        }
    }
}
''', directory, PATH=directory + ":" + os.environ["PATH"])

    def test_missing_executable_falls_back_to_arithmetic(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherCalculator { id: calc; active: true; expression: "3 * -5" }
    Timer {
        interval: 500; running: true
        onTriggered: {
            if (calc.result.value !== "-15") Qt.exit(2);
            else { console.log("CALC_PASS"); Qt.quit(); }
        }
    }
}
''', directory, PATH=directory)

    @unittest.skipUnless(shutil.which("qalc"), "requires qalc")
    def test_qalc_functions_units_percent_and_precision(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    id: root
    property var cases: [
        ["2^3^2", "512"],
        ["sin(pi/2)", "1"],
        ["100 + 10%", "110"],
        ["5 km to m", "5000 m"],
        ["1/7", "0.1428571429"],
        ["2^100", "1.267650600E30"],
        ["1/(2-2)", "error:Cannot divide by zero"]
    ]
    property int index: 0
    LauncherCalculator { id: calc; active: true; expression: root.cases[0][0] }
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: {
            const expected = root.cases[root.index][1];
            const matches = expected.startsWith("error:")
                ? calc.result.error === expected.slice(6)
                : calc.result.value === expected;
            if (matches) {
                root.index++;
                if (root.index === root.cases.length) {
                    console.log("CALC_PASS"); Qt.quit();
                } else calc.expression = root.cases[root.index][0];
            } else if (calc.result.error && calc.result.error !== "Calculating...") {
                console.log("CALC_FAILED", root.cases[root.index][0], JSON.stringify(calc.result));
                Qt.exit(2);
            }
        }
    }
    Timer {
        interval: 6000; running: true
        onTriggered: { console.log("CALC_TIMEOUT", JSON.stringify(calc.result)); Qt.exit(3); }
    }
}
''', directory)

    def test_qalc_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            qalc = Path(directory) / "qalc"
            qalc.write_text("#!/bin/sh\nexec sleep 10\n")
            qalc.chmod(0o755)
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherCalculator { id: calc; active: true; expression: "sqrt(2)" }
    Timer {
        interval: 2200; running: true
        onTriggered: {
            if (calc.result.error !== "Calculation timed out") {
                console.log("CALC_TIMEOUT_FAILED", JSON.stringify(calc.result)); Qt.exit(2);
            } else { console.log("CALC_PASS"); Qt.quit(); }
        }
    }
}
''', directory, PATH=directory + ":" + os.environ["PATH"])

    def test_qalc_empty_output_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            qalc = Path(directory) / "qalc"
            qalc.write_text("#!/bin/sh\nexit 0\n")
            qalc.chmod(0o755)
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherCalculator { id: calc; active: true; expression: "sqrt(2)" }
    Timer {
        interval: 600; running: true
        onTriggered: {
            if (calc.result.error !== "Could not evaluate expression") {
                console.log("CALC_EMPTY_FAILED", JSON.stringify(calc.result)); Qt.exit(2);
            } else { console.log("CALC_PASS"); Qt.quit(); }
        }
    }
}
''', directory, PATH=directory + ":" + os.environ["PATH"])

    def test_deactivating_calculator_discards_running_result(self):
        with tempfile.TemporaryDirectory() as directory:
            qalc = Path(directory) / "qalc"
            marker = Path(directory) / "finished"
            qalc.write_text("#!/bin/sh\nsleep 0.7\n: > \"$CALC_MARKER\"\n"
                            "printf 'late result\\n'\n")
            qalc.chmod(0o755)
            self.run_calculator('''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherCalculator { id: calc; active: true; expression: "sqrt(2)" }
    Timer {
        interval: 350; running: true
        onTriggered: {
            if (calc.result.error !== "Calculating...") Qt.exit(2);
            calc.active = false;
        }
    }
    Timer {
        interval: 1150; running: true
        onTriggered: {
            if (calc.result.error !== "Enter an expression") {
                console.log("CALC_CANCEL_FAILED", JSON.stringify(calc.result)); Qt.exit(3);
            } else { console.log("CALC_PASS"); Qt.quit(); }
        }
    }
}
''', directory, PATH=directory + ":" + os.environ["PATH"],
                CALC_MARKER=str(marker))
            self.assertFalse(marker.exists(), "qalc continued after calculator deactivation")
