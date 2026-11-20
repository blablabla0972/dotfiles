pragma ComponentBehavior: Bound

import QtQuick
import "../theme"

FocusScope {
    id: root

    property string icon: ""
    property string label: ""
    property string valueText: ""
    property real value: 0
    property real maximum: 1
    property var device: null
    property bool commitOnRelease: false
    property bool available: true
    property real step: 0.05

    signal valueRequested(real value)

    implicitHeight: 64
    activeFocusOnTab: root.available

    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.available ? root.valueText : qsTr("Unavailable")

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.78)
        border.width: 1
        border.color: root.activeFocus ? Tokens.focus_ring
            : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.14)
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        height: 16

        Text {
            anchors.left: parent.left
            anchors.right: percentage.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.available ? Tokens.text_primary : Tokens.text_secondary
            elide: Text.ElideRight
        }

        Text {
            id: percentage
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.56)
            text: root.valueText
            font.pixelSize: 12
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            color: Tokens.text_secondary
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: sliderTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 8
        height: 24
        radius: height / 2
        color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b,
            pointer.pressed ? 0.34 : (pointer.containsMouse ? 0.26 : 0.18))
        opacity: root.available ? 1 : 0.6

        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
            width: thumb.x + thumb.width
            height: parent.height
            radius: height / 2
            color: Qt.rgba(Tokens.text_primary.r, Tokens.text_primary.g, Tokens.text_primary.b, 0.76)
        }

        Rectangle {
            visible: root.maximum > 1
            x: 12 + Math.max(0, parent.width - 24) / root.maximum - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 10
            radius: 1
            color: root.displayedValue >= 1 / root.maximum
                ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.64)
                : Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
        }

        Rectangle {
            id: thumb
            x: Math.max(0, parent.width - width) * root.displayedValue
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: Tokens.text_primary
            scale: pointer.pressed ? 0.92 : 1

            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
        }

        Text {
            x: 4
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            color: Tokens.surface
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            enabled: root.available
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            property real dragValue: 0
            property var pressedDevice: null

            Connections {
                target: root
                function onDeviceChanged(): void { pointer.pressedDevice = undefined; }
            }

            function setFromX(x) {
                dragValue = Math.max(0, Math.min(1, (x - 12) / Math.max(1, width - 24)));
                if (!root.commitOnRelease && pressedDevice === root.device)
                    root.valueRequested(dragValue * root.maximum);
            }

            onPressed: (mouse) => {
                pressedDevice = root.device;
                root.forceActiveFocus();
                setFromX(mouse.x);
            }
            onReleased: (mouse) => {
                if (root.commitOnRelease && pressedDevice === root.device) {
                    setFromX(mouse.x);
                    root.valueRequested(dragValue * root.maximum);
                }
            }
            onPositionChanged: (mouse) => {
                if (pressed) setFromX(mouse.x);
            }
        }
    }

    readonly property real normalizedValue: !isFinite(root.value) || root.maximum <= 0
        ? 0 : Math.max(0, Math.min(1, root.value / root.maximum))

    property real displayedValue: pointer.pressed ? pointer.dragValue : root.normalizedValue
    Behavior on displayedValue {
        enabled: !pointer.pressed
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    function adjust(delta: real): void {
        if (root.available) root.valueRequested(Math.max(0, Math.min(root.maximum, root.value + delta)));
    }

    Keys.onPressed: function(event) {
        if (!root.available) return;
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            root.adjust(-root.step);
            break;
        case Qt.Key_Right:
        case Qt.Key_Up:
            root.adjust(root.step);
            break;
        case Qt.Key_Home:
            root.valueRequested(0);
            break;
        case Qt.Key_End:
            root.valueRequested(root.maximum);
            break;
        default:
            return;
        }
        event.accepted = true;
    }
}
