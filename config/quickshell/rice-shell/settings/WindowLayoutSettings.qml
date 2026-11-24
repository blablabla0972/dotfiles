pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "Registry.js" as Registry

ColumnLayout {
    id: root
    required property WindowLayoutStore store
    property var draft: null
    readonly property bool editable: !!store?.writable && !!draft
    readonly property bool modified: !!draft && JSON.stringify(draft) !== JSON.stringify(store?.snapshot?.active)
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    readonly property color muted: Registry.readable(Tokens.text_secondary, Tokens.surface_low, 4.5)
    spacing: 12

    Component.onCompleted: {
        draft = store?.snapshot?.active || null;
        store?.refresh();
    }

    Connections {
        target: root.store
        function onReconciled(): void { root.draft = root.store.snapshot.active; }
    }

    function setGap(group: string, side: int, value: int): void {
        const values = root.draft[group].slice();
        values[side] = value;
        draft = Object.assign({}, draft, { [group]: values });
    }

    Rectangle {
        id: illustration
        visible: !!root.draft
        Layout.fillWidth: true
        Layout.preferredHeight: 156
        radius: 11
        clip: true
        color: Tokens.surface
        border.color: Tokens.outline
        readonly property var outer: root.draft?.outer || [0, 0, 0, 0]
        readonly property var inner: root.draft?.inner || [0, 0, 0, 0]
        GridLayout {
            anchors.fill: parent
            anchors.topMargin: 9 + illustration.outer[0] * 0.6
            anchors.rightMargin: 9 + illustration.outer[1] * 0.6
            anchors.bottomMargin: 9 + illustration.outer[2] * 0.6
            anchors.leftMargin: 9 + illustration.outer[3] * 0.6
            columns: 2
            columnSpacing: 2 + (illustration.inner[1] + illustration.inner[3]) * 0.55
            rowSpacing: 2 + (illustration.inner[0] + illustration.inner[2]) * 0.55
            Repeater {
                model: [qsTr("Active window"), qsTr("Adjacent window"), "", ""]
                delegate: Rectangle {
                    id: tile
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: Tokens.surface_high
                    border.width: root.draft?.border || 0
                    border.color: tile.index === 0 ? Tokens.accent : Tokens.outline
                    Label {
                        anchors.centerIn: parent
                        text: tile.modelData
                        color: Registry.readable(Tokens.text_primary, Tokens.surface_high, 4.5)
                        elide: Text.ElideRight
                        width: Math.max(0, tile.width - 22)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    Repeater {
        model: root.draft ? [
            { key: "inner", title: qsTr("Between windows") },
            { key: "outer", title: qsTr("Around the workspace") }
        ] : []
        delegate: ColumnLayout {
            id: gapGroup
            required property var modelData
            Layout.fillWidth: true
            Label { text: gapGroup.modelData.title; color: root.ink; font.weight: Font.DemiBold }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 480 ? 4 : 2
                columnSpacing: 9
                rowSpacing: 8
                Repeater {
                    model: [qsTr("Top"), qsTr("Right"), qsTr("Bottom"), qsTr("Left")]
                    delegate: ColumnLayout {
                        id: edge
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Label { text: edge.modelData; color: root.muted }
                        SettingsNumberField {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            enabled: root.editable
                            from: 0
                            to: 40
                            value: root.draft?.[gapGroup.modelData.key]?.[edge.index] ?? 0
                            Accessible.name: gapGroup.modelData.title + " · " + edge.modelData
                            onValueModified: root.setGap(gapGroup.modelData.key, edge.index, value)
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        visible: !!root.draft
        Layout.fillWidth: true
        Label { Layout.fillWidth: true; text: qsTr("Border thickness (px)"); color: root.ink }
        SettingsNumberField {
            enabled: root.editable
            from: 0
            to: 12
            value: root.draft?.border ?? 0
            Accessible.name: qsTr("Border thickness")
            onValueModified: root.draft = Object.assign({}, root.draft, { border: value })
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 7
        SettingsActionButton {
            text: qsTr("Apply")
            primary: true
            enabled: root.editable && root.modified
            onClicked: root.store.save(root.draft)
        }
        SettingsActionButton {
            text: qsTr("Refresh")
            enabled: !!root.store && !root.store.busy
            onClicked: root.store.refresh()
        }
        SettingsActionButton {
            text: qsTr("Use Hyprland defaults…")
            enabled: root.editable && !!root.store.snapshot?.saved
            onClicked: resetDialog.open()
        }
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: root.muted
        text: root.store?.busy ? qsTr("Waiting for Hyprland…") : root.store?.message
            || (!root.store?.snapshot?.writable ? qsTr("Layout editing is unavailable in this session.") : "")
        visible: text.length > 0
    }

    property SettingsDialog confirmReset: SettingsDialog {
        id: resetDialog
        title: qsTr("Restore Hyprland spacing?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label {
            wrapMode: Text.Wrap
            text: qsTr("Remove the Rice Settings override and use the values from your Hyprland configuration.")
        }
        onAccepted: root.store.reset()
    }
}
