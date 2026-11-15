pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: 360
    implicitHeight: 480
    property string currentPage: "wifi"
    property bool hotspotVisited: false
    onActivePageChanged: if (activePage === "hotspot") hotspotVisited = true

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
    Accessible.name: "Connectivity Center"

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
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.38)
        clip: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.maximumHeight: 32
            Layout.fillHeight: false
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Connectivity"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Tokens.text_primary
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: closeHover.hovered ? Tokens.surface_high : "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Close Connectivity Center"

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.pixelSize: 14
                    color: Tokens.text_secondary
                }

                HoverHandler { id: closeHover }
                TapHandler { onTapped: root.closeRequested() }
                Keys.onReturnPressed: function(event) {
                    root.closeRequested();
                    event.accepted = true;
                }
                Keys.onSpacePressed: function(event) {
                    root.closeRequested();
                    event.accepted = true;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.maximumHeight: 32
            Layout.fillHeight: false
            spacing: 6

            Repeater {
                model: [
                    { id: "wifi", label: "Wi-Fi", icon: "󰖩" },
                    { id: "bluetooth", label: "Bluetooth", icon: "󰂯" },
                    { id: "hotspot", label: "Hotspot", icon: "󰖪" }
                ]

                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool selected: root.activePage === modelData.id

                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.maximumHeight: 32
                    Layout.fillHeight: false
                    radius: 16
                    color: selected ? Tokens.accent : Tokens.surface_high
                    activeFocusOnTab: true
                    border.width: activeFocus ? 1 : 0
                    border.color: Tokens.accent
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.checkable: true
                    Accessible.checked: selected

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: tab.modelData.icon
                            font.pixelSize: 12
                            color: tab.selected ? Tokens.on_accent : Tokens.text_secondary
                        }
                        Text {
                            text: tab.modelData.label
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: tab.selected ? Tokens.on_accent : Tokens.text_primary
                        }
                    }

                    TapHandler { onTapped: root.selectPage(tab.modelData.id) }
                    Keys.onReturnPressed: function(event) {
                        root.selectPage(tab.modelData.id);
                        event.accepted = true;
                    }
                    Keys.onSpacePressed: function(event) {
                        root.selectPage(tab.modelData.id);
                        event.accepted = true;
                    }
                }
            }
        }

        Item {
            id: pageStage
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Loader {
                id: wifiLoader
                anchors.fill: parent
                active: true
                visible: root.activePage === "wifi"
                source: "WifiDrawer.qml"
            }
            Loader {
                id: bluetoothLoader
                anchors.fill: parent
                active: true
                visible: root.activePage === "bluetooth"
                source: "BluetoothDrawer.qml"
            }
            Loader {
                id: hotspotLoader
                anchors.fill: parent
                active: root.hotspotVisited
                visible: root.activePage === "hotspot"
                source: "HotspotDrawer.qml"
            }
        }
    }

    Connections {
        target: wifiLoader.item
        function onHotspotPageRequested(): void { root.selectPage("hotspot"); }
        function onCloseRequested(): void { root.closeRequested(); }
    }
    Connections {
        target: bluetoothLoader.item
        function onCloseRequested(): void { root.closeRequested(); }
    }
}
