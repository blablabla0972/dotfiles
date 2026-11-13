pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    property var parsedData: ({})
    readonly property bool isValid: isValidCandidate(parsedData)

    function isValidCandidate(data): bool {
        if (!data || typeof data !== "object" || Array.isArray(data)
            || data.schema_version !== 1 || (data.mode !== "dark" && data.mode !== "light"))
            return false;

        var roles = ["background", "surface_low", "surface", "surface_high", "text_primary",
            "text_secondary", "accent", "on_accent", "outline", "focus_ring", "danger"];
        if (!data.colors || typeof data.colors !== "object" || Array.isArray(data.colors)) return false;
        for (var i = 0; i < roles.length; i++) {
            var color = data.colors[roles[i]];
            if (typeof color !== "string" || !/^#[0-9a-fA-F]{6}$/.test(color)) return false;
        }

        if (data.materials !== undefined) {
            if (!data.materials || typeof data.materials !== "object" || Array.isArray(data.materials))
                return false;
            var materialNames = ["bar", "panel", "notification"];
            for (var m = 0; m < materialNames.length; m++) {
                var material = data.materials[materialNames[m]];
                if (material === undefined) continue;
                if (!material || typeof material !== "object" || Array.isArray(material)) return false;
                if (material.opacity !== undefined
                    && (typeof material.opacity !== "number" || !isFinite(material.opacity)
                        || material.opacity < 0 || material.opacity > 1)) return false;
            }
        }
        return true;
    }

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
    readonly property real barOpacity: (isValid && parsedData.materials && parsedData.materials.bar
        && parsedData.materials.bar.opacity !== undefined)
        ? parsedData.materials.bar.opacity : 0.85
    readonly property real panelOpacity: (isValid && parsedData.materials && parsedData.materials.panel
        && parsedData.materials.panel.opacity !== undefined)
        ? parsedData.materials.panel.opacity : 0.92

    readonly property string mode: (isValid && parsedData.mode) ? parsedData.mode : "dark"

    function reloadTheme(): void {
        var raw = themeFile.text();
        if (typeof raw !== "string" || raw.trim().length === 0) return;
        try {
            var candidate = JSON.parse(raw);
            if (isValidCandidate(candidate)) {
                root.parsedData = candidate;
            } else {
                console.warn("Ignoring invalid adaptive theme palette");
            }
        } catch (e) {
            console.warn("Ignoring malformed adaptive theme palette");
        }
    }

    property FileView _themeWatcher: FileView {
        id: themeFile
        path: root.stateHome + "/desktop-wallpaper/adaptive-theme.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadTheme()
        onFileChanged: reload()
    }
}
