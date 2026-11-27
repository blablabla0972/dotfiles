pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: compactMenu ? 328 : 360
    implicitHeight: compactMenu ? pageStage.implicitHeight + 2 * pages.anchors.margins : 480
    property bool compactMenu: false
    property string currentPage: "wifi"
    property bool drawerOpen: false

    signal pageSelected(string page)
    signal closeRequested()
    signal requestSettings(string route)

    readonly property string activePage: {
        const page = String(currentPage || "wifi").toLowerCase();
        return page === "bluetooth" || page === "hotspot" ? page : "wifi";
    }
    readonly property bool wifiLoaded: wifiLoader.item !== null
    readonly property bool bluetoothLoaded: bluetoothLoader.item !== null
    readonly property bool hotspotLoaded: hotspotLoader.item !== null

    Accessible.role: Accessible.Pane
    readonly property string pageTitle: activePage === "wifi" ? "Wi-Fi"
        : activePage === "bluetooth" ? "Bluetooth" : "Hotspot"

    Accessible.name: pageTitle

    function selectPage(page: string): void {
        if (page === "wifi" || page === "bluetooth" || page === "hotspot")
            pageSelected(page);
    }

    function handleEscape(): bool {
        const page = activePage === "wifi" ? wifiLoader.item
            : activePage === "bluetooth" ? bluetoothLoader.item : hotspotLoader.item;
        if (!page) return false;
        if (typeof page.handleEscape === "function") {
            const handledByPage = Boolean(page.forgetDialogOpen || page.forgetConfirmationNetwork
                || page.selectedNetwork || page.detailsNetwork || page.pairingPromptType
                || page.expandedDeviceKey || page.actionStage === "pair"
                || page.actionStage === "waiting-agent" || page.isConnecting);
            const result = page.handleEscape();
            return typeof result === "boolean" ? result : handledByPage;
        }

        if (activePage === "wifi") {
            if (page.forgetConfirmationNetwork) {
                page.forgetConfirmationNetwork = null;
                return true;
            }
            if (page.selectedNetwork) {
                page.cancelPassword();
                return true;
            }
            if (page.detailsNetwork) {
                page.detailsNetwork = null;
                return true;
            }
        } else if (activePage === "bluetooth" && page.pairingPromptType) {
            page.answerPairing(false);
            return true;
        }
        return false;
    }

    Rectangle {
        anchors.fill: parent
        radius: root.compactMenu ? 17 : 26
        color: Tokens.surface
        gradient: root.compactMenu ? menuWash : null
        Gradient {
            id: menuWash
            GradientStop { position: 0; color: Qt.tint(Tokens.menuSurfaceTop, Qt.alpha(Tokens.background, 0.38)) }
            GradientStop { position: 1; color: Qt.tint(Tokens.menuSurface, Qt.alpha(Tokens.background, 0.28)) }
        }
        border.width: 1
        border.color: root.compactMenu ? Tokens.menuLine
            : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.38)
        clip: true
    }

    ColumnLayout {
        id: pages
        anchors.fill: parent
        anchors.margins: root.compactMenu ? 10 : 16
        spacing: root.compactMenu ? 0 : 10

        DrawerHeader {
            Layout.fillWidth: true
            visible: !root.compactMenu
            title: root.pageTitle
            icon: root.activePage === "wifi" ? "󰤨"
                : root.activePage === "bluetooth" ? "󰂯" : "󰖩"
            onCloseRequested: root.closeRequested()
        }

        Item {
            id: pageStage
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: root.compactMenu
                ? (root.activePage === "wifi" ? wifiLoader.contentHeight
                    : root.activePage === "bluetooth" ? bluetoothLoader.contentHeight
                    : hotspotLoader.contentHeight) : 0
            clip: true

            Loader {
                id: wifiLoader
                anchors.left: parent.left
                anchors.right: parent.right
                property real contentHeight: item ? item.implicitHeight : 0
                height: parent.height
                active: root.activePage === "wifi"
                visible: active
                sourceComponent: WifiDrawer {
                    drawerOpen: root.drawerOpen
                    compactMenu: root.compactMenu
                    onRequestSettings: (route) => root.requestSettings(route)
                }
            }
            Loader {
                id: bluetoothLoader
                anchors.left: parent.left
                anchors.right: parent.right
                property real contentHeight: item ? item.implicitHeight : 0
                height: parent.height
                active: root.activePage === "bluetooth"
                visible: active
                sourceComponent: BluetoothDrawer {
                    compactMenu: root.compactMenu
                    onRequestSettings: (route) => root.requestSettings(route)
                }
            }
            Loader {
                id: hotspotLoader
                anchors.fill: parent
                property real contentHeight: item ? item.implicitHeight : 0
                active: root.activePage === "hotspot"
                visible: active
                source: "HotspotDrawer.qml"
            }
        }
    }

    Connections {
        target: wifiLoader.item
        ignoreUnknownSignals: true
        function onHotspotPageRequested(): void { root.selectPage("hotspot"); }
        function onCloseRequested(): void { root.closeRequested(); }
    }
    Connections {
        target: bluetoothLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested(): void { root.closeRequested(); }
    }
}
