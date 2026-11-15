import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = ROOT / "config/quickshell/rice-shell/dashboard"


class DashboardHomeRedesignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = (DASHBOARD / "Home.qml").read_text()
        cls.profile = (DASHBOARD / "ProfileCard.qml").read_text()
        cls.calendar = (DASHBOARD / "CalendarCard.qml").read_text()
        cls.clock = (DASHBOARD / "ClockCard.qml").read_text()
        cls.player = (DASHBOARD / "PlayerCard.qml").read_text()

    def assertContains(self, source, expected):
        if expected not in source:
            self.fail(f"missing QML contract: {expected}")

    def assertPattern(self, source, pattern):
        if not re.search(pattern, source):
            self.fail(f"missing QML pattern: {pattern}")

    def test_home_adapts_columns_and_scrolls_at_narrow_viewports(self):
        self.assertPattern(self.home, r"wideLayout: width >= 820")
        self.assertPattern(self.home, r"mediumLayout: width >= 650")
        self.assertPattern(
            self.home,
            r"columns:\s*root\.wideLayout \? 3 : root\.mediumLayout \? 2 : 1",
        )
        self.assertContains(self.home, "Flickable")
        self.assertContains(self.home, "contentHeight: homeGrid.height")

        wide = re.search(r"wideLayout: width >= (\d+)", self.home)
        medium = re.search(r"mediumLayout: width >= (\d+)", self.home)
        self.assertTrue(wide, "wide breakpoint is missing")
        self.assertTrue(medium, "medium breakpoint is missing")
        wide_min, medium_min = int(wide.group(1)), int(medium.group(1))
        self.assertEqual(3, 3 if 864 >= wide_min else 2 if 864 >= medium_min else 1)
        self.assertEqual(2, 3 if 768 >= wide_min else 2 if 768 >= medium_min else 1)
        self.assertEqual(1, 3 if 640 >= wide_min else 2 if 640 >= medium_min else 1)

    def test_cards_keep_live_system_data_and_identity(self):
        self.assertContains(self.profile, 'Quickshell.env("USER") || qsTr("User")')
        self.assertNotRegex(self.profile.lower(), r"admin")
        self.assertContains(self.calendar, "SystemClock")
        self.assertContains(self.calendar, "root.monthName")
        self.assertContains(self.calendar, "cellItem.isToday")
        self.assertContains(self.clock, "SystemClock")
        self.assertContains(self.clock, '"tnum": 1')

    def test_player_keeps_native_controls_seek_and_bounded_artwork(self):
        for operation in (
            "Media.previous()",
            "Media.next()",
            "Media.togglePlaying()",
            "Media.setPosition(",
        ):
            self.assertContains(self.player, operation)
        self.assertContains(self.player, "Media.activePlayer.identity")
        self.assertContains(self.player, "Media.activePlayer.canSeek")
        self.assertContains(self.player, "Media.length")
        self.assertContains(self.player, "asynchronous: true")
        self.assertContains(self.player, "Math.min(840")
        self.assertContains(self.player, "Math.min(660")


if __name__ == "__main__":
    unittest.main()
