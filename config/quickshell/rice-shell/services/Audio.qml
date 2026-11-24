pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property PwNode sink: effectiveDevice(Pipewire.defaultAudioSink, true)
    readonly property PwNode source: effectiveDevice(Pipewire.defaultAudioSource, false)
    readonly property bool ready: Pipewire.ready
    readonly property bool available: ready && sink !== null && sink.ready && sink.audio !== null
    readonly property bool micAvailable: ready && source !== null && source.ready && source.audio !== null
    readonly property real micVolume: micAvailable ? source.audio.volume : 0
    readonly property bool micMuted: micAvailable && source.audio.muted
    readonly property bool changeBusy: commandTimeout.running || audioCommand.running
    readonly property bool micBusy: changeBusy
    readonly property list<PwNode> devices: ready
        ? Pipewire.nodes.values.filter(node => node.audio !== null && !node.isStream && node.name.length > 0)
        : []
    property PwNode pendingDevice: null
    property string error: ""

    readonly property real volume: available && isFinite(sink.audio.volume)
        ? Math.max(0, Math.min(1.5, sink.audio.volume)) : 0.0
    readonly property bool muted: available ? sink.audio.muted : false

    onSinkChanged: {
        checkDeviceSelection();
        confirmAudioChange();
    }
    onSourceChanged: {
        checkDeviceSelection();
        confirmAudioChange();
    }
    onMicVolumeChanged: confirmAudioChange()
    onMicMutedChanged: confirmAudioChange()
    onDevicesChanged: checkDeviceSelection()

    // Quickshell 0.3.2 can miss first defaults and retain them after metadata removal.
    // ponytail: drop the metadata subscription once native defaults handle both events.
    function effectiveDevice(nativeNode: PwNode, output: bool): PwNode {
        const defaults = metadataWatch.defaults;
        if (!defaults) return nativeNode;
        const key = output ? "default.audio.sink" : "default.audio.source";
        const name = defaults[key];
        if (!name) return null;
        if (nativeNode?.name === name) return nativeNode;
        return devices.find(node => node.isSink === output && node.name === name) ?? null;
    }

    onReadyChanged: {
        if (!ready) metadataWatch.clear();
    }

    property Process _metadataWatch: Process {
        id: metadataWatch
        running: root.ready
        command: ["pw-dump", "-m", "-N", "default"]
        property int metadataId: -1
        property var defaults: null
        property int revision: 0

        function applyMetadata(entries): void {
            const named = {};
            for (const entry of entries) {
                if (entry.subject === 0)
                    named[entry.key] = entry.value?.name;
            }
            defaults = named;
        }

        function clear(): void {
            metadataId = -1;
            defaults = null;
            revision += 1;
        }

        onExited: clear()

        stdout: SplitParser {
            splitMarker: "\n]\n"
            onRead: frame => {
                if (!root.ready) return;
                let objects;
                try {
                    objects = JSON.parse(frame + "\n]");
                } catch (e) {
                    return;
                }
                for (const object of objects) {
                    if (object.props?.["metadata.name"] === "default") {
                        metadataWatch.metadataId = object.id;
                        metadataWatch.revision += 1;
                        metadataRefresh.restart();
                    } else if (object.id === metadataWatch.metadataId && object.info === null) {
                        metadataWatch.metadataId = -1;
                        metadataWatch.revision += 1;
                        metadataWatch.defaults = {};
                    }
                }
            }
        }
    }

    // Monitor frames contain deltas. Read a complete snapshot after a burst of updates.
    property Timer _metadataRefresh: Timer {
        id: metadataRefresh
        interval: 60
        onTriggered: metadataSnapshot.request()
    }

    property Process _metadataSnapshot: Process {
        id: metadataSnapshot
        command: ["pw-dump", "-N", "default"]
        property int revision: -1

        function request(): void {
            if (!running) {
                revision = metadataWatch.revision;
                running = true;
            }
        }

        onExited: {
            if (root.ready && metadataWatch.metadataId !== -1
                    && revision !== metadataWatch.revision)
                metadataRefresh.restart();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.ready || metadataSnapshot.revision !== metadataWatch.revision) return;
                try {
                    const object = JSON.parse(text).find(entry => entry.id === metadataWatch.metadataId);
                    metadataWatch.applyMetadata(object?.metadata ?? []);
                } catch (e) {}
            }
        }
    }

    // Track and bind PipeWire audio nodes so volume & mute properties are read/writeable
    property PwObjectTracker _tracker: PwObjectTracker {
        objects: [root.sink, root.source].filter(Boolean)
    }

    signal osdRequested(string icon, real progress)
    signal micMuteChangedByBackend(bool muted)

    property Connections _micEvents: Connections {
        target: root.micAvailable ? root.source.audio : null
        function onMutedChanged(): void {
            root.micMuteChangedByBackend(root.source.audio.muted);
        }
    }

    function selectDevice(node: PwNode): void {
        if (!node || devices.indexOf(node) < 0 || pendingDevice
                || node === (node.isSink ? sink : source)) return;
        error = "";
        pendingDevice = node;
        deviceTimeout.restart();
        if (node.isSink)
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
        checkDeviceSelection();
    }

    function checkDeviceSelection(): void {
        if (!deviceTimeout.running) return;
        const node = pendingDevice;
        if (!node || devices.indexOf(node) < 0)
            finishDeviceSelection(qsTr("Audio device disconnected"));
        else if (node === (node.isSink ? sink : source))
            finishDeviceSelection("");
    }

    function finishDeviceSelection(message: string): void {
        deviceTimeout.stop();
        pendingDevice = null;
        error = message;
    }

    property Timer _deviceTimeout: Timer {
        id: deviceTimeout
        interval: 2500
        onTriggered: root.finishDeviceSelection(qsTr("Could not switch audio device"))
    }

    function setMicVolume(value: real): void {
        if (!isFinite(value)) return;
        if (micAvailable)
            runAudioCommand(source, ["set-volume", "-l", "1"], String(Math.max(0, Math.min(1, value))));
    }

    function toggleMicMute(): void {
        if (micAvailable) runAudioCommand(source, ["set-mute"], micMuted ? "0" : "1");
    }

    function requestOutputVolume(value: real): void {
        if (available && isFinite(value))
            runAudioCommand(sink, ["set-volume", "-l", "1.5"], String(Math.max(0, Math.min(1.5, value))));
    }

    function requestOutputMute(): void {
        if (available) runAudioCommand(sink, ["set-mute"], muted ? "0" : "1");
    }

    function runAudioCommand(device: PwNode, args: list<string>, value: string): void {
        if (changeBusy) return;
        error = "";
        // The native setter can emit optimistically. Observe the server's event after wpctl writes.
        audioCommand.output = device === sink;
        audioCommand.device = device;
        audioCommand.volumeRequest = args[0] === "set-volume";
        audioCommand.value = Number(value);
        audioCommand.succeeded = false;
        commandTimeout.restart();
        audioCommand.exec(["wpctl"].concat(args, [String(device.id), value]));
    }

    function confirmAudioChange(): void {
        if (!commandTimeout.running || !audioCommand.succeeded) return;
        const device = audioCommand.device;
        if (!device || device !== (audioCommand.output ? sink : source)) {
            error = qsTr("Audio device changed before the update could be confirmed");
            commandTimeout.stop();
        } else if (device.audio && (audioCommand.volumeRequest
                ? Math.abs(device.audio.volume - audioCommand.value) < 0.005
                : device.audio.muted === Boolean(audioCommand.value))) {
            commandTimeout.stop();
        }
    }

    property Process _audioCommand: Process {
        id: audioCommand
        property bool output: false
        property PwNode device: null
        property bool volumeRequest: false
        property real value: 0
        property bool succeeded: false
        onExited: (code) => {
            if (!commandTimeout.running) return;
            if (code !== 0) {
                commandTimeout.stop();
                root.error = output ? qsTr("Could not change output settings")
                    : qsTr("Could not change microphone settings");
            } else {
                succeeded = true;
                root.confirmAudioChange();
            }
        }
    }

    property Timer _commandTimeout: Timer {
        id: commandTimeout
        interval: 2500
        onTriggered: {
            audioCommand.running = false;
            root.error = qsTr("Audio change could not be confirmed");
        }
    }

    // Watch volume and mute changes reactively
    onVolumeChanged: {
        confirmAudioChange();
        var icon = root.muted ? "󰝟" : (root.volume > 0.5 ? "󰕾" : (root.volume > 0.05 ? "󰖀" : "󰕿"));
        if (root.available) root.osdRequested(icon, root.muted ? 0.0 : root.volume);
    }

    onMutedChanged: {
        confirmAudioChange();
        var icon = root.muted ? "󰝟" : (root.volume > 0.5 ? "󰕾" : "󰖀");
        if (root.available) root.osdRequested(icon, root.muted ? 0.0 : root.volume);
    }

    function setVolume(v: real): void {
        if (root.available && isFinite(v)) {
            root.sink.audio.volume = Math.max(0.0, Math.min(1.5, v));
        }
    }

    function volumeUp(step: real): void {
        var s = (step !== undefined && step > 0) ? step : 0.05;
        root.setVolume(root.volume + s);
    }

    function volumeDown(step: real): void {
        var s = (step !== undefined && step > 0) ? step : 0.05;
        root.setVolume(root.volume - s);
    }

    function toggleMute(): void {
        if (root.available) {
            root.sink.audio.muted = !root.sink.audio.muted;
        }
    }
}
