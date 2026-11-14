pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root

    implicitWidth: 900
    implicitHeight: 520
    readonly property bool wideLayout: width >= 820
    readonly property bool mediumLayout: width >= 650 && width < 820
    readonly property int layoutColumns: homeGrid.columns

    signal requestSideDrawer(string type)

    Flickable {
        id: homeViewport
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: homeGrid.height
        interactive: !root.wideLayout && homeGrid.height > height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        GridLayout {
            id: homeGrid
            width: homeViewport.width
            height: Math.max(homeViewport.height, implicitHeight)
            columns: root.wideLayout ? 3 : root.mediumLayout ? 2 : 1
            rowSpacing: 12
            columnSpacing: 12

            ColumnLayout {
                Layout.column: 0
                Layout.row: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.wideLayout
                    ? (homeGrid.width - 2 * homeGrid.columnSpacing) * 0.25
                    : root.mediumLayout
                        ? (homeGrid.width - homeGrid.columnSpacing) * 0.42
                        : homeGrid.width
                spacing: 12

                ProfileCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                }

                CalendarCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 230
                }
            }

            ColumnLayout {
                Layout.column: root.wideLayout ? 1 : root.mediumLayout ? 1 : 0
                Layout.row: root.wideLayout || root.mediumLayout ? 0 : 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.wideLayout
                    ? (homeGrid.width - 2 * homeGrid.columnSpacing) * 0.43
                    : root.mediumLayout
                        ? (homeGrid.width - homeGrid.columnSpacing) * 0.58
                        : homeGrid.width
                spacing: 12

                ClockCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 122
                }

                PlayerCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 300
                }
            }

            QuickSettings {
                Layout.column: root.wideLayout ? 2 : 0
                Layout.row: root.wideLayout ? 0 : root.mediumLayout ? 1 : 2
                Layout.columnSpan: root.mediumLayout ? 2 : 1
                Layout.fillWidth: true
                Layout.fillHeight: root.wideLayout
                Layout.preferredWidth: root.wideLayout
                    ? (homeGrid.width - 2 * homeGrid.columnSpacing) * 0.32
                    : homeGrid.width
                Layout.preferredHeight: 420
                onRequestSideDrawer: (type) => root.requestSideDrawer(type)
            }
        }
    }
}
