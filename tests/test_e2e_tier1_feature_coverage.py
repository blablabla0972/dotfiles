"""Tier 1: Feature Coverage E2E Tests (Opaque-box).

Validates standard interfaces, CLI arguments, and primary behaviors of:
- install.sh (--dry-run, target selection)
- bin/toggle-desktop (show desktop toggle roundtrip)
- config/hypr/scripts/generate-theme.py (--help, --theme-mode-changed)
- config/quickshell/wallpaper-switcher/preview-palette.py (color extraction & envelope)
"""

import json
from pathlib import Path
import re
import sys
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT / "tests") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tests"))

from test_e2e_common import E2EBaseTestCase

SWATCH_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


class TestTier1FeatureCoverage(E2EBaseTestCase):
    """Tier 1: Core feature coverage with opaque-box boundary validation."""

    def test_installer_dry_run_full(self):
        """Verify installer --dry-run reports intended symlinks without mutating disk."""
        proc = self.e2e.run_installer("--dry-run")
        self.assertEqual(proc.returncode, 0, f"Installer failed: {proc.stderr}")
        self.assertIn("(dry-run — chưa thay đổi gì)", proc.stdout)
        self.assertIn("DRY: ln -sT", proc.stdout)

        # Hermetic disk invariant: No symlinks or config dirs must be created
        self.assertFalse(
            (self.e2e.config / "hypr").exists(),
            "Dry run must not create ~/.config/hypr",
        )
        self.assertFalse(
            (self.e2e.home / ".local/bin/toggle-desktop").exists(),
            "Dry run must not create ~/.local/bin/toggle-desktop",
        )

    def test_installer_selective_targets(self):
        """Verify installer respects specific target selection flags in dry-run mode."""
        proc = self.e2e.run_installer("--dry-run", "hypr", "btop")
        self.assertEqual(proc.returncode, 0, f"Installer failed: {proc.stderr}")
        self.assertIn("Chọn lọc (hypr btop)", proc.stdout)

        # Selected targets should be in dry-run execution
        self.assertIn(f"DRY: ln -sT {REPO_ROOT}/config/hypr", proc.stdout)
        self.assertIn(f"DRY: ln -sT {REPO_ROOT}/config/btop", proc.stdout)

        # Unselected targets must NOT appear in link actions
        self.assertNotIn(f"DRY: ln -sT {REPO_ROOT}/config/starship.toml", proc.stdout)
        self.assertNotIn(f"DRY: ln -sT {REPO_ROOT}/config/kitty", proc.stdout)

    def test_installer_no_state_flag(self):
        """Verify --no-state excludes state directory targets."""
        proc = self.e2e.run_installer("--dry-run", "--no-state", "--all")
        self.assertEqual(proc.returncode, 0, f"Installer failed: {proc.stderr}")
        # State directory linking should not be executed
        self.assertNotIn(f"DRY: ln -sT {REPO_ROOT}/state", proc.stdout)

    def test_toggle_desktop_forward_and_backward(self):
        """Verify toggle-desktop toggles to desktop workspace (10) and returns to original workspace."""
        # 1. State: On regular workspace '3'
        self.e2e.set_monitors(workspace="3", special="", special_id=0)

        proc1 = self.e2e.run_toggle_desktop()
        self.assertEqual(proc1.returncode, 0, f"Toggle-desktop jump failed: {proc1.stderr}")

        state_file = self.e2e.runtime / "hypr/e2e_test_instance/toggle-desktop.state"
        self.assertTrue(state_file.exists(), "State file must exist after hiding windows")
        state_content = state_file.read_bytes()
        self.assertEqual(state_content, b"3\x00\x00", "State file must store original workspace '3'")

        batches = self.e2e.get_hyprctl_batches()
        self.assertTrue(len(batches) >= 1)
        self.assertIn('dispatch hl.dsp.focus({ workspace = "10" })', batches[-1])

        # 2. State: Now on desktop workspace '10'
        self.e2e.set_monitors(workspace="10", special="", special_id=0)

        proc2 = self.e2e.run_toggle_desktop()
        self.assertEqual(proc2.returncode, 0, f"Toggle-desktop restore failed: {proc2.stderr}")

        # State file should be cleaned up
        self.assertFalse(state_file.exists(), "State file must be removed after restoration")

        batches = self.e2e.get_hyprctl_batches()
        self.assertIn('dispatch hl.dsp.focus({ workspace = "3" })', batches[-1])

    def test_generate_theme_help(self):
        """Verify generate-theme.py adheres to its command-line help interface contract."""
        proc = self.e2e.run_generate_theme("--help")
        self.assertEqual(proc.returncode, 0, f"Help failed: {proc.stderr}")
        self.assertIn("--apply-wallpaper", proc.stdout)
        self.assertIn("--wallpaper-changed", proc.stdout)
        self.assertIn("--theme-mode-changed", proc.stdout)
        self.assertIn("--request-id", proc.stdout)
        self.assertIn("--json", proc.stdout)

    def test_generate_theme_mode_changed_invocation(self):
        """Verify generate-theme.py --theme-mode-changed executes cleanly in configured desktop."""
        # Setup basic config skeleton
        wallpaper = self.e2e.create_test_image("current_wall.png", b"sample_wallpaper_image_data")
        (self.e2e.config / "hypr").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "noctalia/palettes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "micro/colorschemes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "hypr/current_wallpaper").symlink_to(wallpaper)
        (self.e2e.config / "hypr/colors.conf").write_text("# initial colors\n")
        (self.e2e.config / "micro/colorschemes/adaptive.micro").write_text("# initial micro\n")

        # Copy authentic matugen.json palette template from repo
        palette_template = (REPO_ROOT / "config/noctalia/palettes/matugen.json").read_text()
        (self.e2e.config / "noctalia/palettes/matugen.json").write_text(palette_template)

        # Provide a minimal matugen config.toml in config
        matugen_conf = self.e2e.config / "matugen/config.toml"
        matugen_conf.parent.mkdir(parents=True, exist_ok=True)
        matugen_conf.write_text("""
[config.wallpaper]
set = false
command = ""

[templates.hypr]
input_path = "colors.conf"
output_path = "~/.config/hypr/colors.conf"

[templates.noctalia]
input_path = "matugen.json"
output_path = "~/.config/noctalia/palettes/matugen.json"

[templates.micro]
input_path = "adaptive.micro"
output_path = "~/.config/micro/colorschemes/adaptive.micro"
""")

        proc = self.e2e.run_generate_theme("--theme-mode-changed")
        self.assertEqual(proc.returncode, 0, f"Theme mode change failed: {proc.stderr}\n{proc.stdout}")

    def test_preview_palette_cli_and_caching(self):
        """Verify preview-palette.py outputs valid 5-swatch JSON envelope and caches results."""
        wallpaper = self.e2e.create_test_image("wall.png", b"palette_image_content_test_123")
        req_id = "req-tier1-feat-001"

        # First run (cache miss, renders via stub matugen)
        proc1 = self.e2e.run_preview_palette("--request-id", req_id, "--mode", "dark", str(wallpaper))
        self.assertEqual(proc1.returncode, 0, f"preview-palette failed: {proc1.stderr}")

        data1 = json.loads(proc1.stdout.strip())
        self.assertEqual(data1.get("schema_version"), 1)
        self.assertEqual(data1.get("request_id"), req_id)
        self.assertEqual(data1.get("mode"), "dark")
        self.assertEqual(data1.get("wallpaper"), str(wallpaper.resolve()))

        swatches1 = data1.get("swatches")
        self.assertIsInstance(swatches1, list)
        self.assertEqual(len(swatches1), 5)
        for s in swatches1:
            self.assertTrue(SWATCH_RE.match(s), f"Swatch {s} must be valid hex color")

        # Second run (cache hit: different request-id for same wallpaper & mode)
        req_id_2 = "req-tier1-feat-002"
        proc2 = self.e2e.run_preview_palette("--request-id", req_id_2, "--mode", "dark", str(wallpaper))
        self.assertEqual(proc2.returncode, 0, f"preview-palette cache hit failed: {proc2.stderr}")

        data2 = json.loads(proc2.stdout.strip())
        self.assertEqual(data2.get("request_id"), req_id_2)
        self.assertEqual(data2.get("swatches"), swatches1)


if __name__ == "__main__":
    unittest.main()
