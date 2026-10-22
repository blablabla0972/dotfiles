import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Qt.labs.folderlistmodel

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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property bool closing: false
    property string pendingWallpaper: ""
    readonly property real rowWidth: Math.min(width, 1920)
    readonly property real rowLeft: (width - rowWidth) / 2
    readonly property real selectedWidth: rowWidth * 0.40
    readonly property real sideWidth: rowWidth * 0.22
    readonly property real selectedHeight: Math.min(height * 0.44, 480)
    readonly property real sideHeight: selectedHeight * 0.92

    // Đóng Quickshell với hoạt ảnh mượt mà
    function closeShell() {
        if (closing) return;
        closing = true;
        enterAnimation.stop();
        exitAnimation.start();
    }

    // Áp dụng hình nền an toàn qua helper script (tránh command injection và tranh chấp tiến trình)
    function applyCurrent() {
        if (closing || displayModel.count === 0) return;
        var item = displayModel.get(carousel.currentIndex);
        if (!item || !item.filePath) return;

        closing = true;
        pendingWallpaper = item.filePath;
        enterAnimation.stop();
        exitAnimation.start();
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
        displayModel.clear();
        var n = folderModel.count;
        if (n === 0) return;

        var requiredItems = 7;
        var repeatCount = n < requiredItems ? Math.ceil(requiredItems / n) : 1;
        var cacheRoot = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        var thumbBase = "file://" + cacheRoot + "/wallpaper-switcher-thumbs-v2/";

        for (var r = 0; r < repeatCount; ++r) {
            for (var i = 0; i < n; ++i) {
                var name = folderModel.get(i, "fileName");
                displayModel.append({
                    "fileName": name,
                    "filePath": folderModel.get(i, "filePath"),
                    "fileUrl": folderModel.get(i, "fileUrl"),
                    "thumbUrl": thumbBase + encodeURIComponent(name) + ".jpg",
                    "originalIndex": i
                });
            }
        }
    }

    // Bấm ra ngoài vùng trống để đóng với lớp phủ mờ nhẹ
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.closeShell()

        Rectangle {
            anchors.fill: parent
            color: "#66000000"
            opacity: contentContainer.opacity
        }
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

            delegate: Item {
                id: cardItem
                width: PathView.itemWidth !== undefined ? PathView.itemWidth : root.sideWidth
                height: PathView.itemHeight !== undefined ? PathView.itemHeight : root.sideHeight
                z: PathView.itemZ !== undefined ? PathView.itemZ : 0
                opacity: PathView.itemOpacity !== undefined ? PathView.itemOpacity : 1
                readonly property real slant: height * 0.34
                readonly property bool selected: PathView.isCurrentItem

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
                    layer.enabled: true
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
                    source: cardImg
                    maskEnabled: true
                    maskSource: cardMask
                    autoPaddingEnabled: false
                }

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: cardItem.selected ? 3 : 2
                        strokeColor: cardItem.selected ? "#72d9b3" : "#557267"
                        fillColor: cardItem.selected ? "transparent" : "#4208120d"
                        joinStyle: ShapePath.MiterJoin
                        startX: cardItem.slant + 1.5; startY: 1.5
                        PathLine { x: cardItem.width - 1.5; y: 1.5 }
                        PathLine { x: cardItem.width - cardItem.slant - 1.5; y: cardItem.height - 1.5 }
                        PathLine { x: 1.5; y: cardItem.height - 1.5 }
                        PathLine { x: cardItem.slant + 1.5; y: 1.5 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // Let clicks in a card's transparent corners reach cards behind it.
                    onPressed: (mouse) => {
                        var left = cardItem.slant * (1 - mouse.y / cardItem.height);
                        if (mouse.x < left || mouse.x > left + cardItem.width - cardItem.slant)
                            mouse.accepted = false;
                    }
                    onClicked: {
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

        // Thanh chỉ dẫn phím tắt
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36
            anchors.horizontalCenter: parent.horizontalCenter
            width: hintRow.width + 36
            height: 40
            radius: 20
            color: "#ee1b211e"
            border.color: "#338ad6b6"
            border.width: 1

            Row {
                id: hintRow
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "<b>← / →</b> hoặc <b>H / L</b> : Duyệt ảnh"
                    color: "#dee4df"
                    font.pixelSize: 13
                    font.family: "Adwaita Sans"
                }
                Text {
                    text: "•"
                    color: "#5a645e"
                    font.pixelSize: 13
                }
                Text {
                    text: "<b>Enter</b> : Áp dụng"
                    color: "#8ad6b6"
                    font.pixelSize: 13
                    font.family: "Adwaita Sans"
                }
                Text {
                    text: "•"
                    color: "#5a645e"
                    font.pixelSize: 13
                }
                Text {
                    text: "<b>Esc</b> : Thoát"
                    color: "#ffb4ab"
                    font.pixelSize: 13
                    font.family: "Adwaita Sans"
                }
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
        // Sau khi hoàn thành entrance animation mới kích hoạt cập nhật thumbnail ngầm
        onFinished: {
            Quickshell.execDetached([
                Quickshell.shellDir + "/generate-thumbs.sh"
            ]);
        }
    }

    // Hoạt ảnh biến mất (Exit)
    SequentialAnimation {
        id: exitAnimation
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
                // Decode the wallpaper and generate its theme after the exit animation.
                if (root.pendingWallpaper !== "") {
                    Quickshell.execDetached([
                        Quickshell.shellDir + "/apply-wallpaper.sh",
                        root.pendingWallpaper
                    ]);
                }
                Qt.quit();
            }
        }
    }
}
