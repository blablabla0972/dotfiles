pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../theme"
import "Registry.js" as Registry

SpinBox {
    id: field
    implicitWidth: 118
    implicitHeight: 42
    leftPadding: 37
    rightPadding: 37
    editable: true
    opacity: enabled ? 1 : 0.64
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)

    contentItem: TextInput {
        text: field.displayText
        font: field.font
        color: field.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        validator: field.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        selectByMouse: true
        readOnly: !field.editable
    }
    down.indicator: Label {
        x: 3
        y: 3
        width: 34
        height: 36
        text: "−"
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: field.ink
        background: Rectangle {
            radius: 6
            color: field.down.pressed ? Tokens.surface_high : Tokens.surface_low
        }
    }
    up.indicator: Label {
        x: field.width - width - 3
        y: 3
        width: 34
        height: 36
        text: "+"
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: field.ink
        background: Rectangle {
            radius: 6
            color: field.up.pressed ? Tokens.surface_high : Tokens.surface_low
        }
    }
    background: Rectangle {
        color: Tokens.surface
        radius: 9
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? Registry.readable(Tokens.focus_ring, color, 3) : Tokens.outline
    }
}
