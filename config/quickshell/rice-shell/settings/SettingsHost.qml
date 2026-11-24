pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../services"
import "Registry.js" as Registry

LazyLoader {
    id: host

    property string route: "appearance"
    property var requestedScreen: null
    property var launcherState: null
    property ShellPresentation shellPresentation: null
    property SettingsPreferences preferences: SettingsPreferences {
        watching: host.active
    }
    property WindowLayoutStore layoutState: WindowLayoutStore {}

    signal opening()
    signal openWallpaper()

    function open(request: string, screen): bool {
        const next = request || route;
        if (!Registry.validRoute(next)) return false;
        route = Registry.canonicalRoute(next);
        requestedScreen = screen;
        opening();
        if (active) (item as SettingsWindow).open(route, screen);
        else activeAsync = true;
        return true;
    }

    onActiveChanged: if (active) (item as SettingsWindow).open(route, requestedScreen)

    SettingsWindow {
        id: window
        launcherState: host.launcherState
        shellPresentation: host.shellPresentation
        preferences: host.preferences
        layoutState: host.layoutState
        onRouteChanged: if (route) host.route = route
        onDismissed: Qt.callLater(() => {
            if (window && !window.visible) host.active = false;
        })
        onOpenWallpaper: host.openWallpaper()
    }
}
