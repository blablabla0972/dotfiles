import QtQuick
import QtQuick.Controls.Basic as Basic
import "../theme"

Basic.Button {
    id: control
    implicitWidth: Math.max(64, implicitContentWidth + 28)
    implicitHeight: 34
    padding: 8
    horizontalPadding: 14
    font.pixelSize: 11
    font.weight: Font.Medium
    opacity: enabled ? 1 : 0.5

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.highlighted ? Tokens.on_accent : Tokens.text_primary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: height / 2
        color: control.highlighted ? Tokens.accent
            : control.down ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.24)
            : control.hovered ? Tokens.surface_high
            : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.65)
        border.width: 1
        border.color: control.activeFocus ? Tokens.focus_ring
            : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
        Behavior on color { ColorAnimation { duration: 130 } }
    }
}
