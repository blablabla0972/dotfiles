pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../island" as Island
import "../island/IslandState.js" as IslandState
import "."

Item {
    id: dashboardWindow
    signal requestSettings()

    required property Item surface
    required property Item shape
    property var cardDimensions: IslandState.dashboardGeometry(1920, 1080, 7)
    property string currentTab: "Home"
    property bool expanded: false
    property bool closing: false
    property real revealProgress: 0
    readonly property real headerReveal: Math.min(1, revealProgress / 0.70)
    readonly property real bodyReveal: Math.max(0, Math.min(1, (revealProgress - 0.24) / 0.76))
    property string renderedTab: "Home"
    property real tabEntranceProgress: expanded && renderedTab !== currentTab ? 0 : 1
    Behavior on tabEntranceProgress {
        id: tabFade
        NumberAnimation {
            duration: tabFade.targetValue === 0 ? 85 : 165
            easing.type: tabFade.targetValue === 0 ? Easing.InQuad : Easing.OutCubic
        }
    }
    onTabEntranceProgressChanged: if (tabEntranceProgress === 0) showCurrentTab()
    property string activeSideDrawer: ""
    property string renderedSideDrawer: ""
    onCurrentTabChanged: {
        activeSideDrawer = "";
        if (!expanded) showCurrentTab();
    }
    function showCurrentTab(): void {
        renderedTab = currentTab;
        tabScroll.contentY = 0;
    }
    onActiveSideDrawerChanged: {
        if (activeSideDrawer.length > 0) renderedSideDrawer = activeSideDrawer;
    }
    readonly property bool sideDrawerOpen: expanded && activeSideDrawer.length > 0
    readonly property bool drawerOverlay: !cardDimensions.sideBySide
    readonly property real drawerProgress: drawerSpring.position.x
    readonly property real drawerOffset: drawerOverlay ? 0
        : Math.min(156, cardDimensions.drawerWidth * 0.52) * drawerProgress
    Island.IslandSpring {
        id: drawerSpring
        target: Qt.vector3d(dashboardWindow.sideDrawerOpen ? 1 : 0, 0, 0)
        contracting: !dashboardWindow.sideDrawerOpen
        epsilon: 0.001
    }
    readonly property real activeContentHeight: {
        var loaded = renderedTab === "Home" ? homeLoader.item
            : renderedTab === "Power" ? powerLoader.item
            : renderedTab === "System" ? systemLoader.item
            : renderedTab === "Notifications" ? notificationLoader.item : configLoader.item;
        return loaded ? Math.max(0, loaded.implicitHeight) : 370;
    }
    readonly property bool connectivityLoaded: connectivityLoader.item !== null
    readonly property bool wifiLoaded: connectivityLoader.item ? connectivityLoader.item.wifiLoaded : false
    readonly property bool bluetoothLoaded: connectivityLoader.item ? connectivityLoader.item.bluetoothLoaded : false
    visible: expanded || closing
    focus: expanded
    onExpandedChanged: {
        if (expanded) Qt.callLater(() => {
            if (dashboardWindow.expanded) dashboardWindow.forceActiveFocus();
        });
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

    function selectSideDrawer(type: string): void {
        var drawer = IslandState.normalizeSideDrawer(type);
        if (!drawer) return;
        activeSideDrawer = drawer;
        renderedSideDrawer = drawer;
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
        if (sideDrawerOpen) {
            if (connectivityLoader.item && typeof connectivityLoader.item.handleEscape === "function" && connectivityLoader.item.handleEscape()) return;
            activeSideDrawer = "";
        } else dismiss();
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
            transformOrigin: Item.Top
            scale: 0.99 + 0.01 * dashboardWindow.revealProgress
            visible: dashboardWindow.revealProgress > 0
            enabled: dashboardWindow.expanded && dashboardWindow.revealProgress > 0.9
                && !(dashboardWindow.sideDrawerOpen && dashboardWindow.drawerOverlay)

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 14
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    opacity: dashboardWindow.headerReveal
                    transform: Translate { y: -8 * (1 - dashboardWindow.headerReveal) }

                    Text {
                        visible: dashboardWindow.cardDimensions.width >= 680
                        text: qsTr("Control Center")
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: tabs.implicitWidth + 6
                        implicitHeight: tabs.implicitHeight + 6
                        radius: height / 2
                        color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)
                        Row {
                            id: tabs
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [
                                    { id: "Home", name: qsTr("Home"), icon: "󰋜" },
                                    { id: "Notifications", name: qsTr("Alerts"), icon: "󰂚" },
                                    { id: "System", name: qsTr("System"), icon: "󰍹" },
                                    { id: "Power", name: qsTr("Power"), icon: "󰁹" },
                                    { id: "Config", name: qsTr("Config"), icon: "󰒓" }
                                ]
                                Island.IslandButton {
                                    required property var modelData
                                    text: modelData.name
                                    glyph: dashboardWindow.cardDimensions.width >= 680 ? text : modelData.icon
                                    horizontalPadding: dashboardWindow.cardDimensions.width >= 680 ? 12 : 6
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    prominent: dashboardWindow.currentTab === modelData.id
                                    Accessible.role: Accessible.PageTab
                                    Accessible.selected: prominent
                                    onClicked: dashboardWindow.currentTab = modelData.id
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                    Island.IslandButton {
                        text: qsTr("Close Control Center")
                        glyph: "󰅖"
                        onClicked: dashboardWindow.dismiss()
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
                        opacity: dashboardWindow.tabEntranceProgress * dashboardWindow.bodyReveal
                        enabled: dashboardWindow.renderedTab === dashboardWindow.currentTab && opacity >= 0.8
                        transform: Translate {
                            y: -14 * (1 - dashboardWindow.bodyReveal) + 4 * (1 - dashboardWindow.tabEntranceProgress)
                        }

                        Flickable {
                            id: tabScroll
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: Math.max(height, dashboardWindow.activeContentHeight)
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: (dashboardWindow.renderedTab !== "Home" || dashboardWindow.cardDimensions.width < 820)
                                && contentHeight > height

                            Item {
                                id: tabContent
                                width: tabScroll.width
                                height: tabScroll.contentHeight

                                Loader {
                                    id: homeLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.renderedTab === "Home"
                                    sourceComponent: Home {
                                        onRequestSideDrawer: (type) => dashboardWindow.toggleSideDrawer(type)
                                    }
                                }

                                Loader {
                                    id: systemLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.renderedTab === "System"
                                    sourceComponent: System {}
                                }

                                Loader {
                                    id: powerLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.renderedTab === "Power"
                                    source: "Power.qml"
                                }

                                Loader {
                                    id: notificationLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.renderedTab === "Notifications"
                                    sourceComponent: NotificationCenter {}
                                }

                                Loader {
                                    id: configLoader
                                    anchors.fill: parent
                                    active: dashboardWindow.visible && dashboardWindow.renderedTab === "Config"
                                    sourceComponent: Config {
                                        onRequestSettings: dashboardWindow.requestSettings()
                                    }
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
        x: morphContainer.x + (dashboardWindow.drawerOverlay
            ? 24 * (1 - dashboardWindow.drawerProgress)
            : morphContainer.width + 12 * dashboardWindow.drawerProgress)
        width: dashboardWindow.drawerOverlay ? dashboardWindow.cardDimensions.width
            : dashboardWindow.cardDimensions.drawerWidth
        height: morphContainer.height
        clip: true
        visible: dashboardWindow.sideDrawerOpen || drawerSpring.running
        enabled: dashboardWindow.sideDrawerOpen
        opacity: Math.max(0, Math.min(1, dashboardWindow.drawerProgress)) * dashboardWindow.bodyReveal

        // Absorb inner clicks
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Item {
            width: parent.width
            height: dashboardWindow.cardDimensions.height

            Loader {
                anchors.fill: parent
                active: sideDrawerContainer.visible && dashboardWindow.renderedSideDrawer === "audio"
                sourceComponent: AudioDrawer {
                    onCloseRequested: dashboardWindow.activeSideDrawer = ""
                }
            }

            Loader {
                id: connectivityLoader
                anchors.fill: parent
                active: sideDrawerContainer.visible && dashboardWindow.renderedSideDrawer !== "audio"
                sourceComponent: ConnectivityCenter {
                    currentPage: dashboardWindow.renderedSideDrawer
                    drawerOpen: dashboardWindow.sideDrawerOpen
                    onPageSelected: (page) => dashboardWindow.selectSideDrawer(page)
                    onCloseRequested: dashboardWindow.activeSideDrawer = ""
                }
            }
        }
    }
}
