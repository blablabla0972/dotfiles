pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../services"
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: compactLayout ? 700 : 370

    readonly property bool compactLayout: width < 700
    readonly property int layoutColumns: configGrid.columns
    property int selectedCategory: 0

    readonly property string themeCommandResult: ThemeCommandQueue.result
    readonly property bool themeCommandRunning: ThemeCommandQueue.running
    readonly property int pendingCommandCount: ThemeCommandQueue.pendingCount
    readonly property bool themeCommandBusy: themeCommandRunning || pendingCommandCount > 0
    readonly property bool themeCommandFailed: {
        var result = themeCommandResult.toLowerCase();
        return result.indexOf("failed") >= 0 || result.indexOf("invalid") >= 0;
    }
    readonly property bool shellReloadPending: ThemeCommandQueue.reloadPending
    readonly property bool themeStatusVisible: themeCommandResult.length > 0 || themeCommandBusy
    readonly property string themeStatusText: themeCommandRunning ? "Applying theme changes…"
        : (pendingCommandCount > 0 ? "Waiting for queued changes…" : themeCommandResult)

    function queueCommand(command: var): void {
        ThemeCommandQueue.queueCommand(command);
    }

    function switchTheme(mode: string): void {
        ThemeCommandQueue.switchTheme(mode);
    }

    function regenerateTheme(): void {
        ThemeCommandQueue.regenerateTheme();
    }

    function reloadShell(): void {
        ThemeCommandQueue.requestShellReload();
    }

    function reloadHyprland(): void {
        ThemeCommandQueue.reloadHyprland();
    }

    function runRuntimeAction(action: string): void {
        if (action === "shell") root.reloadShell();
        else if (action === "hyprland") root.reloadHyprland();
        else if (action === "tokens") Tokens.reloadTheme();
    }

    GridLayout {
        id: configGrid
        anchors.fill: parent
        anchors.margins: 10
        columns: root.compactLayout ? 1 : 2
        rowSpacing: root.compactLayout ? 8 : 0
        columnSpacing: root.compactLayout ? 0 : 12

        Rectangle {
            id: navigation
            Layout.fillWidth: root.compactLayout
            Layout.fillHeight: !root.compactLayout
            Layout.minimumWidth: root.compactLayout ? 0 : 170
            Layout.preferredWidth: root.compactLayout ? 0 : (root.width - 20) * 0.27
            Layout.preferredHeight: root.compactLayout ? 54 : 0
            radius: 16
            color: Qt.rgba(Tokens.surface_low.r, Tokens.surface_low.g, Tokens.surface_low.b, 0.82)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.compactLayout ? 7 : 12
                spacing: 8

                Text {
                    Layout.leftMargin: 4
                    visible: !root.compactLayout
                    text: "CONTROL CENTER"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1.2
                    color: Tokens.text_secondary
                }

                GridLayout {
                    id: categoryGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: !root.compactLayout
                    columns: root.compactLayout ? 2 : 1
                    rowSpacing: 6
                    columnSpacing: 6

                    Repeater {
                        model: [
                            { index: 0, title: "Appearance", subtitle: "Color and palette", icon: "󰔎" },
                            { index: 1, title: "Runtime", subtitle: "Shell and compositor", icon: "󰒓" }
                        ]

                        delegate: Rectangle {
                            id: categoryItem
                            required property var modelData
                            readonly property bool selected: root.selectedCategory === modelData.index

                            Layout.fillWidth: true
                            Layout.preferredHeight: root.compactLayout ? 38 : 58
                            radius: 11
                            color: selected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                                : (categoryHover.hovered
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.62)
                                    : "transparent")
                            border.color: selected
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.55)
                                : "transparent"
                            border.width: selected ? 1 : 0

                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 8

                                Text {
                                    text: categoryItem.modelData.icon
                                    font.pixelSize: 16
                                    color: categoryItem.selected ? Tokens.accent : Tokens.text_secondary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: categoryItem.modelData.title
                                        font.pixelSize: 11
                                        font.bold: categoryItem.selected
                                        color: Tokens.text_primary
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: !root.compactLayout
                                        text: categoryItem.modelData.subtitle
                                        font.pixelSize: 9
                                        color: Tokens.text_secondary
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    visible: categoryItem.selected
                                    text: "✓"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Tokens.accent
                                }
                            }

                            HoverHandler { id: categoryHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedCategory = categoryItem.modelData.index
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; visible: !root.compactLayout }
            }
        }

        Rectangle {
            id: settingsPanel
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            radius: 16
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.78)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 11
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)

                        Text {
                            anchors.centerIn: parent
                            text: root.selectedCategory === 0 ? "󰔎" : "󰒓"
                            font.pixelSize: 17
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.selectedCategory === 0 ? "Appearance" : "Runtime"
                            font.pixelSize: 14
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: root.selectedCategory === 0
                                ? "Color mode and wallpaper palette"
                                : "Reload the shell and compositor"
                            font.pixelSize: 9
                            color: Tokens.text_secondary
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    visible: root.themeStatusVisible
                    radius: 9
                    color: root.themeCommandFailed
                        ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.12)
                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.68)
                    border.color: root.themeCommandFailed
                        ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.36)
                        : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.36)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 7

                        Text {
                            text: root.themeCommandFailed ? "!" : (root.themeCommandBusy ? "◌" : "✓")
                            font.pixelSize: 12
                            font.bold: true
                            color: root.themeCommandFailed ? Tokens.danger
                                : (root.themeCommandBusy ? Tokens.accent : Tokens.text_secondary)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.themeStatusText
                            font.pixelSize: 9
                            color: root.themeCommandFailed ? Tokens.danger : Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }
                }

                Flickable {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    contentWidth: width
                    contentHeight: settingsContent.implicitHeight
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: settingsContent
                        width: settingsScroll.width
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.selectedCategory === 0
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "Color mode"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Tokens.text_primary
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            { mode: "dark", title: "Dark Mode", icon: "󰖔" },
                                            { mode: "light", title: "Light Mode", icon: "󰖨" }
                                        ]

                                        delegate: Rectangle {
                                            id: modeItem
                                            required property var modelData
                                            readonly property bool selected: Tokens.mode === modelData.mode

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 46
                                            radius: 10
                                            color: selected
                                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                                                : (modeHover.hovered
                                                    ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.88)
                                                    : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.58))
                                            border.color: selected ? Tokens.accent
                                                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                                            border.width: selected ? 1.2 : 1

                                            Behavior on color {
                                                ColorAnimation { duration: 140 }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 8

                                                Text {
                                                    text: modeItem.modelData.icon
                                                    font.pixelSize: 15
                                                    color: modeItem.selected ? Tokens.accent : Tokens.text_secondary
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modeItem.modelData.title
                                                    font.pixelSize: 10
                                                    font.bold: modeItem.selected
                                                    color: Tokens.text_primary
                                                }

                                                Text {
                                                    visible: modeItem.selected
                                                    text: "✓"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Tokens.accent
                                                }
                                            }

                                            HoverHandler {
                                                id: modeHover
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.switchTheme(modeItem.modelData.mode)
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.34)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "Adaptive palette"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Tokens.text_primary
                                        }

                                        Text {
                                            text: Tokens.isValid ? "Adaptive wallpaper palette active"
                                                : "Using fallback colors; adaptive palette unavailable"
                                            font.pixelSize: 9
                                            color: Tokens.isValid ? Tokens.text_secondary : Tokens.danger
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 104
                                        Layout.preferredHeight: 32
                                        radius: 9
                                        color: regenerateHover.hovered
                                            ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.22)
                                            : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.74)
                                        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: "󰏘"
                                                font.pixelSize: 13
                                                color: Tokens.accent
                                            }

                                            Text {
                                                text: root.themeCommandBusy ? "Queue" : "Regenerate"
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: Tokens.text_primary
                                            }
                                        }

                                        HoverHandler { id: regenerateHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.regenerateTheme()
                                        }
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: root.width < 540 ? 2 : 4
                                    rowSpacing: 6
                                    columnSpacing: 6

                                    Repeater {
                                        model: [
                                            { name: "Accent", color: Tokens.accent },
                                            { name: "Surface", color: Tokens.surface },
                                            { name: "Raised surface", color: Tokens.surface_high },
                                            { name: "Outline", color: Tokens.outline },
                                            { name: "Primary text", color: Tokens.text_primary },
                                            { name: "Secondary text", color: Tokens.text_secondary },
                                            { name: "Danger", color: Tokens.danger },
                                            { name: "On accent", color: Tokens.on_accent }
                                        ]

                                        delegate: Rectangle {
                                            id: swatchItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 29
                                            radius: 8
                                            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.46)
                                            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 7
                                                anchors.rightMargin: 5
                                                spacing: 6

                                                Rectangle {
                                                    Layout.preferredWidth: 16
                                                    Layout.preferredHeight: 16
                                                    radius: 5
                                                    color: swatchItem.modelData.color
                                                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.45)
                                                    border.width: 1
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: swatchItem.modelData.name
                                                    font.pixelSize: 8
                                                    color: Tokens.text_primary
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.selectedCategory === 1
                            spacing: 9

                            Text {
                                Layout.fillWidth: true
                                text: "Session actions"
                                font.pixelSize: 11
                                font.bold: true
                                color: Tokens.text_primary
                            }

                            Repeater {
                                model: [
                                    {
                                        id: "shell",
                                        icon: "󰑓",
                                        title: "Reload Rice Shell",
                                        description: "Reload the current shell configuration.",
                                        action: "Reload"
                                    },
                                    {
                                        id: "hyprland",
                                        icon: "󰒓",
                                        title: "Reload Hyprland",
                                        description: "Re-read compositor rules and keybinds.",
                                        action: "Reload"
                                    },
                                    {
                                        id: "tokens",
                                        icon: "󰚰",
                                        title: "Refresh Theme Tokens",
                                        description: "Read the current adaptive theme file.",
                                        action: "Refresh"
                                    }
                                ]

                                delegate: Rectangle {
                                    id: actionRow
                                    required property var modelData
                                    readonly property bool shellQueued:
                                        modelData.id === "shell" && root.shellReloadPending
                                    readonly property bool actionEnabled: !shellQueued

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 58
                                    radius: 10
                                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.56)
                                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.32)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 9
                                        spacing: 9

                                        Text {
                                            text: actionRow.modelData.icon
                                            font.pixelSize: 17
                                            color: Tokens.accent
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                Layout.fillWidth: true
                                                text: actionRow.modelData.title
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: Tokens.text_primary
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: actionRow.modelData.description
                                                font.pixelSize: 8
                                                color: Tokens.text_secondary
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 78
                                            Layout.preferredHeight: 31
                                            radius: 9
                                            color: actionRow.actionEnabled
                                                ? (actionHover.hovered
                                                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.24)
                                                    : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.13))
                                                : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                                            border.color: actionRow.actionEnabled
                                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.38)
                                                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: actionRow.shellQueued ? "Queued"
                                                    : (root.themeCommandBusy && actionRow.modelData.id !== "tokens"
                                                        ? "Queue" : actionRow.modelData.action)
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: actionRow.actionEnabled ? Tokens.accent : Tokens.text_secondary
                                            }

                                            HoverHandler {
                                                id: actionHover
                                                enabled: actionRow.actionEnabled
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: actionRow.actionEnabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.runRuntimeAction(actionRow.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
