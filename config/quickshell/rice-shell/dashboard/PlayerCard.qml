pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 440
    implicitHeight: 170
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Upper Section: Track Art & Information
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // Album Artwork / Placeholder
            Rectangle {
                width: 64
                height: 64
                radius: 10
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1
                clip: true

                Image {
                    anchors.fill: parent
                    source: Media.trackArtUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: Media.trackArtUrl.length > 0
                }

                Text {
                    anchors.centerIn: parent
                    visible: Media.trackArtUrl.length === 0
                    text: "󰎆"
                    font.pixelSize: 28
                    color: Tokens.accent
                }
            }

            // Track Meta
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: Media.hasPlayer ? Media.trackTitle : "No Active Player"
                    font.pixelSize: 14
                    font.bold: true
                    color: Tokens.text_primary
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: Media.hasPlayer ? (Media.trackArtist || "Unknown Artist") : "Play media to control"
                    font.pixelSize: 12
                    color: Tokens.text_secondary
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: Media.hasPlayer ? Media.trackAlbum : ""
                    font.pixelSize: 10
                    color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        // Lower Section: Controls
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 28

            // Previous
            Rectangle {
                width: 32; height: 32; radius: 16
                color: prevHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15) : "transparent"
                Text { anchors.centerIn: parent; text: "󰒮"; font.pixelSize: 18; color: Tokens.text_secondary }
                HoverHandler { id: prevHover }
                TapHandler { onTapped: Media.previous() }
            }

            // Play / Pause
            Rectangle {
                width: 40; height: 40; radius: 20
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25)
                border.color: Tokens.accent
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: Media.isPlaying ? "󰏤" : "󰐊"
                    font.pixelSize: 20
                    color: Tokens.accent
                }
                HoverHandler { id: playHover }
                TapHandler { onTapped: Media.togglePlaying() }
            }

            // Next
            Rectangle {
                width: 32; height: 32; radius: 16
                color: nextHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15) : "transparent"
                Text { anchors.centerIn: parent; text: "󰒭"; font.pixelSize: 18; color: Tokens.text_secondary }
                HoverHandler { id: nextHover }
                TapHandler { onTapped: Media.next() }
            }
        }
    }
}
