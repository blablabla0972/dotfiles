pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root

    property string themeCommandResult: ""

    Process {
        id: cmdProcess
    }

    function switchTheme(mode: string): void {
        var scriptPath = Quickshell.env("HOME") + "/.config/hypr/scripts/generate-theme.py";
        cmdProcess.command = ["python3", scriptPath, "--theme-mode-changed", "--mode", mode];
        cmdProcess.running = true;
    }

    function regenerateTheme(): void {
        var scriptPath = Quickshell.env("HOME") + "/.config/hypr/scripts/generate-theme.py";
        cmdProcess.command = ["python3", scriptPath, "--wallpaper-changed"];
        cmdProcess.running = true;
    }

    function reloadShell(): void {
        var cmd = "killall quickshell; sleep 0.2; ENABLE_NOTIFICATIONS=1 quickshell -d -p ~/.config/quickshell/rice-shell";
        cmdProcess.command = ["sh", "-c", cmd];
        cmdProcess.running = true;
    }

    function reloadHyprland(): void {
        cmdProcess.command = ["hyprctl", "reload"];
        cmdProcess.running = true;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // Left Section: Theme & Appearance
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰔎"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Theme Appearance"
                            font.pixelSize: 14
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: "Material You adaptive palette"
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }
                }

                // Dark / Light Mode Switcher Pills
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Dark Mode Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 10
                        readonly property bool isDark: Tokens.mode === "dark"
                        color: isDark ? Tokens.accent : (darkHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                        border.color: isDark ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "󰖔"
                                font.pixelSize: 16
                                color: parent.parent.isDark ? Tokens.on_accent : Tokens.text_secondary
                            }
                            Text {
                                text: "Dark Mode"
                                font.pixelSize: 12
                                font.bold: true
                                color: parent.parent.isDark ? Tokens.on_accent : Tokens.text_primary
                            }
                        }

                        HoverHandler { id: darkHover }
                        TapHandler {
                            onTapped: root.switchTheme("dark")
                        }
                    }

                    // Light Mode Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 10
                        readonly property bool isLight: Tokens.mode === "light"
                        color: isLight ? Tokens.accent : (lightHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                        border.color: isLight ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "󰖨"
                                font.pixelSize: 16
                                color: parent.parent.isLight ? Tokens.on_accent : Tokens.text_secondary
                            }
                            Text {
                                text: "Light Mode"
                                font.pixelSize: 12
                                font.bold: true
                                color: parent.parent.isLight ? Tokens.on_accent : Tokens.text_primary
                            }
                        }

                        HoverHandler { id: lightHover }
                        TapHandler {
                            onTapped: root.switchTheme("light")
                        }
                    }
                }

                // Regenerate Palette Button
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 10
                    color: regenHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "󰏘"
                            font.pixelSize: 16
                            color: Tokens.accent
                        }

                        Text {
                            text: "Regenerate Palette from Wallpaper"
                            font.pixelSize: 12
                            font.bold: true
                            color: Tokens.text_primary
                        }
                    }

                    HoverHandler { id: regenHover }
                    TapHandler {
                        onTapped: root.regenerateTheme()
                    }
                }

                Item { Layout.fillHeight: true }

                // Live Color Swatches Preview
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Active Palette Swatches"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_secondary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { name: "accent", color: Tokens.accent },
                                { name: "surface", color: Tokens.surface },
                                { name: "surface_high", color: Tokens.surface_high },
                                { name: "text", color: Tokens.text_primary },
                                { name: "outline", color: Tokens.outline },
                                { name: "danger", color: Tokens.danger }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                height: 26
                                radius: 6
                                color: modelData.color
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
                                border.width: 1
                            }
                        }
                    }
                }
            }
        }

        // Right Section: Shell Management & Actions
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰑓"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Shell & Compositor Control"
                            font.pixelSize: 14
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: "Reload runtime components"
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }
                }

                // 1. Reload Quickshell Shell Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 10
                    color: reloadHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: "󰑓"
                            font.pixelSize: 20
                            color: Tokens.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Reload Rice Shell"
                                font.pixelSize: 12
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Hot-restart bar, island & dashboard"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "Restart"
                            font.pixelSize: 11
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    HoverHandler { id: reloadHover }
                    TapHandler {
                        onTapped: root.reloadShell()
                    }
                }

                // 2. Reload Hyprland Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 10
                    color: hyprHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: "󰒓"
                            font.pixelSize: 20
                            color: Tokens.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Reload Hyprland"
                                font.pixelSize: 12
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Reapply compositor rules and binds"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: "Reload"
                            font.pixelSize: 11
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    HoverHandler { id: hyprHover }
                    TapHandler {
                        onTapped: root.reloadHyprland()
                    }
                }

                // 3. Refresh Tokens Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: tokenHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
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
                            spacing: 2
                            Text {
                                text: "Refresh Theme Tokens"
                                font.pixelSize: 12
                                font.bold: true
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "Re-read adaptive-theme.json"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }
                    }

                    HoverHandler { id: tokenHover }
                    TapHandler {
                        onTapped: Tokens.reloadTheme()
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
                        text: "Screens: " + Quickshell.screens.length
                        font.pixelSize: 10
                        color: Tokens.accent
                    }
                }
            }
        }
    }
}
