pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../launcher/LauncherSearch.js" as LauncherSearch
import "Registry.js" as Registry

ColumnLayout {
    id: root
    property var store: null
    readonly property bool ready: !!store?.ready
    readonly property bool writable: ready && store.writable
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    readonly property color muted: Registry.readable(Tokens.text_secondary, Tokens.surface_low, 4.5)
    readonly property color outline: Qt.tint(Tokens.surface_low,
        Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5))
    readonly property var applications: LauncherSearch.indexApps(DesktopEntries.applications.values)
    property bool clearCalculations: false
    spacing: 12

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: historySettings.implicitHeight + 28
        radius: 15
        color: Tokens.surface_low
        border.color: root.outline

        ColumnLayout {
            id: historySettings
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            Label {
                text: qsTr("History")
                color: root.ink
                font.weight: Font.DemiBold
                font.pixelSize: 16
            }

            Repeater {
                model: [
                    { key: "apps", title: qsTr("Recently used apps"), hint: qsTr("Record apps opened from Launcher.") },
                    { key: "calculations", title: qsTr("Calculator history"), hint: qsTr("Save calculator results in Launcher.") }
                ]
                delegate: GridLayout {
                    id: option
                    required property var modelData
                    readonly property bool calculator: modelData.key === "calculations"
                    readonly property bool allowed: root.ready && (calculator ? root.store.calculationsAllowed : root.store.appsAllowed)
                    readonly property bool enabledByUser: root.ready && (calculator ? root.store.rememberCalculations : root.store.rememberApps)
                    readonly property int count: root.ready
                        ? (calculator ? root.store.savedCalculations.length : root.store.savedRecents.length) : 0

                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 4
                    Label {
                        Layout.fillWidth: true
                        text: option.modelData.title
                        color: root.ink
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    SettingsToggle {
                        Layout.alignment: Qt.AlignRight
                        Accessible.name: option.modelData.title
                        enabled: root.writable && option.allowed
                        checked: option.enabledByUser
                        onToggled: root.store.setHistoryRecording(option.modelData.key, checked)
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: root.muted
                        text: !root.ready ? qsTr("Launcher state is unavailable.")
                            : !option.allowed ? qsTr("Recording is disabled by the shell environment.")
                            : option.modelData.hint + "  " + qsTr("%n saved", "", option.count)
                    }
                    SettingsActionButton {
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Clear…")
                        Accessible.name: qsTr("Clear %1").arg(option.modelData.title)
                        enabled: root.writable && option.count > 0
                        onClicked: {
                            root.clearCalculations = option.calculator;
                            clearHistory.open();
                        }
                    }
                }
            }

            Label {
                visible: root.ready && (!root.store.writable || root.store.saveFailed)
                Layout.fillWidth: true
                text: qsTr("Launcher state could not be saved.")
                color: Registry.readable(Tokens.danger, Tokens.surface_low, 4.5)
                wrapMode: Text.Wrap
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: favorites.implicitHeight + 28
        radius: 15
        color: Tokens.surface_low
        border.color: root.outline

        ColumnLayout {
            id: favorites
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9

            Label {
                text: qsTr("Favorites")
                color: root.ink
                font.weight: Font.DemiBold
                font.pixelSize: 16
            }
            TextField {
                id: filter
                Layout.fillWidth: true
                implicitHeight: 41
                leftPadding: 12
                placeholderText: qsTr("Find an app to pin")
                Accessible.name: placeholderText
                color: root.ink
                placeholderTextColor: root.muted
                background: Rectangle {
                    radius: 9
                    color: Tokens.surface
                    border.width: filter.activeFocus ? 2 : 1
                    border.color: filter.activeFocus ? Registry.readable(Tokens.focus_ring, color, 3) : root.outline
                }
            }
            Label {
                Layout.fillWidth: true
                visible: pinned.count === 0
                wrapMode: Text.Wrap
                color: root.muted
                text: filter.text.trim() ? qsTr("No matching applications.") : qsTr("No applications pinned.")
            }
            ListView {
                id: pinned
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(count, 6) * 42
                visible: count > 0
                clip: true
                model: !root.ready ? [] : filter.text.trim()
                    ? LauncherSearch.searchApps(root.applications, filter.text, root.store.favorites)
                        .map(app => ({ id: app.id, name: app.name }))
                    : root.store.favorites.map(id => ({ id: id, name: DesktopEntries.byId(id)?.name || id }))
                ScrollBar.vertical: ScrollBar {}
                delegate: RowLayout {
                    id: app
                    required property var modelData
                    readonly property bool pinned: root.store.favorites.includes(modelData.id)
                    width: ListView.view.width - 10
                    height: 42
                    Label {
                        Layout.fillWidth: true
                        text: app.modelData.name
                        color: root.ink
                        elide: Text.ElideRight
                    }
                    SettingsActionButton {
                        text: app.pinned ? qsTr("Unpin") : qsTr("Pin")
                        Accessible.name: app.pinned ? qsTr("Unpin %1").arg(app.modelData.name)
                            : qsTr("Pin %1").arg(app.modelData.name)
                        enabled: root.writable
                        onClicked: root.store.toggleFavorite(app.modelData.id)
                    }
                }
            }
        }
    }

    property SettingsDialog confirmation: SettingsDialog {
        id: clearHistory
        title: root.clearCalculations ? qsTr("Clear calculator history?") : qsTr("Clear recently used apps?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label {
            text: qsTr("This removes the saved entries from Launcher.")
            wrapMode: Text.Wrap
            color: root.ink
        }
        onAccepted: if (root.writable) root.store.clearHistory(root.clearCalculations)
    }
}
