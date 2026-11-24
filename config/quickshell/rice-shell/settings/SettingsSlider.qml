pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../theme"
import "Registry.js" as Registry

Slider {
    id: slider
    implicitWidth: 164
    implicitHeight: 40
    padding: 0
    leftPadding: 2
    rightPadding: 2

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + (slider.availableHeight - height) / 2
        width: slider.availableWidth
        height: 6
        radius: height / 2
        color: Tokens.surface_high
        opacity: slider.enabled ? 1 : 0.55

        Rectangle {
            anchors.left: slider.mirrored ? undefined : parent.left
            anchors.right: slider.mirrored ? parent.right : undefined
            width: parent.width * slider.position
            height: parent.height
            radius: parent.radius
            color: Tokens.accent
        }
    }

    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + (slider.availableHeight - height) / 2
        implicitWidth: 17
        implicitHeight: 17
        radius: width / 2
        color: slider.enabled ? Tokens.accent : Tokens.outline
        border.width: slider.visualFocus ? 2 : 0
        border.color: Registry.readable(Tokens.focus_ring, color, 3)
    }
}
