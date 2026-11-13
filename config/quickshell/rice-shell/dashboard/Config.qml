pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../services"
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: width < 700 ? 700 : 370
    readonly property int layoutColumns: configGrid.columns

    readonly property string themeCommandResult: ThemeCommandQueue.result
    readonly property bool themeCommandRunning: ThemeCommandQueue.running
    readonly property int pendingCommandCount: ThemeCommandQueue.pendingCount

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

    GridLayout {
        id: configGrid
        anchors.fill: parent
        columns: root.width < 700 ? 1 : 2
        rowSpacing: 12
        columnSpacing: 12

        // Left Section: Theme & Appearance
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰔎"
                            font.pixelSize: 16
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Theme & Palette"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: "Material You adaptive system"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                    }
                }

                // Dark / Light Mode Switcher Pills
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Dark Mode Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 10
                        readonly property bool isDark: Tokens.mode === "dark"
                        color: isDark ? Tokens.accent : (darkHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                        border.color: isDark ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰖔"
                                font.pixelSize: 14
                                color: parent.parent.isDark ? Tokens.on_accent : Tokens.text_secondary
                            }
                            Text {
                                text: "Dark Mode"
                                font.pixelSize: 11
                                font.bold: true
                                color: parent.parent.isDark ? Tokens.on_accent : Tokens.text_primary
                            }
                        }

                        HoverHandler { id: darkHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchTheme("dark")
                        }
                    }

                    // Light Mode Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 10
                        readonly property bool isLight: Tokens.mode === "light"
                        color: isLight ? Tokens.accent : (lightHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                        border.color: isLight ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰖨"
                                font.pixelSize: 14
                                color: parent.parent.isLight ? Tokens.on_accent : Tokens.text_secondary
                            }
                            Text {
                                text: "Light Mode"
                                font.pixelSize: 11
                                font.bold: true
                                color: parent.parent.isLight ? Tokens.on_accent : Tokens.text_primary
                            }
                        }

                        HoverHandler { id: lightHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchTheme("light")
                        }
                    }
                }

                // Regenerate Palette Button
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 10
                    color: regenHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "󰏘"
                            font.pixelSize: 15
                            color: Tokens.accent
                        }

                        Text {
                            text: "Regenerate Palette from Wallpaper"
                            font.pixelSize: 11
                            font.bold: true
                            color: Tokens.text_primary
                        }
                    }

                    HoverHandler { id: regenHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.regenerateTheme()
                    }
                }

                // Swatches Section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Active Palette Swatches"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_secondary
                    }

                    // 2-row swatch matrix
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: [
                                { name: "Accent", color: Tokens.accent },
                                { name: "Surface", color: Tokens.surface },
                                { name: "High", color: Tokens.surface_high },
                                { name: "Outline", color: Tokens.outline },
                                { name: "Text", color: Tokens.text_primary },
                                { name: "Muted", color: Tokens.text_secondary },
                                { name: "Danger", color: Tokens.danger },
                                { name: "On-Acc", color: Tokens.on_accent }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                height: 32
                                radius: 6
                                color: modelData.color
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.name
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: (parent.modelData.name === "Accent" || parent.modelData.name === "Danger" || parent.modelData.name === "Text") ? "#121318" : "#e2e2e9"
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.themeCommandResult.length > 0
                        || root.themeCommandRunning || root.pendingCommandCount > 0
                    text: root.themeCommandResult.length > 0 ? root.themeCommandResult
                        : (root.themeCommandRunning ? "Applying appearance changes…" : "Changes queued…")
                    font.pixelSize: 9
                    color: root.themeCommandResult.indexOf("failed") >= 0
                        ? Tokens.danger : Tokens.text_secondary
                    wrapMode: Text.Wrap
                }

                Item { Layout.fillHeight: true }

                // Mode Footer
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Status: Adaptive " + Tokens.mode.toUpperCase()
                        font.pixelSize: 10
                        color: Tokens.accent
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Matugen v2.4.0"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                }
            }
        }

        // Right Section: Runtime & Compositor Control
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰑓"
                            font.pixelSize: 16
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Runtime Control"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: "Compositor & desktop shell actions"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                    }
                }

                // 1. Reload Quickshell Shell Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: reloadHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: "󰑓"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "Reload Rice Shell"
                                font.pixelSize: 11
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Hot-restart bar, island & dashboard"
                                font.pixelSize: 9
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "Restart"
                            font.pixelSize: 10
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    HoverHandler { id: reloadHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reloadShell()
                    }
                }

                // 2. Reload Hyprland Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: hyprHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: "󰒓"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "Reload Hyprland"
                                font.pixelSize: 11
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Reapply compositor rules and binds"
                                font.pixelSize: 9
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "Reload"
                            font.pixelSize: 10
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    HoverHandler { id: hyprHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reloadHyprland()
                    }
                }

                // 3. Refresh Tokens Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: tokenHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: "󰚰"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "Refresh Theme Tokens"
                                font.pixelSize: 11
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Re-read adaptive-theme.json"
                                font.pixelSize: 9
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "Sync"
                            font.pixelSize: 10
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    HoverHandler { id: tokenHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Tokens.reloadTheme()
                    }
                }

                Item { Layout.fillHeight: true }

                // Session Status Footer
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Quickshell 0.3.2 • Wayland"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.8)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Active screens: " + Quickshell.screens.length
                        font.pixelSize: 10
                        color: Tokens.accent
                    }
                }
            }
        }
    }
}
