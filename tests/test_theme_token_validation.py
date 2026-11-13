"""Validate palette candidates through the native QML singleton."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOKENS = ROOT / "config/quickshell/rice-shell/theme/Tokens.qml"


@unittest.skipUnless(shutil.which("quickshell"), "Quickshell required")
class ThemeTokenValidationTest(unittest.TestCase):
    def run_until_marker(self, base, main, marker, timeout=5):
        runtime_dir = base / "runtime"
        runtime_dir.mkdir(mode=0o700, exist_ok=True)
        config_home = base / "config"
        config_home.mkdir(exist_ok=True)
        state_home = base / "state"
        (state_home / "desktop-wallpaper").mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(config_home),
                   XDG_STATE_HOME=str(state_home), XDG_RUNTIME_DIR=str(runtime_dir),
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
        for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(name, None)
        process = subprocess.Popen(["quickshell", "--path", str(main), "--no-color"],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1)
        output = ""
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([process.stdout], [], [], 0.1)
                if not ready:
                    if process.poll() is not None:
                        break
                    continue
                line = process.stdout.readline()
                output += line
                if marker in line:
                    break
        finally:
            process.terminate()
            process.wait(timeout=2)
            process.stdout.close()
        return output

    def test_candidate_validation_requires_complete_safe_palette(self):
        with tempfile.TemporaryDirectory(prefix="rice-token-validation-") as directory:
            base = Path(directory)
            theme = base / "theme"
            theme.mkdir()
            shutil.copyfile(TOKENS, theme / "Tokens.qml")
            (theme / "qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            state_home = base / "state"
            (state_home / "desktop-wallpaper").mkdir(parents=True)
            main = base / "main.qml"
            main.write_text('''import QtQuick
import Quickshell
import "./theme"
ShellRoot {
    Timer {
        interval: 50; running: true; repeat: false
        onTriggered: {
            var colors = {
                background: "#000000", surface_low: "#111111", surface: "#222222",
                surface_high: "#333333", text_primary: "#ffffff", text_secondary: "#aaaaaa",
                accent: "#4488cc", on_accent: "#000000", outline: "#555555",
                focus_ring: "#4488cc", danger: "#ff0000"
            };
            var valid = {schema_version: 1, mode: "dark", colors: colors,
                materials: {bar: {opacity: 0.85}, panel: {opacity: 0.92}}};
            var incomplete = JSON.parse(JSON.stringify(valid));
            delete incomplete.colors.focus_ring;
            var wrongType = JSON.parse(JSON.stringify(valid));
            wrongType.colors.accent = 12;
            var badColor = JSON.parse(JSON.stringify(valid));
            badColor.colors.accent = "#12GG00";
            var badMode = JSON.parse(JSON.stringify(valid));
            badMode.mode = "auto";
            var badOpacity = JSON.parse(JSON.stringify(valid));
            badOpacity.materials.panel.opacity = 1.1;
            var nonFiniteOpacity = JSON.parse(JSON.stringify(valid));
            nonFiniteOpacity.materials.bar.opacity = NaN;
            var light = JSON.parse(JSON.stringify(valid));
            light.mode = "light";
            console.log("TOKEN_VALIDATION:" + JSON.stringify({
                dark: Tokens.isValidCandidate(valid), light: Tokens.isValidCandidate(light),
                incomplete: Tokens.isValidCandidate(incomplete), wrongType: Tokens.isValidCandidate(wrongType),
                badColor: Tokens.isValidCandidate(badColor), badMode: Tokens.isValidCandidate(badMode),
                badOpacity: Tokens.isValidCandidate(badOpacity), nonFiniteOpacity: Tokens.isValidCandidate(nonFiniteOpacity)
            }));
        }
    }
}
''')
            output = self.run_until_marker(base, main, "TOKEN_VALIDATION:", timeout=4)
        line = next((line for line in output.splitlines() if "TOKEN_VALIDATION:" in line), "")
        self.assertTrue(line, output)
        actual = json.loads(line.split("TOKEN_VALIDATION:", 1)[1])
        self.assertEqual(actual, {
            "dark": True, "light": True, "incomplete": False, "wrongType": False,
            "badColor": False, "badMode": False, "badOpacity": False, "nonFiniteOpacity": False,
        })

    def test_file_reload_keeps_last_good_and_accepts_atomic_replacement(self):
        colors = {
            "background": "#101010", "surface_low": "#111111", "surface": "#222222",
            "surface_high": "#333333", "text_primary": "#ffffff", "text_secondary": "#aaaaaa",
            "accent": "#123456", "on_accent": "#000000", "outline": "#555555",
            "focus_ring": "#123456", "danger": "#ff0000",
        }
        initial = {"schema_version": 1, "mode": "dark", "colors": colors}
        light = json.loads(json.dumps(initial))
        light["mode"] = "light"
        light["colors"]["accent"] = "#654321"
        invalid = {"schema_version": 1, "mode": "dark", "colors": {"accent": "#ff0000"}}
        with tempfile.TemporaryDirectory(prefix="rice-token-reload-") as directory:
            base = Path(directory)
            theme = base / "theme"
            theme.mkdir()
            shutil.copyfile(TOKENS, theme / "Tokens.qml")
            (theme / "qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            palette = base / "state/desktop-wallpaper/adaptive-theme.json"
            palette.parent.mkdir(parents=True)
            palette.write_text(json.dumps(initial))
            writer = base / "write_palette.py"
            writer.write_text(
                "import os, pathlib, sys\n"
                "path = pathlib.Path(sys.argv[1])\n"
                "temp = path.with_suffix('.tmp')\n"
                "temp.write_text(sys.argv[2])\n"
                "os.replace(temp, path)\n"
            )
            main = base / "main.qml"
            qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "./theme"
ShellRoot {
    id: root
    property var tokenService: Tokens
    property int writeStage: 0
    Process {
        id: writer
        onExited: (exitCode) => {
            if (exitCode !== 0) root.fail("palette writer failed");
            else if (root.writeStage === 1) checkLastGood.start();
            else if (root.writeStage === 2) checkLight.start();
        }
    }
    function writePalette(text, stage) {
        writeStage = stage;
        writer.command = [__PYTHON__, __WRITER__, __PALETTE__, text];
        writer.running = true;
    }
    function fail(message) { console.error("TOKEN_RELOAD_FAIL:" + message); }
    Timer {
        interval: 500; running: true; repeat: false
        onTriggered: {
            if (!Tokens.isValid || Tokens.mode !== "dark"
                || Tokens.parsedData.colors.accent !== "#123456") {
                root.fail("initial dark palette missing"); return;
            }
            root.writePalette(__INVALID__, 1);
        }
    }
    Timer {
        id: checkLastGood; interval: 250; repeat: false
        onTriggered: {
            if (!Tokens.isValid || Tokens.mode !== "dark"
                || Tokens.parsedData.colors.accent !== "#123456") {
                root.fail("invalid replacement discarded last-known-good"); return;
            }
            root.writePalette(__LIGHT__, 2);
        }
    }
    Timer {
        id: checkLight; interval: 350; repeat: false
        onTriggered: {
            if (!Tokens.isValid || Tokens.mode !== "light"
                || Tokens.parsedData.colors.accent !== "#654321") {
                root.fail("valid replacement was not loaded"); return;
            }
            console.log("TOKEN_RELOAD_PASS");
        }
    }
}
'''
            main.write_text(qml.replace("__PYTHON__", json.dumps(sys.executable))
                             .replace("__WRITER__", json.dumps(str(writer)))
                             .replace("__PALETTE__", json.dumps(str(palette)))
                             .replace("__INVALID__", json.dumps(json.dumps(invalid)))
                             .replace("__LIGHT__", json.dumps(json.dumps(light))))
            output = self.run_until_marker(base, main, "TOKEN_RELOAD_", timeout=5)
        self.assertIn("TOKEN_RELOAD_PASS", output, output)
        self.assertNotIn("TOKEN_RELOAD_FAIL", output, output)

    def test_missing_initial_file_uses_dark_fallback(self):
        with tempfile.TemporaryDirectory(prefix="rice-token-default-") as directory:
            base = Path(directory)
            theme = base / "theme"
            theme.mkdir()
            shutil.copyfile(TOKENS, theme / "Tokens.qml")
            (theme / "qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            main = base / "main.qml"
            main.write_text('''import QtQuick
import Quickshell
import "./theme"
ShellRoot {
    Timer {
        interval: 300; running: true; repeat: false
        onTriggered: console.log("TOKEN_DEFAULT:" + Tokens.mode + ":" + Tokens.isValid
            + ":" + Math.round(Tokens.background.r * 255));
    }
}
''')
            output = self.run_until_marker(base, main, "TOKEN_DEFAULT:", timeout=4)
        self.assertIn("TOKEN_DEFAULT:dark:false:18", output, output)


if __name__ == "__main__":
    unittest.main()
