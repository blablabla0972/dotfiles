pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

Rectangle {
    id: preview
    required property var workspace
    required property var strip
    required property bool live
    required property var dropRect
    readonly property rect viewport: Qt.rect(dragViewport.x, dragViewport.y, dragViewport.width, dragViewport.height)
    property string capturedFrame: ""
    readonly property point dragPosition: mapFromItem(null,
        strip.dragPointer.x - (strip.targetMonitor?.x ?? 0),
        strip.dragPointer.y - (strip.targetMonitor?.y ?? 0))
    readonly property var monitor: workspace?.monitor ?? preview.strip.targetMonitor
    readonly property var output: monitor?.lastIpcObject
    readonly property real outputWidth: (output?.width ?? preview.strip.targetScreen.width) / (output?.scale ?? 1)
    readonly property real outputHeight: (output?.height ?? preview.strip.targetScreen.height) / (output?.scale ?? 1)
    readonly property real ratio: Math.min(width / Math.max(1, outputWidth), height / Math.max(1, outputHeight))
    readonly property real insetX: (width - outputWidth * ratio) / 2
    readonly property real insetY: (height - outputHeight * ratio) / 2
    radius: 5
    color: Tokens.background
    clip: true

    onLiveChanged: if (!live) capturedFrame = "";

    Process {
        command: [Quickshell.shellDir + "/../../../build/cod29_workspace_capture", preview.workspace?.name ?? ""]
        running: preview.visible && preview.live && !!preview.workspace
        stdout: SplitParser {
            onRead: data => {
                if (preview.live && data.length > 0)
                    preview.capturedFrame = "data:image/x-portable-pixmap;base64," + data;
            }
        }
    }

    Image {
        id: workspaceImage
        anchors.fill: parent
        source: preview.capturedFrame
        fillMode: Image.PreserveAspectFit
        cache: false
        visible: preview.live && status === Image.Ready
        z: 1
    }

    Image {
        x: preview.insetX
        y: preview.insetY
        width: preview.outputWidth * preview.ratio
        height: preview.outputHeight * preview.ratio
        source: preview.strip.wallpapers[preview.monitor?.name ?? preview.strip.targetScreen.name] ?? ""
        sourceSize.width: Math.ceil(width)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    Repeater {
        model: preview.visible && !workspaceImage.visible ? preview.workspace?.toplevels ?? null : null

        delegate: WindowThumbnail {
            required property var modelData
            toplevel: modelData
            live: preview.live
            visible: client?.mapped === true && !client.hidden && modelData !== preview.strip.draggedWindow
            x: preview.insetX + ((client?.at?.[0] ?? 0) - (preview.monitor?.x ?? 0)) * preview.ratio
            y: preview.insetY + ((client?.at?.[1] ?? 0) - (preview.monitor?.y ?? 0)) * preview.ratio
            width: (client?.size?.[0] ?? 0) * preview.ratio
            height: (client?.size?.[1] ?? 0) * preview.ratio
        }
    }

    Item {
        id: dragViewport
        x: preview.insetX
        y: preview.insetY
        width: preview.outputWidth * preview.ratio
        height: preview.outputHeight * preview.ratio
        clip: true
        z: 2

        WindowThumbnail {
            toplevel: preview.strip.draggedWindow
            live: true
            visible: preview.live && !!toplevel
            readonly property real windowWidth: Math.max(1, client?.size?.[0] ?? 520)
            readonly property real windowHeight: Math.max(1, client?.size?.[1] ?? 320)
            readonly property real windowScale: Math.min(preview.ratio,
                dragViewport.width * .48 / windowWidth, dragViewport.height * .52 / windowHeight)
            width: preview.dropRect ? preview.dropRect.width * preview.ratio : windowWidth * windowScale
            height: preview.dropRect ? preview.dropRect.height * preview.ratio : windowHeight * windowScale
            x: preview.dropRect ? (preview.dropRect.x - (preview.monitor?.x ?? 0)) * preview.ratio
                                : preview.dragPosition.x - dragViewport.x - width * preview.strip.dragAnchor.x
            y: preview.dropRect ? (preview.dropRect.y - (preview.monitor?.y ?? 0)) * preview.ratio
                                : preview.dragPosition.y - dragViewport.y - height * preview.strip.dragAnchor.y
            border.color: Tokens.accent
            border.width: 2
        }
    }
}
