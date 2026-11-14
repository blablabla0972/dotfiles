pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 280
    implicitHeight: 122
    radius: 16
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
    border.width: 1

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(clock.date, "hh:mm")
            font.pixelSize: Math.max(46, Math.min(58, root.height * 0.46))
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: Tokens.text_primary
            textFormat: Text.PlainText
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Tokens.text_secondary
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
}
