import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt.labs.folderlistmodel
import "ApplyState.js" as ApplyState

PanelWindow {
    id: root
    visible: true
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool closing: false
    property var applyState: ApplyState.create(Date.now().toString(36) + "-" + Math.random().toString(36).slice(2))
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    property string themeMode: "dark"
    property var paletteData: ({})
    property string adaptiveText: ""
    property int paletteGeneration: 0
    property string nativePaletteRevision: ""
    property bool paletteHashWanted: false
    readonly property var adaptivePalette: ApplyState.adaptivePalette(adaptiveText, themeMode, nativePaletteRevision)
    readonly property var palette: adaptivePalette || paletteData[themeMode] || ({})
    readonly property real panelOpacity: adaptivePalette ? adaptivePalette.panelOpacity : 1
    property var previewState: ApplyState.createPreview(Date.now().toString(36) + "-preview-" + Math.random().toString(36).slice(2))
    readonly property var previewSwatches: previewState.phase === "ready" ? previewState.swatches
        : [palette.mPrimary || "transparent", palette.mOnPrimary || "transparent",
           palette.mSurfaceVariant || "transparent", palette.mSurface || "transparent", palette.mOnSurface || "transparent"]
    onThemeModeChanged: schedulePreview()

    function invalidatePaletteRevision() {
        paletteGeneration += 1;
        nativePaletteRevision = "";
        paletteHashWanted = false;
    }

    function loadPalette() {
        invalidatePaletteRevision();
        try {
            var next = JSON.parse(paletteFile.text());
            for (var mode of ["dark", "light"])
                for (var role of ["mPrimary", "mOutline", "mSurfaceVariant"])
                    if (!next[mode] || !/^#[0-9a-fA-F]{6}$/.test(next[mode][role]))
                        return;
            paletteData = next;
            paletteHashWanted = true;
            Qt.callLater(pumpPaletteHash);
        } catch (error) {
            // Keep the last complete palette during atomic updates.
        }
    }

    FileView {
        id: paletteFile
        path: root.configHome + "/noctalia/palettes/matugen.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadPalette()
        onLoadFailed: root.invalidatePaletteRevision()
        onFileChanged: {
            root.invalidatePaletteRevision();
            reload();
            if (!modeQuery.running) modeQuery.running = true;
        }
    }

    function pumpPaletteHash() {
        if (!paletteHashWanted || paletteHash.running || paletteHash.generation === paletteGeneration
                || (paletteHash.generation >= 0 && (!paletteHash.outputReady || paletteHash.resultCode < 0))) return;
        paletteHash.generation = paletteGeneration;
        paletteHash.outputReady = false;
        paletteHash.resultCode = -1;
        paletteHash.command = ["sha256sum", "--zero", "--", paletteFile.path];
        paletteHash.running = true;
    }

    function finishPaletteHash() {
        if (!paletteHash.outputReady || paletteHash.resultCode < 0) return;
        var revision = ApplyState.paletteRevision(paletteGeneration, paletteHash.generation,
            paletteHash.output, paletteHash.resultCode, paletteHash.resultStatus);
        if (revision) nativePaletteRevision = revision;
        Qt.callLater(pumpPaletteHash);
    }

    // Hash the actual file bytes once per loaded generation, never the parsed object.
    Process {
        id: paletteHash
        property int generation: -1
        property bool outputReady: false
        property string output: ""
        property int resultCode: -1
        property int resultStatus: -1
        stdout: StdioCollector {
            onStreamFinished: {
                paletteHash.output = text;
                paletteHash.outputReady = true;
                root.finishPaletteHash();
            }
        }
        onExited: (exitCode, exitStatus) => {
            resultCode = exitCode;
            resultStatus = exitStatus;
            root.finishPaletteHash();
        }
    }

    // Optional, read-only transaction output; invalid or mismatched modes use native colors.
    FileView {
        id: adaptiveFile
        path: root.stateHome + "/desktop-wallpaper/adaptive-theme.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.adaptiveText = text()
        onLoadFailed: root.adaptiveText = ""
        onFileChanged: {
            root.adaptiveText = "";
            reload();
        }
    }

    Process {
        id: modeQuery
        command: ["noctalia", "msg", "theme-mode-get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var mode = text.trim();
                if (mode === "dark" || mode === "light") root.themeMode = mode;
            }
        }
    }
    readonly property real rowWidth: Math.min(width, 1920)
    readonly property real rowLeft: (width - rowWidth) / 2
    readonly property real selectedWidth: rowWidth * 0.40
    readonly property real sideWidth: rowWidth * 0.22
    readonly property real selectedHeight: Math.min(height * 0.44, 480)
    readonly property real sideHeight: selectedHeight * 0.92

    function transition(event) {
        applyState = ApplyState.reduce(applyState, event);
        if (event.type === "select") schedulePreview();
        Qt.callLater(pumpApply);
    }

    function schedulePreview() {
        if (closing || !previewState) return;
        previewState = ApplyState.selectPreview(previewState, applyState.selection, themeMode);
        previewDebounce.restart();
    }

    function pumpPreview() {
        if (closing || previewDebounce.running || previewState.phase !== "pending"
                || previewProcess.running || previewProcess.requestId === previewState.requestId
                || (previewProcess.requestId && (!previewProcess.outputReady || previewProcess.resultCode < 0))) return;
        previewProcess.requestId = previewState.requestId;
        previewProcess.outputReady = false;
        previewProcess.resultCode = -1;
        previewProcess.didStart = false;
        previewProcess.command = ["python3", Quickshell.shellDir + "/preview-palette.py",
            "--request-id", previewState.requestId, "--mode", previewState.mode, previewState.wallpaper];
        previewProcess.running = true;
        previewStartWatch.restart();
    }

    function finishPreview() {
        if (!previewProcess.outputReady || previewProcess.resultCode < 0) return;
        previewState = ApplyState.finishPreview(previewState, previewProcess.requestId,
            previewProcess.output, previewProcess.resultCode, previewProcess.resultStatus);
        Qt.callLater(pumpPreview);
        Qt.callLater(pumpApply);
    }

    Timer {
        id: previewDebounce
        interval: 150
        onTriggered: root.pumpPreview()
    }

    Timer {
        id: previewStartWatch
        interval: 1000
        onTriggered: {
            if (!previewProcess.didStart && !previewProcess.running) {
                previewProcess.output = "";
                previewProcess.outputReady = true;
                previewProcess.resultCode = 127;
                previewProcess.resultStatus = 0;
                root.finishPreview();
            }
        }
    }

    Process {
        id: previewProcess
        property string requestId: ""
        property bool didStart: false
        property bool outputReady: false
        property string output: ""
        property int resultCode: -1
        property int resultStatus: -1
        onStarted: didStart = true
        stdout: StdioCollector {
            onStreamFinished: {
                previewProcess.output = text;
                previewProcess.outputReady = true;
                root.finishPreview();
            }
        }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            resultCode = exitCode;
            resultStatus = exitStatus;
            root.finishPreview();
        }
    }

    function pumpApply() {
        var active = applyState.active;
        if (!active) {
            ackTimeout.stop();
            startWatch.stop();
            if (applyState.closed && !visible && !previewProcess.running) Qt.quit();
            return;
        }
        if (applyProcess.running || applyProcess.requestId === active.requestId) return;
        applyProcess.requestId = active.requestId;
        applyProcess.didStart = false;
        applyProcess.command = ["bash", Quickshell.shellDir + "/apply-wallpaper.sh",
            "--request-id", active.requestId, active.wallpaper];
        applyProcess.running = true;
        startWatch.restart();
        ackTimeout.restart();
    }

    // Keep this object alive when Esc hides the window: destroying it would kill the transaction.
    Process {
        id: applyProcess
        property string requestId: ""
        property bool didStart: false
        onStarted: didStart = true
        stdout: StdioCollector {
            onStreamFinished: root.transition({type: "stdout", requestId: applyProcess.requestId, text: text})
        }
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.warn(text.trim()); }
        }
        onExited: (exitCode, exitStatus) => root.transition({type: "exit",
            requestId: requestId, code: exitCode, exitStatus: exitStatus})
        onRunningChanged: { if (!running) Qt.callLater(root.pumpApply); }
    }

    Timer {
        id: startWatch
        interval: 1000
        onTriggered: {
            if (!applyProcess.didStart && !applyProcess.running)
                root.transition({type: "launch_failed", requestId: applyProcess.requestId});
        }
    }

    Timer {
        id: ackTimeout
        interval: 30000
        onTriggered: root.transition({type: "timeout", requestId: applyProcess.requestId})
    }

    function statusText() {
        var state = applyState;
        if (state.active) {
            var name = state.active.wallpaper.split("/").pop();
            var pending = state.phase === "unknown" ? "Outcome unknown; still waiting: " : "Applying: ";
            return pending + name + (state.queued ? " · Next: " + state.queued.split("/").pop() : "") + " · Esc hides";
        }
        if (state.phase === "applied") return "Applied: " + state.applied.split("/").pop();
        if (state.phase === "failed" || state.phase === "rolled_back")
            return (state.phase === "rolled_back" ? "Rolled back" : "Apply failed") + ": " + (state.error || "transaction_failed") + " · Enter to retry";
        if (state.phase === "unknown") return "Outcome unknown · Enter to retry · Esc closes";
        return displayModel.count ? "← / → · H / L · Scroll to select · Enter / Space to apply · Esc closes" : "No wallpapers found · Esc closes";
    }

    // Đóng Quickshell với hoạt ảnh mượt mà
    function closeShell() {
        if (closing) return;
        closing = true;
        previewDebounce.stop();
        transition({type: "close"});
        enterAnimation.stop();
        exitAnimation.start();
    }

    // Navigation is independent of the active transaction; only explicit applies queue work.
    function applyCurrent() {
        if (closing || displayModel.count === 0) return;
        var item = displayModel.get(carousel.currentIndex);
        if (!item || !item.filePath) return;

        transition({type: "request", wallpaper: item.filePath});
    }

    // Đọc ảnh từ thư mục ~/Ảnh/Wallpaper
    FolderListModel {
        id: folderModel
        folder: "file://" + Quickshell.env("HOME") + "/Ảnh/Wallpaper"
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        caseSensitive: false
        showDirs: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name

        onCountChanged: rebuildTimer.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                rebuildTimer.restart();
        }
    }

    // Debounce rebuild model tránh giật lag khi đang quét thư mục
    Timer {
        id: rebuildTimer
        interval: 80
        repeat: false
        onTriggered: root.updateDisplayModel()
    }

    ListModel {
        id: displayModel
    }

    function updateDisplayModel() {
        var selectedPath = applyState.selection;
        displayModel.clear();
        var n = folderModel.count;
        if (n === 0) {
            transition({type: "select", wallpaper: ""});
            return;
        }

        var requiredItems = 7;
        var repeatCount = n < requiredItems ? Math.ceil(requiredItems / n) : 1;
        var cacheRoot = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        var thumbBase = "file://" + cacheRoot + "/wallpaper-switcher-thumbs-v3/";

        for (var r = 0; r < repeatCount; ++r) {
            for (var i = 0; i < n; ++i) {
                var name = folderModel.get(i, "fileName");
                displayModel.append({
                    "fileName": name,
                    "filePath": folderModel.get(i, "filePath"),
                    "fileUrl": folderModel.get(i, "fileUrl"),
                    "thumbUrl": thumbBase + Qt.md5(name) + ".jpg",
                    "originalIndex": i
                });
            }
        }
        for (var index = 0; index < displayModel.count; ++index) {
            if (displayModel.get(index).filePath === selectedPath) {
                carousel.currentIndex = index;
                break;
            }
        }
        syncSelection();
    }

    function syncSelection() {
        var item = displayModel.get(carousel.currentIndex);
        transition({type: "select", wallpaper: item ? item.filePath : ""});
    }

    // Bấm ra ngoài vùng trống để đóng
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.closeShell()
    }

    // Khung chứa nội dung chính với hiệu ứng hiển thị mượt mà trên Render Thread
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: 0.0
        scale: 0.95
        focus: true

        // Khóa input khi đang đóng
        Keys.enabled: !root.closing
        Keys.onLeftPressed: (event) => { carousel.decrementCurrentIndex(); event.accepted = true; }
        Keys.onRightPressed: (event) => { carousel.incrementCurrentIndex(); event.accepted = true; }
        Keys.onReturnPressed: (event) => { root.applyCurrent(); event.accepted = true; }
        Keys.onEnterPressed: (event) => { root.applyCurrent(); event.accepted = true; }
        Keys.onSpacePressed: (event) => { root.applyCurrent(); event.accepted = true; }
        Keys.onEscapePressed: (event) => { root.closeShell(); event.accepted = true; }

        // Hỗ trợ phím tắt Vim (h/l)
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_H) {
                carousel.decrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                carousel.incrementCurrentIndex();
                event.accepted = true;
            }
        }

        WheelHandler {
            enabled: !root.closing && displayModel.count > 1
            onWheel: (event) => {
                if (event.angleDelta.y < 0 || event.angleDelta.x < 0) {
                    carousel.incrementCurrentIndex();
                } else if (event.angleDelta.y > 0 || event.angleDelta.x > 0) {
                    carousel.decrementCurrentIndex();
                }
                event.accepted = true;
            }
        }

        Component.onCompleted: {
            contentContainer.forceActiveFocus();
            enterAnimation.start();
        }

        // A flat slanted ribbon, with a broad selected card like the reference.
        PathView {
            id: carousel
            anchors.fill: parent
            model: displayModel
            pathItemCount: Math.min(7, displayModel.count)
            cacheItemCount: displayModel.count > 7 ? 1 : 0
            snapMode: PathView.SnapOneItem
            maximumFlickVelocity: 1800
            flickDeceleration: 4500
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 240
            interactive: !root.closing
            onCurrentIndexChanged: root.syncSelection()

            delegate: Item {
                id: cardItem
                width: PathView.itemWidth !== undefined ? PathView.itemWidth : root.sideWidth
                height: PathView.itemHeight !== undefined ? PathView.itemHeight : root.sideHeight
                z: PathView.itemZ !== undefined ? PathView.itemZ : 0
                opacity: PathView.itemOpacity !== undefined ? PathView.itemOpacity : 1
                readonly property real slant: height * 0.34
                readonly property bool selected: PathView.isCurrentItem
                readonly property bool effectsActive: root.visible && contentContainer.visible && PathView.onPath && opacity > 0

                Image {
                    id: cardImg
                    anchors.fill: parent
                    source: thumbUrl
                    sourceSize: Qt.size(Math.ceil(root.selectedWidth * (Screen.devicePixelRatio || 1)),
                                        Math.ceil(root.selectedHeight * (Screen.devicePixelRatio || 1)))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    retainWhileLoading: true
                    visible: false
                    onStatusChanged: {
                        if (status === Image.Error && source !== fileUrl) source = fileUrl;
                    }
                }

                // Clip the frame, not the image: straight features stay undistorted.
                Shape {
                    id: cardMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: cardItem.effectsActive
                    layer.smooth: true
                    ShapePath {
                        strokeWidth: 0
                        fillColor: "white"
                        startX: cardItem.slant; startY: 0
                        PathLine { x: cardItem.width; y: 0 }
                        PathLine { x: cardItem.width - cardItem.slant; y: cardItem.height }
                        PathLine { x: 0; y: cardItem.height }
                        PathLine { x: cardItem.slant; y: 0 }
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: cardItem.effectsActive
                    source: cardItem.effectsActive ? cardImg : null
                    maskEnabled: cardItem.effectsActive
                    maskSource: cardItem.effectsActive ? cardMask : null
                    autoPaddingEnabled: false
                }

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: cardItem.selected ? 3 : 2
                        strokeColor: cardItem.selected ? (root.palette.mFocusRing || root.palette.mPrimary || "transparent") : (root.palette.mOutline || "transparent")
                        fillColor: cardItem.selected || !root.palette.mSurfaceVariant ? "transparent" : Qt.alpha(root.palette.mSurfaceVariant, 0.26)
                        joinStyle: ShapePath.MiterJoin
                        startX: cardItem.slant + 1.5; startY: 1.5
                        PathLine { x: cardItem.width - 1.5; y: 1.5 }
                        PathLine { x: cardItem.width - cardItem.slant - 1.5; y: cardItem.height - 1.5 }
                        PathLine { x: 1.5; y: cardItem.height - 1.5 }
                        PathLine { x: cardItem.slant + 1.5; y: 1.5 }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.applyState.active && root.applyState.active.wallpaper === filePath
                        ? (root.applyState.phase === "unknown" ? "Pending…" : "Applying…")
                        : root.applyState.queued === filePath ? "Queued"
                        : root.applyState.applied === filePath ? "Last confirmed" : ""
                    visible: text !== "" && cardItem.effectsActive
                    color: root.palette.mOnSurface || root.palette.mPrimary || "transparent"
                    style: Text.Outline
                    styleColor: root.palette.mSurface || "transparent"
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.closing
                    cursorShape: Qt.PointingHandCursor
                    // Let clicks in a card's transparent corners reach cards behind it.
                    onPressed: (mouse) => {
                        var left = cardItem.slant * (1 - mouse.y / cardItem.height);
                        if (mouse.x < left || mouse.x > left + cardItem.width - cardItem.slant)
                            mouse.accepted = false;
                    }
                    onClicked: {
                        contentContainer.forceActiveFocus();
                        if (carousel.currentIndex === index) root.applyCurrent();
                        else carousel.currentIndex = index;
                    }
                }
            }

            path: Path {
                startX: root.rowLeft - root.sideWidth
                startY: root.height / 2
                PathAttribute { name: "itemWidth"; value: root.sideWidth }
                PathAttribute { name: "itemHeight"; value: root.sideHeight }
                PathAttribute { name: "itemZ"; value: 0 }
                PathAttribute { name: "itemOpacity"; value: 0 }

                PathLine { x: root.rowLeft + root.rowWidth * 0.04; y: root.height / 2 }
                PathPercent { value: 0.5 - 3 / 7 }
                PathAttribute { name: "itemZ"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }

                PathLine { x: root.rowLeft + root.rowWidth * 0.17; y: root.height / 2 }
                PathPercent { value: 0.5 - 2 / 7 }
                PathAttribute { name: "itemZ"; value: 4 }

                PathLine { x: root.rowLeft + root.rowWidth * 0.30; y: root.height / 2 }
                PathPercent { value: 0.5 - 1 / 7 }
                PathAttribute { name: "itemZ"; value: 8 }
                PathAttribute { name: "itemWidth"; value: root.sideWidth }
                PathAttribute { name: "itemHeight"; value: root.sideHeight }

                PathLine { x: root.width / 2; y: root.height / 2 }
                PathPercent { value: 0.5 }
                PathAttribute { name: "itemZ"; value: 25 }
                PathAttribute { name: "itemWidth"; value: root.selectedWidth }
                PathAttribute { name: "itemHeight"; value: root.selectedHeight }

                PathLine { x: root.rowLeft + root.rowWidth * 0.70; y: root.height / 2 }
                PathPercent { value: 0.5 + 1 / 7 }
                PathAttribute { name: "itemZ"; value: 8 }
                PathAttribute { name: "itemWidth"; value: root.sideWidth }
                PathAttribute { name: "itemHeight"; value: root.sideHeight }

                PathLine { x: root.rowLeft + root.rowWidth * 0.83; y: root.height / 2 }
                PathPercent { value: 0.5 + 2 / 7 }
                PathAttribute { name: "itemZ"; value: 4 }

                PathLine { x: root.rowLeft + root.rowWidth * 0.96; y: root.height / 2 }
                PathPercent { value: 0.5 + 3 / 7 }
                PathAttribute { name: "itemZ"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }

                PathLine { x: root.rowLeft + root.rowWidth + root.sideWidth; y: root.height / 2 }
                PathPercent { value: 1 }
                PathAttribute { name: "itemZ"; value: 0 }
                PathAttribute { name: "itemOpacity"; value: 0 }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(parent.height - height - 24, parent.height / 2 + root.selectedHeight / 2 + 24)
            width: Math.min(parent.width - 32, Math.max(statusLabel.implicitWidth, previewRow.implicitWidth) + 32)
            height: statusLabel.implicitHeight + previewRow.height + 28
            radius: 8
            color: Qt.alpha(root.palette.mSurface || "transparent", root.panelOpacity)
            Row {
                id: previewRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                spacing: 6
                Text {
                    text: root.previewState.phase === "ready" ? "Preview"
                        : root.previewState.phase === "pending" ? "Preview pending · current palette"
                        : root.previewState.phase === "failed" ? "Preview unavailable · current palette" : "Current palette"
                    color: root.palette.mOnSurface || root.palette.mPrimary || "transparent"
                }
                Repeater {
                    model: root.previewSwatches
                    Rectangle {
                        required property string modelData
                        width: 16
                        height: 16
                        radius: 3
                        color: modelData
                        border.width: 1
                        border.color: root.palette.mOutline || "transparent"
                    }
                }
            }
            Text {
                id: statusLabel
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                text: root.statusText()
                color: (root.applyState.phase === "failed" || root.applyState.phase === "rolled_back")
                    ? (root.palette.mError || root.palette.mOnSurface || "transparent")
                    : (root.palette.mOnSurface || root.palette.mPrimary || "transparent")
            }
        }

    }

    // Hoạt ảnh xuất hiện (Entrance)
    ParallelAnimation {
        id: enterAnimation
        OpacityAnimator {
            target: contentContainer
            from: 0.0
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
        ScaleAnimator {
            target: contentContainer
            from: 0.95
            to: 1.0
            duration: 200
            easing.type: Easing.OutBack
            easing.overshoot: 1.05
        }
        // Trì hoãn sinh thumbnail ngầm khi UI đã hoàn toàn ổn định và idle
        onFinished: {
            thumbTimer.restart();
        }
    }

    Timer {
        id: thumbTimer
        interval: 800
        running: false
        repeat: false
        onTriggered: {
            Quickshell.execDetached([
                Quickshell.shellDir + "/generate-thumbs.sh"
            ]);
        }
    }

    // Hoạt ảnh biến mất (Exit)
    SequentialAnimation {
        id: exitAnimation
        onStarted: thumbTimer.stop()
        ParallelAnimation {
            OpacityAnimator {
                target: contentContainer
                to: 0.0
                duration: 150
                easing.type: Easing.InQuad
            }
            ScaleAnimator {
                target: contentContainer
                to: 0.95
                duration: 150
                easing.type: Easing.InQuad
            }
        }
        ScriptAction {
            script: {
                root.visible = false;
                root.pumpApply();
            }
        }
    }
}
