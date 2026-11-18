pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../services"
import "../theme"

Item {
    id: root

    readonly property int notificationCount: DesktopControls.notificationHistory.length
    readonly property bool hasNotifications: notificationCount > 0
    readonly property bool dndActive: DesktopControls.doNotDisturb
    property var expandedNotificationId: null

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 8

            Text {
                text: "Notifications"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: Tokens.text_primary
            }

            Rectangle {
                Layout.preferredWidth: countLabel.implicitWidth + 18
                Layout.preferredHeight: 24
                radius: 12
                color: Tokens.surface_high

                Text {
                    id: countLabel
                    anchors.centerIn: parent
                    text: root.notificationCount + (root.notificationCount === 1 ? " alert" : " alerts")
                    font.pixelSize: 10
                    color: Tokens.text_secondary
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 82
                Layout.preferredHeight: 30
                radius: 15
                color: root.dndActive
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                    : Tokens.surface
                border.width: 1
                border.color: root.dndActive ? Tokens.accent : Tokens.outline

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: "󰂛"
                        font.pixelSize: 12
                        color: root.dndActive ? Tokens.accent : Tokens.text_secondary
                    }
                    Text {
                        text: root.dndActive ? "DND on" : "DND off"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: root.dndActive ? Tokens.accent : Tokens.text_primary
                    }
                }

                HoverHandler { id: dndHover }
                TapHandler {
                    onTapped: DesktopControls.doNotDisturb = !DesktopControls.doNotDisturb
                }
            }

            Rectangle {
                Layout.preferredWidth: 76
                Layout.preferredHeight: 30
                radius: 15
                color: clearHover.hovered ? Tokens.surface_high : Tokens.surface
                border.width: 1
                border.color: Tokens.outline
                opacity: root.hasNotifications ? 1 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "Clear all"
                    font.pixelSize: 10
                    color: Tokens.text_primary
                }

                HoverHandler { id: clearHover }
                TapHandler {
                    enabled: root.hasNotifications
                    onTapped: {
                        root.expandedNotificationId = null;
                        DesktopControls.clearNotificationHistory();
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: root.width

            ListView {
                id: notificationList
                anchors.fill: parent
                visible: root.hasNotifications
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: DesktopControls.notificationHistory

                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    readonly property bool expanded: root.expandedNotificationId === modelData.id

                    width: ListView.view.width
                    height: entryContent.implicitHeight + 20
                    radius: 11
                    color: Tokens.surface_high
                    border.width: 1
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)

                    RowLayout {
                        id: entryContent
                        x: 11
                        y: 10
                        width: parent.width - 22
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            Layout.alignment: Qt.AlignTop
                            radius: 9
                            color: Tokens.surface_low
                            clip: true

                            Image {
                                id: appImage
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                source: entry.modelData.appIcon || ""
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰂚"
                                font.pixelSize: 17
                                color: Tokens.text_secondary
                                visible: !appImage.visible
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: entry.modelData.appName || "Unknown app"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Tokens.accent
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: entry.modelData.time || ""
                                    font.pixelSize: 10
                                    color: Tokens.text_secondary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: entry.modelData.summary || "Notification"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Tokens.text_primary
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                id: bodyPreview
                                Layout.fillWidth: true
                                visible: text.length > 0
                                textFormat: Text.PlainText
                                text: entry.modelData.body || ""
                                font.pixelSize: 11
                                color: Tokens.text_secondary
                                wrapMode: Text.Wrap
                                maximumLineCount: entry.expanded ? 8 : 2
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: bodyPreview.truncated || entry.expanded
                                text: entry.expanded ? "Show less" : "Show details"
                                font.pixelSize: 10
                                color: Tokens.accent

                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: root.expandedNotificationId =
                                        entry.expanded ? null : entry.modelData.id
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: entry.modelData.actions && entry.modelData.actions.length > 0
                                spacing: 6

                                Repeater {
                                    model: entry.modelData.actions || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 26
                                        radius: 8
                                        color: actionHover.hovered ? Tokens.surface_high : Tokens.surface
                                        border.width: 1
                                        border.color: Tokens.outline

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.text
                                            font.pixelSize: 10
                                            color: Tokens.text_primary
                                            elide: Text.ElideRight
                                        }

                                        HoverHandler {
                                            id: actionHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                        TapHandler {
                                            onTapped: DesktopControls.requestNotificationAction(
                                                entry.modelData.id, modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: emptyState
                anchors.fill: parent
                visible: !root.hasNotifications

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰂚"
                        font.pixelSize: 26
                        color: Tokens.text_secondary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No notifications"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "New alerts will appear here."
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                }
            }
        }
    }
}
