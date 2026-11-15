pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 340
    implicitHeight: 320
    radius: 16
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1
    clip: true

    readonly property bool hasArtwork: Media.hasPlayer && Media.trackArtUrl.length > 0
        && artImage.status === Image.Ready
    readonly property real artworkScale: Math.min(3, Math.max(1, Screen.devicePixelRatio || 1))
    readonly property real artworkSize: Math.min(152, Math.max(64, width - 64),
        Math.max(72, height - (Media.hasPlayer ? 210 : 160)))
    readonly property string playerIdentity: Media.hasPlayer && Media.activePlayer
        ? (Media.activePlayer.identity || Media.activePlayer.desktopEntry || qsTr("Media player"))
        : qsTr("Media player")

    property bool seeking: false
    property real seekPreviewPosition: 0
    property var seekPlayer: null
    property int seekTrackId: -1

    readonly property real displayedPosition: seeking ? seekPreviewPosition : Media.position
    readonly property real displayedProgress: Media.length > 0
        ? Math.max(0, Math.min(1, displayedPosition / Media.length)) : 0

    function beginSeek(x: real, width: real): void {
        if (!Media.hasPlayer || !Media.activePlayer || !Media.activePlayer.canSeek
            || Media.length <= 0 || width <= 0)
            return;
        seeking = true;
        seekPlayer = Media.activePlayer;
        seekTrackId = Media.activePlayer.uniqueId;
        updateSeek(x, width);
    }

    function updateSeek(x: real, width: real): void {
        if (!seeking || width <= 0 || Media.length <= 0) return;
        var fraction = Math.max(0, Math.min(1, x / width));
        seekPreviewPosition = fraction * Media.length;
    }

    function cancelSeek(): void {
        seeking = false;
        seekPlayer = null;
        seekTrackId = -1;
    }

    function commitSeek(): void {
        if (!seeking) return;
        var target = seekPreviewPosition;
        var player = seekPlayer;
        var canCommit = player && player === Media.activePlayer
            && player.uniqueId === seekTrackId && player.canSeek && Media.length > 0;
        cancelSeek();
        if (canCommit) Media.setPosition(target);
    }

    // MPRIS positions are refreshed only while this visible card is playing.
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

    Connections {
        target: Media
        function onActivePlayerChanged() { root.cancelSeek(); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.playerIdentity
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Tokens.text_primary
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                text: !Media.hasPlayer ? qsTr("READY") : Media.isPlaying ? qsTr("PLAYING") : qsTr("PAUSED")
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: Media.isPlaying ? Tokens.accent : Tokens.text_secondary
                textFormat: Text.PlainText
            }
        }

        Item { Layout.fillHeight: true }

        Item {
            id: artworkFrame
            objectName: "playerArtwork"
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: root.artworkSize
            Layout.maximumWidth: root.artworkSize
            Layout.minimumHeight: root.artworkSize
            Layout.maximumHeight: root.artworkSize
            Layout.preferredWidth: root.artworkSize
            Layout.preferredHeight: root.artworkSize

            Rectangle {
                anchors.fill: parent
                radius: 13
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)
            }

            Image {
                id: artImage
                anchors.fill: parent
                source: Media.trackArtUrl
                sourceSize.width: Math.min(840, Math.ceil(root.artworkSize * root.artworkScale))
                sourceSize.height: Math.min(660, Math.ceil(root.artworkSize * root.artworkScale))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }

            Rectangle {
                id: artworkMask
                layer.enabled: true
                anchors.fill: parent
                radius: 13
                color: "white"
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: artImage
                maskEnabled: true
                maskSource: artworkMask
                visible: root.hasArtwork
            }

            Rectangle {
                anchors.fill: parent
                radius: 13
                color: Qt.rgba(0.04, 0.05, 0.07, 0.12)
                visible: root.hasArtwork
            }

            Text {
                anchors.centerIn: parent
                visible: !root.hasArtwork
                text: "󰎆"
                font.pixelSize: 46
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.55)
            }

            Rectangle {
                anchors.fill: parent
                radius: 13
                color: "transparent"
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
                border.width: 1
            }
        }


        ColumnLayout {
            objectName: "playerMetadata"
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: Media.hasPlayer ? Media.trackTitle : qsTr("No Active Player")
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Tokens.text_primary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: Media.hasPlayer ? (Media.trackArtist || qsTr("Unknown Artist"))
                    : qsTr("Play media to control")
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 11
                color: Tokens.text_secondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: Media.hasPlayer

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: Media.formatTime(root.displayedPosition)
                    font.pixelSize: 10
                    color: Tokens.text_secondary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Media.length > 0 ? Media.formatTime(Media.length) : qsTr("Live")
                    font.pixelSize: 10
                    color: Tokens.text_secondary
                }
            }

            Item {
                id: seekHitArea
                Layout.fillWidth: true
                Layout.preferredHeight: 20

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 3
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)
                    opacity: Media.activePlayer && Media.activePlayer.canSeek && Media.length > 0 ? 1 : 0.55

                    Rectangle {
                        height: parent.height
                        width: parent.width * root.displayedProgress
                        radius: parent.radius
                        color: Tokens.accent
                        Behavior on width {
                            enabled: !root.seeking
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    id: playerSeekArea
                    anchors.fill: parent
                    enabled: Media.hasPlayer && Media.activePlayer !== null
                        && Media.activePlayer.canSeek && Media.length > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: (mouse) => root.beginSeek(mouse.x, width)
                    onPositionChanged: (mouse) => {
                        if (pressed) root.updateSeek(mouse.x, width);
                    }
                    onReleased: (mouse) => {
                        root.updateSeek(mouse.x, width);
                        root.commitSeek();
                    }
                    onCanceled: root.cancelSeek()
                }
            }
        }

        RowLayout {
            objectName: "playerTransport"
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 2
            spacing: 24

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: prevHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                    : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.72)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                border.width: 1
                opacity: Media.canPrev ? 1 : 0.45
                Accessible.name: qsTr("Previous track")

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    font.pixelSize: 17
                    color: prevHover.hovered ? Tokens.accent : Tokens.text_primary
                }
                HoverHandler {
                    id: prevHover
                    enabled: Media.hasPlayer && Media.canPrev
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: Media.hasPlayer && Media.canPrev
                    onTapped: Media.previous()
                }
            }

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 24
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, playHover.hovered ? 0.32 : 0.2)
                border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.8)
                border.width: 1
                opacity: Media.canToggle ? 1 : 0.45
                Accessible.name: Media.isPlaying ? qsTr("Pause") : qsTr("Play")

                Text {
                    anchors.centerIn: parent
                    text: Media.isPlaying ? "󰏤" : "󰐊"
                    font.pixelSize: 21
                    color: Tokens.text_primary
                }
                HoverHandler {
                    id: playHover
                    enabled: Media.hasPlayer && Media.canToggle
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: Media.hasPlayer && Media.canToggle
                    onTapped: Media.togglePlaying()
                }
            }

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: nextHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                    : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.72)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                border.width: 1
                opacity: Media.canNext ? 1 : 0.45
                Accessible.name: qsTr("Next track")

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    font.pixelSize: 17
                    color: nextHover.hovered ? Tokens.accent : Tokens.text_primary
                }
                HoverHandler {
                    id: nextHover
                    enabled: Media.hasPlayer && Media.canNext
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: Media.hasPlayer && Media.canNext
                    onTapped: Media.next()
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
