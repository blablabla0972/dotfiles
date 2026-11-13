pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 280
    implicitHeight: 220
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1
    clip: true

    readonly property bool hasArtwork: Media.hasPlayer && Media.trackArtUrl.length > 0 && artImage.status === Image.Ready

    // MPRIS positions are fetched on demand; update only while this card is visible.
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && Media.isPlaying && Media.activePlayer !== null
            && Media.activePlayer.positionSupported
        onTriggered: {
            if (Media.activePlayer && Media.isPlaying)
                Media.activePlayer.positionChanged();
        }
    }

    // 1. Full-Bleed Artwork Background
    Image {
        id: artImage
        anchors.fill: parent
        source: Media.trackArtUrl
        fillMode: Image.PreserveAspectCrop
        visible: Media.hasPlayer && Media.trackArtUrl.length > 0
        asynchronous: true
        opacity: root.hasArtwork ? 0.35 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    // 2. 3-Stop Dark Gradient Overlay for Maximum Readability
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.06, 0.08, root.hasArtwork ? 0.45 : 0.20) }
            GradientStop { position: 0.45; color: Qt.rgba(0.06, 0.06, 0.08, root.hasArtwork ? 0.70 : 0.40) }
            GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.06, 0.08, root.hasArtwork ? 0.94 : 0.70) }
        }
    }

    // 3. Fallback Decorative Glyph when no artwork
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        anchors.bottomMargin: 8
        visible: !root.hasArtwork
        text: "󰎆"
        font.pixelSize: 84
        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.06)
    }

    // 4. Foreground Card Content Layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Header: Player Badge & Active Status
        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                height: 22
                implicitWidth: playerBadgeRow.implicitWidth + 14
                radius: 11
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.8)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                border.width: 1

                RowLayout {
                    id: playerBadgeRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "󰎆"
                        font.pixelSize: 11
                        color: Tokens.accent
                    }

                    Text {
                        text: Media.hasPlayer ? "Now Playing" : "Media Player"
                        font.pixelSize: 10
                        font.bold: true
                        color: Tokens.text_secondary
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Small Live Equalizer Dots if Playing
            Row {
                spacing: 3
                visible: Media.hasPlayer && Media.isPlaying
                Layout.alignment: Qt.AlignVCenter

                Rectangle { width: 3; height: 8; radius: 1.5; color: Tokens.accent }
                Rectangle { width: 3; height: 14; radius: 1.5; color: Tokens.accent }
                Rectangle { width: 3; height: 10; radius: 1.5; color: Tokens.accent }
                Rectangle { width: 3; height: 6; radius: 1.5; color: Tokens.accent }
            }
        }

        // Track Information
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: Media.hasPlayer ? Media.trackTitle : "No Active Player"
                font.pixelSize: 15
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

        Item { Layout.fillHeight: true }

        // Track Progress Seek Bar
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Media.hasPlayer

            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.85)

                Rectangle {
                    height: parent.height
                    width: parent.width * Media.progress
                    radius: 2
                    color: Tokens.accent

                    Behavior on width {
                        NumberAnimation { duration: 300 }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Media.isPlaying ? "Playing" : "Paused"
                    font.pixelSize: 9
                    color: Tokens.text_secondary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: Media.isPlaying ? "MPRIS" : "Ready"
                    font.pixelSize: 9
                    color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                }
            }
        }

        // Playback Controls
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 28

            // Previous
            Rectangle {
                width: 34
                height: 34
                radius: 17
                color: prevHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    font.pixelSize: 16
                    color: prevHover.hovered ? Tokens.accent : Tokens.text_primary
                }
                HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Media.previous() }
            }

            // Play / Pause
            Rectangle {
                width: 44
                height: 44
                radius: 22
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, playHover.hovered ? 0.35 : 0.22)
                border.color: Tokens.accent
                border.width: 1.5

                Text {
                    anchors.centerIn: parent
                    text: Media.isPlaying ? "󰏤" : "󰐊"
                    font.pixelSize: 20
                    color: Tokens.accent
                }
                HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Media.togglePlaying() }
            }

            // Next
            Rectangle {
                width: 34
                height: 34
                radius: 17
                color: nextHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.6)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    font.pixelSize: 16
                    color: nextHover.hovered ? Tokens.accent : Tokens.text_primary
                }
                HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Media.next() }
            }
        }
    }
}
