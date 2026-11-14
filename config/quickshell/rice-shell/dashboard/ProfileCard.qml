pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 200
    implicitHeight: 90
    radius: 16
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 54
            Layout.preferredHeight: 54
            Layout.alignment: Qt.AlignVCenter
            radius: 27
            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.14)

            Text {
                anchors.centerIn: parent
                text: "󰀄"
                font.pixelSize: 27
                color: Tokens.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: Quickshell.env("USER") || qsTr("User")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Tokens.text_primary
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("CachyOS · Hyprland")
                font.pixelSize: 11
                color: Tokens.text_secondary
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }
}
