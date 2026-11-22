//@ pragma UseQApplication
//@ pragma DefaultEnv QS_PIPEWIRE_IMMEDIATE_RECONNECT = 1
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
import "launcher/LauncherSearch.js" as LauncherSearch
import "overlays"
import "modules/cod29"

ShellRoot {
    id: root
    reloadableId: "riceShellRoot"

    LauncherStore { id: launcherStore }
    readonly property var launcherIndex: LauncherSearch.indexApps(DesktopEntries.applications.values)
    Variants {
        model: Quickshell.screens

        TopEdgeWorkspaceStrip {
            required property var modelData
            targetScreen: modelData
        }
    }

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
    property list<WindowSwitcher> switcherInstances: []

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
        if (switcherInstances.some(switcher => switcher && switcher.visible)) return true;
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
        for (var switcher of switcherInstances) {
            if (switcher && switcher !== target) switcher.dismiss();
        }
    }

    function stepWindowSwitcher(direction: int): void {
        var active = switcherInstances.find(switcher => switcher && switcher.visible);
        if (active) {
            active.step(direction);
            return;
        }
        var inst = instanceOnScreen(switcherInstances, null);
        if (!inst) return;
        dismissOtherModals(inst);
        inst.open(direction);
    }

    function commitWindowSwitcher(): void {
        if (switcherSuperLeft.pressed || switcherSuperRight.pressed) return;
        var active = switcherInstances.find(switcher => switcher && switcher.visible);
        if (active) active.accept(active.selectedAddress);
    }

    GlobalShortcut {
        appid: "rice"
        name: "window-switcher-next"
        onPressed: root.stepWindowSwitcher(1)
    }

    GlobalShortcut {
        appid: "rice"
        name: "window-switcher-prev"
        onPressed: root.stepWindowSwitcher(-1)
    }

    GlobalShortcut {
        id: switcherSuperLeft
        appid: "rice"
        name: "window-switcher-super-left"
        onReleased: root.commitWindowSwitcher()
    }

    GlobalShortcut {
        id: switcherSuperRight
        appid: "rice"
        name: "window-switcher-super-right"
        onReleased: root.commitWindowSwitcher()
    }

    function toggleLauncher(screen: var): void {
        var inst = instanceOnScreen(launcherInstances, screen);
        if (!inst) return;
        if (inst.visible && !inst.closing) {
            inst.dismiss();
            return;
        }
        dismissOtherModals(inst);
        inst.toggle();
    }

    property Launcher brightnessRequester: null
    property int brightnessSession: -1

    function launcherFeedback(launcher: Launcher, session: int, message: string): void {
        if (launcher && launcher.visible && !launcher.closing && launcher.session === session)
            launcher.feedback = message;
    }

    function finishLauncherBrightness(message: string): void {
        launcherFeedback(brightnessRequester, brightnessSession, message);
        brightnessRequester = null;
        brightnessFeedbackTimeout.stop();
    }

    Timer {
        id: brightnessFeedbackTimeout
        interval: 2500
        onTriggered: root.finishLauncherBrightness(DesktopControls.brightnessError || "Could not confirm brightness")
    }

    Process {
        id: launcherVolume
        property Launcher requester: null
        property int session: -1
        property int sinkId: -1
        property real target: -1

        function finish(message: string): void {
            root.launcherFeedback(requester, session, message);
            requester = null;
            volumeTimeout.stop();
        }

        function acknowledge(): void {
            if (requester && !running && Audio.available && Audio.sink.id === sinkId
                    && Math.abs(Audio.volume - target) < 0.005)
                finish("Volume " + Math.round(Audio.volume * 100) + "%");
        }

        function request(launcher: Launcher, percent: real): void {
            if (requester || running) {
                launcher.feedback = "Volume adjustment in progress";
                return;
            }
            requester = launcher;
            session = launcher.session;
            target = percent / 100;
            sinkId = Audio.sink.id;
            launcher.feedback = "Adjusting volume…";
            volumeTimeout.restart();
            exec(["wpctl", "set-volume", "--limit", "1.5", String(sinkId), String(target)]);
        }

        onExited: (code, status) => {
            if (code !== 0 || status !== 0) finish("Could not set volume");
            else Qt.callLater(acknowledge);
        }
    }
    Timer {
        id: volumeTimeout
        interval: 2000
        onTriggered: launcherVolume.finish("Could not confirm volume")
    }

    Process {
        id: copyResult
        property Launcher requester: null
        property int session: -1
        property string expression: ""
        property string value: ""

        function request(launcher: Launcher, result: string, input: string): void {
            if (running || value) {
                launcher.feedback = "Clipboard copy in progress";
                return;
            }
            requester = launcher;
            session = launcher.session;
            expression = input;
            value = result;
            launcher.feedback = "Copying…";
            command = ["wl-copy", "--", result];
            running = true;
            Qt.callLater(checkStart);
        }

        function checkStart(): void {
            if (!running && value) finish(false);
        }

        function finish(success: bool): void {
            if (!value) return;
            if (success) launcherStore.recordCalculation(expression, value);
            root.launcherFeedback(requester, session, success ? "Copied to clipboard" : "Could not copy result");
            requester = null;
            value = "";
            expression = "";
        }
        onExited: (code, status) => finish(code === 0 && status === 0)
        onRunningChanged: if (!running) Qt.callLater(checkStart)
    }

    readonly property var launcherActionStatuses: {
        const output = !Audio.available ? "Output unavailable"
            : Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%";
        const backlight = DesktopControls.brightnessPending ? "Adjusting brightness…"
            : DesktopControls.brightnessAvailable
            ? Math.round(DesktopControls.brightnessLevel * 100) + "%" : "Backlight unavailable";
        return {
            "dnd": DesktopControls.doNotDisturb ? "On" : "Off",
            "volume-up": output, "volume-down": output, "volume-mute": output,
            "mic-mute": !Audio.micAvailable ? "Microphone unavailable" : Audio.micMuted ? "Muted" : "On",
            "brightness-up": backlight, "brightness-down": backlight,
            "night-light": DesktopControls.nightLightActive ? "On" : "Off",
            "awake": DesktopControls.caffeineActive ? "On" : "Off"
        };
    }

    function runLauncherAction(launcher: Launcher, action: string, argument: real): void {
        if (!launcher || !launcher.visible || launcher.closing) return;
        switch (action) {
        case "dnd":
        case "dnd-on":
        case "dnd-off":
            if (action === "dnd") riceIpc.toggleDnd();
            else DesktopControls.doNotDisturb = action === "dnd-on";
            launcher.feedback = DesktopControls.doNotDisturb ? "Do Not Disturb on" : "Do Not Disturb off";
            break;
        case "volume-up":
        case "volume-down":
        case "volume-set":
        case "volume-mute":
            if (!Audio.available) {
                launcher.feedback = "Audio output unavailable";
                break;
            }
            if (action === "volume-up") riceIpc.volumeUp();
            else if (action === "volume-down") riceIpc.volumeDown();
            else if (action === "volume-mute") riceIpc.volumeMute();
            else if (Number.isFinite(argument) && argument >= 0 && argument <= 150) {
                launcherVolume.request(launcher, argument);
                break;
            }
            launcher.feedback = "";
            break;
        case "mic-mute":
            if (Audio.micAvailable) Audio.toggleMicMute();
            else launcher.feedback = "Microphone unavailable";
            break;
        case "night-light":
        case "night-light-on":
        case "night-light-off":
            if (action === "night-light") DesktopControls.toggleNightLight();
            else DesktopControls.nightLightRequested = action === "night-light-on";
            break;
        case "awake":
        case "awake-on":
        case "awake-off":
            if (action === "awake") DesktopControls.toggleCaffeine();
            else DesktopControls.caffeineRequested = action === "awake-on";
            break;
        case "brightness-up":
        case "brightness-down":
        case "brightness-set":
            if (action === "brightness-set" && (!Number.isFinite(argument) || argument < 5 || argument > 100)) break;
            if (brightnessRequester || DesktopControls.brightnessPending) {
                launcher.feedback = "Brightness adjustment in progress";
                break;
            }
            if (!DesktopControls.brightnessAvailable) {
                launcher.feedback = DesktopControls.brightnessError || "Backlight unavailable";
                DesktopControls.refreshBrightness(false);
                break;
            }
            brightnessRequester = launcher;
            brightnessSession = launcher.session;
            launcher.feedback = "Adjusting brightness…";
            brightnessFeedbackTimeout.restart();
            DesktopControls.setBrightness(action === "brightness-set" ? argument / 100
                : DesktopControls.brightnessLevel + (action === "brightness-up" ? 0.1 : -0.1));
            break;
        case "system":
        case "power":
        case "notifications":
        case "home":
        case "config":
        case "audio":
            if (!instanceOnScreen(islandInstances, launcher.targetScreen)) {
                launcher.feedback = "Control Center unavailable";
                break;
            }
            launcher.dismiss();
            if (action === "audio") root.toggleSideDrawer("audio", launcher.targetScreen);
            else root.toggleDashboard(action[0].toUpperCase() + action.slice(1), launcher.targetScreen);
            break;
        case "windows": {
            const switcher = instanceOnScreen(switcherInstances, launcher.targetScreen);
            if (!switcher) {
                launcher.feedback = "Window switcher unavailable";
                break;
            }
            dismissOtherModals(switcher);
            switcher.open(1);
            break;
        }
        case "clipboard":
        case "screenshot":
        case "wallpaper": {
            const home = Quickshell.env("HOME");
            const command = action === "clipboard" ? ["qs", "-c", "clipboard-history", "-n"]
                : action === "screenshot" ? [home + "/.config/hypr/scripts/screenshot-region.sh"]
                : ["quickshell", "-p", home + "/.config/quickshell/wallpaper-switcher"];
            launcher.dismiss();
            utilityDelay.command = command;
            utilityDelay.restart();
            break;
        }
        case "clear-recents":
        case "clear-calculations":
            launcherStore.clearHistory(action === "clear-calculations");
            launcher.feedback = "History cleared";
            break;
        case "reload":
            launcher.dismiss();
            riceIpc.islandNotify("Rice Shell", "Shell reload requested");
            riceIpc.reloadShell();
            break;
        }
    }

    Timer {
        id: utilityDelay
        property var command: []
        interval: 130
        onTriggered: Quickshell.execDetached(command)
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
        readonly property bool windowSwitcherShortcuts: true

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

        function islandNotification(notificationId: int, summary: string, body: string,
                                     appName: string, appIcon: string, actionsJson: string): void {
            var island = root.instanceOnScreen(islandInstances, null);
            var actions = [];
            try { actions = JSON.parse(actionsJson || "[]"); }
            catch (error) { console.warn("Discarding invalid notification actions"); }
            if (island) island.triggerNotification(summary, body, appName, appIcon,
                notificationId, actions);
        }

        function toggleLauncher(): void {
            root.toggleLauncher(null);
        }

        function stepWindowSwitcher(direction: int): void {
            root.stepWindowSwitcher(direction);
        }

        function cancelWindowSwitcher(): bool {
            var active = root.switcherInstances.find(switcher => switcher && switcher.visible);
            if (!active) return false;
            active.dismiss();
            return true;
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

                onRequestSideDrawer: (type) => {
                    root.toggleSideDrawer(type, modelData);
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
                store: launcherStore
                sharedIndex: root.launcherIndex
                actionStatuses: root.launcherActionStatuses
                actionAvailability: ({
                    "volume-up": Audio.available, "volume-down": Audio.available,
                    "volume-mute": Audio.available, "mic-mute": Audio.micAvailable,
                    "brightness-up": DesktopControls.brightnessAvailable,
                    "brightness-down": DesktopControls.brightnessAvailable
                })
                onActionsModeChanged: {
                    if (actionsMode && !DesktopControls.brightnessAvailable)
                        DesktopControls.refreshBrightness(false);
                }
                onQuickActionRequested: (action, argument) => root.runLauncherAction(screenLauncher, action, argument)
                onCopyResultRequested: (result, expression) => copyResult.request(screenLauncher, result, expression)

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

    Variants {
        model: Quickshell.screens

        delegate: Component {
            WindowSwitcher {
                id: switcher
                required property ShellScreen modelData
                targetScreen: modelData

                Component.onCompleted: root.switcherInstances.push(switcher)
                Component.onDestruction: {
                    var idx = root.switcherInstances.indexOf(switcher);
                    if (idx >= 0) root.switcherInstances.splice(idx, 1);
                }
            }
        }
    }

    Connections {
        target: Audio
        function onVolumeChanged(): void { launcherVolume.acknowledge(); }
        function onMicMuteChangedByBackend(muted: bool): void {
            root.dispatchOsd(muted ? "󰍭" : "󰍬", muted ? 0 : 1, "microphone");
        }
        function onOsdRequested(icon: string, progress: real): void {
            root.dispatchOsd(icon, progress, "volume");
        }
    }

    Connections {
        target: DesktopControls
        function onErrorOccurred(message: string): void {
            if (message === "Failed to set brightness" && root.brightnessRequester)
                root.finishLauncherBrightness(message);
            riceIpc.islandNotify("Control Center", message);
        }
        function onBrightnessRefreshed(level: real, showOsd: bool): void {
            if (root.brightnessRequester && !DesktopControls.brightnessPending)
                root.finishLauncherBrightness("Brightness: " + Math.round(level * 100) + "%");
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
