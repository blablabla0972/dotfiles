pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    property string adaptiveRaw: ""
    property var parsedData: ({})
    readonly property bool isValid: parsedData && parsedData.schema_version === 1 && parsedData.colors

    // Semantic Palette Roles with WCAG-safe fallbacks
    readonly property color background: isValid ? parsedData.colors.background : "#121318"
    readonly property color surface_low: isValid ? parsedData.colors.surface_low : "#16171d"
    readonly property color surface: isValid ? parsedData.colors.surface : "#1a1b21"
    readonly property color surface_high: isValid ? parsedData.colors.surface_high : "#282a32"
    readonly property color text_primary: isValid ? parsedData.colors.text_primary : "#e2e2e9"
    readonly property color text_secondary: isValid ? parsedData.colors.text_secondary : "#8f9099"
    readonly property color accent: isValid ? parsedData.colors.accent : "#adc6ff"
    readonly property color on_accent: isValid ? parsedData.colors.on_accent : "#002e69"
    readonly property color outline: isValid ? parsedData.colors.outline : "#43474e"
    readonly property color focus_ring: isValid ? parsedData.colors.focus_ring : "#adc6ff"
    readonly property color danger: isValid ? parsedData.colors.danger : "#ffb4ab"

    // Material opacities
    readonly property real barOpacity: (isValid && parsedData.materials && parsedData.materials.bar)
        ? parsedData.materials.bar.opacity : 0.85
    readonly property real panelOpacity: (isValid && parsedData.materials && parsedData.materials.panel)
        ? parsedData.materials.panel.opacity : 0.92

    readonly property string mode: (isValid && parsedData.mode) ? parsedData.mode : "dark"

    function reloadTheme(): void {
        try {
            if (themeFile.text().trim().length > 0) {
                var data = JSON.parse(themeFile.text());
                if (data && data.schema_version === 1) {
                    root.parsedData = data;
                }
            }
        } catch (e) {
            // Keep existing or fallback
        }
    }

    property FileView _themeWatcher: FileView {
        id: themeFile
        path: root.stateHome + "/desktop-wallpaper/adaptive-theme.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadTheme()
        onFileChanged: {
            reload();
            root.reloadTheme();
        }
    }
}
