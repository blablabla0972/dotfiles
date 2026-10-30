"""Tier 4: Real-World Scenarios E2E Tests (Opaque-box).

Validates full life-cycle user workflows, transactional resilience, and end-to-end integration:
- Complete installation lifecycle (dry-run -> fresh install -> idempotent rerun -> cleanup)
- Theme switcher resilience & atomic snapshot rollback under injected failures
- Full end-to-end workflow (install -> preview -> apply -> toggle desktop -> return)
"""

import hashlib
import json
import os
from pathlib import Path
import sys
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT / "tests") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tests"))

from test_e2e_common import E2EBaseTestCase


class TestTier4RealWorld(E2EBaseTestCase):
    """Tier 4: Real-world workflow and end-to-end lifecycle verification."""

    def test_full_fresh_installation_lifecycle(self):
        """Verify full lifecycle: dry-run, fresh installation, idempotency, and non-destructive re-run."""
        # Phase 1: Dry-run check on pristine home
        proc_dry = self.e2e.run_installer("--dry-run")
        self.assertEqual(proc_dry.returncode, 0, f"Dry-run failed: {proc_dry.stderr}")
        self.assertFalse((self.e2e.config / "hypr").exists(), "Dry-run must not create files")

        # Phase 2: Live fresh installation
        proc_install = self.e2e.run_installer(use_sandbox=True)
        self.assertEqual(proc_install.returncode, 0, f"Installation failed: {proc_install.stderr}")

        # Verify core targets were symlinked
        expected_symlinks = [
            self.e2e.config / "hypr",
            self.e2e.config / "kitty",
            self.e2e.config / "btop",
            self.e2e.config / "starship.toml",
            self.e2e.home / ".local/bin/toggle-desktop",
        ]
        for link in expected_symlinks:
            self.assertTrue(link.is_symlink(), f"Target must be a symlink: {link}")
            self.assertTrue(link.exists(), f"Symlink must resolve to an existing target: {link}")

        # Phase 3: Idempotency check — running install.sh again must not create backups or fail
        proc_idempotent = self.e2e.run_installer(use_sandbox=True)
        self.assertEqual(proc_idempotent.returncode, 0, f"Second install failed: {proc_idempotent.stderr}")
        self.assertIn("đã link sẵn", proc_idempotent.stdout)
        self.assertFalse(
            (self.e2e.config / "backups").exists(),
            "No backup directory should be created when files are already cleanly linked",
        )

    def test_theme_transaction_failure_and_rollback_resilience(self):
        """Verify theme engine atomically rolls back all files to original contents on failure."""
        wallpaper = self.e2e.create_test_image("rollback_wall.png", b"rollback_test_image")

        # Setup initial configuration state
        (self.e2e.config / "hypr").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "noctalia/palettes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "micro/colorschemes").mkdir(parents=True, exist_ok=True)
        (self.e2e.state / "noctalia").mkdir(parents=True, exist_ok=True)

        colors_file = self.e2e.config / "hypr/colors.conf"
        colors_file.write_text("# ORIGINAL COLORS CONF CONTENT\n", encoding="utf-8")
        original_colors_bytes = colors_file.read_bytes()

        palette_file = self.e2e.config / "noctalia/palettes/matugen.json"
        authentic_palette = (REPO_ROOT / "config/noctalia/palettes/matugen.json").read_text()
        palette_file.write_text(authentic_palette, encoding="utf-8")
        original_palette_bytes = palette_file.read_bytes()

        settings_file = self.e2e.state / "noctalia/settings.toml"
        settings_file.write_text("[theme]\nmode = 'dark'\n", encoding="utf-8")
        original_settings_bytes = settings_file.read_bytes()

        current_wall_link = self.e2e.config / "hypr/current_wallpaper"
        current_wall_link.symlink_to(wallpaper)

        # Matugen config
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
""")

        # Inject failure trigger for matugen to simulate mid-transaction failure
        fail_trigger = self.e2e.home / ".matugen_fail"
        fail_trigger.write_text("simulate crash")

        # Execute generate-theme.py with wallpaper
        proc = self.e2e.run_generate_theme(str(wallpaper))
        self.assertNotEqual(proc.returncode, 0, "Theme generation must fail when generator errors")

        # Clean up trigger
        fail_trigger.unlink(missing_ok=True)

        # Verify rollback: Every file must be restored to its exact pre-transaction bytes
        self.assertEqual(
            colors_file.read_bytes(),
            original_colors_bytes,
            "colors.conf was not cleanly restored to original bytes",
        )
        self.assertEqual(
            palette_file.read_bytes(),
            original_palette_bytes,
            "matugen.json was not cleanly restored to original bytes",
        )
        self.assertEqual(
            settings_file.read_bytes(),
            original_settings_bytes,
            "settings.toml was not cleanly restored to original bytes",
        )

    def test_end_to_end_user_desktop_workflow(self):
        """Verify seamless complete lifecycle: Install -> Preview -> Apply -> Toggle -> Return."""
        # 1. User installs dotfiles
        proc_install = self.e2e.run_installer(use_sandbox=True)
        self.assertEqual(proc_install.returncode, 0)

        # 2. User browses wallpaper previews
        wall1 = self.e2e.create_test_image("nature.png", b"nature_scenery_image_bytes")
        wall2 = self.e2e.create_test_image("city.png", b"cyberpunk_city_image_bytes")

        proc_p1 = self.e2e.run_preview_palette("--request-id", "wf-prev-1", "--mode", "dark", str(wall1))
        self.assertEqual(proc_p1.returncode, 0)
        data_p1 = json.loads(proc_p1.stdout.strip())
        self.assertEqual(len(data_p1["swatches"]), 5)

        proc_p2 = self.e2e.run_preview_palette("--request-id", "wf-prev-2", "--mode", "dark", str(wall2))
        self.assertEqual(proc_p2.returncode, 0)
        data_p2 = json.loads(proc_p2.stdout.strip())
        self.assertEqual(len(data_p2["swatches"]), 5)

        # 3. User selects wall1 and applies theme
        (self.e2e.config / "micro/colorschemes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "micro/colorschemes/adaptive.micro").write_text("# adaptive micro\n")
        (self.e2e.config / "hypr/colors.conf").write_text("# hypr colors\n")
        (self.e2e.config / "hypr/current_wallpaper").unlink(missing_ok=True)
        (self.e2e.config / "hypr/current_wallpaper").symlink_to(wall1)

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

        proc_apply = self.e2e.run_generate_theme("--theme-mode-changed")
        self.assertEqual(proc_apply.returncode, 0, f"Theme application failed: {proc_apply.stderr}")

        # 4. User presses show-desktop shortcut
        self.e2e.set_monitors(workspace="2", special="", special_id=0)
        proc_toggle1 = self.e2e.run_toggle_desktop()
        self.assertEqual(proc_toggle1.returncode, 0)

        # 5. User presses show-desktop shortcut again to return
        self.e2e.set_monitors(workspace="10", special="", special_id=0)
        proc_toggle2 = self.e2e.run_toggle_desktop()
        self.assertEqual(proc_toggle2.returncode, 0)

        # Verify restoration back to workspace 2
        batches = self.e2e.get_hyprctl_batches()
        self.assertIn('dispatch hl.dsp.focus({ workspace = "2" })', batches[-1])


if __name__ == "__main__":
    unittest.main()
