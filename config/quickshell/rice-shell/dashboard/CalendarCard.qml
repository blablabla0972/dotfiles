pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: root

    implicitWidth: 220
    implicitHeight: 180
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    readonly property date now: new Date()
    readonly property int currentDay: now.getDate()
    readonly property string monthName: Qt.formatDateTime(now, "MMMM yyyy")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Month Header
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.monthName
            font.pixelSize: 12
            font.bold: true
            color: Tokens.accent
        }

        // Days of Week Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: 10
                    font.bold: true
                    color: Tokens.text_secondary
                }
            }
        }

        // Days Grid (Simplified 4x7 preview)
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 2
            columnSpacing: 0

            Repeater {
                model: 28

                Item {
                    required property int index
                    readonly property int dayNumber: index + 1
                    readonly property bool isToday: dayNumber === root.currentDay

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: isToday ? Tokens.accent : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: dayNumber.toString()
                            font.pixelSize: 10
                            font.bold: isToday
                            color: isToday ? Tokens.on_accent : Tokens.text_primary
                        }
                    }
                }
            }
        }
    }
}
