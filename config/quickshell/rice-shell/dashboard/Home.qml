pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: 370

    RowLayout {
        anchors.fill: parent
        spacing: 10

        // Left Column: Profile (top) + Calendar (bottom)
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 200
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
            Layout.minimumWidth: 260
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
            Layout.preferredWidth: 220

            QuickSettings {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
