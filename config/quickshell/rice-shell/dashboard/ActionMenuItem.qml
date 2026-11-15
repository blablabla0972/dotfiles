import QtQuick
import QtQuick.Controls.Basic as Basic
import "../theme"

Basic.MenuItem {
    id: control
    implicitWidth: 220
    implicitHeight: visible ? 38 : 0
    leftPadding: 14
    rightPadding: 14
    contentItem: Text {
        text: control.text
        font.pixelSize: 12
        font.weight: control.highlighted ? Font.Medium : Font.Normal
        color: control.enabled ? Tokens.text_primary : Tokens.text_secondary
        opacity: control.enabled ? 1 : 0.5
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 12
        color: control.highlighted
            ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18) : "transparent"
    }
}
