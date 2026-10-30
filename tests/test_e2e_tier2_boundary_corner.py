"""Tier 2: Boundary & Corner Cases E2E Tests (Opaque-box).

Validates edge conditions, adversarial inputs, error handling, and corruption recovery:
- install.sh (invalid targets, path traversal, empty arguments)
- bin/toggle-desktop (missing focused monitor, corrupted state recovery)
- config/hypr/scripts/generate-theme.py (missing files, malformed request-ids, flags)
- config/quickshell/wallpaper-switcher/preview-palette.py (invalid modes, missing files, corrupted cache)
"""

import json
from pathlib import Path
import sys
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT / "tests") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tests"))

from test_e2e_common import E2EBaseTestCase


class TestTier2BoundaryCorner(E2EBaseTestCase):
    """Tier 2: Boundary, error handling, and recovery tests."""

    def test_installer_invalid_component_rejected(self):
        """Verify installer exits 1 and reports error when given an unknown target."""
        proc = self.e2e.run_installer("unknown_component_xyz")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("Mục cài không hợp lệ: unknown_component_xyz", proc.stderr)
        self.assertFalse((self.e2e.config / "unknown_component_xyz").exists())

    def test_installer_path_traversal_and_forbidden_targets(self):
        """Verify installer strictly rejects path traversals, hidden files, and empty targets."""
        forbidden_targets = ["../etc", "../../passwd", ".git", "", "config/hypr"]
        for target in forbidden_targets:
            with self.subTest(target=target):
                proc = self.e2e.run_installer(target)
                self.assertEqual(
                    proc.returncode, 1,
                    f"Installer should reject forbidden target: '{target}'",
                )
                self.assertIn("Mục cài không hợp lệ", proc.stderr)

    def test_toggle_desktop_missing_focused_monitor(self):
        """Verify toggle-desktop fails safely when no monitor is reported as focused."""
        # Setup: zero focused monitors in hyprctl monitors -j output
        self.e2e.set_monitors(workspace="1", focused=False)

        proc = self.e2e.run_toggle_desktop()
        self.assertNotEqual(proc.returncode, 0, "toggle-desktop must fail if no focused monitor exists")
        # Ensure no state file was written
        state_file = self.e2e.runtime / "hypr/e2e_test_instance/toggle-desktop.state"
        self.assertFalse(state_file.exists(), "State file must not be created on monitor failure")

    def test_toggle_desktop_corrupted_state_recovery(self):
        """Verify toggle-desktop recovers safely when state file is empty or contains desktop ws."""
        state_file = self.e2e.runtime / "hypr/e2e_test_instance/toggle-desktop.state"
        state_file.parent.mkdir(parents=True, exist_ok=True)
        # Empty state file
        state_file.write_bytes(b"")

        # Current workspace is desktop ws 10
        self.e2e.set_monitors(workspace="10", special="", special_id=0)

        proc = self.e2e.run_toggle_desktop()
        self.assertEqual(proc.returncode, 0, f"toggle-desktop must gracefully handle empty state: {proc.stderr}")

        # State file should be cleaned up after return
        self.assertFalse(state_file.exists(), "State file must be unlinked")

        batches = self.e2e.get_hyprctl_batches()
        self.assertTrue(len(batches) >= 1)
        # When saved workspace is empty, it falls back to "previous"
        self.assertIn('dispatch hl.dsp.focus({ workspace = "previous" })', batches[-1])

    def test_toggle_desktop_binary_state_escaping(self):
        """Verify toggle-desktop safely escapes non-ASCII characters in state without crashing."""
        state_file = self.e2e.runtime / "hypr/e2e_test_instance/toggle-desktop.state"
        state_file.parent.mkdir(parents=True, exist_ok=True)
        # Non-ASCII or special characters
        state_file.write_bytes("workspace;with\"quotes'\0\0".encode("utf-8"))

        self.e2e.set_monitors(workspace="10", special="", special_id=0)

        proc = self.e2e.run_toggle_desktop()
        self.assertEqual(proc.returncode, 0, f"Must handle special characters safely: {proc.stderr}")
        self.assertFalse(state_file.exists())

    def test_generate_theme_nonexistent_wallpaper_file(self):
        """Verify generate-theme.py handles missing wallpaper file and emits structured failure."""
        fake_path = "/nonexistent/path/wallpaper_404.png"
        proc = self.e2e.run_generate_theme("--apply-wallpaper", fake_path, "--json")
        self.assertEqual(proc.returncode, 1, "Must exit 1 for missing wallpaper")

        output_json = json.loads(proc.stdout.strip())
        self.assertEqual(output_json.get("status"), "failed")
        self.assertEqual(output_json.get("error_code"), "invalid_wallpaper")

    def test_generate_theme_invalid_request_id(self):
        """Verify generate-theme.py validates request-id format according to schema regex."""
        wallpaper = self.e2e.create_test_image("wall.png", b"image data")
        invalid_id = "req with forbidden spaces and $ symbols!"

        proc = self.e2e.run_generate_theme(
            "--apply-wallpaper", str(wallpaper),
            "--request-id", invalid_id,
            "--json",
        )
        self.assertEqual(proc.returncode, 1, "Must exit 1 for invalid request-id")

        output_json = json.loads(proc.stdout.strip())
        self.assertEqual(output_json.get("status"), "failed")
        self.assertEqual(output_json.get("error_code"), "invalid_request")

    def test_generate_theme_json_without_apply_wallpaper_rejected(self):
        """Verify --json or --request-id without --apply-wallpaper is rejected."""
        proc = self.e2e.run_generate_theme("--json")
        self.assertEqual(proc.returncode, 1)
        output_json = json.loads(proc.stdout.strip())
        self.assertEqual(output_json.get("status"), "failed")
        self.assertEqual(output_json.get("error_code"), "invalid_request")

    def test_preview_palette_invalid_options(self):
        """Verify preview-palette.py enforces required arguments and valid mode."""
        wallpaper = self.e2e.create_test_image("wall.png", b"data")

        # Invalid mode option
        proc_mode = self.e2e.run_preview_palette("--request-id", "r1", "--mode", "sepia", str(wallpaper))
        self.assertNotEqual(proc_mode.returncode, 0, "Invalid mode must be rejected")

        # Missing request-id option
        proc_req = self.e2e.run_preview_palette("--mode", "dark", str(wallpaper))
        self.assertNotEqual(proc_req.returncode, 0, "Missing request-id must be rejected")

    def test_preview_palette_missing_file(self):
        """Verify preview-palette.py handles non-existent file cleanly."""
        proc = self.e2e.run_preview_palette(
            "--request-id", "r1",
            "--mode", "dark",
            "/nonexistent/file_not_found.png",
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("Palette preview unavailable", proc.stderr)

    def test_preview_palette_corrupted_cache_recovery(self):
        """Verify preview-palette.py recovers transparently from corrupted disk cache."""
        wallpaper = self.e2e.create_test_image("wall_cache.png", b"unique_image_data_cache_test")

        # Step 1: Run once to populate cache
        proc1 = self.e2e.run_preview_palette("--request-id", "req-1", "--mode", "dark", str(wallpaper))
        self.assertEqual(proc1.returncode, 0)
        data1 = json.loads(proc1.stdout.strip())
        swatches1 = data1["swatches"]

        cache_dir = self.e2e.cache / "wallpaper-switcher/previews-v1"
        self.assertTrue(cache_dir.is_dir(), "Cache directory must be created")
        cached_files = list(cache_dir.glob("*.json"))
        self.assertEqual(len(cached_files), 1, "Exactly one cache file expected")
        cache_file = cached_files[0]

        # Step 2: Corrupt the cache file with malformed JSON
        cache_file.write_text("{this is corrupted malformed json: true", encoding="utf-8")

        # Step 3: Run again, should handle corruption gracefully, re-render, and overwrite cache
        proc2 = self.e2e.run_preview_palette("--request-id", "req-2", "--mode", "dark", str(wallpaper))
        self.assertEqual(proc2.returncode, 0, f"Failed to recover from corrupted cache: {proc2.stderr}")
        data2 = json.loads(proc2.stdout.strip())
        self.assertEqual(data2["swatches"], swatches1)

        # Step 4: Verify cache file is once again valid JSON
        repaired_content = json.loads(cache_file.read_text(encoding="utf-8"))
        self.assertEqual(repaired_content.get("schema_version"), 1)
        self.assertEqual(repaired_content.get("swatches"), swatches1)


if __name__ == "__main__":
    unittest.main()
