pragma ComponentBehavior: Bound

import Quickshell

PersistentProperties {
    reloadableId: "riceShellPresentation"

    property string dashboardTab: "Home"
    property bool showTray: true
    property bool showConnectivity: true
    property bool showBattery: true
    property bool showClockSeconds: false
    property bool showMediaPreview: true
    property bool volumeOsd: true
    property bool brightnessOsd: true
    property bool microphoneOsd: true

    function allowsOsd(kind: string): bool {
        if (kind === "microphone") return microphoneOsd;
        if (kind === "brightness") return brightnessOsd;
        return volumeOsd;
    }
}
