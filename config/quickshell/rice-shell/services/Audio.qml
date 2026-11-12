pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0.0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    // Track and bind PipeWire audio nodes so volume & mute properties are read/writeable
    property PwObjectTracker _tracker: PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(Boolean)
    }

    signal osdRequested(string icon, real progress)

    // Watch volume and mute changes reactively
    onVolumeChanged: {
        var icon = root.muted ? "󰝟" : (root.volume > 0.5 ? "󰕾" : (root.volume > 0.05 ? "󰖀" : "󰕿"));
        root.osdRequested(icon, root.muted ? 0.0 : root.volume);
    }

    onMutedChanged: {
        var icon = root.muted ? "󰝟" : (root.volume > 0.5 ? "󰕾" : "󰖀");
        root.osdRequested(icon, root.muted ? 0.0 : root.volume);
    }

    function setVolume(v: real): void {
        if (root.sink && root.sink.audio) {
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
        if (root.sink && root.sink.audio) {
            root.sink.audio.muted = !root.sink.audio.muted;
        }
    }
}
