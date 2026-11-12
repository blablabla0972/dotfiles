pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 200
    implicitHeight: 95
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // User Avatar Circle with Status Dot
        Item {
            width: 50
            height: 50

            Rectangle {
                anchors.fill: parent
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

            // Active Green Status Indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: 2
                anchors.rightMargin: 2
                width: 12
                height: 12
                radius: 6
                color: "#4ade80"
                border.color: Tokens.surface_high
                border.width: 2
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
