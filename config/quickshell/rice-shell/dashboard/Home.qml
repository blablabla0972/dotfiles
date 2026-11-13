pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: width < 700 ? 650 : 370
    readonly property int layoutColumns: homeGrid.columns

    signal requestSideDrawer(string type)

    GridLayout {
        id: homeGrid
        anchors.fill: parent
        columns: root.width < 700 ? 2 : 3
        rowSpacing: 10
        columnSpacing: 10

        // Left Column: Profile (top) + Calendar (bottom)
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: root.width < 700 ? (root.width - 10) / 2 : 200
            spacing: 10

            ProfileCard {
                Layout.fillWidth: true
            }

            CalendarCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // Center Column: Clock (top) + Media Player (bottom)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: root.width < 700 ? (root.width - 10) / 2 : 260
            spacing: 10

            ClockCard {
                Layout.fillWidth: true
            }

            PlayerCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // Right Column: Quick Settings & Toggles
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: 220
            Layout.columnSpan: root.width < 700 ? 2 : 1

            QuickSettings {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onRequestSideDrawer: (type) => root.requestSideDrawer(type)
            }
        }
    }
}
