pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "theme"

ShellRoot {
    id: root

    property var entries: []
    property var preview: ({})
    property string error: ""
    property string confirmation: ""
    property string pasteTarget: ""
    property bool pasteAfterCopy: false
    property string typeFilter: "all"
    property var thumbnails: ({})
    property bool detailsOpen: false
    readonly property string backend: Quickshell.shellPath("clipboard.py")
    readonly property var filtered: {
        const query = search.text.trim().toLocaleLowerCase();
        return entries.filter(entry => {
            if (typeFilter === "image" && entry.kind !== "image") return false;
            if (typeFilter === "text" && entry.kind !== "text" && entry.kind !== "link") return false;
            return entry.searchText.includes(query);
        });
    }
    readonly property var selectedEntry: filtered[history.currentIndex]
    readonly property string selectedId: selectedEntry?.id || ""

    function entryKind(text: string): string {
        if (text.startsWith("[[ binary data "))
            return /\b(png|jpe?g|webp|gif|bmp|svg|tiff?)\b/i.test(text) ? "image" : "binary";
        return /^https?:\/\//i.test(text.trim()) ? "link" : "text";
    }

    onSelectedIdChanged: {
        preview = ({});
        confirmation = "";
        previewTimer.restart();
    }
    onDetailsOpenChanged: {
        if (detailsOpen) previewTimer.restart();
    }

    function result(text: string, forPreview: bool): var {
        let value;
        try {
            value = JSON.parse(text);
        } catch (_) {
            value = { error: "Không đọc được dữ liệu clipboard." };
        }
        if (!value.error || forPreview) return value;
        root.error = value.error;
        return null;
    }

    function refresh(): void {
        if (!listing.running) listing.running = true;
    }

    function moveSelection(step: int): void {
        if (history.count && !confirmation)
            history.currentIndex = Math.max(0, Math.min(history.count - 1, history.currentIndex + step));
    }

    function resetSelection(): void {
        confirmation = "";
        history.currentIndex = filtered.length ? 0 : -1;
        history.positionViewAtBeginning();
    }

    function open(address: string): void {
        pasteTarget = address;
        panel.visible = true;
        refresh();
        search.forceActiveFocus();
    }

    function act(action: string): void {
        if (operation.running || pasteProcess.running || (action !== "wipe" && !selectedId)) return;
        error = "";
        pasteAfterCopy = action === "paste";
        if (pasteAfterCopy) action = "copy";
        operation.action = action;
        operation.command = ["python3", backend, action];
        if (action !== "wipe") operation.command = ["python3", backend, action, selectedId];
        operation.running = true;
    }

    IpcHandler {
        target: "clipboard"
        function close(): void { Qt.quit(); }
    }

    Process {
        id: targetLookup
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.open(root.result(text, false)?.address || "")
        }
    }

    Process {
        id: listing
        command: ["python3", root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data = root.result(text, false);
                if (!data) return;
                const previousId = root.selectedId;
                const previousIndex = history.currentIndex;
                root.entries = data.entries.map(entry => {
                    entry.kind = root.entryKind(entry.preview);
                    entry.metadata = entry.kind === "image" || entry.kind === "binary"
                        ? entry.preview.slice(15, -2).trim().replace(/(\d)x(\d)/, "$1×$2") : "";
                    const label = entry.kind === "image" ? "Ảnh Hình ảnh " : "";
                    entry.searchText = (label + entry.preview + " " + entry.metadata).toLocaleLowerCase();
                    return entry;
                });
                const retained = root.filtered.findIndex(entry => entry.id === previousId);
                history.currentIndex = retained >= 0 ? retained
                    : Math.min(Math.max(0, previousIndex), root.filtered.length - 1);
                previewTimer.restart();
            }
        }
    }

    Timer {
        id: previewTimer
        interval: 80
        onTriggered: {
            if (!root.detailsOpen || !root.selectedId || previewProcess.running) return;
            previewProcess.requestedId = root.selectedId;
            previewProcess.command = ["python3", root.backend, "preview", root.selectedId];
            previewProcess.running = true;
        }
    }

    Process {
        id: previewProcess
        property string requestedId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (previewProcess.requestedId !== root.selectedId) return;
                const data = root.result(text, true);
                if (data.error || data.id === root.selectedId) root.preview = data;
            }
        }
        onExited: { if (requestedId !== root.selectedId) previewTimer.restart(); }
    }

    Process {
        id: operation
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var data = root.result(text, false);
                if (!data || !data.ok) return;
                if (operation.action === "copy") {
                    if (!root.pasteAfterCopy) {
                        Qt.quit();
                        return;
                    }
                    panel.visible = false;
                    pasteProcess.running = true;
                }
                else {
                    if (operation.action === "wipe") root.thumbnails = ({});
                    root.confirmation = "";
                    root.refresh();
                    search.forceActiveFocus();
                }
            }
        }
    }

    Process {
        id: pasteProcess
        command: ["python3", root.backend, "paste", root.pasteTarget]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.result(text, false);
                if (data && data.ok) Qt.quit();
                else {
                    panel.visible = true;
                    search.forceActiveFocus();
                }
            }
        }
    }

    component UiText: Text {
        font.family: "Adwaita Sans"
        color: Tokens.text_primary
    }

    component KeyHint: Row {
        id: hint
        required property string keys
        property string label: ""
        spacing: 6

        Rectangle {
            width: keyText.implicitWidth + 12
            height: 21
            radius: 5
            color: Tokens.surface_low
            border.color: Qt.alpha(Tokens.outline, 0.85)
            UiText {
                id: keyText
                anchors.centerIn: parent
                text: hint.keys
                font.pixelSize: 11
            }
        }
        UiText {
            anchors.verticalCenter: parent.verticalCenter
            visible: hint.label.length > 0
            text: hint.label
            color: Tokens.text_secondary
            font.pixelSize: 11
        }
    }

    component ActionButton: Button {
        id: control
        property bool destructive: false
        property bool primary: false
        property bool selected: false
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        font.family: "Adwaita Sans"
        font.pixelSize: 13
        font.weight: primary || selected ? Font.DemiBold : Font.Normal
        icon.width: 16
        icon.height: 16
        readonly property color foreground: primary ? Tokens.on_accent : destructive ? Tokens.danger : selected ? Tokens.accent : Tokens.text_primary
        icon.color: foreground
        palette.buttonText: enabled ? foreground : Tokens.text_secondary
        Accessible.name: text || ToolTip.text
        ToolTip.visible: hovered && ToolTip.text.length > 0
        ToolTip.delay: 600
        background: Rectangle {
            radius: 8
            color: control.primary ? (control.hovered ? Qt.lighter(Tokens.accent, 1.08) : Tokens.accent)
                : control.selected ? Qt.alpha(Tokens.accent, 0.14)
                : control.hovered || control.down ? Tokens.surface_high : "transparent"
            opacity: control.enabled ? 1 : 0.45
            border.width: control.activeFocus ? 1 : 0
            border.color: Tokens.focus_ring
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: panel.visible
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "clipboard-history-dismiss"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: Qt.quit()
            }
        }
    }

    PanelWindow {
        id: panel
        visible: false
        screen: Quickshell.screens.find(screen => Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
        anchors.top: true
        margins.top: 12
        implicitWidth: Math.min(960, (screen?.width || 960) - 24)
        implicitHeight: (width < 580 ? 300 : 254) + (root.detailsOpen ? 242 : 0) + (root.error ? 28 : 0)
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "clipboard-history"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (visible) reveal.restart();
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 16
            color: Tokens.surface_low
            border.width: 1
            border.color: Tokens.outline

            NumberAnimation on opacity {
                id: reveal
                from: 0
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                GridLayout {
                    columns: card.width < 580 ? 1 : 2
                    columnSpacing: 12
                    rowSpacing: 8
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: [
                                { key: "all", label: "Tất cả" },
                                { key: "text", label: "Văn bản" },
                                { key: "image", label: "Ảnh" }
                            ]
                            ActionButton {
                                required property var modelData
                                text: modelData.label
                                implicitHeight: 32
                                selected: root.typeFilter === modelData.key
                                Accessible.checkable: true
                                Accessible.checked: selected
                                onClicked: {
                                    if (root.typeFilter !== modelData.key) {
                                        root.typeFilter = modelData.key;
                                        root.resetSelection();
                                    }
                                    search.forceActiveFocus();
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        UiText {
                            text: root.filtered.length + " mục"
                            color: Tokens.text_secondary
                            font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 340
                        spacing: 6

                        TextField {
                            id: search
                            Layout.fillWidth: true
                            implicitHeight: 34
                            leftPadding: 12
                            rightPadding: searchKey.visible ? searchKey.implicitWidth + 16 : 10
                            font.family: "Adwaita Sans"
                            font.pixelSize: 13
                            placeholderText: "Tìm trong lịch sử…"
                            color: Tokens.text_primary
                            placeholderTextColor: Tokens.text_secondary
                            selectByMouse: true
                            Accessible.name: "Tìm kiếm clipboard"
                            KeyHint {
                                id: searchKey
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.width >= 170 && !search.text
                                keys: "Ctrl+F"
                            }
                            background: Rectangle {
                                radius: 8
                                color: Tokens.surface
                                border.color: search.activeFocus ? Qt.alpha(Tokens.accent, 0.46) : Tokens.outline
                            }
                            onTextChanged: root.resetSelection()
                            onAccepted: { if (!root.confirmation) root.act("paste"); }
                            Keys.onDownPressed: root.moveSelection(1)
                            Keys.onUpPressed: root.moveSelection(-1)
                            Keys.onPressed: event => {
                                if (event.modifiers === Qt.NoModifier && !search.text
                                        && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                                    root.moveSelection(event.key === Qt.Key_Left ? -1 : 1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
                                    event.accepted = true;
                                    if (root.selectedId && !root.confirmation && !operation.running)
                                        root.confirmation = "delete";
                                }
                            }
                        }
                        ActionButton {
                            icon.name: "edit-clear"
                            ToolTip.text: "Xóa lịch sử"
                            implicitWidth: 32
                            implicitHeight: 32
                            padding: 0
                            destructive: true
                            enabled: root.entries.length > 0 && !operation.running
                            onClicked: root.confirmation = "wipe"
                        }
                        ActionButton {
                            icon.name: "window-close"
                            ToolTip.text: "Đóng · Esc"
                            implicitWidth: 32
                            implicitHeight: 32
                            padding: 0
                            onClicked: Qt.quit()
                        }
                    }
                }

                ListView {
                    id: history
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: 8
                    cacheBuffer: 0
                    model: root.filtered
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain);
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            const delta = event.pixelDelta.y || event.angleDelta.y;
                            history.contentX = Math.max(history.originX, Math.min(
                                history.originX + Math.max(0, history.contentWidth - history.width),
                                history.contentX - delta));
                        }
                    }

                    delegate: ItemDelegate {
                        id: entryCard
                        required property var modelData
                        required property int index
                        readonly property bool isImage: modelData.kind === "image"
                        property string thumbnail: root.thumbnails[modelData.id] || ""

                        width: Math.max(160, Math.floor((history.width - 3 * history.spacing) / 4))
                        height: history.height - 9
                        padding: 8
                        hoverEnabled: true
                        highlighted: history.currentIndex === index
                        Accessible.name: isImage ? "Ảnh · " + modelData.metadata : modelData.preview
                        onClicked: history.currentIndex = index
                        onDoubleClicked: {
                            history.currentIndex = index;
                            if (!root.confirmation) root.act("paste");
                        }

                        Process {
                            command: ["python3", root.backend, "thumbnail", entryCard.modelData.id]
                            running: entryCard.isImage && !(entryCard.modelData.id in root.thumbnails)
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    try {
                                        entryCard.thumbnail = JSON.parse(text).source || "";
                                        const stored = Object.keys(root.thumbnails);
                                        if (stored.length >= 48) delete root.thumbnails[stored[0]];
                                        root.thumbnails[entryCard.modelData.id] = entryCard.thumbnail;
                                    } catch (_) {}
                                }
                            }
                        }

                        background: Rectangle {
                            radius: 10
                            color: entryCard.hovered ? Tokens.surface_high : Tokens.surface
                            border.width: entryCard.highlighted || entryCard.activeFocus ? 2 : 1
                            border.color: entryCard.highlighted || entryCard.activeFocus ? Tokens.accent : Tokens.outline
                        }

                        contentItem: ColumnLayout {
                            spacing: 4
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: entryCard.isImage ? Tokens.background : "transparent"
                                clip: true
                                Image {
                                    id: thumbnailImage
                                    anchors.fill: parent
                                    visible: entryCard.isImage
                                    source: entryCard.thumbnail
                                    asynchronous: true
                                    cache: false
                                    fillMode: Image.PreserveAspectFit
                                }
                                UiText {
                                    anchors.centerIn: parent
                                    visible: entryCard.isImage && thumbnailImage.status !== Image.Ready
                                    text: "Ảnh"
                                    color: Tokens.text_secondary
                                    font.pixelSize: 13
                                }
                                UiText {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    visible: !entryCard.isImage
                                    text: entryCard.modelData.kind === "binary" ? "Dữ liệu" : entryCard.modelData.preview
                                    textFormat: Text.PlainText
                                    color: entryCard.modelData.kind === "link" ? Tokens.accent : Tokens.text_primary
                                    font.pixelSize: 14
                                    wrapMode: Text.WrapAnywhere
                                    elide: Text.ElideRight
                                    maximumLineCount: Math.max(1, Math.floor(height / 20))
                                }
                            }

                            RowLayout {
                                spacing: 4
                                UiText {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    text: entryCard.modelData.metadata
                                        || (entryCard.modelData.kind === "link" ? "Liên kết" : "Văn bản")
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Tokens.text_secondary
                                    font.pixelSize: 11
                                }
                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 22
                                    UiText {
                                        anchors.centerIn: parent
                                        visible: entryCard.highlighted && !entryCard.hovered
                                        text: "↵"
                                        color: Tokens.accent
                                    }
                                    ActionButton {
                                        anchors.fill: parent
                                        visible: entryCard.hovered || hovered || activeFocus
                                        enabled: !operation.running && !root.confirmation
                                        padding: 0
                                        icon.name: "edit-delete"
                                        ToolTip.text: "Xóa mục"
                                        destructive: true
                                        onClicked: {
                                            history.currentIndex = entryCard.index;
                                            root.confirmation = "delete";
                                        }
                                    }
                                }
                            }
                        }
                    }

                    UiText {
                        anchors.centerIn: parent
                        visible: history.count === 0
                        text: listing.running ? "Đang tải…" : root.entries.length ? "Không có mục phù hợp." : "Chưa có nội dung đã sao chép."
                        color: Tokens.text_secondary
                        font.pixelSize: 13
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 230
                    visible: root.detailsOpen
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        Layout.leftMargin: 2
                        Layout.rightMargin: 2
                        UiText { text: "Xem trước"; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        UiText {
                            visible: !!root.preview.truncated
                            text: "Đã cắt bớt"
                            color: Tokens.danger
                            font.pixelSize: 11
                        }
                        UiText {
                            visible: !!root.preview.kind
                            Layout.maximumWidth: 175
                            text: root.selectedEntry?.metadata || (root.selectedEntry?.kind === "link" ? "Liên kết" : "Văn bản")
                            color: Tokens.text_secondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: Tokens.surface_low
                        border.color: Qt.alpha(Tokens.outline, 0.72)
                        clip: true
                        Image {
                            id: imagePreview
                            anchors.fill: parent
                            anchors.margins: 14
                            visible: root.preview.kind === "image"
                            source: visible ? root.preview.source : ""
                            sourceSize: Qt.size(800, 800)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }
                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 1
                            visible: root.preview.kind === "text" || root.preview.kind === "binary"
                            clip: true
                            TextArea {
                                text: root.preview.text || ""
                                textFormat: TextEdit.PlainText
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                padding: 16
                                color: root.selectedEntry?.kind === "link" ? Tokens.accent : Tokens.text_primary
                                selectionColor: Tokens.accent
                                selectedTextColor: Tokens.on_accent
                                font.family: "Adwaita Sans"
                                font.pixelSize: 15
                                background: null
                                Accessible.name: "Xem trước nội dung clipboard"
                            }
                        }
                        UiText {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            visible: !root.preview.kind || imagePreview.status === Image.Error
                            text: root.preview.error || (imagePreview.status === Image.Error
                                ? "Không thể hiển thị ảnh xem trước."
                                : root.selectedId ? "Đang tải xem trước…" : "Chọn nội dung để xem trước")
                            color: root.preview.error || imagePreview.status === Image.Error ? Tokens.danger : Tokens.text_secondary
                            font.pixelSize: 13
                        }
                    }
                }

                UiText { Layout.fillWidth: true; visible: !!root.error; text: root.error; textFormat: Text.PlainText; color: Tokens.danger; wrapMode: Text.Wrap; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(Tokens.outline, 0.6)
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    currentIndex: root.confirmation ? 1 : 0

                    RowLayout {
                        Row {
                            visible: card.width >= 640
                            spacing: 12
                            KeyHint { keys: "← →"; label: "Chọn" }
                            KeyHint { keys: "Enter"; label: "Dán" }
                            KeyHint { keys: "Shift+Del"; label: "Xóa" }
                        }
                        Item { Layout.fillWidth: true }
                        ActionButton { text: "Xem trước"; selected: root.detailsOpen; onClicked: root.detailsOpen = !root.detailsOpen }
                        ActionButton { icon.name: "edit-delete"; ToolTip.text: "Xóa mục"; implicitWidth: 36; destructive: true; enabled: !!root.selectedId && !operation.running; onClicked: root.confirmation = "delete" }
                        ActionButton { text: "Sao chép"; icon.name: "edit-copy"; enabled: !!root.selectedId && !operation.running; onClicked: root.act("copy") }
                        ActionButton { text: "Dán"; icon.name: "edit-paste"; implicitWidth: 92; primary: true; enabled: !!root.selectedId && !operation.running; onClicked: root.act("paste") }
                    }
                    RowLayout {
                        UiText {
                            Layout.fillWidth: true
                            text: root.confirmation === "wipe" ? "Xóa toàn bộ lịch sử clipboard?" : "Xóa mục này khỏi lịch sử?"
                            color: Tokens.danger
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                        }
                        ActionButton { text: "Hủy"; onClicked: root.confirmation = "" }
                        ActionButton { text: root.confirmation === "wipe" ? "Xóa tất cả" : "Xóa"; destructive: true; enabled: !operation.running; onClicked: root.act(root.confirmation) }
                    }
                }

            }
        }

        Shortcut { sequence: "Escape"; onActivated: { if (root.confirmation) root.confirmation = ""; else Qt.quit(); } }
        Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
        Shortcut {
            sequences: ["Return", "Enter"]
            enabled: !search.activeFocus && !root.confirmation
            onActivated: root.act("paste")
        }
        Shortcut { sequence: "Delete"; enabled: !!root.selectedId && !search.activeFocus; onActivated: root.confirmation = "delete" }
        Shortcut {
            sequence: "Shift+Delete"
            enabled: !search.activeFocus && !!root.selectedId && !root.confirmation && !operation.running
            onActivated: root.confirmation = "delete"
        }
    }

    Component.onCompleted: {
        const address = Quickshell.env("CLIPBOARD_FOCUS_ADDRESS");
        if (address) root.open(address);
        else targetLookup.running = true;
    }
}
