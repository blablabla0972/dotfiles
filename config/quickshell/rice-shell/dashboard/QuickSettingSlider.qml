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
    property bool available: true
    property real step: 0.05

    signal valueRequested(real value)

    implicitHeight: 44
    activeFocusOnTab: root.available

    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.available ? root.valueText : qsTr("Unavailable")

    Column {
        anchors.fill: parent
        spacing: 3

        Row {
            width: parent.width
            height: 16
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                font.pixelSize: 14
                color: root.available ? Tokens.accent : Tokens.text_secondary
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.available ? Tokens.text_primary : Tokens.text_secondary
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                font.pixelSize: 11
                color: Tokens.text_secondary
                visible: root.valueText.length > 0
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.valueText
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.available ? Tokens.accent : Tokens.text_secondary
            }
        }

        Item {
            id: sliderTrack
            width: parent.width
            height: 22
            opacity: root.available ? 1 : 0.48

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: 2
                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.45)
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(parent.width, parent.width * root.normalizedValue))
                height: 4
                radius: 2
                color: root.available ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.86)
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)
            }

            Rectangle {
                visible: root.maximum > 1
                x: parent.width / root.maximum - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 10
                radius: 1
                color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
            }

            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * root.normalizedValue - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: root.activeFocus ? Tokens.focus_ring : (root.available ? Tokens.accent : Tokens.text_secondary)
                border.width: 2
                border.color: Tokens.surface_high
            }

            Rectangle {
                anchors.fill: parent
                radius: 9
                color: "transparent"
                border.width: root.activeFocus ? 1 : 0
                border.color: Tokens.focus_ring
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.available
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                function setFromX(x) {
                    var fraction = Math.max(0, Math.min(1, x / width));
                    root.valueRequested(fraction * root.maximum);
                }

                onPressed: (mouse) => setFromX(mouse.x)
                onPositionChanged: (mouse) => {
                    if (pressed) setFromX(mouse.x);
                }
            }
        }
    }

    readonly property real normalizedValue: !isFinite(root.value) || root.maximum <= 0
        ? 0 : Math.max(0, Math.min(1, root.value / root.maximum))

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
