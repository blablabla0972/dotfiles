pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real pillWidth: 140
    property real pillHeight: 28
    property real antiCornerRadius: 12
    property real bottomRadius: 14
    property color fillColor: "#1a1b21"
    property color borderColor: "#43474e"
    property bool showAntiCorners: true

    property int animDurationWidth: 240
    property int animDurationHeight: 220
    property real overshoot: 0.6
    property int easingTypeWidth: overshoot > 0 ? Easing.OutBack : Easing.OutCubic
    property int easingTypeHeight: Easing.OutCubic

    width: pillWidth + (showAntiCorners ? antiCornerRadius * 2 : 0)
    height: pillHeight

    // Smooth geometry morphing transitions
    Behavior on pillWidth {
        NumberAnimation {
            duration: root.animDurationWidth
            easing.type: root.easingTypeWidth
            easing.overshoot: root.overshoot
        }
    }
    Behavior on pillHeight {
        NumberAnimation {
            duration: root.animDurationHeight
            easing.type: root.easingTypeHeight
        }
    }

    // Main Central Pill
    Rectangle {
        id: pillBody
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.pillWidth
        height: root.pillHeight
        radius: root.bottomRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        topLeftRadius: 0
        topRightRadius: 0
        color: root.fillColor
        border.color: Qt.rgba(root.borderColor.r, root.borderColor.g, root.borderColor.b, 0.4)
        border.width: 1
    }

    // Left Smooth Concave Anti-Corner
    Shape {
        id: antiCornerLeft
        visible: root.showAntiCorners
        anchors.top: parent.top
        anchors.right: pillBody.left
        width: root.antiCornerRadius
        height: root.antiCornerRadius

        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            startX: antiCornerLeft.width
            startY: 0

            PathLine { x: antiCornerLeft.width; y: antiCornerLeft.height }
            PathCubic {
                x: 0
                y: 0
                control1X: antiCornerLeft.width * 0.45
                control1Y: antiCornerLeft.height * 0.9
                control2X: 0
                control2Y: antiCornerLeft.height * 0.3
            }
            PathLine { x: antiCornerLeft.width; y: 0 }
        }
    }

    // Right Smooth Concave Anti-Corner
    Shape {
        id: antiCornerRight
        visible: root.showAntiCorners
        anchors.top: parent.top
        anchors.left: pillBody.right
        width: root.antiCornerRadius
        height: root.antiCornerRadius

        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            startX: 0
            startY: 0

            PathLine { x: 0; y: antiCornerRight.height }
            PathCubic {
                x: antiCornerRight.width
                y: 0
                control1X: antiCornerRight.width * 0.55
                control1Y: antiCornerRight.height * 0.9
                control2X: antiCornerRight.width
                control2Y: antiCornerRight.height * 0.3
            }
            PathLine { x: 0; y: 0 }
        }
    }
}
