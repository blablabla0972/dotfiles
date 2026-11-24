pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../services"
import "../theme"
import "Registry.js" as Registry

FloatingWindow {
    id: root
    title: qsTr("Rice Settings")
    visible: false
    color: Tokens.background
    implicitWidth: Math.min(1120, screen ? Math.max(1, screen.width - 48) : 1120)
    implicitHeight: Math.min(760, screen ? Math.max(1, screen.height - 48) : 760)
    minimumSize: Qt.size(Math.min(560, implicitWidth), Math.min(420, implicitHeight))

    property string route: ""
    property int generation: 0
    property var history: []
    property var restore: null
    property Item beforeSearch: null
    property string routeMessage: ""
    property bool categories: false
    property var launcherState: null
    property ShellPresentation shellPresentation: null
    property SettingsPreferences preferences: null
    property WindowLayoutStore layoutState: null
    readonly property bool reducedMotion: !!preferences?.reduceMotion
    readonly property bool compact: !!preferences?.compactRows
    readonly property bool wide: contentItem.width > 880
    readonly property int sidebarWidth: 246
    readonly property int pageGutter: wide ? 28 : 22
    readonly property int pageLimit: 830
    readonly property var page: Registry.pageFor(route || "appearance")
    readonly property bool showingResults: Registry.normalize(searchField.text).length >= 2
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.background, 4.5)
    readonly property color subdued: Registry.readable(Tokens.text_secondary, Tokens.surface_low, 4.5)
    readonly property color selection: Qt.tint(Tokens.surface_low,
        Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18))
    readonly property color divider: Qt.tint(Tokens.surface_low,
        Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.55))

    signal dismissed()
    signal openWallpaper()

    onVisibleChanged: if (!visible) dismissed()

    function open(next: string, requestedScreen): void {
        const mapped = visible;
        if (!mapped && requestedScreen) screen = requestedScreen;
        navigate(Registry.canonicalRoute(next));
        visible = true;
        if (mapped && Hyprland.usingLua) {
            Hyprland.dispatch(`(function()
                local address
                for _, window in ipairs(hl.get_windows()) do
                    if window.pid == ${Quickshell.processId} and window.title == ${JSON.stringify(title)}
                        and window.address:match("^0x%x+$") then
                        if address then return end
                        address = window.address
                    end
                end
                if address then return hl.dsp.focus({window = "address:" .. address}) end
            end)()`);
        } else if (mapped) {
            const clients = Hyprland.toplevels.values.filter(client =>
                client.title === title && client.lastIpcObject.pid === Quickshell.processId);
            if (clients.length === 1 && !clients[0].activated)
                clients[0].wayland?.activate();
        }
    }

    function navigate(next: string, saved): void {
        if (route && route !== next && saved === undefined) {
            const focusItem = searchField.activeFocus || results.activeFocus
                ? beforeSearch : contentItem.Window.window?.activeFocusItem;
            let focus = focusItem;
            while (focus && !focus.objectName) focus = focus.parent;
            history = history.slice(-19).concat([{
                route: route, scroll: view.contentY, focus: focus ? focus.objectName : ""
            }]);
        }
        restore = saved || null;
        searchField.clear();
        routeMessage = "";
        categories = false;
        route = next;
        generation++;
        scheduleFocus();
    }

    function back(): void {
        if (searchField.text.length) {
            endSearch();
        } else if (history.length) {
            const previous = history[history.length - 1];
            history = history.slice(0, -1);
            navigate(previous.route, previous);
        } else if (!wide && !categories) {
            showCategories();
        }
    }

    function showCategories(): void {
        categories = true;
        nav.currentIndex = Registry.pages.indexOf(page);
        nav.forceActiveFocus();
    }

    function endSearch(): void {
        searchField.clear();
        if (beforeSearch && beforeSearch.visible) beforeSearch.forceActiveFocus();
        else currentPage.heading.forceActiveFocus();
    }

    function scheduleFocus(): void {
        if (!currentPage.loaded) return;
        const request = generation;
        Qt.callLater(() => {
            if (!root || request !== root.generation || !root.visible || !currentPage.loaded
                    || searchField.text.length || (!root.wide && root.categories)) return;
            const target = (restore && restore.focus) || route.split("#")[1];
            const row = target && currentPage.findItem(target);
            if (!restore && target && !row)
                root.routeMessage = qsTr("The requested setting is no longer available.");
            view.contentY = Math.max(0, Math.min(
                restore ? restore.scroll : row ? row.mapToItem(view.contentItem, 0, 0).y - 8 : 0,
                view.contentHeight - view.height));
            (row || currentPage.heading).forceActiveFocus();
            restore = null;
        });
    }

    Shortcut {
        sequences: [StandardKey.Find, "Ctrl+K"]
        onActivated: searchField.forceActiveFocus(Qt.ShortcutFocusReason)
    }
    Shortcut { sequence: "Alt+Left"; onActivated: root.back() }
    Shortcut { sequences: [StandardKey.Close]; onActivated: root.visible = false }
    Connections {
        target: root.contentItem.Window.window
        function onActiveFocusItemChanged(): void {
            const focusItem = target.activeFocusItem;
            if (focusItem && !searchField.activeFocus && !results.activeFocus)
                root.beforeSearch = focusItem;
        }
    }

    Control {
        anchors.fill: parent
        font.family: "Noto Sans"
        font.pixelSize: 14
        palette.window: Tokens.background
        palette.windowText: root.ink
        palette.base: Tokens.surface_low
        palette.text: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
        palette.button: Tokens.surface_high
        palette.buttonText: Registry.readable(Tokens.text_primary, Tokens.surface_high, 4.5)
        palette.highlight: Tokens.accent
        palette.highlightedText: Registry.readable(Tokens.on_accent, Tokens.accent, 4.5)

        contentItem: ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                spacing: 10

                RowLayout {
                    Layout.preferredWidth: root.wide ? root.sidebarWidth + root.pageGutter - 25 : implicitWidth
                    spacing: 8

                    SettingsIcon {
                        visible: root.wide || root.categories
                        Layout.leftMargin: 4
                        name: "shell"
                        color: Registry.readable(Tokens.accent, Tokens.background, 4.5)
                    }
                    Label {
                        visible: root.wide || root.categories
                        text: root.title
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: root.ink
                    }
                    Choice {
                        visible: (root.wide && root.history.length > 0 && !root.showingResults)
                            || (!root.wide && !root.categories)
                        symbol: "back"
                        Accessible.name: root.wide ? qsTr("Back") : qsTr("Categories")
                        onClicked: root.wide ? root.back() : root.showCategories()
                    }
                }
                TextField {
                    id: searchField
                    objectName: "settings-search"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 400
                    Layout.minimumWidth: 130
                    Layout.maximumWidth: root.wide ? 440 : Infinity
                    implicitHeight: 42
                    leftPadding: 40
                    rightPadding: searchField.text.length ? 44 : (root.wide ? 64 : 14)
                    placeholderText: qsTr("Search settings")
                    placeholderTextColor: root.subdued
                    Accessible.name: placeholderText
                    selectByMouse: true
                    maximumLength: 128
                    background: Rectangle {
                        radius: 9
                        color: Tokens.surface
                        border.width: searchField.activeFocus ? 2 : 1
                        border.color: searchField.activeFocus ? Registry.readable(Tokens.focus_ring, color, 3) : root.divider
                        SettingsIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            color: root.subdued
                        }
                    }
                    Rectangle {
                        visible: root.wide && !searchField.text.length && !searchField.activeFocus
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: shortcutHint.implicitWidth + 14
                        height: 24
                        radius: 5
                        color: Tokens.surface_low
                        border.color: root.divider

                        Label {
                            id: shortcutHint
                            anchors.centerIn: parent
                            text: "Ctrl K"
                            font.pixelSize: 11
                            color: root.subdued
                            Accessible.ignored: true
                        }
                    }
                    Choice {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 36
                        visible: searchField.text.length > 0
                        symbol: "close"
                        Accessible.name: qsTr("Clear search")
                        onClicked: root.endSearch()
                    }
                    onAccepted: if (results.currentItem) root.navigate(results.currentItem.modelData.route)
                    Keys.onEscapePressed: event => {
                        if (inputMethodComposing) event.accepted = false;
                        else root.endSearch();
                    }
                    Keys.onDownPressed: event => {
                        event.accepted = root.showingResults && !inputMethodComposing && results.count > 0;
                        if (event.accepted) {
                            results.currentIndex = 0;
                            results.forceActiveFocus(Qt.TabFocusReason);
                        }
                    }
                }
                Item { Layout.fillWidth: root.wide }
                Choice {
                    objectName: "settings-close"
                    symbol: "close"
                    Accessible.name: qsTr("Close Settings")
                    onClicked: root.visible = false
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.divider }
            Label {
                Layout.fillWidth: true
                Layout.margins: root.wide ? 24 : 16
                visible: root.routeMessage.length > 0 && !root.showingResults
                text: root.routeMessage
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    visible: root.wide || (!root.showingResults && root.categories)
                    Layout.preferredWidth: root.sidebarWidth
                    Layout.fillWidth: !root.wide
                    Layout.fillHeight: true
                    color: Tokens.surface_low

                    ListView {
                        id: nav
                        anchors.fill: parent
                        anchors.margins: 12
                        anchors.topMargin: 12
                        spacing: 2
                        clip: true
                        keyNavigationEnabled: true
                        model: Registry.pages
                        Keys.onReturnPressed: if (currentItem) root.navigate(currentItem.modelData.id)
                        Keys.onEnterPressed: if (currentItem) root.navigate(currentItem.modelData.id)
                        delegate: ColumnLayout {
                            id: navRow
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            spacing: 3

                            Label {
                                Layout.leftMargin: 12
                                Layout.topMargin: navRow.index === 0 ? 4 : 12
                                Layout.bottomMargin: 3
                                visible: navRow.index === 0
                                    || Registry.pages[navRow.index - 1].group !== navRow.modelData.group
                                text: navRow.modelData.group
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: root.subdued
                                Accessible.role: Accessible.Heading
                            }

                            Choice {
                                Layout.fillWidth: true
                                objectName: "nav-" + navRow.modelData.id
                                text: navRow.modelData.label
                                symbol: navRow.modelData.icon
                                Accessible.name: text
                                selectedPage: navRow.modelData.id === root.page.id
                                highlighted: selectedPage || (nav.activeFocus && navRow.ListView.isCurrentItem)
                                Accessible.selected: selectedPage
                                onActiveFocusChanged: if (activeFocus) nav.currentIndex = navRow.index
                                onClicked: root.navigate(navRow.modelData.id)
                            }
                        }
                        ScrollBar.vertical: ScrollBar {}
                    }
                }
                Rectangle { visible: root.wide; Layout.fillHeight: true; implicitWidth: 1; color: root.divider }

                Flickable {
                    id: view
                    visible: !root.showingResults && (root.wide || !root.categories)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentHeight: currentPage.height + 2 * currentPage.y
                    ScrollBar.vertical: ScrollBar {}

                    SettingsPage {
                        id: currentPage
                        objectName: "settings-page"
                        x: root.pageGutter
                        y: root.wide ? 26 : 20
                        width: Math.max(0, Math.min(root.pageLimit, view.width - 2 * root.pageGutter))
                        page: root.page
                        detailRoute: root.route.split("#")[1] || ""
                        windowActive: root.contentItem.Window.window?.active ?? false
                        onRequestRoute: route => root.navigate(route)
                        launcherState: root.launcherState
                        shellPresentation: root.shellPresentation
                        preferences: root.preferences
                        layoutState: root.layoutState
                        onOpenWallpaper: root.openWallpaper()
                        onReady: root.scheduleFocus()
                        opacity: loaded ? 1 : 0
                        Behavior on opacity {
                            enabled: !root.reducedMotion
                            NumberAnimation { duration: 150 }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: !currentPage.loaded
                        text: currentPage.failed ? qsTr("Unable to load settings") : qsTr("Loading…")
                    }
                }

                ListView {
                    id: results
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.maximumWidth: root.pageLimit
                    Layout.margins: root.pageGutter
                    visible: root.showingResults
                    clip: true
                    spacing: 4
                    activeFocusOnTab: visible && count > 0
                    model: root.showingResults ? Registry.search(searchField.text) : []
                    keyNavigationEnabled: true
                    Keys.onReturnPressed: if (currentItem) root.navigate(currentItem.modelData.route)
                    Keys.onEnterPressed: if (currentItem) root.navigate(currentItem.modelData.route)
                    Keys.onEscapePressed: root.endSearch()
                    Keys.onUpPressed: event => {
                        event.accepted = currentIndex === 0;
                        if (event.accepted) searchField.forceActiveFocus();
                    }
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Choice {
                        required property var modelData
                        width: ListView.view.width
                        text: modelData.label
                        subtitle: modelData.page
                        symbol: modelData.icon
                        Accessible.description: modelData.page
                        highlighted: activeFocus || (results.activeFocus && ListView.isCurrentItem)
                        onClicked: root.navigate(modelData.route)
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: results.count === 0
                        text: qsTr("No matching settings")
                    }
                }
                Item { visible: root.wide && root.showingResults; Layout.fillWidth: true }
            }
        }
    }

    component Choice: Button {
        id: choice
        property string symbol
        property bool selectedPage: false
        property string subtitle
        readonly property color textBase: fill.color.a ? fill.color : Tokens.surface_low
        readonly property color foreground: Registry.readable(Tokens.text_primary, textBase, 4.5)
        implicitWidth: text ? contentItem.implicitWidth + leftPadding + rightPadding : 38
        implicitHeight: subtitle ? 55 : root.compact ? 33 : 38
        leftPadding: text ? 11 : 0
        rightPadding: text ? 8 : 0
        contentItem: RowLayout {
            spacing: 10
            Item {
                visible: choice.symbol.length > 0
                implicitWidth: 20
                implicitHeight: 20
                Layout.fillWidth: !choice.text

                SettingsIcon {
                    anchors.centerIn: parent
                    name: choice.symbol
                    width: 19
                    height: 19
                    color: Registry.readable(choice.highlighted ? Tokens.accent : Tokens.text_secondary,
                        choice.textBase, 4.5)
                }
            }
            ColumnLayout {
                visible: choice.text.length > 0
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: choice.text
                    elide: Text.ElideRight
                    font.pixelSize: 14
                    font.weight: choice.highlighted ? Font.DemiBold : Font.Medium
                    color: choice.foreground
                }
                Label {
                    visible: choice.subtitle.length > 0
                    text: choice.subtitle
                    font.pixelSize: 12
                    color: Registry.readable(Tokens.text_secondary, choice.textBase, 4.5)
                }
            }
        }
        background: Rectangle {
            id: fill
            radius: 8
            color: choice.down ? Tokens.surface_high : choice.highlighted ? root.selection
                : choice.hovered ? Tokens.surface : "transparent"
            border.width: choice.visualFocus ? 2 : 0
            border.color: Registry.readable(Tokens.focus_ring, choice.highlighted ? root.selection : Tokens.surface_low, 3)
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 16
                radius: 2
                visible: choice.selectedPage
                color: Registry.readable(Tokens.accent, root.selection, 3)
            }
            Behavior on color {
                enabled: !root.reducedMotion
                ColorAnimation { duration: 120 }
            }
        }
    }
}
