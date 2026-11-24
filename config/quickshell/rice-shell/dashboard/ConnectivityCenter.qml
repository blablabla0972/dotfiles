pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: 360
    implicitHeight: 480
    property string currentPage: "wifi"
    property bool drawerOpen: false

    signal pageSelected(string page)
    signal closeRequested()

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
        radius: 26
        color: Tokens.surface
        border.width: 1
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.38)
        clip: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        DrawerHeader {
            Layout.fillWidth: true
            title: root.pageTitle
            icon: root.activePage === "wifi" ? "󰤨"
                : root.activePage === "bluetooth" ? "󰂯" : "󰖩"
            onCloseRequested: root.closeRequested()
        }

        Item {
            id: pageStage
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Loader {
                id: wifiLoader
                anchors.fill: parent
                active: root.activePage === "wifi"
                visible: active
                sourceComponent: WifiDrawer { drawerOpen: root.drawerOpen }
            }
            Loader {
                id: bluetoothLoader
                anchors.fill: parent
                active: root.activePage === "bluetooth"
                visible: active
                source: "BluetoothDrawer.qml"
            }
            Loader {
                id: hotspotLoader
                anchors.fill: parent
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
