pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "theme"
import "bar"

ShellRoot {
    id: root

    // Public IPC Handler for the rice desktop shell
    IpcHandler {
        target: "rice"

        readonly property string status: "ok"
        readonly property string version: "1.0.0"
        readonly property string shell: "quickshell-rice"
        readonly property string themeMode: Tokens.mode
        readonly property int screenCount: Quickshell.screens.length

        function health(): void {
            console.log("rice health: status=" + status + " screens=" + screenCount + " mode=" + themeMode);
        }

        function toggleLauncher(): void {
            // Target for M5 launcher implementation
        }

        function toggleDashboard(tab: string): void {
            // Target for M5 control center implementation
        }

        function toggleNotifications(): void {
            // Target for M6 notifications center implementation
        }

        function toggleSession(): void {
            // Target for M7 session dialog implementation
        }

        function volumeUp(): void {
            // Handled via native Pipewire service in M4
        }

        function volumeDown(): void {
            // Handled via native Pipewire service in M4
        }

        function volumeMute(): void {
            // Handled via native Pipewire service in M4
        }

        function brightnessChanged(): void {
            // OSD trigger in M4
        }
    }

    // Top Bar instantiated across all active Wayland monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {
                required property var modelData
                targetScreen: modelData
            }
        }
    }

    // Conditional Loader for NotificationServer (M6/M9 guard)
    // Only loads when explicitly requested in isolated tests or upon final cutover
    Loader {
        id: notificationLoader
        active: Quickshell.env("ENABLE_NOTIFICATIONS") === "1"
        source: "overlays/Notifications.qml"
    }
}
