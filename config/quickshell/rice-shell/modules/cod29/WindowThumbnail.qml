import QtQuick
import Quickshell.Wayland
import "../../theme"

Rectangle {
    id: thumbnail
    required property var toplevel
    required property bool live
    readonly property var client: toplevel?.lastIpcObject
    radius: 3
    color: Tokens.surface_high
    border.color: Tokens.outline
    clip: true

    Text {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 4)
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        text: thumbnail.client?.class ?? ""
        font.pixelSize: thumbnail.width < 120 ? 8 : 13
        color: Tokens.text_primary
        visible: !capture.hasContent
    }

    ScreencopyView {
        id: capture
        anchors.fill: parent
        anchors.margins: 1
        live: thumbnail.live
        captureSource: thumbnail.visible ? thumbnail.toplevel?.wayland ?? null : null
    }
}
