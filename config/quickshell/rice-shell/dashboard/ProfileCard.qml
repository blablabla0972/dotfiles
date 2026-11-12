pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 220
    implicitHeight: 110
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // User Avatar Circle
        Rectangle {
            width: 50
            height: 50
            radius: 25
            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
            border.color: Tokens.accent
            border.width: 1.5

            Text {
                anchors.centerIn: parent
                text: "󰀄"
                font.pixelSize: 26
                color: Tokens.accent
            }
        }

        // User Metadata
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                text: "Hello,"
                font.pixelSize: 11
                color: Tokens.text_secondary
            }

            Text {
                text: Quickshell.env("USER") || "Admin"
                font.pixelSize: 15
                font.bold: true
                color: Tokens.text_primary
                elide: Text.ElideRight
            }

            Text {
                text: "CachyOS / Hyprland"
                font.pixelSize: 10
                color: Tokens.accent
            }
        }
    }
}
