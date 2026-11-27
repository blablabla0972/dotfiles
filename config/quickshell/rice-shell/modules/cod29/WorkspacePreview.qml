pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"

Rectangle {
    id: preview
    required property var workspace
    required property var strip
    readonly property rect viewport: Qt.rect(insetX, insetY, outputWidth * ratio, outputHeight * ratio)
    readonly property var monitor: workspace?.monitor ?? preview.strip.targetMonitor
    readonly property var output: monitor?.lastIpcObject
    readonly property bool rotated: ((output?.transform ?? 0) % 2) !== 0
    readonly property real outputWidth: Math.max(1, (output ? (rotated ? output.height : output.width) / Math.max(0.01, output.scale) : preview.strip.targetScreen?.width) ?? 1)
    readonly property real outputHeight: Math.max(1, (output ? (rotated ? output.width : output.height) / Math.max(0.01, output.scale) : preview.strip.targetScreen?.height) ?? 1)
    readonly property real ratio: Math.min(width / Math.max(1, outputWidth), height / Math.max(1, outputHeight))
    readonly property real insetX: (width - outputWidth * ratio) / 2
    readonly property real insetY: (height - outputHeight * ratio) / 2
    radius: 5
    color: Tokens.background
    clip: true
}
