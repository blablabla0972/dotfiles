pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../theme"

PanelWindow {
    id: launcherWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: launcherWindow.visible ? scrim : null
    }

    property string searchText: ""
    property int selectedIndex: 0

    // Filter desktop entries based on search query
    readonly property var allApps: Quickshell.applications ? Quickshell.applications.values : []
    readonly property var filteredApps: {
        var query = searchText.trim().toLowerCase();
        if (query.length === 0) return allApps.slice(0, 15);
        var results = [];
        for (var i = 0; i < allApps.length; i++) {
            var app = allApps[i];
            if (!app || !app.name) continue;
            var name = app.name.toLowerCase();
            var desc = app.description ? app.description.toLowerCase() : "";
            if (name.indexOf(query) !== -1 || desc.indexOf(query) !== -1) {
                results.push(app);
                if (results.length >= 25) break;
            }
        }
        return results;
    }

    function toggle(): void {
        visible = !visible;
        if (visible) {
            searchText = "";
            selectedIndex = 0;
            searchInput.text = "";
            searchInput.forceActiveFocus();
        }
    }

    function launchSelected(): void {
        if (filteredApps.length > 0 && selectedIndex >= 0 && selectedIndex < filteredApps.length) {
            var app = filteredApps[selectedIndex];
            if (app) {
                app.execute();
                launcherWindow.visible = false;
            }
        }
    }

    // Backdrop Scrim
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        TapHandler {
            onTapped: launcherWindow.visible = false
        }

        // Center Launcher Card
        Rectangle {
            id: launcherCard
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 32)
            height: Math.min(480, parent.height - 48)
            radius: 18
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.panelOpacity)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            TapHandler {
                // Prevent tap from bubbling to scrim
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Search Input Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 12
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)
                    border.color: searchInput.activeFocus ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                    border.width: searchInput.activeFocus ? 1.5 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "󰍉"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            color: Tokens.text_primary
                            font.pixelSize: 14
                            verticalAlignment: TextInput.AlignVCenter
                            activeFocusOnPress: true

                            onTextChanged: {
                                launcherWindow.searchText = text;
                                launcherWindow.selectedIndex = 0;
                            }

                            Keys.onEscapePressed: (event) => {
                                launcherWindow.visible = false;
                                event.accepted = true;
                            }

                            Keys.onReturnPressed: (event) => {
                                launcherWindow.launchSelected();
                                event.accepted = true;
                            }

                            Keys.onDownPressed: (event) => {
                                if (launcherWindow.filteredApps.length > 0) {
                                    launcherWindow.selectedIndex = Math.min(launcherWindow.filteredApps.length - 1, launcherWindow.selectedIndex + 1);
                                }
                                event.accepted = true;
                            }

                            Keys.onUpPressed: (event) => {
                                if (launcherWindow.filteredApps.length > 0) {
                                    launcherWindow.selectedIndex = Math.max(0, launcherWindow.selectedIndex - 1);
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Application List View
                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: launcherWindow.filteredApps
                    spacing: 4
                    currentIndex: launcherWindow.selectedIndex

                    delegate: Rectangle {
                        id: appDelegate
                        required property DesktopEntry modelData
                        required property int index
                        readonly property bool isSelected: launcherWindow.selectedIndex === index

                        width: appList.width
                        height: 44
                        radius: 10
                        color: isSelected ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : (appHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.5) : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Image {
                                width: 26
                                height: 26
                                source: appDelegate.modelData.icon || ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: appDelegate.modelData.name || ""
                                    font.pixelSize: 13
                                    font.bold: appDelegate.isSelected
                                    color: appDelegate.isSelected ? Tokens.accent : Tokens.text_primary
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: appDelegate.modelData.description || ""
                                    font.pixelSize: 10
                                    color: Tokens.text_secondary
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }
                        }

                        HoverHandler { id: appHover }
                        TapHandler {
                            onTapped: {
                                appDelegate.modelData.execute();
                                launcherWindow.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
