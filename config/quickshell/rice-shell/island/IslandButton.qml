pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "../theme"

T.AbstractButton {
    id: control
    property string glyph: text
    property bool prominent: false
    property bool highlighted: false
    property string glyphObjectName: ""
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + leftPadding + rightPadding)
    implicitHeight: 30
    horizontalPadding: 6
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.4
    font.pixelSize: 15
    Accessible.name: text
    property real pressScale: down ? 0.94 : 1
    Behavior on pressScale {
        NumberAnimation { duration: control.down ? 70 : 150; easing.type: Easing.OutCubic }
    }

    background: Rectangle {
        scale: control.pressScale
        radius: height / 2
        color: control.prominent ? (control.down ? Qt.darker(Tokens.accent, 1.12) : Tokens.accent)
            : control.down || control.hovered ? Tokens.surface_high
            : control.highlighted ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.14) : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: control.prominent ? Tokens.on_accent : Tokens.focus_ring
        Behavior on color { ColorAnimation { duration: 110 } }
    }
    contentItem: Text {
        id: label
        objectName: control.glyphObjectName
        text: control.glyph
        scale: control.pressScale
        textFormat: Text.PlainText
        font: control.font
        color: control.prominent ? Tokens.on_accent
            : control.highlighted || control.hovered ? Tokens.accent : Tokens.text_primary
        Behavior on color { ColorAnimation { duration: 110 } }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        Accessible.ignored: true
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
