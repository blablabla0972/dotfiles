pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: osdWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false
    implicitWidth: 240
    implicitHeight: 64

    anchors {
        bottom: true
        bottomMargin: 60
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: osdWindow.visible ? osdCard : null
    }

    property string iconText: "󰕾"
    property real progressValue: 0.5

    function showOsd(icon, val): void {
        iconText = icon;
        progressValue = Math.max(0, Math.min(1, val));
        visible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: osdWindow.visible = false
    }

    Connections {
        target: Audio
        function onOsdRequested(icon: string, progress: real): void {
            osdWindow.showOsd(icon, progress);
        }
    }

    Rectangle {
        id: osdCard
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.92)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Text {
                text: osdWindow.iconText
                font.pixelSize: 18
                color: Tokens.accent
            }

            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)

                Rectangle {
                    height: parent.height
                    width: parent.width * osdWindow.progressValue
                    radius: 4
                    color: Tokens.accent
                }
            }
        }
    }
}
