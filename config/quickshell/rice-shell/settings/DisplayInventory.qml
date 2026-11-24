pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "Registry.js" as Registry

ColumnLayout {
    id: root
    required property var monitors
    property string selectedOutput: ""
    readonly property var layouts: Registry.displayLayouts(monitors)
    readonly property var selected: layouts.find(entry => entry.output.name === selectedOutput) || layouts[0]
    readonly property var display: selected?.output
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    readonly property color accentSurface: Qt.tint(Tokens.surface,
        Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15))
    signal refreshRequested()
    spacing: 12

    Rectangle {
        id: map
        Layout.fillWidth: true
        Layout.preferredHeight: 156
        visible: root.layouts.length > 0
        color: Tokens.surface
        radius: 12
        border.color: Tokens.outline
        clip: true

        readonly property real leftEdge: root.layouts.length ? Math.min(...root.layouts.map(entry => entry.x)) : 0
        readonly property real topEdge: root.layouts.length ? Math.min(...root.layouts.map(entry => entry.y)) : 0
        readonly property real layoutWidth: root.layouts.length
            ? Math.max(...root.layouts.map(entry => entry.x + entry.w)) - leftEdge : 1
        readonly property real layoutHeight: root.layouts.length
            ? Math.max(...root.layouts.map(entry => entry.y + entry.h)) - topEdge : 1
        readonly property real zoom: Math.max(0, Math.min((width - 30) / layoutWidth, (height - 28) / layoutHeight))
        readonly property real insetX: (width - layoutWidth * zoom) / 2
        readonly property real insetY: (height - layoutHeight * zoom) / 2

        Repeater {
            model: root.layouts
            delegate: Button {
                id: output
                required property var modelData
                readonly property bool selected: root.selected?.output.name === modelData.output.name
                x: map.insetX + (modelData.x - map.leftEdge) * map.zoom
                y: map.insetY + (modelData.y - map.topEdge) * map.zoom
                width: Math.max(2, modelData.w * map.zoom - 3)
                height: Math.max(2, modelData.h * map.zoom - 3)
                text: modelData.output.name
                Accessible.name: qsTr("Select display %1").arg(text)
                onClicked: root.selectedOutput = modelData.output.name
                contentItem: Label {
                    text: output.text
                    visible: output.width >= 45 && output.height >= 24
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.weight: output.selected ? Font.DemiBold : Font.Medium
                    color: Registry.readable(Tokens.text_primary, output.selected ? root.accentSurface : Tokens.surface_high, 4.5)
                }
                background: Rectangle {
                    radius: 8
                    color: output.selected ? root.accentSurface : Tokens.surface_high
                    border.width: output.selected || output.visualFocus ? 2 : 1
                    border.color: output.selected || output.visualFocus
                        ? Registry.readable(Tokens.focus_ring, color, 3) : Tokens.outline
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox {
            id: displayPicker
            Layout.fillWidth: true
            visible: root.layouts.length > 0
            Accessible.name: qsTr("Display")
            model: root.layouts.map(entry => entry.output.name)
            currentIndex: root.layouts.indexOf(root.selected)
            onActivated: index => root.selectedOutput = displayPicker.model[index]
        }
        SettingsActionButton { text: qsTr("Refresh"); onClicked: root.refreshRequested() }
    }

    Label {
        Layout.fillWidth: true
        visible: root.layouts.length === 0
        text: qsTr("No displays reported by Hyprland.")
        color: root.ink
        wrapMode: Text.Wrap
    }

    Label {
        Layout.fillWidth: true
        visible: !!root.display
        text: root.display?.description || root.display?.name || ""
        font.weight: Font.DemiBold
        color: root.ink
        wrapMode: Text.Wrap
    }

    GridLayout {
        id: metrics
        Layout.fillWidth: true
        visible: !!root.display
        columns: width >= 460 ? 3 : 2
        columnSpacing: 7
        rowSpacing: 7
        Repeater {
            model: !root.display ? [] : [
                [qsTr("Resolution"), "%1 × %2".arg(root.display.width).arg(root.display.height)],
                [qsTr("Refresh rate"), Number.isFinite(root.display.refreshRate)
                    ? qsTr("%1 Hz").arg(root.display.refreshRate.toFixed(2)) : qsTr("Unknown")],
                [qsTr("Scale"), qsTr("%1%").arg(Math.round(root.display.scale * 1000) / 10)],
                [qsTr("Position"), "%1, %2".arg(root.display.x).arg(root.display.y)],
                [qsTr("Variable refresh rate"), typeof root.display.vrr !== "boolean" ? qsTr("Unknown")
                    : root.display.vrr ? qsTr("On") : qsTr("Off")],
                [qsTr("Orientation"), qsTr("%1°").arg((root.display.transform & 3) * 90)]
            ]
            delegate: Rectangle {
                id: metric
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: metricContent.implicitHeight + 16
                radius: 9
                color: Tokens.surface
                border.color: Tokens.outline
                ColumnLayout {
                    id: metricContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 9
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Label {
                        Layout.fillWidth: true
                        text: metric.modelData[0]
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        color: Registry.readable(Tokens.text_secondary, Tokens.surface, 4.5)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: metric.modelData[1]
                        font.weight: Font.DemiBold
                        color: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    Label {
        visible: !!root.display
        Layout.fillWidth: true
        text: qsTr("Supported modes")
        font.weight: Font.DemiBold
        color: root.ink
    }
    Repeater {
        model: root.display ? Array.from(root.display.availableModes || []) : []
        delegate: RowLayout {
            id: mode
            required property string modelData
            Layout.fillWidth: true
            Layout.minimumHeight: 30
            readonly property bool current: Registry.activeDisplayMode(root.display, modelData)
            Label { Layout.fillWidth: true; text: mode.modelData; wrapMode: Text.Wrap; color: root.ink }
            Label {
                visible: mode.current
                text: qsTr("Active")
                color: Registry.readable(Tokens.accent, Tokens.surface_low, 4.5)
            }
        }
    }

    DisplayPreview {
        Layout.fillWidth: true
        output: root.display
        onChanged: root.refreshRequested()
    }
}
