import QtQuick
import QtQuick.Controls.Basic as Basic
import "../theme"

Basic.Menu {
    id: control
    popupType: Basic.Popup.Item
    implicitWidth: Math.max(220, contentItem.implicitWidth + leftPadding + rightPadding)
    padding: 6
    overlap: 0
    background: Rectangle {
        radius: 18
        color: Tokens.surface
        border.width: 1
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 90 } }
}
