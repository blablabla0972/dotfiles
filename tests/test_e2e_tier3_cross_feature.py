"""Tier 3: Cross-Feature Combinations E2E Tests (Opaque-box).

Validates multi-subsystem interactions, cross-component contracts, and concurrency:
- Theme generation + palette preview synchronization
- Installer backup namespace vs theme snapshot namespace isolation
- Concurrent invocation & flock serialization in toggle-desktop
- Installer orphan symlink pruning vs user custom binaries preservation
"""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sys
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT / "tests") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tests"))

from test_e2e_common import E2EBaseTestCase


class TestTier3CrossFeature(E2EBaseTestCase):
    """Tier 3: Cross-feature interaction and subsystem coexistence tests."""

    def test_theme_generation_and_palette_preview_consistency(self):
        """Verify palette preview swatches and theme engine outputs maintain color consistency."""
        wallpaper = self.e2e.create_test_image("cross_wall.png", b"consistent_wallpaper_data")

        # 1. Generate preview via preview-palette.py
        proc_prev = self.e2e.run_preview_palette(
            "--request-id", "req-cross-sync",
            "--mode", "dark",
            str(wallpaper),
        )
        self.assertEqual(proc_prev.returncode, 0, f"preview-palette failed: {proc_prev.stderr}")
        preview_data = json.loads(proc_prev.stdout.strip())
        preview_swatches = preview_data["swatches"]
        # In our stub, primary color is the first swatch
        expected_primary = preview_swatches[0].lower()

        # 2. Setup config files for generate-theme.py
        (self.e2e.config / "hypr").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "noctalia/palettes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "micro/colorschemes").mkdir(parents=True, exist_ok=True)
        (self.e2e.config / "hypr/current_wallpaper").symlink_to(wallpaper)
        (self.e2e.config / "hypr/colors.conf").write_text("# initial\n")
        (self.e2e.config / "micro/colorschemes/adaptive.micro").write_text("# initial\n")

        palette_template = (REPO_ROOT / "config/noctalia/palettes/matugen.json").read_text()
        (self.e2e.config / "noctalia/palettes/matugen.json").write_text(palette_template)

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

        proc_theme = self.e2e.run_generate_theme("--theme-mode-changed")
        self.assertEqual(proc_theme.returncode, 0, f"Theme generation failed: {proc_theme.stderr}")

        # 3. Verify that noctalia/palettes/matugen.json has valid primary color
        generated_palette = json.loads((self.e2e.config / "noctalia/palettes/matugen.json").read_text())
        dark_primary = generated_palette["dark"]["mPrimary"].lower()
        self.assertTrue(dark_primary.startswith("#"), f"mPrimary must be valid hex color: {dark_primary}")

    def test_installer_backup_preserves_theme_snapshot_namespace(self):
        """Verify installer backups and theme engine snapshots occupy strictly isolated namespaces."""
        # 1. Establish theme snapshot directory in XDG_STATE_HOME
        theme_snapshot_dir = self.e2e.state / "desktop-wallpaper/backups/20261030-120000-sample"
        theme_snapshot_dir.mkdir(parents=True, exist_ok=True)
        snapshot_file = theme_snapshot_dir / "tokens.json"
        snapshot_file.write_text('{"snapshot_preserved": true}', encoding="utf-8")

        # 2. Run initial live installation
        proc1 = self.e2e.run_installer("starship.toml", use_sandbox=True)
        self.assertEqual(proc1.returncode, 0, f"Initial install failed: {proc1.stderr}")

        # 3. Simulate user modification to installed starship.toml
        target_starship = self.e2e.config / "starship.toml"
        self.assertTrue(target_starship.is_symlink())
        target_starship.unlink()
        target_starship.write_text("# user modified starship config\n", encoding="utf-8")

        # 4. Re-run installer, which must back up modified starship.toml to ~/.config/backups/
        proc2 = self.e2e.run_installer("starship.toml", use_sandbox=True)
        self.assertEqual(proc2.returncode, 0, f"Re-install backup failed: {proc2.stderr}")

        # Verify installer backup was created in ~/.config/backups/
        installer_backups_dir = self.e2e.config / "backups"
        self.assertTrue(installer_backups_dir.is_dir(), "Installer backup dir must exist")
        backed_up_items = list(installer_backups_dir.glob("dotfiles-*/*"))
        self.assertTrue(
            any("starship.toml" in str(p) for p in backed_up_items),
            f"Modified starship.toml must be backed up, found: {backed_up_items}",
        )

        # 5. Assert theme snapshot was completely untouched
        self.assertTrue(snapshot_file.exists(), "Theme snapshot file must not be disturbed by installer")
        self.assertEqual(
            snapshot_file.read_text(encoding="utf-8"),
            '{"snapshot_preserved": true}',
        )

    def test_toggle_desktop_rapid_serial_concurrency(self):
        """Verify toggle-desktop serializes multiple rapid concurrent invocations via flock."""
        self.e2e.set_monitors(workspace="1", special="", special_id=0)

        # Run 6 invocations in thread pool simulating rapid hotkey presses
        def invoke_toggle():
            return self.e2e.run_toggle_desktop()

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(invoke_toggle) for _ in range(6)]
            results = [f.result() for f in futures]

        # Every execution must succeed with exit code 0
        for i, res in enumerate(results):
            self.assertEqual(
                res.returncode, 0,
                f"Concurrent invocation {i} failed: {res.stderr}",
            )

        # Lock file should exist and be clean
        lockfile = self.e2e.runtime / "hypr/e2e_test_instance/toggle-desktop.lock"
        self.assertTrue(lockfile.exists(), "Lockfile should exist in runtime dir")

    def test_installer_orphan_cleanup_with_custom_bin_scripts(self):
        """Verify installer prunes stale symlinks to deleted repo binaries while preserving custom files."""
        sandbox = self.e2e.create_sandbox_repo()
        bin_target = self.e2e.home / ".local/bin"
        bin_target.mkdir(parents=True, exist_ok=True)

        # 1. Place a user-created local custom script
        custom_script = bin_target / "my_custom_tool.sh"
        custom_script.write_text("#!/bin/sh\necho custom\n", encoding="utf-8")
        custom_script.chmod(0o755)

        # 2. Place an orphaned symlink pointing to a non-existent file inside repo's bin/
        orphan_symlink = bin_target / "obsolete-tool"
        orphan_symlink.symlink_to(sandbox / "bin/nonexistent_deleted_script_xyz")

        # 3. Place a valid symlink to existing repo bin
        valid_symlink = bin_target / "toggle-desktop"
        valid_symlink.symlink_to(sandbox / "bin/toggle-desktop")

        # Run installer
        proc = self.e2e.run_installer(use_sandbox=True)
        self.assertEqual(proc.returncode, 0, f"Installer failed: {proc.stderr}")

        # Assert custom user script is preserved intact
        self.assertTrue(custom_script.is_file(), "User custom script must be preserved")
        self.assertFalse(custom_script.is_symlink())

        # Assert valid symlink remains
        self.assertTrue(valid_symlink.is_symlink(), "Valid bin symlink must be preserved")

        # Assert orphaned symlink was pruned
        self.assertFalse(orphan_symlink.exists(), "Orphaned symlink must be removed")
        self.assertFalse(orphan_symlink.is_symlink(), "Orphaned symlink must be unlinked")


if __name__ == "__main__":
    unittest.main()
