pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "theme"
import "services"
import "bar"
import "island"
import "dashboard"
import "launcher"

ShellRoot {
    id: root

    // Lists of active window instances for multi-monitor IPC dispatch
    property list<Island> islandInstances: []
    property list<Dashboard> dashboardInstances: []
    property list<Launcher> launcherInstances: []

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

        function islandToggle(): void {
            for (var i = 0; i < islandInstances.length; i++) {
                var island = islandInstances[i];
                if (island) {
                    island.isPinned = !island.isPinned;
                    island.updateMode();
                }
            }
        }

        function islandOsd(icon: string, progress: real): void {
            for (var i = 0; i < islandInstances.length; i++) {
                if (islandInstances[i]) islandInstances[i].triggerOsd(icon, progress);
            }
        }

        function islandNotify(summary: string, body: string): void {
            for (var i = 0; i < islandInstances.length; i++) {
                if (islandInstances[i]) islandInstances[i].triggerNotification(summary, body, "󰂚");
            }
        }

        function toggleLauncher(): void {
            for (var i = 0; i < launcherInstances.length; i++) {
                if (launcherInstances[i]) launcherInstances[i].toggle();
            }
        }

        function toggleDashboard(tab: string): void {
            for (var i = 0; i < dashboardInstances.length; i++) {
                if (dashboardInstances[i]) dashboardInstances[i].toggle(tab);
            }
        }

        function toggleNotifications(): void {
            // Target for M6 notifications center implementation
        }

        function toggleSession(): void {
            toggleDashboard("Config");
        }

        function volumeUp(): void {
            Audio.volumeUp(0.05);
        }

        function volumeDown(): void {
            Audio.volumeDown(0.05);
        }

        function volumeMute(): void {
            Audio.toggleMute();
        }

        function brightnessChanged(): void {
            islandOsd("󰃠", 0.7);
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

    // Dynamic Island overlay instantiated on all active monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Island {
                id: screenIsland
                required property var modelData
                targetScreen: modelData

                Component.onCompleted: {
                    root.islandInstances.push(screenIsland);
                }
                Component.onDestruction: {
                    var idx = root.islandInstances.indexOf(screenIsland);
                    if (idx >= 0) root.islandInstances.splice(idx, 1);
                }
            }
        }
    }

    // Control Center Dashboard instantiated on all active monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Dashboard {
                id: screenDashboard
                required property var modelData
                targetScreen: modelData

                Component.onCompleted: {
                    root.dashboardInstances.push(screenDashboard);
                }
                Component.onDestruction: {
                    var idx = root.dashboardInstances.indexOf(screenDashboard);
                    if (idx >= 0) root.dashboardInstances.splice(idx, 1);
                }
            }
        }
    }

    // Application Search Launcher instantiated on all active monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Launcher {
                id: screenLauncher
                required property var modelData
                targetScreen: modelData

                Component.onCompleted: {
                    root.launcherInstances.push(screenLauncher);
                }
                Component.onDestruction: {
                    var idx = root.launcherInstances.indexOf(screenLauncher);
                    if (idx >= 0) root.launcherInstances.splice(idx, 1);
                }
            }
        }
    }

    // Conditional Loader for NotificationServer (M6/M9 guard)
    Loader {
        id: notificationLoader
        active: Quickshell.env("ENABLE_NOTIFICATIONS") === "1"
        source: "overlays/Notifications.qml"
    }
}
