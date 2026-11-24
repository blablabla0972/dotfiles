pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "Registry.js" as Registry

ComboBox {
    id: combo
    implicitHeight: 42
    leftPadding: 13
    rightPadding: 33
    hoverEnabled: true
    ToolTip.visible: combo.hovered && valueLabel.truncated && !combo.popup.visible
    ToolTip.text: combo.displayText
    ToolTip.delay: 500

    FontMetrics {
        id: metrics
        font.family: combo.font.family
        font.pixelSize: combo.font.pixelSize
        font.weight: Font.DemiBold
    }

    background: Rectangle {
        radius: 10
        color: combo.hovered ? Tokens.surface_high : Tokens.surface
        border.width: combo.visualFocus ? 2 : 1
        border.color: combo.visualFocus ? Registry.readable(Tokens.focus_ring, color, 3) : Tokens.outline
    }

    contentItem: Label {
        id: valueLabel
        text: combo.displayText
        elide: Text.ElideMiddle
        verticalAlignment: Text.AlignVCenter
        color: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)
        opacity: combo.enabled ? 1 : 0.55
    }

    indicator: SettingsIcon {
        x: combo.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        name: "down"
        color: Registry.readable(Tokens.text_secondary, Tokens.surface, 4.5)
    }

    delegate: ItemDelegate {
        id: option
        required property int index
        readonly property bool selected: combo.currentIndex === index
        width: combo.popup.availableWidth
        height: 38
        text: combo.textAt(index)
        highlighted: combo.highlightedIndex === index
        hoverEnabled: true
        Accessible.selected: selected
        background: Rectangle {
            id: optionFill
            radius: 6
            color: option.highlighted || option.hovered ? Tokens.surface_high
                : option.selected ? Qt.tint(Tokens.surface_low, Qt.alpha(Tokens.accent, 0.16)) : "transparent"
        }
        contentItem: RowLayout {
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: option.text
                font.family: combo.font.family
                font.pixelSize: combo.font.pixelSize
                elide: Text.ElideMiddle
                font.weight: option.selected ? Font.DemiBold : Font.Normal
                color: Registry.readable(option.selected ? Tokens.accent : Tokens.text_primary,
                    optionFill.color.a > 0 ? optionFill.color : Tokens.surface_low, 4.5)
            }
            SettingsIcon {
                opacity: option.selected ? 1 : 0
                name: "check"
                color: Registry.readable(Tokens.accent, Tokens.surface_high, 3)
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
            }
        }
    }

    popup: Popup {
        id: menu
        property real optionWidth: 0
        x: combo.width - width
        y: combo.height + 4
        width: Math.max(combo.width, Math.min(520, optionWidth, (combo.Window.window?.width ?? 552) - 32))
        padding: 5
        onAboutToShow: {
            let longest = 0;
            for (let index = 0; index < combo.count; index++)
                longest = Math.max(longest, metrics.advanceWidth(combo.textAt(index)));
            optionWidth = Math.ceil(longest + 62);
        }
        background: Rectangle {
            radius: 12
            color: Tokens.surface_low
            border.color: Tokens.outline
        }
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 268)
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
