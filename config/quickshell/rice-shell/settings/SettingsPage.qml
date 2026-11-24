pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as FileDialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import "../dashboard" as DashboardUi
import "../services"
import "../theme"
import "Registry.js" as Registry

ColumnLayout {
    id: root
    required property var page
    property string detailRoute: ""
    property var launcherState: null
    property ShellPresentation shellPresentation: null
    property SettingsPreferences preferences: null
    property WindowLayoutStore layoutState: null
    readonly property bool compact: !!preferences?.compactRows
    property bool windowActive: false
    readonly property alias heading: heading
    readonly property bool loaded: sections.status === Loader.Ready
    readonly property bool failed: sections.status === Loader.Error
    readonly property string configHome: ThemeCommandQueue.configHome

    property string draftMode: ""
    property string expectedMode: ""
    property int themeRequest: 0
    property string themeMessage: ""

    signal ready()
    signal openWallpaper()
    signal requestRoute(string route)

    spacing: compact ? 14 : 20
    readonly property color card: Qt.tint(Tokens.surface, Qt.alpha(Tokens.surface_high, 0.53))
    readonly property color rule: Qt.tint(card, Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.58))
    readonly property color softAccent: Qt.tint(card, Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16))

    function findItem(name: string): Item {
        function find(item) {
            if (item.objectName === name && item.visible && item.enabled) return item;
            for (const child of item.children) {
                const match = find(child);
                if (match) return match;
            }
            return null;
        }
        return sections.item ? find(sections.item) : null;
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 5
        spacing: 5
        Label {
            id: heading
            Layout.fillWidth: true
            text: root.page.label
            font.pixelSize: 29
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            Accessible.role: Accessible.Heading
            activeFocusOnTab: true
        }
        Label {
            Layout.fillWidth: true
            text: root.page.summary
            font.pixelSize: 14
            color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
            wrapMode: Text.Wrap
        }
    }

    Loader {
        id: sections
        Layout.fillWidth: true
        asynchronous: true
        sourceComponent: ({
            appearance: appearance, desktop: desktop, display: display, shell: shell, sound: sound,
            network: network, bluetooth: bluetooth, notifications: notifications, launcher: launcher,
            "power-input": power, keyboard: keyboardPage, maintenance: maintenance
        })[root.page.id]
        onLoaded: root.ready()
    }

    Connections {
        target: ThemeCommandQueue
        function onThemeModeFinished(requestId: int, outcome: string, actualMode: string): void {
            if (requestId !== root.themeRequest) return;
            root.themeRequest = 0;
            root.themeMessage = ({
                applied: qsTr("Color mode applied."),
                conflict: qsTr("Color mode changed elsewhere. Review your choice before applying."),
                failed: qsTr("Theme generator failed. Current colors were retained where possible."),
                unconfirmed: qsTr("Theme generator finished. The new palette could not be confirmed."),
                superseded: qsTr("A newer theme request replaced this one.")
            })[outcome];
            if (outcome === "applied") root.draftMode = "";
        }
    }

    Component {
        id: appearance
        ColumnLayout {
            spacing: root.compact ? 8 : 12
            ReadCommand {
                id: gtkIcons
                argv: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
                jsonResponse: false
            }
            FileView {
                id: picker
                path: root.configHome + "/quickshell/wallpaper-switcher/shell.qml"
                printErrors: false
            }
            FileView {
                id: generator
                path: ThemeCommandQueue.themeScript
                printErrors: false
            }
            ReadCommand { id: matugen; argv: ["matugen", "--version"]; jsonResponse: false }
            ReadCommand {
                id: wallpaper
                argv: ["readlink", "-e", root.configHome + "/hypr/current_wallpaper"]
                jsonResponse: false
                textLimit: 4096
            }
            Connections {
                target: Tokens
                function onParsedDataChanged(): void { wallpaper.refresh(); }
            }
            Label {
                text: qsTr("Personalization")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                id: wallpaperRow
                objectName: "wallpaper"
                stacked: true
                showHeading: false
                label: qsTr("Wallpaper")
                description: typeof wallpaper.value === "string" ? wallpaper.value.split("/").pop()
                    : picker.loaded ? qsTr("Choose a wallpaper for your desktop.") : qsTr("Wallpaper picker is unavailable.")

                detail: GridLayout {
                    id: wallpaperContent
                    columns: preview.visible && width >= 515 ? 2 : 1
                    columnSpacing: 18
                    rowSpacing: 10

                    Rectangle {
                        id: preview
                        visible: wallpaperImage.status === Image.Ready
                        Layout.fillWidth: true
                        Layout.maximumWidth: 260
                        Layout.preferredWidth: 260
                        Layout.preferredHeight: 124
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        color: Tokens.surface
                        clip: true

                        Image {
                            id: wallpaperImage
                            objectName: "wallpaper-preview"
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 560
                            source: typeof wallpaper.value === "string" && wallpaper.value.startsWith("/")
                                ? "file://" + encodeURI(wallpaper.value).replace(/#/g, "%23").replace(/\?/g, "%3F")
                                : ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 5

                        Label {
                            Layout.fillWidth: true
                            text: wallpaperRow.label
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            color: Registry.readable(Tokens.text_primary, root.card, 4.5)
                        }
                        Label {
                            Layout.fillWidth: true
                            text: wallpaperRow.description
                            wrapMode: Text.Wrap
                            color: Registry.readable(Tokens.text_secondary, root.card, 4.5)
                        }
                        SettingsActionButton {
                            Layout.topMargin: 5
                            objectName: "change-wallpaper"
                            text: qsTr("Change wallpaper")
                            iconName: "image"
                            primary: root.draftMode.length === 0
                            enabled: picker.loaded
                            onClicked: root.openWallpaper()
                        }
                    }
                }
            }
            SettingsGroup {
                surface: root.card
                rule: root.rule
                SettingRow {
                    objectName: "color-mode"
                    grouped: true
                    label: qsTr("Color mode")
                    description: !generator.loaded ? qsTr("Theme generator is unavailable.")
                        : matugen.error ? qsTr("Matugen is unavailable.")
                        : !Tokens.isValid ? qsTr("Adaptive palette unavailable")
                        : Tokens.mode === "dark" ? qsTr("Current mode: Dark") : qsTr("Current mode: Light")
                    detail: ColumnLayout {
                        spacing: 8
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 4

                            ButtonGroup { id: modes }
                            Repeater {
                                model: [{ id: "light", label: qsTr("Light"), icon: "sun" },
                                    { id: "dark", label: qsTr("Dark"), icon: "moon" }]
                                delegate: RadioButton {
                                    id: mode
                                    required property var modelData
                                    objectName: "color-mode-" + modelData.id
                                    text: modelData.label
                                    implicitHeight: 38
                                    leftPadding: 10
                                    rightPadding: 10
                                    hoverEnabled: true
                                    indicator: Item {}

                                    background: Rectangle {
                                        id: modeFill
                                        radius: 7
                                        color: mode.checked ? root.softAccent : mode.hovered ? Tokens.surface_high : Tokens.surface
                                        border.width: mode.visualFocus ? 2 : 1
                                        border.color: mode.visualFocus ? Registry.readable(Tokens.focus_ring, color, 3) : root.rule
                                    }
                                    contentItem: RowLayout {
                                        spacing: 6
                                        readonly property color ink: Registry.readable(mode.checked ? Tokens.accent : Tokens.text_primary,
                                            modeFill.color, 4.5)

                                        SettingsIcon {
                                            name: mode.modelData.icon
                                            color: parent.ink
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                        }
                                        Label {
                                            text: mode.text
                                            font.pixelSize: 14
                                            font.weight: mode.checked ? Font.DemiBold : Font.Medium
                                            color: parent.ink
                                        }
                                    }
                                    checked: (root.draftMode || Tokens.mode) === modelData.id
                                    ButtonGroup.group: modes
                                    enabled: root.themeRequest === 0
                                    onClicked: {
                                        if (!root.draftMode) root.expectedMode = Tokens.mode;
                                        root.draftMode = modelData.id === Tokens.mode ? "" : modelData.id;
                                        root.themeMessage = "";
                                    }
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            visible: root.draftMode.length > 0
                            implicitHeight: 30
                            radius: 6
                            color: root.draftMode === "dark" ? "#20212b" : "#e8e9f2"

                            Label {
                                anchors.centerIn: parent
                                text: root.draftMode === "dark" ? qsTr("Dark preview") : qsTr("Light preview")
                                color: root.draftMode === "dark" ? "#e8e9f2" : "#20212b"
                                font.pixelSize: 12
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            visible: text.length > 0
                            text: root.themeRequest ? qsTr("Applying color mode…")
                                : root.draftMode && root.expectedMode !== Tokens.mode
                                    ? qsTr("Color mode changed elsewhere. Review the current mode and confirm your choice.")
                                    : root.themeMessage
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            visible: root.draftMode.length > 0
                            SettingsActionButton {
                                primary: true
                                readonly property bool conflicting: root.expectedMode !== Tokens.mode
                                objectName: "apply-color-mode"
                                text: conflicting ? qsTr("Confirm current mode") : qsTr("Apply")
                                enabled: root.themeRequest === 0 && Tokens.isValid
                                    && generator.loaded && !!matugen.value
                                    && (conflicting || root.draftMode !== Tokens.mode)
                                onClicked: {
                                    if (conflicting) {
                                        root.expectedMode = Tokens.mode;
                                        root.themeMessage = "";
                                        if (root.draftMode === Tokens.mode) root.draftMode = "";
                                        return;
                                    }
                                    const request = ThemeCommandQueue.requestThemeMode(root.draftMode, root.expectedMode);
                                    root.themeRequest = request;
                                    if (!request) root.themeMessage = qsTr("Theme service is busy or the palette changed. Try again.");
                                }
                            }
                            SettingsActionButton {
                                objectName: "cancel-color-mode"
                                text: qsTr("Cancel")
                                enabled: root.themeRequest === 0
                                onClicked: {
                                    root.draftMode = "";
                                    root.themeMessage = "";
                                }
                            }
                        }
                    }
                }
                SettingRow {
                    objectName: "palette"
                    grouped: true
                    showDivider: true
                    label: qsTr("Adaptive palette")
                    description: Tokens.isValid ? qsTr("Adaptive colors from the current wallpaper.")
                        : qsTr("Using fallback colors until an adaptive palette is available.")
                    detail: RowLayout {
                        Repeater {
                            model: [
                                { color: Tokens.background, label: qsTr("Background") },
                                { color: root.card, label: qsTr("Surface") },
                                { color: Tokens.text_secondary, label: qsTr("Secondary text") },
                                { color: Tokens.accent, label: qsTr("Accent") }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 20
                                implicitHeight: 20
                                radius: 5
                                color: modelData.color
                                border.color: Tokens.outline
                                Accessible.name: modelData.label
                            }
                        }
                    }
                }
            }
            Label {
                text: qsTr("Interface & accessibility")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingsGroup {
                surface: root.card
                rule: root.rule
                Repeater {
                    model: [
                        { id: "reduce-motion", key: "reduceMotion", label: qsTr("Reduce motion"),
                            detail: qsTr("Skip page transitions and hover animations in Rice Settings.") },
                        { id: "compact-rows", key: "compactRows", label: qsTr("Compact layout"),
                            detail: qsTr("Use less space between settings and navigation items.") }
                    ]
                    delegate: SettingRow {
                        id: preferenceRow
                        required property var modelData
                        required property int index
                        grouped: true
                        showDivider: index > 0
                        objectName: modelData.id
                        label: modelData.label
                        description: modelData.detail
                        detail: SettingsToggle {
                            Accessible.name: preferenceRow.label
                            enabled: !!root.preferences?.writable
                            checked: root.preferences?.busy && root.preferences.draft?.[preferenceRow.modelData.key] !== undefined
                                ? root.preferences.draft[preferenceRow.modelData.key]
                                : root.preferences?.values?.[preferenceRow.modelData.key] === true
                            onToggled: root.preferences?.propose(preferenceRow.modelData.key, checked)
                        }
                    }
                }
                SettingRow {
                    objectName: "fonts"
                    grouped: true
                    showDivider: true
                    label: qsTr("Interface font")
                    description: qsTr("Font in use by Rice Settings.")
                    detail: Label { text: heading.font.family; wrapMode: Text.Wrap }
                }
                SettingRow {
                    objectName: "icons"
                    grouped: true
                    showDivider: true
                    label: qsTr("GTK icon theme")
                    description: qsTr("Current desktop application icon theme.")
                    detail: Label {
                        text: typeof gtkIcons.value === "string" ? gtkIcons.value.replace(/^'|'$/g, "")
                            : gtkIcons.error ? qsTr("Unavailable") : qsTr("Reading…")
                        wrapMode: Text.Wrap
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !!root.preferences?.issue || !!root.preferences?.draft
                Label {
                    Layout.fillWidth: true
                    text: root.preferences?.issue || qsTr("Saving preferences…")
                    wrapMode: Text.Wrap
                }
                SettingsActionButton {
                    visible: !!root.preferences?.draft
                    text: qsTr("Retry")
                    enabled: !!root.preferences?.writable
                    onClicked: root.preferences.retry()
                }
                SettingsActionButton {
                    visible: !!root.preferences?.draft
                    text: qsTr("Discard")
                    enabled: !root.preferences?.busy
                    onClicked: root.preferences.discard()
                }
            }
        }
    }

    Component {
        id: display
        ColumnLayout {
            spacing: 12
            Component.onCompleted: {
                Hyprland.refreshMonitors();
                DesktopControls.refreshBrightness(false);
            }
            ReadCommand { id: gammaTool; argv: ["gammastep", "-V"]; jsonResponse: false }

            Label {
                text: qsTr("Screen configuration")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "displays"
                stacked: true
                label: qsTr("Displays")
                description: Hyprland.monitors.values.length ? qsTr("Inspect each output and its supported modes.")
                    : qsTr("No outputs reported by Hyprland.")
                detail: DisplayInventory {
                    monitors: Hyprland.monitors.values.map(monitor => monitor.lastIpcObject)
                    onRefreshRequested: Hyprland.refreshMonitors()
                }
            }
            Label {
                text: qsTr("Brightness & color")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "brightness"
                label: qsTr("Brightness")
                description: DesktopControls.brightnessAvailable ? qsTr("Built-in display backlight")
                    : DesktopControls.brightnessError || qsTr("Checking for an adjustable backlight…")
                detail: ColumnLayout {
                    ValueControl {
                        id: brightness
                        Layout.fillWidth: true
                        controlName: qsTr("Brightness")
                        minimum: 5
                        available: DesktopControls.brightnessAvailable
                        busy: DesktopControls.brightnessPending
                        observed: Math.round(DesktopControls.confirmedBrightness * 100)
                        tolerance: 1
                        onCommit: amount => DesktopControls.setBrightness(amount / 100)
                        Connections {
                            target: DesktopControls
                            function onBrightnessRefreshed(): void {
                                if (brightness.pending >= 0)
                                    brightness.acknowledge(Math.abs(brightness.observed - brightness.pending) <= brightness.tolerance);
                            }
                            function onErrorOccurred(): void {
                                if (DesktopControls.brightnessError) brightness.acknowledge(false);
                            }
                        }
                    }
                    SettingsActionButton {
                        text: qsTr("Refresh brightness")
                        onClicked: DesktopControls.refreshBrightness(false)
                    }
                }
            }
            SettingRow {
                objectName: "night-light"
                label: qsTr("Night Light")
                description: DesktopControls.nightLightError || (gammaTool.error ? qsTr("Night Light service is unavailable.")
                    : qsTr("Use warmer display colors in this session."))
                detail: SettingsToggle {
                    Accessible.name: qsTr("Night Light")
                    enabled: !!gammaTool.value
                    checked: DesktopControls.nightLightRequested
                    onToggled: DesktopControls.toggleNightLight()
                }
            }
        }
    }

    Component {
        id: desktop
        ColumnLayout {
            spacing: 12
            FileView {
                id: sourceRules
                path: root.configHome + "/hypr/config/windowrules.lua"
                preload: false
                printErrors: false
            }

            Label {
                text: qsTr("Window layout")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "gaps"
                stacked: true
                label: qsTr("Window spacing")
                description: qsTr("Adjust tiled window gaps and borders in Hyprland.")
                detail: WindowLayoutSettings { store: root.layoutState }
            }
            SettingRow {
                objectName: "window-effects"
                stacked: true
                label: qsTr("Window effects")
                description: qsTr("Values currently reported by Hyprland.")
                detail: GridLayout {
                    columns: width >= 520 ? 4 : 2
                    columnSpacing: 12
                    rowSpacing: 8
                    Repeater {
                        model: [
                            ["rounding", qsTr("Corner radius")], ["blur", qsTr("Blur")],
                            ["shadows", qsTr("Shadows")], ["animation", qsTr("Animations")]
                        ]
                        delegate: ColumnLayout {
                            id: effect
                            required property var modelData
                            readonly property var backendValue: root.layoutState?.snapshot?.effects?.[modelData[0]]
                            Layout.fillWidth: true
                            spacing: 3
                            Label {
                                text: effect.modelData[1]
                                color: Registry.readable(Tokens.text_secondary, root.card, 4.5)
                                wrapMode: Text.Wrap
                            }
                            Label {
                                text: typeof effect.backendValue === "number" ? qsTr("%1 px").arg(effect.backendValue)
                                    : typeof effect.backendValue === "boolean" ? (effect.backendValue ? qsTr("On") : qsTr("Off"))
                                    : qsTr("Unavailable")
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
            Label {
                text: qsTr("Workspaces")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "workspaces"
                stacked: true
                label: qsTr("Workspaces")
                description: Hyprland.focusedWorkspace
                    ? qsTr("Workspace %1 is active").arg(Hyprland.focusedWorkspace.name)
                    : qsTr("No workspace is active.")
                detail: ColumnLayout {
                    spacing: 6
                    Repeater {
                        model: Array.from(Hyprland.workspaces.values).filter(workspace => workspace.id > 0)
                            .sort((a, b) => a.id - b.id)
                        delegate: RowLayout {
                            id: workspaceRow
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.minimumHeight: 44
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Workspace %1").arg(workspaceRow.modelData.name)
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("%1 · %n window(s)", "", workspaceRow.modelData.toplevels.values.length)
                                        .arg(workspaceRow.modelData.monitor?.name || qsTr("No display"))
                                    color: Registry.readable(Tokens.text_secondary, root.card, 4.5)
                                    wrapMode: Text.Wrap
                                }
                            }
                            SettingsActionButton {
                                text: workspaceRow.modelData.focused ? qsTr("Active") : qsTr("Switch")
                                enabled: !workspaceRow.modelData.focused
                                Accessible.name: qsTr("Switch to workspace %1").arg(workspaceRow.modelData.name)
                                onClicked: workspaceRow.modelData.activate()
                            }
                        }
                    }
                }
            }
            Label {
                text: qsTr("Advanced")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                id: rulesSection
                objectName: "window-rules"
                stacked: true
                label: qsTr("Window rules")
                description: qsTr("Inspect the active Hyprland configuration module.")
                property string rulesText: ""
                detail: ColumnLayout {
                    SettingsActionButton {
                        text: rulesSection.rulesText ? qsTr("Hide configuration") : qsTr("View configuration")
                        onClicked: {
                            if (rulesSection.rulesText) {
                                rulesSection.rulesText = "";
                                return;
                            }
                            rulesSection.rulesText = sourceRules.text().slice(0, 65536) || qsTr("Could not read the rule module.");
                        }
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 300
                        visible: rulesSection.rulesText.length > 0
                        clip: true
                        TextArea {
                            readOnly: true
                            selectByMouse: true
                            Accessible.name: qsTr("Window rules configuration")
                            textFormat: TextEdit.PlainText
                            text: rulesSection.rulesText
                            font.family: "monospace"
                            color: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)
                            wrapMode: TextEdit.WrapAnywhere
                            background: Rectangle { color: Tokens.surface; radius: 8 }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: shell
        ColumnLayout {
            spacing: 18

            Label { text: qsTr("Control Center"); font.pixelSize: 16; font.weight: Font.DemiBold; Accessible.role: Accessible.Heading }
            SettingRow {
                objectName: "control-center"
                label: qsTr("Opening tab")
                description: qsTr("Choose what opens when you click the Control Center shortcut.")
                detail: SettingsComboBox {
                    readonly property var tabs: ["Home", "Notifications", "System", "Power", "Config"]
                    Accessible.name: qsTr("Control Center opening tab")
                    model: [qsTr("Home"), qsTr("Alerts"), qsTr("System"), qsTr("Power"), qsTr("Config")]
                    enabled: !!root.shellPresentation
                    currentIndex: Math.max(0, tabs.indexOf(root.shellPresentation?.dashboardTab))
                    onActivated: index => root.shellPresentation.dashboardTab = tabs[index]
                }
            }

            Repeater {
                model: root.page.rows.slice(1)
                delegate: ColumnLayout {
                    id: shellSection
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Label { text: shellSection.modelData[1]; font.pixelSize: 16; font.weight: Font.DemiBold; Accessible.role: Accessible.Heading }
                    ShellPresentationSettings {
                        objectName: shellSection.modelData[0]
                        activeFocusOnTab: true
                        Layout.fillWidth: true
                        section: shellSection.modelData[0]
                        presentation: root.shellPresentation
                    }
                }
            }
        }
    }

    Component {
        id: notifications
        ColumnLayout {
            spacing: 18

            SettingRow {
                objectName: "do-not-disturb"
                label: qsTr("Do Not Disturb")
                description: qsTr("Pause notification popups.")
                detail: SettingsToggle {
                    Accessible.name: qsTr("Do Not Disturb")
                    checked: DesktopControls.doNotDisturb
                    onToggled: DesktopControls.doNotDisturb = checked
                }
            }
        }
    }

    Component {
        id: launcher
        LauncherSettings {
            objectName: "launcher"
            activeFocusOnTab: true
            store: root.launcherState
        }
    }

    Component {
        id: sound
        ColumnLayout {
            spacing: 10

            Label { text: qsTr("Output"); font.pixelSize: 16; font.weight: Font.DemiBold; Accessible.role: Accessible.Heading }

            SettingsGroup {
                surface: root.card
                rule: root.rule
                SettingRow {
                    objectName: "output-volume"
                    grouped: true
                    label: qsTr("Output volume")
                    description: Audio.available ? (Audio.error || qsTr("Above 100% amplifies the signal and may distort sound."))
                        : qsTr("No audio output is available.")
                    detail: ValueControl {
                        controlName: qsTr("Output volume")
                        maximum: 150
                        available: Audio.available
                        busy: Audio.changeBusy
                        identity: Audio.sink
                        observed: Math.round(Audio.volume * 100)
                        onCommit: amount => Audio.requestOutputVolume(amount / 100)
                    }
                }
                SettingRow {
                    objectName: "output-mute"
                    grouped: true
                    showDivider: true
                    label: qsTr("Output mute")
                    description: Audio.available ? (Audio.error || (Audio.changeBusy ? qsTr("Waiting for the audio service…")
                        : Audio.muted ? qsTr("Output is muted.") : qsTr("Output is audible.")))
                        : qsTr("No audio output is available.")
                    detail: SettingsActionButton {
                        text: Audio.muted ? qsTr("Unmute output") : qsTr("Mute output")
                        enabled: Audio.available && !Audio.changeBusy
                        onClicked: Audio.requestOutputMute()
                    }
                }
                SettingRow {
                    objectName: "output-device"
                    grouped: true
                    showDivider: true
                    label: qsTr("Output device")
                    description: Audio.error || (Audio.pendingDevice ? qsTr("Waiting for the device to become default…")
                        : Audio.available ? (Audio.sink.description || Audio.sink.name) : qsTr("No audio output is available."))
                    detail: DeviceChooser { output: true }
                }
            }
            Label {
                font.pixelSize: 16
                font.weight: Font.DemiBold
                Accessible.role: Accessible.Heading
                Layout.topMargin: 10
                text: qsTr("Input")
            }
            SettingRow {
                objectName: "microphone"
                stacked: true
                label: qsTr("Microphone")
                description: Audio.error || (Audio.micAvailable ? (Audio.source.description || Audio.source.name)
                    : qsTr("No microphone is available."))
                detail: ColumnLayout {
                    ValueControl {
                        Layout.fillWidth: true
                        controlName: qsTr("Microphone volume")
                        available: Audio.micAvailable
                        busy: Audio.micBusy
                        identity: Audio.source
                        observed: Math.round(Audio.micVolume * 100)
                        onCommit: amount => Audio.setMicVolume(amount / 100)
                    }
                    SettingsActionButton {
                        text: Audio.micMuted ? qsTr("Unmute microphone") : qsTr("Mute microphone")
                        enabled: Audio.micAvailable && !Audio.micBusy
                        onClicked: Audio.toggleMicMute()
                    }
                    DeviceChooser { output: false; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                }
            }
        }
    }

    Component {
        id: network
        ColumnLayout {
            id: networkPage
            spacing: 16
            readonly property bool showingHotspot: root.detailRoute === "hotspot"

            RowLayout {
                Layout.fillWidth: true
                spacing: 18
                Repeater {
                    model: root.page.rows
                    delegate: TabButton {
                        id: networkTab
                        required property var modelData
                        objectName: modelData[0]
                        text: modelData[1]
                        checkable: false
                        checked: (modelData[0] === "hotspot") === networkPage.showingHotspot
                        implicitWidth: Math.max(76, contentItem.implicitWidth + 24)
                        implicitHeight: 39
                        onClicked: root.requestRoute("network#" + modelData[0])

                        contentItem: Label {
                            text: networkTab.text
                            font.pixelSize: 14
                            font.weight: networkTab.checked ? Font.DemiBold : Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Registry.readable(networkTab.checked ? Tokens.accent : Tokens.text_secondary,
                                Tokens.background, 4.5)
                        }
                        background: Rectangle {
                            radius: 6
                            color: networkTab.hovered ? Tokens.surface_low : "transparent"
                            border.color: Tokens.focus_ring
                            border.width: networkTab.visualFocus ? 2 : 0
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                radius: 1
                                visible: networkTab.checked
                                color: Tokens.accent
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Loader {
                Layout.fillWidth: true
                objectName: "settings-network-manager"
                sourceComponent: networkPage.showingHotspot ? hotspotSettings : wifiSettings
            }
        }
    }

    Component {
        id: wifiSettings
        DashboardUi.WifiDrawer {
            settingsPage: true
            drawerOpen: root.windowActive
            onHotspotPageRequested: root.requestRoute("network#hotspot")
        }
    }

    Component {
        id: hotspotSettings
        DashboardUi.HotspotDrawer { settingsPage: true }
    }

    Component {
        id: bluetooth
        DashboardUi.BluetoothDrawer {
            objectName: "bluetooth"
            settingsPage: true
        }
    }

    Component {
        id: power
        ColumnLayout {
            id: powerPage
            spacing: 12
            readonly property var battery: UPower.displayDevice
            readonly property bool hasBattery: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
            readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
            readonly property int charge: hasBattery ? Math.round(battery.percentage * 100) : 0
            property int pendingProfile: -1
            property string profileError: ""
            readonly property var modes: [
                { profile: PowerProfile.PowerSaver, text: qsTr("Power Saver") },
                { profile: PowerProfile.Balanced, text: qsTr("Balanced") },
                { profile: PowerProfile.Performance, text: qsTr("Performance") }
            ].filter(entry => entry.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

            Connections {
                target: PowerProfiles
                function onProfileChanged(): void {
                    if (powerPage.pendingProfile !== PowerProfiles.profile) return;
                    powerPage.pendingProfile = -1;
                    profileTimeout.stop();
                }
            }
            Timer {
                id: profileTimeout
                interval: 5000
                onTriggered: {
                    powerPage.pendingProfile = -1;
                    powerPage.profileError = qsTr("Could not confirm the power mode.");
                }
            }
            ReadCommand { id: profiles; argv: ["powerprofilesctl", "get"]; jsonResponse: false }
            ReadCommand { id: inhibit; argv: ["systemd-inhibit", "--version"]; jsonResponse: false }
            Label {
                text: qsTr("Battery & performance")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "battery"
                label: qsTr("Battery")
                description: !powerPage.hasBattery ? qsTr("No battery detected.")
                    : powerPage.charging ? qsTr("Charging")
                    : UPower.onBattery ? qsTr("On battery") : qsTr("Plugged in")
                detail: RowLayout {
                    visible: powerPage.hasBattery
                    ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: powerPage.charge }
                    Label { text: qsTr("%1%").arg(powerPage.charge); font.weight: Font.DemiBold }
                }
            }
            SettingRow {
                objectName: "power-profile"
                label: qsTr("Power mode")
                description: powerPage.profileError || (profiles.error ? qsTr("Power profile service is unavailable.")
                    : powerPage.pendingProfile >= 0 ? qsTr("Changing power mode…") : qsTr("Balance responsiveness and battery life."))
                detail: SettingsComboBox {
                    Accessible.name: qsTr("Power mode")
                    model: powerPage.modes
                    textRole: "text"
                    valueRole: "profile"
                    currentIndex: indexOfValue(PowerProfiles.profile)
                    displayText: powerPage.modes.find(entry => entry.profile === PowerProfiles.profile)?.text || ""
                    enabled: !!profiles.value && powerPage.pendingProfile < 0
                    onActivated: {
                        if (currentValue === PowerProfiles.profile) return;
                        powerPage.profileError = "";
                        powerPage.pendingProfile = currentValue;
                        profileTimeout.restart();
                        PowerProfiles.profile = currentValue;
                    }
                }
            }
            Label {
                text: qsTr("Sleep & lock")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "awake"
                label: qsTr("Keep awake")
                description: DesktopControls.caffeineError || (inhibit.error ? qsTr("Idle inhibition is unavailable.")
                    : qsTr("Temporarily prevent idle sleep."))
                detail: SettingsToggle {
                    Accessible.name: qsTr("Keep awake")
                    enabled: !!inhibit.value
                    checked: DesktopControls.caffeineRequested
                    onToggled: DesktopControls.toggleCaffeine()
                }
            }
            SettingRow {
                objectName: "lock-idle"
                stacked: true
                label: qsTr("Lock and idle")
                description: qsTr("Inspect the active configuration files.")
                detail: RowLayout {
                    Repeater {
                        model: [{ label: qsTr("Lock configuration"), file: "hyprlock.conf" },
                            { label: qsTr("Idle configuration"), file: "hypridle.conf" }]
                        delegate: SettingsActionButton {
                            id: configButton
                            required property var modelData
                            text: modelData.label
                            enabled: sourceFile.loaded
                            FileView {
                                id: sourceFile
                                path: root.configHome + "/hypr/" + configButton.modelData.file
                                printErrors: false
                            }
                            onClicked: Quickshell.execDetached(["xdg-open", sourceFile.path])
                        }
                    }
                }
            }
        }
    }

    Component {
        id: keyboardPage
        ColumnLayout {
            spacing: 12

            ReadCommand { id: input; argv: ["hyprctl", "-j", "devices"] }
            ReadCommand {
                id: binds
                argv: ["hyprctl", "-j", "binds"]
            }

            SettingRow {
                objectName: "keyboard-layout"
                stacked: true
                label: qsTr("Keyboards")
                description: input.error || (input.running ? qsTr("Reading keyboard devices…")
                    : qsTr("Active layout for each detected keyboard."))
                detail: ColumnLayout {
                    id: keyboards
                    readonly property var devices: Array.isArray(input.value?.keyboards)
                        ? Array.from(input.value.keyboards).filter(item => typeof item?.name === "string")
                            .sort((a, b) => Number(!!b.main) - Number(!!a.main)) : []
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: keyboardFilter
                            Layout.fillWidth: true
                            placeholderText: qsTr("Filter by name or layout")
                            Accessible.name: placeholderText
                        }
                        SettingsActionButton {
                            text: qsTr("Refresh")
                            enabled: !input.running
                            onClicked: input.refresh()
                        }
                    }
                    ListView {
                        id: keyboardList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(count, 5) * 55
                        visible: count > 0
                        clip: true
                        model: keyboards.devices.filter(item => Registry.normalize(item.name + " " + (item.active_keymap || ""))
                            .includes(Registry.normalize(keyboardFilter.text)))
                        ScrollBar.vertical: ScrollBar {}
                        delegate: RowLayout {
                            id: keyboard
                            required property var modelData
                            width: ListView.view.width - 10
                            height: 55
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: keyboard.modelData.name
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: keyboard.modelData.active_keymap || keyboard.modelData.layout || qsTr("Unknown layout")
                                    elide: Text.ElideRight
                                    color: Registry.readable(Tokens.text_secondary, root.card, 4.5)
                                }
                            }
                            Label { visible: !!keyboard.modelData.main; text: qsTr("Primary") }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: keyboardList.count === 0 && !input.running && !input.error
                        text: keyboardFilter.text ? qsTr("No matching keyboards.") : qsTr("No keyboard devices reported.")
                        wrapMode: Text.Wrap
                    }
                }
            }
            SettingRow {
                objectName: "shortcuts"
                stacked: true
                label: qsTr("Keyboard shortcuts")
                description: binds.error || (binds.running ? qsTr("Reading shortcut bindings…") : qsTr("Active compositor bindings"))
                detail: ColumnLayout {
                    TextField {
                        id: keyFilter
                        Layout.fillWidth: true
                        placeholderText: qsTr("Filter shortcuts")
                        Accessible.name: placeholderText
                    }
                    ListView {
                        id: shortcutList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(count, 7) * 38
                        visible: count > 0
                        clip: true
                        model: Array.isArray(binds.value) ? binds.value.map(binding => {
                            if (!binding || !Number.isInteger(binding.modmask) || typeof binding.dispatcher !== "string")
                                return null;
                            const keys = ["Shift", "Caps Lock", "Ctrl", "Alt", "Mod2", "Mod3", "Super", "Mod5"]
                                .filter((_, i) => binding.modmask & (1 << i));
                            const key = typeof binding.key === "string" && binding.key ? binding.key
                                : Number.isInteger(binding.keycode) && binding.keycode > 0 ? "code:" + binding.keycode : "";
                            if (!key) return null;
                            const title = typeof binding.description === "string" && binding.description
                                ? binding.description.slice(0, 160) : binding.dispatcher.slice(0, 100);
                            const combination = keys.concat(key).join("+");
                            return Registry.normalize(combination + " " + title).includes(Registry.normalize(keyFilter.text))
                                ? { combination, title } : null;
                        }).filter(Boolean) : []
                        ScrollBar.vertical: ScrollBar {}
                        delegate: RowLayout {
                            id: shortcut
                            required property var modelData
                            width: ListView.view.width - 10
                            height: 38
                            Label {
                                Layout.fillWidth: true
                                text: shortcut.modelData.title
                                elide: Text.ElideRight
                            }
                            Label {
                                text: shortcut.modelData.combination
                                font.family: "Iosevka Nerd Font Mono"
                                leftPadding: 8
                                rightPadding: 8
                                topPadding: 4
                                bottomPadding: 4
                                color: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)
                                background: Rectangle { color: Tokens.surface; radius: 6; border.color: root.rule }
                            }
                        }
                    }
                    Label {
                        visible: shortcutList.count === 0 && !binds.error && !binds.running
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: keyFilter.text ? qsTr("No matching shortcuts.") : qsTr("No compositor shortcuts reported.")
                    }
                }
            }
        }
    }

    Component {
        id: maintenance
        ColumnLayout {
            id: maintenancePage
            spacing: 12
            property string copyStatus: ""
            readonly property var actions: [
                { id: "regenerate-theme", label: qsTr("Regenerate adaptive palette"),
                    summary: qsTr("Rebuild colors from the current wallpaper and color mode.") },
                { id: "reload-compositor", label: qsTr("Reload Hyprland"),
                    summary: qsTr("Re-read the current compositor configuration.") },
                { id: "reload-shell", label: qsTr("Reload Rice Shell"),
                    summary: qsTr("Reload the shell after queued theme operations finish.") }
            ]
            function copyDiagnostics(): void {
                const details = [
                    runtime.value || qsTr("Quickshell version unavailable"),
                    typeof compositor.value?.version === "string" ? "Hyprland " + compositor.value.version.slice(0, 64)
                        : qsTr("Hyprland version unavailable"),
                    qsTr("Outputs: %1").arg(Hyprland.monitors.values.length),
                    Audio.ready ? qsTr("Audio connected") : qsTr("Audio unavailable"),
                    Tokens.isValid ? qsTr("Adaptive palette valid") : qsTr("Adaptive palette unavailable"),
                    DesktopControls.brightnessAvailable ? qsTr("Backlight available") : qsTr("Backlight unconfirmed")
                ];
                clipboard.command = ["wl-copy", "--", details.join("\n")];
                clipboard.running = true;
            }
            Process {
                id: clipboard
                onExited: code => maintenancePage.copyStatus = code === 0 ? qsTr("Diagnostics copied.")
                    : qsTr("Clipboard is unavailable.")
            }
            ReadCommand { id: compositor; argv: ["hyprctl", "-j", "version"] }
            ReadCommand { id: runtime; argv: ["quickshell", "--version"]; jsonResponse: false }
            FileView { id: maintenanceGenerator; path: ThemeCommandQueue.themeScript; printErrors: false }
            property FileDialogs.FileDialog importFile: FileDialogs.FileDialog {
                id: importPreferences
                title: qsTr("Choose a Rice Settings preferences file")
                nameFilters: [qsTr("JSON files (*.json)")]
                onAccepted: root.preferences?.inspect(selectedFile.toString())
            }
            property FileDialogs.FileDialog exportFile: FileDialogs.FileDialog {
                id: exportPreferences
                title: qsTr("Save a preferences copy")
                fileMode: FileDialogs.FileDialog.SaveFile
                defaultSuffix: "json"
                nameFilters: [qsTr("JSON files (*.json)")]
                options: FileDialogs.FileDialog.DontConfirmOverwrite
                onAccepted: root.preferences?.exportCopy(selectedFile.toString())
            }
            property SettingsDialog importReview: SettingsDialog {
                id: reviewPreferences
                bodyHeight: 145
                title: qsTr("Review imported preferences")
                standardButtons: Dialog.Apply | Dialog.Cancel
                contentItem: ColumnLayout {
                    objectName: "settings-import-review"
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("These changes apply inside Rice Settings only.")
                        wrapMode: Text.Wrap
                    }
                    Repeater {
                        model: [
                            { key: "reduceMotion", name: qsTr("Reduce motion") },
                            { key: "compactRows", name: qsTr("Compact layout") }
                        ]
                        delegate: Label {
                            required property var modelData
                            readonly property bool current: root.preferences?.values?.[modelData.key] === true
                            readonly property bool imported: root.preferences?.importPreview?.values?.[modelData.key] === true
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: current === imported ? qsTr("%1 stays %2").arg(modelData.name)
                                .arg(current ? qsTr("on") : qsTr("off"))
                                : qsTr("%1 changes from %2 to %3").arg(modelData.name)
                                    .arg(current ? qsTr("on") : qsTr("off")).arg(imported ? qsTr("on") : qsTr("off"))
                        }
                    }
                }
                onApplied: {
                    root.preferences?.confirmImport();
                    close();
                }
                onRejected: if (root.preferences) root.preferences.importPreview = null
            }
            Connections {
                target: root.preferences
                function onImportPreviewChanged(): void {
                    if (root.preferences?.importPreview) reviewPreferences.open();
                    else if (reviewPreferences.visible) reviewPreferences.close();
                }
            }
            property SettingsDialog preferencesRecovery: SettingsDialog {
                id: recoverPreferences
                title: qsTr("Restore previous preferences?")
                standardButtons: Dialog.Ok | Dialog.Cancel
                contentItem: Label {
                    text: qsTr("This restores only Rice Settings layout and animation preferences.")
                    wrapMode: Text.Wrap
                }
                onAccepted: root.preferences?.restore()
            }
            property SettingsDialog confirmation: SettingsDialog {
                id: confirmOperation
                property var operation: null
                title: operation?.label || ""
                standardButtons: Dialog.Ok | Dialog.Cancel
                contentItem: Label {
                    text: confirmOperation.operation?.summary || ""
                    wrapMode: Text.Wrap
                }
                onAccepted: {
                    switch (operation?.id) {
                    case "regenerate-theme": ThemeCommandQueue.regenerateTheme(); break;
                    case "reload-compositor": ThemeCommandQueue.reloadHyprland(); break;
                    case "reload-shell": ThemeCommandQueue.requestShellReload(); break;
                    }
                }
            }
            Label {
                text: qsTr("System status")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "diagnostics"
                stacked: true
                label: qsTr("Diagnostics")
                description: qsTr("Rice Shell instance %1").arg(Quickshell.instanceId)
                detail: ColumnLayout {
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: runtime.value || runtime.error || qsTr("Reading Quickshell version…")
                    }
                    Label {
                        text: compositor.value && typeof compositor.value.version === "string"
                            ? qsTr("Hyprland %1").arg(compositor.value.version.slice(0, 64))
                            : compositor.error || qsTr("Reading compositor version…")
                    }
                    Label { text: Audio.ready ? qsTr("Audio service connected") : qsTr("Audio service unavailable") }
                    Label { text: Tokens.isValid ? qsTr("Adaptive palette valid") : qsTr("Adaptive palette unavailable") }
                    Label { text: DesktopControls.brightnessAvailable ? qsTr("Backlight available") : qsTr("No confirmed backlight") }
                    RowLayout {
                        SettingsActionButton {
                            text: qsTr("Copy diagnostics")
                            enabled: !clipboard.running
                            onClicked: maintenancePage.copyDiagnostics()
                        }
                        SettingsActionButton {
                            text: qsTr("Recheck")
                            enabled: !runtime.running && !compositor.running
                            onClicked: {
                                runtime.refresh();
                                compositor.refresh();
                                DesktopControls.refreshBrightness(false);
                                maintenancePage.copyStatus = "";
                            }
                        }
                    }
                    Label {
                        visible: text.length > 0
                        text: maintenancePage.copyStatus
                    }
                }
            }
            Label {
                text: qsTr("Preferences & backups")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            SettingRow {
                objectName: "settings-preferences"
                label: qsTr("Settings preferences")
                description: root.preferences?.issue || qsTr("Restore the previous saved layout and animation preferences.")
                detail: RowLayout {
                    SettingsActionButton {
                        text: qsTr("Re-read")
                        enabled: !!root.preferences && !root.preferences.busy
                        onClicked: root.preferences.refresh()
                    }
                    SettingsActionButton {
                        text: qsTr("Restore…")
                        enabled: !!root.preferences?.recoverable && !root.preferences.busy
                        onClicked: recoverPreferences.open()
                    }
                }
            }
            SettingRow {
                objectName: "preference-copies"
                stacked: true
                label: qsTr("Import and export preferences")
                description: qsTr("Save layout and animation options to JSON, or preview changes from a saved copy.")
                detail: RowLayout {
                    SettingsActionButton {
                        text: qsTr("Import…")
                        enabled: !!root.preferences?.writable
                        onClicked: importPreferences.open()
                    }
                    SettingsActionButton {
                        text: qsTr("Export…")
                        enabled: !!root.preferences?.writable
                        onClicked: exportPreferences.open()
                    }
                    SettingsActionButton {
                        visible: !!root.preferences?.importPreview
                        text: qsTr("Review")
                        onClicked: reviewPreferences.open()
                    }
                }
            }
            Label {
                text: qsTr("Maintenance actions")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Registry.readable(Tokens.text_secondary, Tokens.background, 4.5)
                Accessible.role: Accessible.Heading
            }
            Repeater {
                model: maintenancePage.actions
                delegate: SettingRow {
                    id: operationRow
                    required property var modelData
                    objectName: modelData.id
                    label: modelData.label
                    description: modelData.summary
                    detail: SettingsActionButton {
                        text: operationRow.label + qsTr("…")
                        Accessible.name: operationRow.label
                        enabled: modelData.id !== "regenerate-theme" || maintenanceGenerator.loaded
                        onClicked: {
                            confirmOperation.operation = operationRow.modelData;
                            confirmOperation.open();
                        }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: text.length > 0
                text: ThemeCommandQueue.running ? qsTr("Applying changes…") : ThemeCommandQueue.result
            }
        }
    }

    component SettingRow: FocusScope {
        id: row
        required property string label
        property string description
        property Item detail
        property bool stacked: false
        property bool showHeading: true
        property bool grouped: false
        property bool showDivider: false
        readonly property bool rowFocused: row.activeFocus && row.Window.window?.activeFocusItem === row
        readonly property bool sideBySide: !stacked && !!detail && width >= 470
        Layout.fillWidth: true
        implicitHeight: grouped
            ? Math.max(root.compact ? 46 : 55, body.implicitHeight + (root.compact ? 10 : 14))
            : Math.max(root.compact ? 58 : 68, body.implicitHeight + (root.compact ? 20 : 28))
        activeFocusOnTab: true
        Accessible.role: Accessible.Grouping
        Accessible.name: label
        Accessible.description: description

        Rectangle {
            anchors.fill: parent
            color: row.grouped ? "transparent" : root.card
            radius: 10
            visible: !row.grouped || row.rowFocused
            border.width: row.rowFocused ? 2 : 1
            border.color: row.rowFocused ? Registry.readable(Tokens.focus_ring, root.card, 3) : root.rule
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            height: 1
            visible: row.showDivider && !row.rowFocused
            color: root.rule
        }
        GridLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            columns: row.sideBySide ? 2 : 1
            rowSpacing: root.compact ? 8 : 12
            columnSpacing: 20
            ColumnLayout {
                visible: row.showHeading
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    text: row.label
                    wrapMode: Text.Wrap
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Registry.readable(Tokens.text_primary, root.card, 4.5)
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.description
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    color: Registry.readable(Tokens.text_secondary, root.card, 4.5)
                }
            }
            Item {
                visible: !!row.detail
                Layout.fillWidth: !row.sideBySide
                Layout.preferredWidth: row.sideBySide && row.detail
                    ? Math.min(body.width * 0.48, Math.max(100, row.detail.implicitWidth)) : -1
                implicitHeight: row.detail ? row.detail.implicitHeight : 0
                onWidthChanged: if (row.detail) row.detail.width = width
                Component.onCompleted: if (row.detail) {
                    row.detail.parent = this;
                    row.detail.width = width;
                }
            }
        }
    }

    component DeviceChooser: SettingsComboBox {
        id: chooser
        required property bool output
        objectName: output ? "output-device-picker" : "input-device-picker"
        readonly property var selected: output ? Audio.sink : Audio.source
        implicitWidth: 280
        enabled: count > 0 && !Audio.pendingDevice && !Audio.changeBusy
        model: Array.from(Audio.devices).filter(device => !!device.isSink === output)
            .map(device => ({ device: device, label: device.description || device.name }))
        textRole: "label"
        currentIndex: model.findIndex(entry => entry.device === selected)
        displayText: currentIndex < 0 ? qsTr("No default device")
            : model[currentIndex].label
        Accessible.name: output ? qsTr("Output device") : qsTr("Input device")
        onActivated: Audio.selectDevice(model[index].device)
    }

    component ValueControl: RowLayout {
        id: valueControl
        required property string controlName
        required property bool available
        required property int observed
        property var identity
        property bool busy: false
        property int minimum: 0
        property int maximum: 100
        property int tolerance: 0
        property int draft: -1
        property int pending: -1
        property string message: ""
        property var targetIdentity

        signal commit(int amount)

        function acknowledge(success: bool): void {
            if (pending < 0) return;
            pending = -1;
            timeout.stop();
            message = success ? "" : qsTr("Change could not be confirmed.");
        }

        function submit(): void {
            if (draft < 0) return;
            const amount = draft;
            draft = -1;
            if (!available || busy || targetIdentity !== identity) return;
            if (Math.abs(observed - amount) <= tolerance) return;
            pending = amount;
            message = "";
            timeout.restart();
            commit(amount);
        }

        function stage(amount: int): void {
            if (draft < 0) targetIdentity = identity;
            draft = Math.max(minimum, Math.min(maximum, amount));
        }

        onIdentityChanged: {
            draft = -1;
            acknowledge(false);
        }
        onObservedChanged: if (pending >= 0 && Math.abs(observed - pending) <= tolerance) acknowledge(true)

        Timer { id: keyboardCommit; interval: 180; onTriggered: valueControl.submit() }
        Timer { id: timeout; interval: 2500; onTriggered: valueControl.acknowledge(false) }

        SettingsSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            from: valueControl.minimum
            to: valueControl.maximum
            stepSize: 1
            enabled: valueControl.available && !valueControl.busy && valueControl.pending < 0
            value: valueControl.draft >= 0 ? valueControl.draft
                : valueControl.pending >= 0 ? valueControl.pending : valueControl.observed
            Accessible.name: valueControl.controlName
            onMoved: valueControl.stage(Math.round(value))
            Keys.onPressed: event => {
                const current = Math.round(value);
                let next;
                switch (event.key) {
                case Qt.Key_Up: next = current + 1; break;
                case Qt.Key_Down: next = current - 1; break;
                case Qt.Key_Left: next = current + (mirrored ? 1 : -1); break;
                case Qt.Key_Right: next = current + (mirrored ? -1 : 1); break;
                case Qt.Key_Home: next = valueControl.minimum; break;
                case Qt.Key_End: next = valueControl.maximum; break;
                default: return;
                }
                event.accepted = true;
                valueControl.stage(next);
                keyboardCommit.restart();
            }
            onPressedChanged: {
                if (pressed) keyboardCommit.stop();
                else valueControl.submit();
            }
        }
        Label {
            Layout.maximumWidth: 112
            elide: Text.ElideRight
            text: !valueControl.available ? qsTr("Unavailable")
                : valueControl.pending >= 0 ? qsTr("Applying…")
                : valueControl.message || qsTr("%1%").arg(valueControl.draft >= 0 ? valueControl.draft : valueControl.observed)
        }
    }

    component ReadCommand: Process {
        id: commandReader
        required property list<string> argv
        property bool jsonResponse: true
        property int textLimit: 150
        property var value: null
        property string error: ""
        property string buffer: ""
        command: argv
        running: true

        function refresh(): void {
            if (running) return;
            buffer = "";
            error = "";
            running = true;
        }

        property Timer deadline: Timer {
            running: commandReader.running
            interval: 1800
            onTriggered: {
                commandReader.error = qsTr("Request timed out.");
                commandReader.running = false;
            }
        }

        stdout: SplitParser {
            onRead: line => {
                if (commandReader.buffer.length + line.length > 262144) {
                    commandReader.error = qsTr("Response is too large.");
                    commandReader.running = false;
                } else {
                    commandReader.buffer += line + "\n";
                }
            }
        }
        onExited: code => {
            if (error) return;
            try {
                if (code !== 0) throw Error();
                const parsed = jsonResponse ? JSON.parse(buffer) : buffer.trim().slice(0, textLimit);
                if (!parsed || (jsonResponse && typeof parsed !== "object")) throw Error();
                value = parsed;
            } catch (exception) {
                error = qsTr("Diagnostic data is unavailable.");
            }
            buffer = "";
        }
        function reportMissing(): void {
            if (!running && !value && !error) error = qsTr("Diagnostic tool is unavailable.");
        }
        onRunningChanged: if (!running) Qt.callLater(commandReader.reportMissing)
    }
}
