"""Run Audio.qml and its drawer against a private PipeWire/WirePlumber graph."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

SHELL = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell"
TOOLS = ("quickshell", "pipewire", "wireplumber", "pw-cli", "pw-dump", "wpctl", "dbus-daemon")

PROBE = """
//@ pragma DefaultEnv QS_PIPEWIRE_IMMEDIATE_RECONNECT = 1
import QtQuick
import Quickshell
import Quickshell.Io
import "./services"
import "./dashboard"

ShellRoot {
    id: probe
    property var micEvents: []

    Window {
        visible: false
        AudioDrawer { anchors.fill: parent }
    }

    Connections {
        target: Audio
        function onMicMuteChangedByBackend(muted) {
            probe.micEvents = probe.micEvents.concat(muted);
        }
    }

    IpcHandler {
        target: "probe"
        function snapshot(): string {
            return JSON.stringify({
                ready: Audio.ready, micAvailable: Audio.micAvailable,
                available: Audio.available, muted: Audio.micMuted, volume: Audio.micVolume,
                sink: Audio.sink?.name ?? "", source: Audio.source?.name ?? "",
                devices: Audio.devices.map(node => node.name),
                events: probe.micEvents, pending: Audio.pendingDevice !== null,
                error: Audio.error
            });
        }
        function select(name: string): void {
            Audio.selectDevice(Audio.devices.find(node => node.name === name) ?? null);
        }
        function mute(): void { Audio.toggleMicMute(); }
        function gain(value: real): void { Audio.setMicVolume(value); }
    }
}
"""


@unittest.skipUnless(all(shutil.which(tool) for tool in TOOLS), "PipeWire and Quickshell tools required")
class AudioPipeWireTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="rice-audio-")
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.env = {
            **os.environ,
            "XDG_RUNTIME_DIR": temp.name,
            "PIPEWIRE_RUNTIME_DIR": temp.name,
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_CACHE_HOME": str(self.base / "cache"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "QT_QPA_PLATFORM": "offscreen",
            "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={temp.name}/no-system-bus",
        }
        for name in ("PIPEWIRE_REMOTE", "PIPEWIRE_CONFIG_DIR", "PIPEWIRE_CONFIG_PREFIX",
                     "PIPEWIRE_CONFIG_NAME", "WIREPLUMBER_CONFIG_DIR", "WAYLAND_DISPLAY",
                     "DISPLAY", "QS_PIPEWIRE_IMMEDIATE_RECONNECT"):
            self.env.pop(name, None)
        for name in ("services", "dashboard", "theme"):
            (self.base / name).symlink_to(SHELL / name, target_is_directory=True)
        (self.base / "shell.qml").write_text(PROBE)
        config = self.base / "config/wireplumber/wireplumber.conf.d"
        config.mkdir(parents=True)
        (config / "90-test.conf").write_text(
            "wireplumber.profiles = { main = { hardware.audio = disabled "
            "hardware.bluetooth = disabled hardware.video-capture = disabled } }"
        )
        self.start("dbus-daemon", "--session", "--nofork", "--print-address=1")
        self.wait_for(lambda: (self.base / "dbus-daemon.log").read_text().strip())
        self.env["DBUS_SESSION_BUS_ADDRESS"] = (self.base / "dbus-daemon.log").read_text().splitlines()[0]
        bin_dir = self.base / "bin"
        bin_dir.mkdir()
        wpctl = bin_dir / "wpctl"
        wpctl.write_text(f"#!/bin/sh\n[ ! -e {shlex.quote(str(self.base / 'reject'))} ] || exit 1\n"
                         f"exec {shlex.quote(shutil.which('wpctl'))} \"$@\"\n")
        wpctl.chmod(0o700)
        self.shell = self.start("env", f"PATH={bin_dir}:{os.environ['PATH']}",
                                "quickshell", "-p", str(self.base / "shell.qml"))

    def start(self, *args):
        with (self.base / f"{args[0]}.log").open("ab") as log:
            process = subprocess.Popen(args, env=self.env, stdout=log, stderr=log)
        self.addCleanup(self.stop, process)
        return process

    @staticmethod
    def stop(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    def command(self, *args, check=True):
        return subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=5, check=check)

    def start_graph(self):
        self.pipewire = self.start("pipewire")
        self.wait_for(lambda: self.command("pw-cli", "info", "0", check=False).returncode == 0)
        self.wireplumber = self.start("wireplumber")

    def wait_for(self, condition):
        until = time.monotonic() + 8
        while time.monotonic() < until:
            result = condition()
            if result:
                return result
            time.sleep(0.05)
        diagnostics = "\n".join(
            f"{log.name}:\n{log.read_text(errors='replace')[-1500:]}" for log in self.base.glob("*.log")
        )
        diagnostics += self.command("wpctl", "status", check=False).stdout
        graph = self.command("pw-dump", check=False)
        if graph.returncode == 0:
            defaults = [obj["metadata"] for obj in json.loads(graph.stdout)
                        if obj.get("props", {}).get("metadata.name") == "default" and "metadata" in obj]
            diagnostics += repr(defaults)
        self.fail(f"PipeWire condition timed out {getattr(self, 'latest', None)}\n{diagnostics}")

    def ipc(self, method, *args, check=True):
        return self.command("quickshell", "ipc", "--pid", str(self.shell.pid),
                            "call", "probe", method, *args, check=check)

    def state(self, condition):
        def observe():
            reply = self.ipc("snapshot", check=False)
            if reply.returncode == 0:
                state = json.loads(reply.stdout)
                self.latest = state
                if condition(state):
                    return state
            return None
        return self.wait_for(observe)

    def add_node(self, name, direction):
        self.command("pw-cli", "create-node", "adapter",
                     f"{{ factory.name=support.null-audio-sink node.name={name} "
                     f"media.class=Audio/{direction} object.linger=true audio.position=[ FL FR ] }}")
        return self.wait_for(lambda: self.node_id(name))

    def node_id(self, name):
        graph = json.loads(self.command("pw-dump").stdout)
        return next((str(obj["id"]) for obj in graph
                     if obj.get("info", {}).get("props", {}).get("node.name") == name), None)

    def test_defaults_gain_mute_unplug_and_reconnect(self):
        self.state(lambda s: not s["ready"] and not s["devices"] and not s["micAvailable"])
        self.start_graph()
        self.state(lambda s: s["ready"] and not s["devices"] and not s["micAvailable"])
        self.ipc("mute")
        self.assertEqual(self.state(lambda s: s["ready"])["events"], [])
        sink_a = self.add_node("speaker-a", "Sink")
        self.add_node("speaker-b", "Sink")
        mic_a = self.add_node("mic-a", "Source")
        mic_b = self.add_node("mic-b", "Source")
        self.state(lambda s: s["available"] and s["micAvailable"] and len(s["devices"]) == 4)
        self.command("wpctl", "set-default", mic_a)
        self.command("wpctl", "set-default", sink_a)
        self.state(lambda s: s["available"] and s["micAvailable"] and s["source"] == "mic-a"
                   and len(s["devices"]) == 4)
        self.ipc("select", "speaker-b")
        self.state(lambda s: s["sink"] == "speaker-b" and not s["pending"] and s["source"] == "mic-a")
        self.ipc("select", "mic-b")
        self.state(lambda s: s["source"] == "mic-b" and not s["pending"] and s["sink"] == "speaker-b")
        self.command("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "1")
        self.state(lambda s: s["muted"] and s["events"] == [True])
        self.ipc("mute")
        self.state(lambda s: not s["muted"] and s["events"] == [True, False])
        marker = self.base / "reject"
        marker.touch()
        self.ipc("mute")
        failed = self.state(lambda s: s["error"])
        self.assertFalse(failed["muted"])
        self.assertEqual(failed["events"], [True, False])
        marker.unlink()
        self.ipc("gain", "0.55")
        self.state(lambda s: abs(s["volume"] - .55) < .001 and not s["error"])
        self.ipc("gain", "2")
        self.state(lambda s: abs(s["volume"] - 1) < .001)
        self.ipc("gain", "0.37")
        self.state(lambda s: abs(s["volume"] - .37) < .001)
        self.command("pw-cli", "destroy", mic_b)
        self.state(lambda s: s["source"] == "mic-a" and "mic-b" not in s["devices"])
        self.command("pw-cli", "destroy", mic_a)
        self.state(lambda s: not s["micAvailable"] and not s["source"])
        self.stop(self.wireplumber)
        self.state(lambda s: s["ready"] and not s["available"] and not s["sink"]
                   and len(s["devices"]) == 2)
        self.wireplumber = self.start("wireplumber")
        self.state(lambda s: s["available"] and s["sink"] in ("speaker-a", "speaker-b"))
        self.stop(self.wireplumber)
        self.stop(self.pipewire)
        self.state(lambda s: not s["ready"] and not s["available"] and not s["devices"])
        self.start_graph()
        self.add_node("mic-reconnected", "Source")
        self.state(lambda s: s["micAvailable"] and s["source"] == "mic-reconnected"
                   and s["events"] == [True, False])
        self.command("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "1")
        self.state(lambda s: s["muted"] and s["events"] == [True, False, True])
        self.assertNotRegex((self.base / "env.log").read_text(), r"(?:ReferenceError|TypeError):")
