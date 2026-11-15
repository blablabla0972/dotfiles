pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../theme"
import "LaunchCommand.js" as LaunchCommand

PanelWindow {
    id: launcherWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false
    property bool closing: false

    Timer {
        id: closeTimer
        interval: 110
        onTriggered: launcherWindow.visible = false
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: Region {
        item: launcherWindow.visible ? scrim : null
    }

    property string searchText: ""
    property int selectedIndex: 0
    property string selectedCategory: "All"

    readonly property var categories: ["All", "Internet", "Development", "Multimedia", "System", "Settings"]

    function getCategoryIcon(cat: string): string {
        switch (cat) {
        case "Internet": return "󰖟";
        case "Development": return "󰅩";
        case "Multimedia": return "󰕼";
        case "System": return "󰒋";
        case "Settings": return "󰒓";
        default: return "󰕰";
        }
    }

    function matchesCategory(app, category: string): bool {
        if (!category || category === "All") return true;
        if (!app) return false;

        var tokens = [];
        if (app.categories) {
            for (var i = 0; i < app.categories.length; i++) {
                if (app.categories[i]) tokens.push(app.categories[i].toLowerCase());
            }
        }
        if (app.keywords) {
            for (var k = 0; k < app.keywords.length; k++) {
                if (app.keywords[k]) tokens.push(app.keywords[k].toLowerCase());
            }
        }
        var tokenStr = tokens.join(" ");
        var meta = (tokenStr + " " + (app.name || "") + " " + (app.genericName || "") + " " + (app.comment || "")).toLowerCase();

        switch (category) {
        case "Internet":
            return meta.includes("network") || meta.includes("web") || meta.includes("browser")
                || meta.includes("internet") || meta.includes("email") || meta.includes("chat")
                || meta.includes("feed") || meta.includes("download") || meta.includes("irc")
                || meta.includes("discord") || meta.includes("instantmessaging");
        case "Development":
            return meta.includes("development") || meta.includes("programming") || meta.includes("ide")
                || meta.includes("code") || meta.includes("editor") || meta.includes("debugger")
                || meta.includes("git") || meta.includes("texteditor") || meta.includes("terminal");
        case "Multimedia":
            return meta.includes("audiovideo") || meta.includes("audio") || meta.includes("video")
                || meta.includes("media") || meta.includes("player") || meta.includes("music")
                || meta.includes("recorder") || meta.includes("graphics") || meta.includes("image")
                || meta.includes("photo") || meta.includes("mpv") || meta.includes("sound");
        case "System":
            return meta.includes("system") || meta.includes("filetools") || meta.includes("filemanager")
                || meta.includes("terminalemulator") || meta.includes("monitor") || meta.includes("security")
                || meta.includes("utility") || meta.includes("core") || meta.includes("disk")
                || meta.includes("archive") || meta.includes("package");
        case "Settings":
            return meta.includes("settings") || meta.includes("preference") || meta.includes("hardware")
                || meta.includes("config") || meta.includes("desktopsettings") || meta.includes("control")
                || meta.includes("setup");
        default:
            return true;
        }
    }

    function getZeroStateApps(): var {
        var raw = allApps;
        if (!raw || raw.length === 0) return [];

        var valid = [];
        for (var i = 0; i < raw.length; i++) {
            var a = raw[i];
            if (a && a.name && !a.noDisplay) {
                if (matchesCategory(a, selectedCategory)) {
                    valid.push(a);
                }
            }
        }

        valid.sort(function(x, y) {
            return (x.name || "").localeCompare(y.name || "");
        });

        return valid;
    }

    // Filter desktop entries based on search query and category
    readonly property var allApps: DesktopEntries.applications ? DesktopEntries.applications.values : []
    readonly property var filteredApps: {
        var query = searchText.trim();

        // 1. Terminal Command Runner mode (starts with >)
        if (query.startsWith(">")) {
            var rawCmd = query.substring(1).trim();
            return [{
                isCommand: true,
                id: "cmd-runner",
                name: rawCmd.length > 0 ? ("Run: " + rawCmd) : "Run command in terminal...",
                comment: rawCmd.length > 0 ? ("Execute '" + rawCmd + "' in terminal") : "Type a shell command after '>'",
                icon: "utilities-terminal",
                command: rawCmd
            }];
        }

        // 2. Zero-state: valid apps in the selected category, sorted alphabetically
        if (query.length === 0) {
            return getZeroStateApps();
        }

        // 3. Search query filtering
        var lower = query.toLowerCase();
        var startsMatches = [];
        var nameMatches = [];
        var otherMatches = [];

        var apps = allApps;
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            if (!app || !app.name || app.noDisplay) continue;

            // Apply active category filter
            if (!matchesCategory(app, selectedCategory)) continue;

            var name = (app.name || "").toLowerCase();
            var generic = (app.genericName || "").toLowerCase();
            var comment = (app.comment || "").toLowerCase();

            if (name.startsWith(lower)) {
                startsMatches.push(app);
            } else if (name.includes(lower)) {
                nameMatches.push(app);
            } else if (generic.includes(lower) || comment.includes(lower)) {
                otherMatches.push(app);
            } else {
                var matchedKeyword = false;
                if (app.keywords) {
                    for (var k = 0; k < app.keywords.length; k++) {
                        if (app.keywords[k] && app.keywords[k].toLowerCase().includes(lower)) {
                            matchedKeyword = true;
                            break;
                        }
                    }
                }
                if (matchedKeyword) {
                    otherMatches.push(app);
                }
            }
        }

        var combined = startsMatches.concat(nameMatches).concat(otherMatches);
        return combined.slice(0, 40);
    }

    function toggle(): void {
        if (visible) dismiss();
        else visible = true;
    }

    function dismiss(): void {
        if (!visible || closing) return;
        closing = true;
        closeTimer.restart();
    }

    function cycleCategory(step: int): void {
        var count = categories.length;
        var idx = categories.indexOf(selectedCategory);
        if (idx < 0) idx = 0;
        var nextIdx = (idx + step + count) % count;
        selectedCategory = categories[nextIdx];
        selectedIndex = filteredApps.length > 0 ? 0 : -1;
        if (appList) appList.positionViewAtBeginning();
        if (categoryList) categoryList.positionViewAtIndex(nextIdx, ListView.Contain);
    }

    function executeCommand(cmd: string): void {
        if (closing) return;
        var cleanCmd = cmd ? cmd.trim() : "";
        if (cleanCmd.startsWith(">")) {
            cleanCmd = cleanCmd.substring(1).trim();
        }
        if (cleanCmd.length === 0) return;

        var terminal = (Quickshell.env("TERMINAL") || "").trim() || "kitty";
        var args = ["uwsm", "app", "--", terminal, "-e", "bash", "-c", cleanCmd];
        try {
            Quickshell.execDetached(args);
            dismiss();
        } catch (e) {
            console.warn("Command execution failed: " + e);
        }
    }

    function launchSelected(): void {
        if (closing) return;
        var query = searchText.trim();
        if (query.startsWith(">")) {
            executeCommand(query);
            return;
        }

        if (filteredApps.length === 0 || selectedIndex < 0 || selectedIndex >= filteredApps.length) return;

        var item = filteredApps[selectedIndex];
        if (item) {
            if (item.isCommand) {
                executeCommand(item.command);
            } else if (typeof item.execute === "function") {
                const context = LaunchCommand.launchContext(item,
                    Quickshell.env("TERMINAL"), Quickshell.env("HOME"));
                if (context) Quickshell.execDetached(context);
                else item.execute();
                dismiss();
            }
        }
    }

    onFilteredAppsChanged: {
        selectedIndex = filteredApps.length === 0 ? -1 : Math.max(0, Math.min(selectedIndex, filteredApps.length - 1));
    }

    onSelectedIndexChanged: {
        if (appList && selectedIndex >= 0 && selectedIndex < filteredApps.length) {
            appList.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    onVisibleChanged: {
        closeTimer.stop();
        closing = false;
        if (visible) {
            searchText = "";
            selectedCategory = "All";
            searchInput.text = "";
            selectedIndex = filteredApps.length > 0 ? 0 : -1;
            searchInput.forceActiveFocus();
            if (appList) appList.positionViewAtBeginning();
            if (categoryList) categoryList.positionViewAtBeginning();
        }
    }

    // Backdrop Scrim: keep application names readable over busy windows.
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(Tokens.background.r, Tokens.background.g, Tokens.background.b,
                       launcherWindow.visible && !launcherWindow.closing ? 0.22 : 0)
        Behavior on color { ColorAnimation { duration: 110 } }

        TapHandler {
            onTapped: (eventPoint) => {
                const p = launcherCard.mapFromItem(scrim, eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > launcherCard.width || p.y > launcherCard.height)
                    launcherWindow.dismiss();
            }
        }

        // Center Launcher Card
        Rectangle {
            id: launcherCard
            anchors.centerIn: parent
            width: Math.min(620, parent.width - 32)
            height: Math.min(570, parent.height - 48)
            radius: 26
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Math.max(0.97, Tokens.panelOpacity))
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1
            clip: true

            enabled: !launcherWindow.closing
            scale: launcherWindow.visible && !launcherWindow.closing ? 1.0 : 0.98
            opacity: launcherWindow.visible && !launcherWindow.closing ? 1.0 : 0.0

            Behavior on scale {
                NumberAnimation { duration: launcherWindow.closing ? 110 : 150; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: launcherWindow.closing ? 100 : 130; easing.type: Easing.OutQuad }
            }

            TapHandler {
                // Prevent tap from bubbling to scrim
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Applications"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: launcherWindow.filteredApps.length + " results"
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                }

                // Search Input Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 18
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)
                    border.color: searchInput.activeFocus ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: searchInput.activeFocus ? 1.5 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: launcherWindow.searchText.trim().startsWith(">") ? "󰞷" : "󰍉"
                            font.pixelSize: 21
                            color: Tokens.accent
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            color: Tokens.text_primary
                            font.pixelSize: 16
                            verticalAlignment: TextInput.AlignVCenter
                            activeFocusOnPress: true
                            selectByMouse: true
                            clip: true

                            Text {
                                anchors.fill: parent
                                visible: searchInput.text.length === 0
                                text: "Search applications…"
                                color: Tokens.text_secondary
                                font: searchInput.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            onTextChanged: {
                                launcherWindow.searchText = text;
                                launcherWindow.selectedIndex = launcherWindow.filteredApps.length > 0 ? 0 : -1;
                                if (appList) appList.positionViewAtBeginning();
                            }

                            Keys.onEscapePressed: (event) => {
                                launcherWindow.dismiss();
                                event.accepted = true;
                            }

                            Keys.onReturnPressed: (event) => {
                                launcherWindow.launchSelected();
                                event.accepted = true;
                            }

                            Keys.onDownPressed: (event) => {
                                if (launcherWindow.filteredApps.length > 0) {
                                    launcherWindow.selectedIndex = Math.min(launcherWindow.filteredApps.length - 1, launcherWindow.selectedIndex + 1);
                                    appList.positionViewAtIndex(launcherWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            }

                            Keys.onUpPressed: (event) => {
                                if (launcherWindow.filteredApps.length > 0) {
                                    launcherWindow.selectedIndex = Math.max(0, launcherWindow.selectedIndex - 1);
                                    appList.positionViewAtIndex(launcherWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            }

                            Keys.onTabPressed: (event) => {
                                launcherWindow.cycleCategory(1);
                                event.accepted = true;
                            }

                            Keys.onBacktabPressed: (event) => {
                                launcherWindow.cycleCategory(-1);
                                event.accepted = true;
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Tab) {
                                    launcherWindow.cycleCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Backtab) {
                                    launcherWindow.cycleCategory(-1);
                                    event.accepted = true;
                                }
                            }
                        }

                        // Clear button when search text is not empty
                        Rectangle {
                            visible: searchInput.text.length > 0
                            width: 20
                            height: 20
                            radius: 10
                            color: clearHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.pixelSize: 12
                                color: Tokens.text_secondary
                            }

                            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    searchInput.text = "";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Category Selector Pills
                ListView {
                    id: categoryList
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    orientation: ListView.Horizontal
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    model: launcherWindow.categories
                    currentIndex: launcherWindow.categories.indexOf(launcherWindow.selectedCategory)

                    delegate: Rectangle {
                        id: catPill
                        required property string modelData
                        required property int index
                        readonly property bool isSelected: launcherWindow.selectedCategory === catPill.modelData

                        implicitWidth: pillContent.implicitWidth + 24
                        height: 32
                        radius: 16

                        color: isSelected
                            ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.22)
                            : (pillHover.hovered
                                ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                                : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.35))

                        border.color: isSelected
                            ? Tokens.accent
                            : (pillHover.hovered
                                ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.45)
                                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2))
                        border.width: isSelected ? 1.5 : 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: pillContent
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: launcherWindow.getCategoryIcon(catPill.modelData)
                                font.pixelSize: 13
                                color: catPill.isSelected ? Tokens.accent : (pillHover.hovered ? Tokens.text_primary : Tokens.text_secondary)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                text: catPill.modelData
                                font.pixelSize: 11
                                font.bold: catPill.isSelected
                                color: catPill.isSelected ? Tokens.accent : (pillHover.hovered ? Tokens.text_primary : Tokens.text_secondary)
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        HoverHandler {
                            id: pillHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                launcherWindow.selectedCategory = catPill.modelData;
                                launcherWindow.selectedIndex = launcherWindow.filteredApps.length > 0 ? 0 : -1;
                                if (appList) appList.positionViewAtBeginning();
                                categoryList.positionViewAtIndex(catPill.index, ListView.Contain);
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }

                // Application List View
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: appList
                        anchors.fill: parent
                        model: launcherWindow.filteredApps
                        reuseItems: true
                        cacheBuffer: 120
                        spacing: 4
                        currentIndex: launcherWindow.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: appDelegate
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: launcherWindow.selectedIndex === appDelegate.index
                            readonly property bool isCommand: appDelegate.modelData && appDelegate.modelData.isCommand === true

                            width: appList.width
                            height: 56
                            radius: 16

                            color: isSelected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.12)
                                : (appHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.5) : "transparent")
                            border.color: isSelected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.26)
                                : (appHover.hovered ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25) : "transparent")
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                // Icon container
                                Item {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36

                                    // Command runner icon box
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        visible: appDelegate.isCommand
                                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                                        border.color: Tokens.accent
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰞷"
                                            font.pixelSize: 16
                                            color: Tokens.accent
                                        }
                                    }

                                    // Desktop application icon
                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        visible: !appDelegate.isCommand && status === Image.Ready
                                        source: (!appDelegate.isCommand && appDelegate.modelData && appDelegate.modelData.icon)
                                            ? (Quickshell.iconPath(appDelegate.modelData.icon) || appDelegate.modelData.icon)
                                            : ""
                                        asynchronous: true
                                        sourceSize: Qt.size(36, 36)
                                        fillMode: Image.PreserveAspectFit
                                    }

                                    // Fallback icon if desktop icon is missing/loading
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !appDelegate.isCommand && appIcon.status !== Image.Ready
                                        text: "󰀻"
                                        font.pixelSize: 20
                                        color: appDelegate.isSelected ? Tokens.accent : Tokens.text_secondary
                                    }
                                }

                                // App Name and Description
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: (appDelegate.modelData && appDelegate.modelData.name) ? appDelegate.modelData.name : ""
                                        font.pixelSize: 14
                                        font.weight: appDelegate.isSelected ? Font.DemiBold : Font.Normal
                                        color: Tokens.text_primary
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (!appDelegate.modelData) return "";
                                            if (appDelegate.isCommand) return appDelegate.modelData.comment || "";
                                            return appDelegate.modelData.comment || appDelegate.modelData.genericName || "";
                                        }
                                        font.pixelSize: 11
                                        color: Tokens.text_secondary
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }

                                // The selected row states the Enter action.
                                Rectangle {
                                    visible: appDelegate.isCommand || appDelegate.isSelected
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                                    border.color: Tokens.accent
                                    border.width: 1
                                    implicitWidth: cmdBadgeRow.implicitWidth + 12

                                    RowLayout {
                                        id: cmdBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: appDelegate.isCommand ? "↵ Run" : "↵ Open"
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: Tokens.accent
                                        }
                                    }
                                }
                            }

                            HoverHandler {
                                id: appHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    launcherWindow.selectedIndex = appDelegate.index;
                                    launcherWindow.launchSelected();
                                }
                            }
                        }
                    }

                    // Empty state when no apps match
                    Item {
                        anchors.fill: parent
                        visible: launcherWindow.filteredApps.length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "󰍉"
                                font.pixelSize: 32
                                color: Tokens.text_secondary
                                opacity: 0.6
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "No applications found"
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: launcherWindow.selectedCategory !== "All"
                                    ? ("No apps match in '" + launcherWindow.selectedCategory + "'. Press Tab to cycle categories.")
                                    : "Type '> command' to run a command in the terminal."
                                font.pixelSize: 11
                                color: Tokens.text_secondary
                            }
                        }
                    }
                }

                // Footer Bar with navigation shortcuts
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 8
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.3)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "↑↓"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.accent
                            }
                            Text {
                                text: "Navigate"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "•"
                            font.pixelSize: 8
                            color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "↵"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.accent
                            }
                            Text {
                                text: "Launch"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "•"
                            font.pixelSize: 8
                            color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "Tab"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.accent
                            }
                            Text {
                                text: "Category"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "•"
                            font.pixelSize: 8
                            color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: ">"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.accent
                            }
                            Text {
                                text: "Run Cmd"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "Esc"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.text_secondary
                            }
                            Text {
                                text: "Dismiss"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }
                    }
                }
            }
        }
    }
}
