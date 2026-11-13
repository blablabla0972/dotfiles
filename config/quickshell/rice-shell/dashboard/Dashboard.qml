pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../island/IslandState.js" as IslandState
import "."

Item {
    id: dashboardWindow

    required property Item surface
    required property Item shape
    property var cardDimensions: ({ width: 760, height: 440, radius: 22,
        sideBySide: true, drawerOverlay: false, drawerWidth: 300 })
    property string currentTab: "Home"
    property bool expanded: false
    property bool closing: false
    property real revealProgress: 0
    property real tabEntranceProgress: 1
    readonly property real tabEntranceOffset: 10 * (1 - tabEntranceProgress)
    property string activeSideDrawer: ""
    property string renderedSideDrawer: ""
    onCurrentTabChanged: {
        activeSideDrawer = "";
        tabScroll.contentY = 0;
        if (expanded) {
            tabEntranceProgress = 0;
            tabEntranceAnimation.restart();
        }
    }
    onActiveSideDrawerChanged: {
        if (activeSideDrawer.length > 0) renderedSideDrawer = activeSideDrawer;
    }
    readonly property bool sideDrawerOpen: expanded && activeSideDrawer.length > 0
    readonly property bool drawerOverlay: !cardDimensions.sideBySide
    readonly property real drawerOffset: drawerOverlay ? 0 : Math.min(156, sideDrawerContainer.width * 0.52)
    readonly property real activeContentHeight: {
        var loaded = currentTab === "Home" ? homeLoader.item
            : currentTab === "System" ? systemLoader.item
            : currentTab === "Notifications" ? notificationLoader.item : configLoader.item;
        return loaded ? Math.max(0, loaded.implicitHeight) : 370;
    }
    readonly property bool wifiLoaded: wifiLoader.item !== null
    readonly property bool bluetoothLoaded: bluetoothLoader.item !== null
    visible: expanded || closing
    focus: expanded
    onExpandedChanged: {
        if (expanded) Qt.callLater(() => {
            if (dashboardWindow.expanded) dashboardWindow.forceActiveFocus();
        });
    }

    NumberAnimation {
        id: tabEntranceAnimation
        target: dashboardWindow
        property: "tabEntranceProgress"
        from: 0
        to: 1
        duration: 210
        easing.type: Easing.OutCubic
    }

    Keys.onEscapePressed: (event) => {
        handleEscape();
        event.accepted = true;
    }

    // TextInput can consume Escape before it reaches the parent Keys handler.
    Shortcut {
        sequence: "Escape"
        enabled: dashboardWindow.expanded
        context: Qt.WindowShortcut
        onActivated: dashboardWindow.handleEscape()
    }

    function toggleSideDrawer(type: string): void {
        var drawer = IslandState.normalizeSideDrawer(type);
        if (!drawer) {
            console.warn("Ignoring unknown side drawer: " + type);
            return;
        }
        activeSideDrawer = activeSideDrawer === drawer ? "" : drawer;
    }

    function toggle(tab): void {
        var target = IslandState.normalizeDashboardTab(tab || "Home");
        if (typeof tab === "string" && tab.length > 0 && tab !== target)
            console.warn("Unknown Dashboard tab '" + tab + "'; opening Home");
        if (expanded && currentTab === target) {
            dismiss();
        } else {
            currentTab = target;
            expanded = true;
            closing = false;
        }
    }

    function dismiss(): void {
        if (!expanded) return;
        closing = true;
        activeSideDrawer = "";
        expanded = false;
    }

    function handleEscape(): void {
        if (sideDrawerOpen) activeSideDrawer = "";
        else dismiss();
    }

    function containsDrawer(x: real, y: real): bool {
        return sideDrawerOpen && sideDrawerContainer.visible && x >= sideDrawerContainer.x
            && x <= sideDrawerContainer.x + sideDrawerContainer.width
            && y >= sideDrawerContainer.y
            && y <= sideDrawerContainer.y + sideDrawerContainer.height;
    }

    // Same geometry as the Island; only the contents are owned here.
    Item {
        id: morphContainer
        x: dashboardWindow.surface.x + dashboardWindow.shape.a
        y: dashboardWindow.surface.y
        width: dashboardWindow.shape.pillWidth
        height: dashboardWindow.shape.pillHeight
        clip: true

        MouseArea {
            anchors.fill: parent
            enabled: dashboardWindow.expanded
            onClicked: {}
        }

        // Dashboard Content Layout
        Item {
            id: cardContent
            anchors.horizontalCenter: parent.horizontalCenter
            width: dashboardWindow.cardDimensions.width
            height: dashboardWindow.cardDimensions.height
            y: -18 * (1 - dashboardWindow.revealProgress)
            opacity: Math.max(0, (dashboardWindow.revealProgress - 0.15) / 0.85)
            enabled: dashboardWindow.expanded && opacity > 0.9

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 14
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                // Header: Branding, Tabs, and Dismiss Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Left Branding / Title
                    Row {
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "󰍹"
                                font.pixelSize: 14
                                color: Tokens.accent
                            }
                        }

                        Text {
                            visible: dashboardWindow.cardDimensions.width >= 680
                            text: "Control Center"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Center Tab Navigation Pills
                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignHCenter

                        Repeater {
                            model: [
                                { id: "Home", name: "Home", icon: "󰋜" },
                                { id: "Notifications", name: "Alerts", icon: "󰂚" },
                                { id: "System", name: "System", icon: "󰍹" },
                                { id: "Config", name: "Config", icon: "󰒓" }
                            ]

                            Rectangle {
                                id: tabPill
                                required property var modelData
                                readonly property bool isSelected: dashboardWindow.currentTab === modelData.id

                                width: tabRow.implicitWidth + 24
                                height: 30
                                radius: 15
                                color: isSelected ? Tokens.accent : (tabHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8) : "transparent")
                                border.color: isSelected ? "transparent" : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                                border.width: isSelected ? 0 : 1

                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }

                                Row {
                                    id: tabRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: tabPill.modelData.icon
                                        font.pixelSize: 12
                                        color: tabPill.isSelected ? Tokens.on_accent : Tokens.text_primary
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Text {
                                        visible: dashboardWindow.cardDimensions.width >= 680
                                        text: tabPill.modelData.name
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: tabPill.isSelected ? Tokens.on_accent : Tokens.text_primary
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }
                                }

                                HoverHandler { id: tabHover }
                                TapHandler {
                                    onTapped: dashboardWindow.currentTab = tabPill.modelData.id
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Right Close Button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: closeHover.hovered ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.2) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.6)
                        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.pixelSize: 14
                            color: closeHover.hovered ? Tokens.danger : Tokens.text_secondary
                        }

                        HoverHandler { id: closeHover }
                        TapHandler {
                            onTapped: dashboardWindow.dismiss()
                        }
                    }
                }

                // Tab View Body with Lazy Loading
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        id: tabStage
                        anchors.fill: parent
                        clip: true
                        opacity: dashboardWindow.tabEntranceProgress
                        enabled: dashboardWindow.tabEntranceProgress >= 0.8
                        transform: Translate { y: dashboardWindow.tabEntranceOffset }

                        Flickable {
                            id: tabScroll
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: Math.max(height, dashboardWindow.activeContentHeight)
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Item {
                                id: tabContent
                                width: tabScroll.width
                                height: tabScroll.contentHeight

                                Loader {
                                    id: homeLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.currentTab === "Home"
                                    visible: dashboardWindow.currentTab === "Home"
                                    sourceComponent: Home {
                                        onRequestSideDrawer: (type) => dashboardWindow.toggleSideDrawer(type)
                                    }
                                }

                                Loader {
                                    id: systemLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.currentTab === "System"
                                    visible: dashboardWindow.currentTab === "System"
                                    sourceComponent: System {}
                                }

                                Loader {
                                    id: notificationLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.currentTab === "Notifications"
                                    visible: dashboardWindow.currentTab === "Notifications"
                                    sourceComponent: NotificationCenter {}
                                }

                                Loader {
                                    id: configLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.currentTab === "Config"
                                    visible: dashboardWindow.currentTab === "Config"
                                    sourceComponent: Config {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Narrow screens use the drawer as an in-card page; wide screens show a sidecar.
    Item {
        id: sideDrawerContainer
        anchors.top: morphContainer.top
        x: dashboardWindow.drawerOverlay ? morphContainer.x
            : morphContainer.x + morphContainer.width + 12
        width: dashboardWindow.sideDrawerOpen
            ? (dashboardWindow.drawerOverlay ? dashboardWindow.cardDimensions.width
                : dashboardWindow.cardDimensions.drawerWidth) : 0
        height: morphContainer.height
        clip: true
        visible: width > 0
        enabled: dashboardWindow.sideDrawerOpen
        opacity: dashboardWindow.sideDrawerOpen ? 1.0 : 0.0

        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // Absorb inner clicks
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Item {
            anchors.fill: parent

            Loader {
                id: wifiLoader
                anchors.fill: parent
                active: (dashboardWindow.sideDrawerOpen || sideDrawerContainer.width > 0)
                    && dashboardWindow.renderedSideDrawer === "wifi"
                sourceComponent: WifiDrawer {
                    onCloseRequested: dashboardWindow.activeSideDrawer = ""
                }
            }

            Loader {
                id: bluetoothLoader
                anchors.fill: parent
                active: (dashboardWindow.sideDrawerOpen || sideDrawerContainer.width > 0)
                    && dashboardWindow.renderedSideDrawer === "bluetooth"
                sourceComponent: BluetoothDrawer {
                    onCloseRequested: dashboardWindow.activeSideDrawer = ""
                }
            }
        }
    }
}
