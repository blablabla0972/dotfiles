pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: Math.min(940, parent ? parent.width - 24 : 940)
    implicitHeight: 310

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // Left Column: Profile (top) + Calendar (bottom)
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
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
            Layout.minimumWidth: 380
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
            Layout.preferredWidth: 230

            QuickSettings {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
