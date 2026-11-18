from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
NOTIFICATIONS = ROOT / "config/quickshell/rice-shell/overlays/Notifications.qml"
CENTER = ROOT / "config/quickshell/rice-shell/dashboard/NotificationCenter.qml"
ISLAND = ROOT / "config/quickshell/rice-shell/island/Island.qml"
CONTROLS = ROOT / "config/quickshell/rice-shell/services/DesktopControls.qml"


class NotificationActionTests(unittest.TestCase):
    def test_server_advertises_only_implemented_actions(self):
        source = NOTIFICATIONS.read_text()
        self.assertIn("actionsSupported: true", source)
        self.assertIn("inlineReplySupported: false", source)
        self.assertIn("actionIconsSupported: false", source)

    def test_live_actions_are_serialized_as_metadata(self):
        notifications = NOTIFICATIONS.read_text()
        controls = CONTROLS.read_text()
        self.assertIn("liveNotifications", notifications)
        self.assertIn("action.invoke()", notifications)
        self.assertIn("notificationActionRequested", controls)
        self.assertIn("actions: Array.isArray(actions)", controls)

    def test_both_surfaces_request_actions_once(self):
        center = CENTER.read_text()
        island = ISLAND.read_text()
        for source in (center, island):
            self.assertIn("requestNotificationAction", source)
            self.assertIn("actions", source)
        self.assertIn("invokedActions", notifications := NOTIFICATIONS.read_text())
        self.assertIn("onClosed", notifications)
        self.assertIn("unregisterNotification", notifications)


if __name__ == "__main__":
    unittest.main()
