pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "Registry.js" as Registry

Button {
    id: action
    property bool primary: false
    property string iconName
    readonly property color ink: Registry.readable(primary && enabled ? Tokens.on_accent : Tokens.text_primary,
        actionFill.color, 4.5)
    readonly property color outlineColor: Qt.tint(Tokens.surface_low,
        Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.58))
    implicitHeight: 42
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true
    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        RowLayout {
            id: content
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width)
            spacing: 7
            opacity: action.enabled ? 1 : 0.6

            SettingsIcon {
                visible: action.iconName.length > 0
                name: action.iconName
                color: action.ink
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
            }
            Label {
                Layout.fillWidth: true
                text: action.text
                elide: Text.ElideRight
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: action.ink
            }
        }
    }
    background: Rectangle {
        id: actionFill
        radius: 8
        color: action.primary && action.enabled
            ? Qt.tint(Tokens.accent, Qt.alpha(Tokens.on_accent, action.down ? 0.18 : action.hovered ? 0.08 : 0))
            : action.down ? Tokens.surface_low : action.hovered ? Tokens.surface_high : Tokens.surface
        border.width: action.visualFocus ? 2 : 1
        border.color: action.visualFocus ? Registry.readable(Tokens.focus_ring, color, 3) : action.outlineColor
    }
}
