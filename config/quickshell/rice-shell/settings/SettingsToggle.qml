pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../theme"
import "Registry.js" as Registry

Switch {
    id: toggle
    implicitHeight: 42
    hoverEnabled: true
    spacing: 10
    padding: 4

    indicator: Rectangle {
        x: toggle.text.length
            ? (toggle.mirrored ? toggle.width - width - toggle.rightPadding : toggle.leftPadding)
            : (toggle.mirrored ? toggle.leftPadding : toggle.width - width - toggle.rightPadding)
        y: (toggle.height - height) / 2
        implicitWidth: 44
        implicitHeight: 24
        radius: height / 2
        color: toggle.checked ? Tokens.accent : toggle.hovered ? Tokens.surface : Tokens.surface_high
        opacity: toggle.enabled ? 1 : 0.48
        border.color: toggle.checked ? color : Registry.readable(
            Qt.tint(Tokens.outline, Qt.alpha(Tokens.text_secondary, 0.55)), color, 3)

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            visible: toggle.visualFocus
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Registry.readable(Tokens.focus_ring, Tokens.surface, 3)
        }

        Rectangle {
            x: toggle.checked !== toggle.mirrored ? parent.width - width - 4 : 4
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: width
            radius: width / 2
            color: Registry.readable(toggle.checked ? Tokens.on_accent : Tokens.text_secondary, parent.color, 3)
        }
    }

    contentItem: Label {
        leftPadding: text.length && !toggle.mirrored ? toggle.indicator.width + toggle.spacing : 0
        rightPadding: text.length && toggle.mirrored ? toggle.indicator.width + toggle.spacing : 0
        text: toggle.text
        verticalAlignment: Text.AlignVCenter
        color: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    }
}
