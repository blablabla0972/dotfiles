from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
BINDINGS = ROOT / "config/hypr/config/binds.lua"
SCRIPT = ROOT / "config/hypr/scripts/screenshot-region.sh"


class ScreenshotWorkflowTests(unittest.TestCase):
    def test_print_uses_freezing_region_workflow(self):
        source = BINDINGS.read_text()
        print_line = next(line for line in source.splitlines() if 'hl.bind("Print"' in line)
        self.assertIn("~/.config/hypr/scripts/screenshot-region.sh", print_line)
        self.assertNotIn("grim", print_line)

    def test_fullscreen_binding_stays_separate(self):
        source = BINDINGS.read_text()
        fullscreen_line = next(line for line in source.splitlines() if 'mainMod .. " + Print"' in line)
        self.assertIn("grim - | wl-copy", fullscreen_line)
        self.assertNotIn("screenshot-region.sh", fullscreen_line)

    def test_region_script_has_cancel_and_cleanup_guards(self):
        source = SCRIPT.read_text()
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True, capture_output=True, text=True)
        for fragment in (
            'flock -n 9 || exit 0',
            'for command in hyprpicker hyprctl jq slurp grim satty xdg-user-dir',
            'notify-send "Ảnh chụp màn hình" "Thiếu lệnh $command."',
            'hyprpicker -r -z -d',
            'sleep 0.08',
            '> "$tmp/geometry" &',
            'wait "$selector" || exit 0',
            'trap cleanup EXIT',
            '--copy-command "wl-copy --type image/png"',
            '--actions-on-enter save-to-clipboard',
            '--actions-on-escape exit',
        ):
            self.assertIn(fragment, source)
        self.assertNotIn('--auto-copy', source)


if __name__ == "__main__":
    unittest.main()
