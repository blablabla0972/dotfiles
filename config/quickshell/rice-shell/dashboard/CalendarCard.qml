pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

Rectangle {
    id: root

    implicitWidth: 200
    implicitHeight: 210
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
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

    // Calendar date math: Monday = 0, ..., Sunday = 6
    readonly property int firstDayWeekday: (new Date(root.currentYear, root.currentMonth, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(root.currentYear, root.currentMonth + 1, 0).getDate()
    readonly property int prevMonthDays: new Date(root.currentYear, root.currentMonth, 0).getDate()
    readonly property int totalCells: (root.firstDayWeekday + root.daysInMonth > 35) ? 42 : 35

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        // Month Header
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.monthName
                font.pixelSize: 12
                font.bold: true
                color: Tokens.accent
            }
        }

        // Days of Week Header (Mon - Sun)
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

        // Dynamic Days Grid
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 1
            columnSpacing: 0

            Repeater {
                model: root.totalCells

                Item {
                    id: cellItem
                    required property int index

                    readonly property bool isPrevMonth: index < root.firstDayWeekday
                    readonly property bool isNextMonth: index >= (root.firstDayWeekday + root.daysInMonth)
                    readonly property bool isCurrentMonth: !isPrevMonth && !isNextMonth

                    readonly property int dayNumber: {
                        if (isPrevMonth) {
                            return root.prevMonthDays - (root.firstDayWeekday - 1 - index);
                        } else if (isNextMonth) {
                            return index - (root.firstDayWeekday + root.daysInMonth) + 1;
                        } else {
                            return index - root.firstDayWeekday + 1;
                        }
                    }

                    readonly property bool isToday: isCurrentMonth && (dayNumber === root.currentDay)

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: cellItem.isToday ? Tokens.accent : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: cellItem.dayNumber.toString()
                            font.pixelSize: 9
                            font.bold: cellItem.isToday
                            color: {
                                if (cellItem.isToday) return Tokens.on_accent;
                                if (cellItem.isCurrentMonth) return Tokens.text_primary;
                                return Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.35);
                            }
                        }
                    }
                }
            }
        }
    }
}

