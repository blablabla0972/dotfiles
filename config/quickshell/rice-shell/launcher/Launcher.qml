pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../theme"
import "LaunchCommand.js" as LaunchCommand
import "LauncherSearch.js" as LauncherSearch
import "QuickActions.js" as QuickActions

PanelWindow {
    id: launcherWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false
    property bool closing: false

    Timer {
        id: closeTimer
        interval: launcherWindow.reducedMotion ? 0 : 110
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
        item: launcherWindow.visible && !launcherWindow.closing ? scrim : null
    }

    property string searchText: ""
    property int selectedIndex: 0
    property string selectedCategory: "All"
    readonly property bool calculatorMode: searchText.trim().startsWith("=")
    readonly property bool actionsMode: searchText.trim().startsWith(":")
    readonly property bool commandMode: searchText.trim().startsWith(">")
    readonly property bool appMode: !calculatorMode && !actionsMode && !commandMode && !contextApp
    property bool browseAll: false
    readonly property bool homeMode: appMode && !searchText.trim() && !browseAll && selectedCategory === "All"
    readonly property bool reducedMotion: Quickshell.env("RICE_LAUNCHER_REDUCED_MOTION") === "1"
    property string pendingConfirmation: ""
    property var store: null
    property var sharedIndex: null
    property var actionStatuses: ({})
    property var actionAvailability: ({})
    property var contextApp: null
    property int returnIndex: 0
    property int session: 0
    property string feedback: ""
    signal quickActionRequested(string action, real argument)
    signal copyResultRequested(string result, string expression)

    LauncherCalculator {
        id: calculator
        active: launcherWindow.visible && !launcherWindow.closing && launcherWindow.calculatorMode
        expression: launcherWindow.calculatorMode ? launcherWindow.searchText.trim().slice(1) : ""
    }

    Timer {
        id: activationGuard
        interval: 500
    }

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
        return LauncherSearch.matchesCategory(app, category);
    }

    function getZeroStateApps(): var {
        return zeroStateApps;
    }

    // Filter desktop entries based on search query and category
    readonly property var allApps: DesktopEntries.applications ? DesktopEntries.applications.values : []
    readonly property var indexedApps: sharedIndex ?? LauncherSearch.indexApps(allApps)
    readonly property var categoryApps: indexedApps.filter(function(record) {
        return launcherWindow.matchesCategory(record.app, launcherWindow.selectedCategory);
    })
    readonly property var zeroStateApps: {
        var apps = categoryApps.map(function(record) { return record.app; });
        const favorites = store?.favorites || [];
        const recents = store?.recents || [];
        const byId = new Map(apps.map(app => [app.id, app]));
        const ordered = [];
        const recent = recents.filter(id => !favorites.includes(id) && byId.has(id))
            .sort((a, b) => (store?.frequency?.[b] || 0) - (store?.frequency?.[a] || 0));
        for (const id of favorites.concat(recent)) {
            if (!byId.has(id)) continue;
            ordered.push(byId.get(id));
            byId.delete(id);
        }
        if (!ordered.length && selectedCategory === "All") {
            for (const id of ["firefox", "org.mozilla.firefox", "org.kde.dolphin", "thunar",
                              "kitty", "Alacritty", "org.gnome.Nautilus", "code"]) {
                if (!byId.has(id)) continue;
                ordered.push(byId.get(id));
                byId.delete(id);
            }
        }
        apps.sort((x, y) => x.name.localeCompare(y.name));
        return ordered.concat(apps.filter(app => byId.has(app.id)));
    }
    readonly property var filteredApps: {
        var query = searchText.trim();

        if (contextApp) {
            return [{kind: "desktop-action", name: "Open " + contextApp.name, contextOpen: true},
                {name: isFavorite(contextApp) ? "Remove from favorites" : "Add to favorites",
                 kind: "desktop-action", contextFavorite: true, disabled: !store?.ready}]
                .concat(Array.from(contextApp.actions || [], action => ({
                    kind: "desktop-action", name: action.name, icon: action.icon, desktopAction: action
                })));
        }
        if (calculatorMode) {
            const expression = query.slice(1).trim();
            const history = store?.calculations || [];
            if (!expression && history.length) return history.map(entry => ({
                kind: "history", name: entry.value, comment: entry.expression, expression: entry.expression
            }));
            const result = calculator.result;
            return [{
                kind: result.value === undefined ? "message" : "calculation",
                name: result.display ?? result.value ?? result.error,
                comment: expression || "Calculator",
                copyValue: result.value,
                expression: expression,
                disabled: result.value === undefined
            }];
        }
        if (actionsMode) return QuickActions.findActions(query.slice(1), actionStatuses, actionAvailability);

        // 1. Terminal Command Runner mode (starts with >)
        if (query.startsWith(">")) {
            var rawCmd = query.substring(1).trim();
            return [{
                isCommand: true,
                kind: "command",
                id: "cmd-runner",
                name: rawCmd.length > 0 ? ("Run: " + rawCmd) : "Run command in terminal...",
                comment: rawCmd.length > 0 ? ("Execute '" + rawCmd + "' in terminal") : "Type a shell command after '>'",
                icon: "utilities-terminal",
                command: rawCmd
            }];
        }

        // 2. Zero-state: favorites, recent apps, then remaining apps alphabetically
        if (query.length === 0) {
            const apps = getZeroStateApps();
            if (!homeMode || !apps.length) return apps;
            return apps.slice(0, 9).concat(QuickActions.findActions("system", actionStatuses, actionAvailability)
                .filter(item => item.action === "system"));
        }

        return LauncherSearch.searchApps(categoryApps, query, store?.favorites, store?.recents, store?.frequency);
    }

    function toggle(): void {
        if (closing) {
            closeTimer.stop();
            session++;
            activationGuard.stop();
            feedback = "";
            closing = false;
            searchInput.forceActiveFocus();
        } else if (visible) dismiss();
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

    function isFavorite(app): bool {
        return !!app && !!store && store.favorites.includes(app.id);
    }

    function toggleFavorite(app): void {
        if (!store?.ready || !app?.id) return;
        const adding = !isFavorite(app);
        store.toggleFavorite(app.id);
        feedback = adding ? "Added to favorites" : "Removed from favorites";
        if (appMode) selectedIndex = filteredApps.indexOf(app);
    }

    function openContext(app): void {
        if (!appMode || closing || !app || app.kind) return;
        returnIndex = selectedIndex;
        contextApp = app;
        selectedIndex = 0;
        appList.positionViewAtBeginning();
    }

    function closeContext(): void {
        contextApp = null;
        selectedIndex = Math.min(returnIndex, filteredApps.length - 1);
        searchInput.forceActiveFocus();
    }

    function selectMode(prefix: string): void {
        if (contextApp) closeContext();
        searchInput.text = prefix;
        searchInput.cursorPosition = prefix.length;
        searchInput.forceActiveFocus();
    }

    function accept(event): void {
        if (!event.isAutoRepeat) {
            if (appMode && (event.modifiers & Qt.AltModifier))
                openContext(filteredApps[selectedIndex]);
            else launchSelected();
        }
        event.accepted = true;
    }

    function launchSelected(): void {
        if (closing) return;
        var query = searchText.trim();
        if (query.startsWith(">")) {
            if (query.length > 1 && pendingConfirmation !== query) {
                pendingConfirmation = query;
                feedback = "Press Enter again to run in terminal";
                return;
            }
            executeCommand(query);
            return;
        }

        if (filteredApps.length === 0 || selectedIndex < 0 || selectedIndex >= filteredApps.length) return;

        var item = filteredApps[selectedIndex];
        if (!item || item.disabled) return;
        if (contextApp) {
            if (item.contextFavorite) {
                toggleFavorite(contextApp);
                return;
            }
            if (item.desktopAction) {
                item.desktopAction.execute();
                if (store) store.recordLaunch(contextApp.id);
                dismiss();
                return;
            }
            item = contextApp;
        }
        if (item.kind === "history") {
            selectMode("= " + item.expression);
            return;
        }
        if (calculatorMode || actionsMode || item.kind === "quick-action") {
            if (activationGuard.running) return;
            if (item.confirm && pendingConfirmation !== item.action) {
                pendingConfirmation = item.action;
                feedback = "Press Enter again to confirm " + item.name;
                return;
            }
            pendingConfirmation = "";
            activationGuard.restart();
            if (calculatorMode) copyResultRequested(item.copyValue, item.expression);
            else quickActionRequested(item.action, item.argument ?? 0);
            return;
        }

        if (item) {
            if (item.isCommand) {
                executeCommand(item.command);
            } else if (typeof item.execute === "function") {
                const context = LaunchCommand.launchContext(item,
                    Quickshell.env("TERMINAL"), Quickshell.env("HOME"));
                if (context) Quickshell.execDetached(context);
                else item.execute();
                if (store) store.recordLaunch(item.id);
                dismiss();
            }
        }
    }

    onFilteredAppsChanged: {
        selectedIndex = filteredApps.length === 0 ? -1 : Math.max(0, Math.min(selectedIndex, filteredApps.length - 1));
    }

    onSelectedIndexChanged: {
        pendingConfirmation = "";
        if (appList && selectedIndex >= 0 && selectedIndex < filteredApps.length) {
            appList.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    onVisibleChanged: {
        closeTimer.stop();
        closing = false;
        if (visible) {
            session++;
            activationGuard.stop();
            contextApp = null;
            browseAll = false;
            pendingConfirmation = "";
            searchText = "";
            feedback = "";
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
        Behavior on color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 110 } }

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
            readonly property int homeHeight: 610
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(12, Math.round((parent.height - homeHeight) / 2))
            width: Math.max(0, Math.min(700, parent.width - 24))
            height: Math.max(0, Math.min(
                launcherWindow.homeMode ? homeHeight : launcherWindow.commandMode ? 258
                : launcherWindow.calculatorMode && calculator.expression.trim() ? 272
                : launcherWindow.appMode ? Math.min(540, 320 + Math.max(0, launcherWindow.filteredApps.length - 1) * 56) : 540,
                parent.height - 24))
            Behavior on height { NumberAnimation { duration: launcherWindow.reducedMotion ? 0 : 160; easing.type: Easing.OutCubic } }
            radius: 24
            color: Tokens.surface
            border.color: Qt.alpha(Tokens.outline, 0.7)
            border.width: 1
            clip: true

            enabled: !launcherWindow.closing
            scale: launcherWindow.visible && !launcherWindow.closing ? 1.0 : 0.98
            opacity: launcherWindow.visible && !launcherWindow.closing ? 1.0 : 0.0

            Behavior on scale {
                NumberAnimation { duration: launcherWindow.reducedMotion ? 0 : launcherWindow.closing ? 110 : 150; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: launcherWindow.reducedMotion ? 0 : launcherWindow.closing ? 100 : 130; easing.type: Easing.OutQuad }
            }

            TapHandler {
                // Prevent tap from bubbling to scrim
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: launcherCard.width < 440 ? 12 : 20
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: launcherWindow.contextApp ? launcherWindow.contextApp.name
                            : launcherWindow.calculatorMode ? "Calculator"
                            : launcherWindow.actionsMode ? "Quick Actions"
                            : launcherWindow.commandMode ? "Terminal Command" : "Applications"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Button {
                        visible: launcherWindow.homeMode
                        focusPolicy: Qt.NoFocus
                        text: "All apps"
                        Accessible.name: text
                        implicitHeight: 30
                        leftPadding: 11
                        rightPadding: 11
                        background: Rectangle {
                            radius: 9
                            color: parent.hovered ? Tokens.surface_high : "transparent"
                            border.color: Qt.alpha(Tokens.outline, 0.65)
                        }
                        contentItem: Text {
                            text: parent.text
                            color: Tokens.text_primary
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            launcherWindow.browseAll = true;
                            searchInput.forceActiveFocus();
                        }
                    }
                    ToolButton {
                        visible: !launcherWindow.contextApp
                        focusPolicy: Qt.NoFocus
                        text: "⋯"
                        implicitWidth: 30
                        implicitHeight: 30
                        Accessible.name: "Launcher modes"
                        ToolTip.text: Accessible.name
                        ToolTip.visible: hovered
                        background: Rectangle {
                            radius: 9
                            color: parent.hovered ? Tokens.surface_high : "transparent"
                        }
                        onClicked: modeMenu.open()
                        Menu {
                            id: modeMenu
                            MenuItem { text: "Apps"; onTriggered: launcherWindow.selectMode("") }
                            MenuItem { text: "Quick Actions (:)"; onTriggered: launcherWindow.selectMode(":") }
                            MenuItem { text: "Calculator (=)"; onTriggered: launcherWindow.selectMode("=") }
                            MenuItem { text: "Terminal command (>)"; onTriggered: launcherWindow.selectMode(">") }
                        }
                    }
                    Text {
                        text: launcherWindow.feedback
                        textFormat: Text.PlainText
                        visible: text.length > 0
                        Layout.maximumWidth: launcherCard.width * 0.56
                        elide: Text.ElideRight
                        Accessible.name: text
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                }

                // Search Input Box
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 14
                    color: Tokens.surface_high
                    border.color: searchInput.activeFocus ? Qt.alpha(Tokens.accent, 0.74) : Qt.alpha(Tokens.outline, 0.5)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: launcherWindow.calculatorMode ? "=" : launcherWindow.actionsMode ? ":"
                                : launcherWindow.searchText.trim().startsWith(">") ? "󰞷" : "󰍉"
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
                            Accessible.name: "Launcher search"
                            selectByMouse: true
                            clip: true

                            Text {
                                anchors.fill: parent
                                visible: searchInput.text.length === 0
                                text: "Search applications"
                                elide: Text.ElideRight
                                color: Tokens.text_secondary
                                font: searchInput.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            onTextChanged: {
                                launcherWindow.pendingConfirmation = "";
                                if (launcherWindow.contextApp) launcherWindow.closeContext();
                                launcherWindow.feedback = "";
                                launcherWindow.searchText = text;
                                launcherWindow.selectedIndex = launcherWindow.filteredApps.length > 0 ? 0 : -1;
                                if (appList) appList.positionViewAtBeginning();
                            }

                            Keys.onEscapePressed: (event) => {
                                if (launcherWindow.contextApp) launcherWindow.closeContext();
                                else launcherWindow.dismiss();
                                event.accepted = true;
                            }

                            Keys.onReturnPressed: (event) => launcherWindow.accept(event)
                            Keys.onEnterPressed: (event) => launcherWindow.accept(event)

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
                                if (launcherWindow.appMode)
                                    launcherWindow.cycleCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                                event.accepted = true;
                            }

                            Keys.onBacktabPressed: (event) => {
                                if (launcherWindow.appMode)
                                    launcherWindow.cycleCategory(-1);
                                event.accepted = true;
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier) && launcherWindow.appMode) {
                                    if (!event.isAutoRepeat) launcherWindow.toggleFavorite(
                                        launcherWindow.filteredApps[launcherWindow.selectedIndex]);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.AltModifier) && launcherWindow.homeMode) {
                                    launcherWindow.browseAll = true;
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
                    visible: launcherWindow.appMode
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

                        Behavior on color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 150 } }
                        Behavior on border.color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 150 } }

                        RowLayout {
                            id: pillContent
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: launcherWindow.getCategoryIcon(catPill.modelData)
                                font.pixelSize: 13
                                color: catPill.isSelected ? Tokens.accent : (pillHover.hovered ? Tokens.text_primary : Tokens.text_secondary)
                                Behavior on color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 150 } }
                            }

                            Text {
                                text: catPill.modelData
                                font.pixelSize: 11
                                font.bold: catPill.isSelected
                                color: catPill.isSelected ? Tokens.accent : (pillHover.hovered ? Tokens.text_primary : Tokens.text_secondary)
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 150 } }
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

                RowLayout {
                    visible: launcherWindow.appMode
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6

                    Text {
                        Layout.fillWidth: true
                        text: launcherWindow.homeMode ? "Suggestions" : "Results"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        visible: !launcherWindow.homeMode
                        text: launcherWindow.filteredApps.length
                        font.pixelSize: 12
                        color: Tokens.text_secondary
                    }
                }

                // Application List View
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Qt.tint(Tokens.surface, Qt.alpha(Tokens.background, 0.45))
                    border.color: Qt.alpha(Tokens.outline, 0.45)
                    border.width: 1
                    clip: true

                    ListView {
                        id: appList
                        anchors.fill: parent
                        anchors.margins: 6
                        model: launcherWindow.filteredApps
                        reuseItems: true
                        cacheBuffer: 120
                        spacing: 4
                        currentIndex: launcherWindow.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: appDelegate
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: launcherWindow.selectedIndex === appDelegate.index
                            readonly property bool isCommand: appDelegate.modelData && appDelegate.modelData.isCommand === true

                            readonly property string kind: modelData.kind ?? "application"
                            readonly property bool isQuick: kind === "quick-action" || kind === "history"
                                || kind === "calculation" || kind === "message"
                            readonly property bool favorite: launcherWindow.appMode && launcherWindow.isFavorite(modelData)
                            readonly property bool recent: launcherWindow.appMode && !favorite && !launcherWindow.searchText.trim()
                                && (launcherWindow.store?.recents.slice(0, 8).includes(modelData.id) ?? false)

                            width: appList.width
                            height: launcherWindow.homeMode ? 46
                                : launcherWindow.calculatorMode && calculator.expression.trim() ? 66 : 52
                            radius: 12
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.name
                            Accessible.description: modelData.comment || ""
                            Accessible.selected: isSelected
                            Accessible.onPressAction: {
                                launcherWindow.selectedIndex = index;
                                launcherWindow.launchSelected();
                            }

                            color: isSelected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.12)
                                : (appHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.5) : "transparent")
                            border.color: isSelected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.26)
                                : (appHover.hovered ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25) : "transparent")
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 120 } }
                            Behavior on border.color { ColorAnimation { duration: launcherWindow.reducedMotion ? 0 : 120 } }

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
                                        visible: appDelegate.isCommand || appDelegate.isQuick
                                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                                        border.color: Tokens.accent
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: appDelegate.modelData.glyph || (launcherWindow.calculatorMode ? "=" : appDelegate.isCommand ? "󰞷" : "›")
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
                                        visible: !appDelegate.isQuick && !appDelegate.isCommand && appIcon.status !== Image.Ready
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
                                        textFormat: Text.PlainText
                                        font.pixelSize: launcherWindow.calculatorMode ? 21 : 14
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
                                        textFormat: Text.PlainText
                                        font.pixelSize: 11
                                        color: Tokens.text_secondary
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }

                                Text {
                                    visible: appDelegate.favorite || (appDelegate.recent && launcherCard.width >= 440)
                                    text: appDelegate.favorite ? "★" : "Recent"
                                    font.pixelSize: 11
                                    color: appDelegate.favorite ? Tokens.accent : Tokens.text_secondary
                                    Accessible.name: appDelegate.favorite ? "Favorite" : "Recent"
                                }

                                // The selected row states the Enter action.
                                Rectangle {
                                    visible: launcherCard.width >= 420 && !appDelegate.modelData.disabled
                                        && (appDelegate.isCommand || appDelegate.isSelected)
                                        Layout.preferredHeight: 23
                                    radius: 10
                                    color: Tokens.accent
                                    implicitWidth: cmdBadgeRow.implicitWidth + 12

                                    RowLayout {
                                        id: cmdBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: appDelegate.kind === "history" ? "↵ Reuse" : launcherWindow.calculatorMode ? "↵ Copy"
                                                : appDelegate.isCommand || launcherWindow.actionsMode ? "↵ Run" : "↵ Open"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Tokens.on_accent
                                        }
                                    }
                                }
                            }

                            HoverHandler {
                                id: appHover
                                cursorShape: appDelegate.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                            }

                            TapHandler {
                                enabled: !appDelegate.modelData.disabled
                                onTapped: {
                                    launcherWindow.selectedIndex = appDelegate.index;
                                    launcherWindow.launchSelected();
                                }
                            }
                            TapHandler {
                                enabled: launcherWindow.appMode
                                acceptedButtons: Qt.RightButton
                                onTapped: {
                                    launcherWindow.selectedIndex = appDelegate.index;
                                    launcherWindow.openContext(appDelegate.modelData);
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
                            width: Math.max(0, parent.width - 24)
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "󰍉"
                                font.pixelSize: 32
                                color: Tokens.text_secondary
                                opacity: 0.6
                            }

                            Text {
                                Layout.fillWidth: true
                                text: launcherWindow.actionsMode ? "No matching actions" : "No applications found"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: launcherWindow.actionsMode ? "Try DND, volume, brightness, System, Power or reload."
                                    : launcherWindow.selectedCategory !== "All"
                                    ? ("No apps match in '" + launcherWindow.selectedCategory + "'. Press Tab to cycle categories.")
                                    : "Check the name or try a different keyword."
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                font.pixelSize: 11
                                color: Tokens.text_secondary
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: [
                            { keys: "↑↓", label: "Navigate", show: launcherWindow.appMode && launcherCard.width >= 420 },
                            { keys: "Tab", label: "Category", show: launcherWindow.appMode },
                            { keys: "Alt+↵", label: "App actions", show: launcherWindow.appMode && launcherCard.width >= 540 },
                            { keys: "Ctrl+P", label: "Favorite", show: launcherWindow.appMode && launcherCard.width >= 540 },
                            { keys: "↵", label: launcherWindow.calculatorMode
                                ? (calculator.expression.trim() ? "Copy result" : "Reuse expression")
                                : launcherWindow.actionsMode ? "Run action" : "Open", show: !launcherWindow.appMode },
                            { keys: "Esc", label: launcherWindow.contextApp ? "Back" : "Close", show: true }
                        ]
                        delegate: Item {
                            id: shortcut
                            required property var modelData
                            Layout.fillWidth: modelData.keys === "Esc"
                            implicitWidth: hint.implicitWidth
                            implicitHeight: hint.implicitHeight
                            visible: modelData.show

                            Row {
                                id: hint
                                anchors.right: parent.right
                                spacing: 5

                                Rectangle {
                                    width: keyLabel.implicitWidth + 10
                                    height: 21
                                    radius: 5
                                    color: Tokens.surface_high
                                    Text {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: shortcut.modelData.keys
                                        color: Tokens.text_primary
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: shortcut.modelData.label
                                    color: Tokens.text_secondary
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
