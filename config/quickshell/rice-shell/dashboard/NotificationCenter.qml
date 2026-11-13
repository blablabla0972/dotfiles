pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../services"
import "../theme"

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Notifications"
                font.pixelSize: 16
                font.bold: true
                color: Tokens.text_primary
            }

            Text {
                text: "(" + DesktopControls.notificationHistory.length + ")"
                font.pixelSize: 12
                color: Tokens.text_secondary
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                id: clearButton
                Layout.preferredWidth: 84
                Layout.preferredHeight: 28
                radius: 14
                color: clearHover.hovered ? Tokens.surface_high : Tokens.surface
                border.color: Tokens.outline
                opacity: DesktopControls.notificationHistory.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "Clear all"
                    font.pixelSize: 12
                    color: Tokens.text_primary
                }

                HoverHandler { id: clearHover }
                TapHandler {
                    enabled: DesktopControls.notificationHistory.length > 0
                    onTapped: DesktopControls.clearNotificationHistory()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Tokens.surface_low
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)

            ListView {
                id: notificationList
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 7
                boundsBehavior: Flickable.StopAtBounds
                model: DesktopControls.notificationHistory

                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    width: ListView.view.width
                    height: entryContent.implicitHeight + 18
                    radius: 10
                    color: Tokens.surface_high

                    Column {
                        id: entryContent
                        x: 12
                        y: 9
                        width: parent.width - 24
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                width: parent.width - entryTime.width - 10
                                textFormat: Text.PlainText
                                text: entry.modelData.summary
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }

                            Text {
                                id: entryTime
                                text: entry.modelData.time
                                font.pixelSize: 11
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            textFormat: Text.PlainText
                            text: entry.modelData.appName
                            font.pixelSize: 11
                            color: Tokens.accent
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            textFormat: Text.PlainText
                            text: entry.modelData.body
                            font.pixelSize: 12
                            color: Tokens.text_secondary
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: DesktopControls.notificationHistory.length === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰂚"
                    font.pixelSize: 28
                    color: Tokens.text_secondary
                }

                Text {
                    text: "No notifications yet"
                    font.pixelSize: 13
                    color: Tokens.text_secondary
                }
            }
        }
    }
}
