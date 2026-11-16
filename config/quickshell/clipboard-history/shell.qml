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
    readonly property string backend: Quickshell.shellPath("clipboard.py")
    readonly property var filtered: entries.filter(entry => entry.preview.toLocaleLowerCase().includes(search.text.toLocaleLowerCase()))
    readonly property string selectedId: filtered[history.currentIndex] ? filtered[history.currentIndex].id : ""

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

    function result(text: string): var {
        try {
            var value = JSON.parse(text);
            if (value.error) { root.error = value.error; return null; }
            return value;
        } catch (error) {
            root.error = "Không đọc được dữ liệu clipboard.";
            return null;
        }
    }

    function refresh(): void {
        if (!listing.running) listing.running = true;
    }

    function act(action: string): void {
        if (operation.running || (action !== "wipe" && !selectedId)) return;
        error = "";
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
        id: listing
        command: ["python3", root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data = root.result(text);
                if (!data) return;
                root.entries = data.entries;
                history.currentIndex = root.filtered.length ? 0 : -1;
                previewTimer.restart();
            }
        }
    }

    Timer {
        id: previewTimer
        interval: 80
        onTriggered: {
            if (!root.selectedId || previewProcess.running) return;
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
                var data = root.result(text);
                if (data && data.id === root.selectedId) root.preview = data;
            }
        }
        onExited: { if (requestedId !== root.selectedId) previewTimer.restart(); }
    }

    Process {
        id: operation
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var data = root.result(text);
                if (!data || !data.ok) return;
                if (operation.action === "copy") Qt.quit();
                else { root.confirmation = ""; root.refresh(); }
            }
        }
    }

    component ActionButton: Button {
        id: control
        property bool destructive: false
        property bool primary: false
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 12
        font.pixelSize: 13
        font.weight: primary ? Font.DemiBold : Font.Normal
        icon.width: 16
        icon.height: 16
        icon.color: control.primary ? Tokens.on_accent : control.destructive ? Tokens.danger : Tokens.text_primary
        palette.buttonText: !enabled ? Tokens.text_secondary : primary ? Tokens.on_accent : destructive ? Tokens.danger : Tokens.text_primary
        Accessible.name: text || ToolTip.text
        ToolTip.visible: hovered && ToolTip.text.length > 0
        ToolTip.delay: 600
        background: Rectangle {
            radius: 10
            color: control.primary ? Tokens.accent : control.hovered || control.down ? Tokens.surface_high : "transparent"
            opacity: control.enabled ? 1 : 0.45
            border.width: control.activeFocus ? 1 : 0
            border.color: Tokens.focus_ring
        }
    }

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(screen => Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "clipboard-history"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#55000000"
            TapHandler {
                onTapped: point => {
                    if (point.position.x < card.x || point.position.x > card.x + card.width
                        || point.position.y < card.y || point.position.y > card.y + card.height)
                        Qt.quit();
                }
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(820, panel.width - 48)
            height: Math.min(560, panel.height - 128)
            radius: 22
            color: Tokens.surface
            border.width: 1
            border.color: Tokens.outline

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 44; implicitHeight: 44; radius: 14
                        color: Qt.alpha(Tokens.accent, 0.12)
                        Image { anchors.centerIn: parent; width: 24; height: 24; source: Quickshell.iconPath("edit-paste", "text-x-generic") }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "Clipboard"; color: Tokens.text_primary; font.pixelSize: 22; font.weight: Font.DemiBold }
                        Text { text: "Nội dung đã sao chép, luôn trong tầm tay"; color: Tokens.text_secondary; font.pixelSize: 12 }
                    }
                    Item { Layout.fillWidth: true }
                    ActionButton {
                        text: "Xóa lịch sử"
                        icon.name: "edit-clear"
                        destructive: true
                        enabled: root.entries.length > 0 && !operation.running
                        onClicked: root.confirmation = "wipe"
                    }
                    ActionButton { icon.name: "window-close"; implicitWidth: 36; ToolTip.text: "Đóng · Esc"; onClicked: Qt.quit() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 18

                    ColumnLayout {
                        Layout.preferredWidth: Math.min(296, card.width * 0.4)
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: Layout.preferredWidth
                        Layout.fillHeight: true
                        spacing: 12
                        TextField {
                            id: search
                            Layout.fillWidth: true
                            implicitHeight: 42
                            leftPadding: 38
                            rightPadding: 12
                            font.pixelSize: 13
                            placeholderText: "Tìm trong lịch sử…"
                            color: Tokens.text_primary
                            placeholderTextColor: Tokens.text_secondary
                            selectByMouse: true
                            Accessible.name: "Tìm kiếm clipboard"
                            Image { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; opacity: 0.7; source: Quickshell.iconPath("edit-find", "system-search") }
                            background: Rectangle { radius: 12; color: Tokens.surface_low; border.width: 1; border.color: search.activeFocus ? Qt.alpha(Tokens.accent, 0.55) : Qt.alpha(Tokens.outline, 0.45) }
                            onTextChanged: { history.currentIndex = root.filtered.length ? 0 : -1; }
                            onAccepted: root.act("copy")
                            Keys.onDownPressed: history.currentIndex = Math.min(root.filtered.length - 1, history.currentIndex + 1)
                            Keys.onUpPressed: history.currentIndex = Math.max(0, history.currentIndex - 1)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            Text { text: search.text ? "KẾT QUẢ" : "GẦN ĐÂY"; color: Tokens.text_secondary; font.pixelSize: 10; font.letterSpacing: 1.4; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            Text { text: root.filtered.length + " mục"; color: Tokens.text_secondary; font.pixelSize: 11 }
                        }
                        ListView {
                            id: history
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: root.filtered
                            currentIndex: -1
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            delegate: ItemDelegate {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property string kind: root.entryKind(modelData.preview)
                                width: history.width
                                height: 70
                                leftPadding: 12
                                rightPadding: 12
                                highlighted: history.currentIndex === index
                                Accessible.name: modelData.preview
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        implicitWidth: 36; implicitHeight: 36; radius: 10
                                        color: row.highlighted ? Qt.alpha(Tokens.accent, 0.12) : Tokens.surface_high
                                        Image {
                                            anchors.centerIn: parent; width: 19; height: 19
                                            source: Quickshell.iconPath(row.kind === "image" ? "image-x-generic" : row.kind === "link" ? "internet-web-browser" : "text-x-generic", "edit-paste")
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: row.kind === "image" ? "Ảnh đã sao chép" : row.kind === "binary" ? "Dữ liệu đã sao chép" : row.modelData.preview
                                            textFormat: Text.PlainText
                                            color: Tokens.text_primary
                                            font.pixelSize: 13
                                            font.weight: row.highlighted ? Font.DemiBold : Font.Normal
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: row.kind === "image" || row.kind === "binary" ? row.modelData.preview.slice(15, -2).trim() : row.kind === "link" ? "Liên kết" : "Văn bản"
                                            textFormat: Text.PlainText
                                            color: Tokens.text_secondary
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                background: Rectangle {
                                    radius: 12
                                    color: row.highlighted ? Qt.alpha(Tokens.accent, 0.09) : row.hovered ? Tokens.surface_high : "transparent"
                                    border.width: row.highlighted || row.activeFocus ? 1 : 0
                                    border.color: Qt.alpha(Tokens.accent, row.activeFocus ? 0.8 : 0.25)
                                }
                                onClicked: history.currentIndex = index
                                onDoubleClicked: { history.currentIndex = index; root.act("copy"); }
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                visible: root.filtered.length === 0
                                text: listing.running ? "Đang tải…" : root.entries.length ? "Không tìm thấy nội dung." : "Chưa có nội dung đã sao chép."
                                textFormat: Text.PlainText
                                color: Tokens.text_secondary
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: Tokens.surface_low
                        border.width: 1
                        border.color: Qt.alpha(Tokens.outline, 0.5)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Xem trước"; color: Tokens.text_primary; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    visible: !!root.preview.kind
                                    implicitWidth: kindLabel.implicitWidth + 16
                                    implicitHeight: 24
                                    radius: 7
                                    color: Tokens.surface_high
                                    Text { id: kindLabel; anchors.centerIn: parent; text: root.preview.kind === "image" ? (root.preview.mime || "image").split("/").pop().toUpperCase() : root.preview.kind === "binary" ? "Dữ liệu" : "Văn bản"; color: Tokens.text_secondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Tokens.outline, 0.4) }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Image {
                                    id: imagePreview
                                    anchors.fill: parent
                                    visible: root.preview.kind === "image"
                                    source: visible ? root.preview.source : ""
                                    sourceSize: Qt.size(800, 800)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    onStatusChanged: { if (status === Image.Error) root.error = "Không thể hiển thị ảnh xem trước."; }
                                }
                                ScrollView {
                                    anchors.fill: parent
                                    visible: root.preview.kind === "text" || root.preview.kind === "binary"
                                    clip: true
                                    TextArea {
                                        text: root.preview.text || ""
                                        textFormat: TextEdit.PlainText
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.WrapAnywhere
                                        padding: 0
                                        color: Tokens.text_primary
                                        selectionColor: Tokens.accent
                                        selectedTextColor: Tokens.on_accent
                                        font.pixelSize: 14
                                        background: null
                                        Accessible.name: "Xem trước nội dung clipboard"
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    visible: !root.preview.kind
                                    text: root.selectedId ? "Đang tải xem trước…" : "Chọn nội dung để xem trước"
                                    color: Tokens.text_secondary
                                    font.pixelSize: 13
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                ActionButton { icon.name: "edit-delete"; ToolTip.text: "Xóa mục"; implicitWidth: 36; destructive: true; enabled: !!root.selectedId && !operation.running; onClicked: root.confirmation = "delete" }
                                Item { Layout.fillWidth: true }
                                ActionButton { text: "Sao chép"; icon.name: "edit-copy"; primary: true; enabled: !!root.selectedId && !operation.running; onClicked: root.act("copy") }
                            }
                        }
                    }
                }

                Text { Layout.fillWidth: true; visible: !!root.error; text: root.error; textFormat: Text.PlainText; color: Tokens.danger; wrapMode: Text.Wrap; font.pixelSize: 12 }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.confirmation
                    Text {
                        Layout.fillWidth: true
                        text: root.confirmation === "wipe" ? "Xóa toàn bộ lịch sử clipboard?" : "Xóa mục này khỏi lịch sử?"
                        color: Tokens.danger
                        font.pixelSize: 13
                    }
                    ActionButton { text: "Hủy"; onClicked: root.confirmation = "" }
                    ActionButton { text: "Xóa"; destructive: true; enabled: !operation.running; onClicked: root.act(root.confirmation) }
                }

            }
        }

        Shortcut { sequence: "Escape"; onActivated: { if (root.confirmation) root.confirmation = ""; else Qt.quit(); } }
        Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
        Shortcut { sequence: "Delete"; enabled: !!root.selectedId && !search.activeFocus; onActivated: root.confirmation = "delete" }
    }

    Component.onCompleted: { root.refresh(); search.forceActiveFocus(); }
}
