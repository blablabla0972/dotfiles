pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 210
    implicitHeight: 242
    radius: 16
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
    border.width: 1

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property date now: clock.date
    readonly property int currentYear: now.getFullYear()
    readonly property int currentMonth: now.getMonth()
    readonly property int currentDay: now.getDate()
    readonly property string monthName: Qt.formatDateTime(now, "MMMM yyyy")

    // Calendar date math: Monday = 0, ..., Sunday = 6.
    readonly property int firstDayWeekday: (new Date(root.currentYear, root.currentMonth, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(root.currentYear, root.currentMonth + 1, 0).getDate()
    readonly property int prevMonthDays: new Date(root.currentYear, root.currentMonth, 0).getDate()
    readonly property int totalCells: (root.firstDayWeekday + root.daysInMonth > 35) ? 42 : 35

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 9

        Text {
            Layout.fillWidth: true
            text: root.monthName
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Tokens.text_primary
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: Tokens.text_secondary
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 3
            columnSpacing: 0

            Repeater {
                model: root.totalCells

                Item {
                    id: cellItem
                    required property int index

                    readonly property bool isPrevMonth: index < root.firstDayWeekday
                    readonly property bool isNextMonth: index >= root.firstDayWeekday + root.daysInMonth
                    readonly property bool isCurrentMonth: !isPrevMonth && !isNextMonth
                    readonly property int dayNumber: {
                        if (isPrevMonth)
                            return root.prevMonthDays - (root.firstDayWeekday - 1 - index);
                        if (isNextMonth)
                            return index - (root.firstDayWeekday + root.daysInMonth) + 1;
                        return index - root.firstDayWeekday + 1;
                    }
                    readonly property bool isToday: isCurrentMonth && dayNumber === root.currentDay

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 26

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(28, parent.width - 2, parent.height - 2)
                        height: width
                        radius: width / 2
                        color: cellItem.isToday
                            ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.9)
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: cellItem.dayNumber.toString()
                            font.pixelSize: 11
                            font.weight: cellItem.isToday ? Font.DemiBold : Font.Normal
                            color: {
                                if (cellItem.isToday) return Tokens.on_accent;
                                if (cellItem.isCurrentMonth) return Tokens.text_primary;
                                return Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.58);
                            }
                        }
                    }
                }
            }
        }
    }
}
