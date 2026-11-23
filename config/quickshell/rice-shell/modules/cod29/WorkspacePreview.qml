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
    readonly property real outputWidth: (output?.width ?? preview.strip.targetScreen?.width ?? 1) / (output?.scale ?? 1)
    readonly property real outputHeight: (output?.height ?? preview.strip.targetScreen?.height ?? 1) / (output?.scale ?? 1)
    readonly property real ratio: Math.min(width / Math.max(1, outputWidth), height / Math.max(1, outputHeight))
    readonly property real insetX: (width - outputWidth * ratio) / 2
    readonly property real insetY: (height - outputHeight * ratio) / 2
    radius: 5
    color: Tokens.background
    clip: true
}
