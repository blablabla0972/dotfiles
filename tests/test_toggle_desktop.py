"""Workspace state regressions using the isolated compositor/Lua fixture."""

import shutil
import unittest

import test_wallpaper_helpers as helpers


@unittest.skipUnless(shutil.which("jq") and shutil.which("lua"), "jq and Lua required")
class ToggleDesktopStateTests(unittest.TestCase):
    def setUp(self):
        self.fixture = helpers.ToggleDesktopTests("test_special_workspaces_round_trip")
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.setUp()

    def toggle(self):
        result = self.fixture.run_helper(helpers.ROOT / "bin/toggle-desktop")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_pipe_in_workspace_does_not_restore_an_unopened_special(self):
        workspace = "name:Design|special:special:notes"
        self.fixture.monitor(workspace)
        self.toggle()
        self.fixture.monitor("10")
        self.toggle()
        self.assertEqual(self.fixture.calls(), [["focus", "10"], ["focus", workspace]])
        self.assertFalse(self.fixture.state.exists())

    def test_multiline_workspace_and_special_names_round_trip(self):
        workspace = "name:Design\nReview\n"
        special = "special:Notes\nproject|draft\n"
        self.fixture.monitor(workspace, special, -99)
        self.toggle()
        self.fixture.monitor("10")
        self.toggle()
        self.assertEqual(self.fixture.calls(), [
            ["special", "Notes\nproject|draft\n"], ["focus", "10"],
            ["focus", workspace], ["special", "Notes\nproject|draft\n"],
        ])
        self.assertFalse(self.fixture.state.exists())

    def test_previous_version_state_remains_restorable(self):
        self.fixture.state.parent.mkdir(parents=True)
        self.fixture.state.write_text("3|special:special:notes")
        self.fixture.monitor("10")
        self.toggle()
        self.assertEqual(self.fixture.calls(), [["focus", "3"], ["special", "notes"]])
        self.assertFalse(self.fixture.state.exists())


if __name__ == "__main__":
    unittest.main()
