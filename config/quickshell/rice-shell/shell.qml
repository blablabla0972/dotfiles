//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "theme"
import "services"
import "bar"
import "island"
import "island/IslandState.js" as IslandState
import "dashboard"
import "launcher"

ShellRoot {
    id: root
    reloadableId: "riceShellRoot"

    PersistentProperties {
        id: retainedNotificationHistory
        reloadableId: "riceNotificationHistory"
        property string entriesJson: "[]"
    }

    Connections {
        target: retainedNotificationHistory
        function onReloaded(): void {
            var entries = [];
            try { entries = JSON.parse(retainedNotificationHistory.entriesJson); }
            catch (error) { console.warn("Discarding invalid retained notification history"); }
            DesktopControls.restoreNotificationHistory(entries);
        }
    }

    Connections {
        target: DesktopControls
        function onNotificationHistoryChanged(): void {
            retainedNotificationHistory.entriesJson = JSON.stringify(DesktopControls.notificationHistory);
        }
    }

    // Lists of active window instances for multi-monitor IPC dispatch
    property list<Island> islandInstances: []
    property list<Launcher> launcherInstances: []
    property list<PowerMenu> powerMenuInstances: []

    // Expose IPC handler reference and convenience dispatchers for child components
    property alias ipcHandler: riceIpc

    Connections {
        target: ThemeCommandQueue
        function onReloadRequested(): void { Quickshell.reload(false); }
    }

    // A bar click targets its own monitor; IPC and keyboard shortcuts target focus.
    function instanceOnScreen(instances: var, requestedScreen: var): var {
        var screenName = requestedScreen ? requestedScreen.name
            : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
        for (var i = 0; i < instances.length; i++) {
            var inst = instances[i];
            if (inst && inst.targetScreen && inst.targetScreen.name === screenName)
                return inst;
        }
        for (var j = 0; j < instances.length; j++) {
            if (instances[j]) return instances[j];
        }
        return null;
    }

    function dispatchOsd(icon: string, progress: real, kind: string): void {
        var island = instanceOnScreen(islandInstances, null);
        if (island) island.triggerOsd(icon, progress, kind);
    }

    function hasInteractiveModal(): bool {
        for (var i = 0; i < islandInstances.length; i++) {
            if (islandInstances[i] && islandInstances[i].dashboardExpanded) return true;
        }
        for (var j = 0; j < launcherInstances.length; j++) {
            if (launcherInstances[j] && launcherInstances[j].visible) return true;
        }
        for (var k = 0; k < powerMenuInstances.length; k++) {
            if (powerMenuInstances[k] && powerMenuInstances[k].visible) return true;
        }
        return false;
    }

    function dismissOtherModals(target: var): void {
        for (var i = 0; i < islandInstances.length; i++) {
            var island = islandInstances[i];
            if (!island) continue;
            if (island !== target) island.dismissDashboard();
            island.isPinned = false;
        }
        for (var j = 0; j < launcherInstances.length; j++) {
            var launcher = launcherInstances[j];
            if (launcher && launcher !== target) launcher.dismiss();
        }
        for (var k = 0; k < powerMenuInstances.length; k++) {
            var powerMenu = powerMenuInstances[k];
            if (powerMenu && powerMenu !== target) powerMenu.dismissMenu();
        }
    }

    function toggleLauncher(screen: var): void {
        var inst = instanceOnScreen(launcherInstances, screen);
        if (!inst) return;
        if (inst.visible) {
            inst.dismiss();
            return;
        }
        dismissOtherModals(inst);
        inst.toggle();
    }

    function toggleDashboard(tab: string, screen: var): void {
        var inst = instanceOnScreen(islandInstances, screen);
        if (!inst) return;
        var targetTab = IslandState.normalizeDashboardTab(tab || "Home");
        if (tab && targetTab !== tab)
            console.warn("Unknown Dashboard tab '" + tab + "'; opening Home");
        if (inst.dashboardExpanded && inst.dashboardCurrentTab === targetTab) {
            inst.toggleDashboard(targetTab);
            return;
        }
        dismissOtherModals(inst);
        inst.toggleDashboard(targetTab);
    }

    function togglePowerMenu(screen: var): void {
        var inst = instanceOnScreen(powerMenuInstances, screen);
        if (!inst) return;
        if (inst.visible) {
            inst.toggle();
            return;
        }
        dismissOtherModals(inst);
        inst.toggle();
    }

    function toggleSideDrawer(type: string, screen: var): void {
        var inst = instanceOnScreen(islandInstances, screen);
        if (!inst) return;
        var drawer = IslandState.normalizeSideDrawer(type);
        if (!drawer) {
            console.warn("Ignoring unknown side drawer: " + type);
            return;
        }
        dismissOtherModals(inst);
        if (!inst.dashboardExpanded || inst.dashboardCurrentTab !== "Home")
            inst.toggleDashboard("Home");
        inst.toggleSideDrawer(drawer);
    }

    // Public IPC Handler for the rice desktop shell
    IpcHandler {
        id: riceIpc
        target: "rice"

        readonly property string status: "ok"
        readonly property string version: "1.0.0"
        readonly property string shell: "quickshell-rice"
        readonly property string themeMode: Tokens.mode
        readonly property int screenCount: Quickshell.screens.length

        function desktopState(): string {
            return JSON.stringify({
                dnd: DesktopControls.doNotDisturb,
                night: DesktopControls.nightLightActive,
                awake: DesktopControls.caffeineActive,
                lastSummary: DesktopControls.lastSummary,
                alerts: islandInstances.map(i => i.activeAlert ? i.activeAlert.summary || "" : "")
            });
        }

        function toggleDnd(): void { DesktopControls.doNotDisturb = !DesktopControls.doNotDisturb; }
        function toggleNightLight(): void { DesktopControls.toggleNightLight(); }
        function toggleCaffeine(): void { DesktopControls.toggleCaffeine(); }
        function reloadShell(): void { ThemeCommandQueue.requestShellReload(); }

        function health(): void {
            console.log("rice health: status=" + status + " screens=" + screenCount + " mode=" + themeMode);
        }

        function islandToggle(): void {
            var island = root.instanceOnScreen(islandInstances, null);
            if (island) {
                if (island.dashboardShowing) island.dismissDashboard();
                else island.isPinned = !island.isPinned;
            }
        }

        function islandOsd(icon: string, progress: real): void {
            root.dispatchOsd(icon, progress, "volume");
        }

        function islandNotify(summary: string, body: string): void {
            var island = root.instanceOnScreen(islandInstances, null);
            if (island) island.triggerNotification(summary, body, "", "");
        }

        function islandNotification(summary: string, body: string, appName: string, appIcon: string): void {
            var island = root.instanceOnScreen(islandInstances, null);
            if (island) island.triggerNotification(summary, body, appName, appIcon);
        }

        function toggleLauncher(): void {
            root.toggleLauncher(null);
        }

        function toggleDashboard(tab: string): void {
            root.toggleDashboard(tab, null);
        }

        function dismissDashboard(): void {
            for (var i = 0; i < islandInstances.length; i++) {
                if (islandInstances[i]) islandInstances[i].dismissDashboard();
            }
        }

        function toggleSideDrawer(type: string): void {
            root.toggleSideDrawer(type || "wifi", null);
        }

        function toggleNotifications(): void {
            root.toggleDashboard("Notifications", null);
        }

        function toggleSession(): void {
            toggleDashboard("Config");
        }

        function togglePowerMenu(): void {
            root.togglePowerMenu(null);
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
            DesktopControls.refreshBrightness(true);
        }
    }

    // Top Bar instantiated across all active Wayland monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {
                required property var modelData
                targetScreen: modelData

                onRequestLauncher: () => {
                    root.toggleLauncher(modelData);
                }

                onRequestDashboard: (tab) => {
                    root.toggleDashboard(tab, modelData);
                }

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

                onRequestDashboard: (tab) => {
                    root.toggleDashboard(tab, modelData);
                }

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

    // Session power menu instantiated on all active monitors
    Variants {
        model: Quickshell.screens

        delegate: Component {
            PowerMenu {
                id: screenPowerMenu
                required property var modelData
                targetScreen: modelData

                Component.onCompleted: {
                    root.powerMenuInstances.push(screenPowerMenu);
                }
                Component.onDestruction: {
                    var idx = root.powerMenuInstances.indexOf(screenPowerMenu);
                    if (idx >= 0) root.powerMenuInstances.splice(idx, 1);
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

    Connections {
        target: Audio
        function onOsdRequested(icon: string, progress: real): void {
            root.dispatchOsd(icon, progress, "volume");
        }
    }

    Connections {
        target: DesktopControls
        function onErrorOccurred(message: string): void { riceIpc.islandNotify("Control Center", message); }
        function onBrightnessRefreshed(level: real, showOsd: bool): void {
            if (showOsd) root.dispatchOsd("󰃠", level, "brightness");
        }
    }

    // Receive desktop notifications and apply the shared DND state.
    Loader {
        id: notificationLoader
        active: Quickshell.env("ENABLE_NOTIFICATIONS") !== "0"
        source: "overlays/Notifications.qml"
        onLoaded: item.notificationReceived.connect(riceIpc.islandNotification)
    }
}
