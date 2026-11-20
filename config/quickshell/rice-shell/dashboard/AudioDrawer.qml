pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../theme"
import "../services"

Rectangle {
    id: root

    signal closeRequested()

    property var switchingProfile: null
    property string profileError: ""
    readonly property PwNode profileSink: switchingProfile ? Audio.devices.find(node =>
        node.isSink && Number(node.properties["device.id"]) === switchingProfile.card
        && switchingProfile.devices.includes(Number(node.properties["card.profile.device"]))) ?? null : null
    onProfileSinkChanged: {
        if (!profileSink || !switchingProfile) return;
        const node = profileSink;
        profileTimeout.stop();
        switchingProfile = null;
        Audio.selectDevice(node);
    }

    readonly property var alternateOutputs: {
        const choices = [];
        for (const [card, params] of Object.entries(routeMonitor.cards)) {
            const active = params.Profile?.[0]?.index;
            if (active === undefined) continue;
            for (const route of params.EnumRoute ?? []) {
                if (route.direction !== "Output" || route.available === "no"
                        || !route.devices?.length || route.profiles?.includes(active)) continue;
                const profile = (params.EnumProfile ?? []).find(profile =>
                    profile.available !== "no" && route.profiles?.includes(profile.index));
                if (profile) choices.push({card: Number(card), index: profile.index,
                    devices: route.devices, label: route.description || route.name});
            }
        }
        return choices;
    }

    function switchProfile(choice): void {
        if (!alternateOutputs.some(output => output.card === choice.card && output.index === choice.index) || switchingProfile || Audio.pendingDevice) return;
        profileError = "";
        Audio.error = "";
        switchingProfile = choice;
        profileTimeout.restart();
        // A temporary profile switch lets WirePlumber keep handling jack events.
        profileCommand.exec(["pw-cli", "set-param", String(choice.card), "Profile",
            "{ index: " + choice.index + ", save: false }"]);
    }

    Process {
        id: profileCommand
        onExited: code => {
            if (code !== 0 && root.switchingProfile)
                profileTimeout.triggered();
        }
    }

    Timer {
        id: profileTimeout
        interval: 2500
        onTriggered: {
            profileTimeout.stop();
            root.switchingProfile = null;
            root.profileError = qsTr("Could not switch audio profile");
        }
    }

    function isDisconnected(node: PwNode): bool {
        const card = node?.properties?.["device.id"];
        const port = node?.properties?.["card.profile.device"];
        if (card === undefined || port === undefined) return false;
        const direction = node.isSink ? "Output" : "Input";
        const routes = routeMonitor.cards[card]?.EnumRoute?.filter(route =>
            route.direction === direction && route.devices?.includes(Number(port))) ?? [];
        return routes.length > 0 && routes.every(route => route.available === "no");
    }

    PwObjectTracker {
        objects: Audio.devices
    }

    // PipeWire retains some unplugged ALSA nodes in its graph. Watch their card routes.
    Process {
        id: routeMonitor
        property var cards: ({})
        running: root.visible && Audio.ready
        command: ["pw-dump", "-m", "-N", "PipeWire:Interface:Device"]
        onExited: cards = ({})

        stdout: SplitParser {
            splitMarker: "\n]\n"
            onRead: frame => {
                let objects;
                try {
                    objects = JSON.parse(frame + "\n]");
                } catch (e) {
                    return;
                }
                const cards = Object.assign({}, routeMonitor.cards);
                for (const object of objects) {
                    if (object.info === null) delete cards[object.id];
                    else if (object.info?.params)
                        cards[object.id] = Object.assign({}, cards[object.id], object.info.params);
                }
                routeMonitor.cards = cards;
            }
        }
    }

    radius: 26
    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.97)
    border.width: 1
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.38)
    clip: true
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Audio devices")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: qsTr("Audio devices")
                color: Tokens.text_primary
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: closeHover.hovered || activeFocus ? Tokens.surface_high : "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close audio menu")
                Accessible.onPressAction: root.closeRequested()

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.pixelSize: 14
                    color: Tokens.text_secondary
                }

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.closeRequested()
                }
                Keys.onReturnPressed: (event) => {
                    root.closeRequested();
                    event.accepted = true;
                }
                Keys.onSpacePressed: (event) => {
                    root.closeRequested();
                    event.accepted = true;
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.profileError || Audio.error || (!Audio.ready ? qsTr("PipeWire unavailable") : "")
            color: root.profileError || Audio.error ? Tokens.danger : Tokens.text_secondary
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: controls.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: controls
                width: scroll.width
                spacing: 8

                DeviceSection {
                    Layout.fillWidth: true
                    output: true
                }

                DeviceSection {
                    Layout.fillWidth: true
                    output: false
                }

                RowLayout {
                    Layout.fillWidth: true

                    QuickSettingSlider {
                        Layout.fillWidth: true
                        icon: Audio.micMuted ? "󰍭" : "󰍬"
                        label: qsTr("Mic gain")
                        device: Audio.source
                        commitOnRelease: true
                        available: Audio.micAvailable && !Audio.micBusy
                        value: Audio.micVolume
                        valueText: !Audio.micAvailable ? qsTr("Unavailable")
                            : Math.round(Audio.micVolume * 100) + "%"
                                + (Audio.micVolume > 1 ? qsTr(" · Boost") : "")
                        onValueRequested: value => Audio.setMicVolume(value)
                    }

                    QuickSettingTile {
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 56
                        icon: Audio.micMuted ? "󰍭" : "󰍬"
                        label: qsTr("Mic")
                        sublabel: !Audio.micAvailable ? qsTr("Unavailable")
                            : Audio.micMuted ? qsTr("Muted") : qsTr("On")
                        active: Audio.micMuted
                        available: Audio.micAvailable
                        pending: Audio.micBusy
                        onActivated: Audio.toggleMicMute()
                    }
                }
            }
        }
    }

    component DeviceSection: ColumnLayout {
        id: section
        required property bool output
        readonly property PwNode current: output ? Audio.sink : Audio.source
        readonly property list<PwNode> devices: Audio.devices.filter(node => node.isSink === output)

        Text {
            Layout.fillWidth: true
            text: section.output ? qsTr("Output") : qsTr("Input")
            color: Tokens.text_secondary
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            visible: Audio.ready && (!section.current || section.devices.length === 0)
            text: section.devices.length === 0 ? qsTr("No devices available") : qsTr("No default device")
            color: Tokens.text_secondary
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Repeater {
            model: section.devices

            QuickSettingTile {
                required property PwNode modelData
                readonly property bool disconnected: !active && root.isDisconnected(modelData)
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                icon: section.output ? "󰕾" : "󰍬"
                label: modelData?.nickname || modelData?.description || modelData?.name || ""
                sublabel: active ? qsTr("Current default") : disconnected ? qsTr("Unplugged") : ""
                active: modelData !== null && modelData === section.current
                available: modelData !== null && !disconnected && Audio.pendingDevice === null
                    && !root.switchingProfile
                pending: modelData !== null && Audio.pendingDevice === modelData
                onActivated: {
                    root.profileError = "";
                    Audio.selectDevice(modelData);
                }
            }
        }
        Repeater {
            model: section.output ? root.alternateOutputs : []

            QuickSettingTile {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                icon: "󰕾"
                label: modelData.label
                available: !root.switchingProfile && !Audio.pendingDevice
                pending: root.switchingProfile?.card === modelData.card
                    && root.switchingProfile?.index === modelData.index
                onActivated: root.switchProfile(modelData)
            }
        }

    }
}
