"""Native Quickshell regressions for Island input and dashboard dismissal."""

import json
import os
import re
import select
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "config/quickshell/rice-shell/island/Island.qml"
SHAPE = ROOT / "config/quickshell/rice-shell/island/IslandShape.qml"
DASHBOARD = ROOT / "config/quickshell/rice-shell/dashboard/Dashboard.qml"


def qml_block(source, marker):
    """Return one balanced QML block, including its original source text."""
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


@unittest.skipUnless(shutil.which("quickshell"), "Quickshell native runtime required")
class IslandMaskNativeRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.island = ISLAND.read_text()
        cls.shape = SHAPE.read_text()
        cls.dashboard = DASHBOARD.read_text()

    def run_native(self, qml):
        # A private offscreen shell: no Wayland connection or live-shell reload.
        with tempfile.TemporaryDirectory(prefix="island-mask-native-") as directory:
            shell = Path(directory) / "shell.qml"
            shell.write_text(qml)
            env = os.environ.copy()
            env.update({
                "QT_QPA_PLATFORM": "offscreen",
                "QSG_RHI_BACKEND": "software",
                "QT_QUICK_BACKEND": "software",
            })
            process = subprocess.Popen(
                ["quickshell", "--path", str(shell), "--no-color"],
                cwd=directory,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            output_lines = []
            try:
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([process.stdout], [], [], 0.25)
                    if ready:
                        line = process.stdout.readline()
                        if not line:
                            break
                        output_lines.append(line)
                        if "NATIVE_MASK:" in line:
                            break
                    if process.poll() is not None:
                        break
            finally:
                if process.poll() is None:
                    process.terminate()
                try:
                    remaining, _ = process.communicate(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    remaining, _ = process.communicate(timeout=2)
                output_lines.append(remaining)
        output = "".join(output_lines)
        match = re.search(r"NATIVE_MASK:(\{[^\n]*\})", output)
        self.assertIsNotNone(match, output[-2500:])
        return json.loads(match.group(1))

    def test_input_region_follows_modal_and_releases_while_closing(self):
        self.assertIn("readonly property bool modalOpen: isPinned || dashboard.expanded", self.island)
        self.assertIn("readonly property bool dashboardShowing: dashboard.expanded || dashboard.closing", self.island)
        self.assertIn("readonly property real r:", self.shape)
        region = qml_block(self.island, "mask: Region {").replace(
            "mask: Region {", "property var maskRegion: Region {", 1
        )
        qml = """
import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: islandWindow
        width: 1000; height: 700
        readonly property real topGap: 6
        property bool isPinned: false
        readonly property bool dashboardShowing: dashboard.expanded || dashboard.closing
        readonly property bool modalOpen: isPinned || dashboard.expanded

        QtObject {
            id: dashboard
            property bool expanded: false
            property bool closing: false
        }
        Rectangle {
            id: scrim
            anchors.fill: parent
            color: "transparent"
            Item {
                id: islandContainer
                x: 320; y: 0; width: 314; height: 90
                Item {
                    id: islandShape
                    property real a: 7
                    property real pillWidth: 300
                    property real pillHeight: 90
                    property real r: 14
                }
            }
        }
        @@REGION@@
        function sample() {
            return {
                modal: modalOpen,
                showing: dashboardShowing,
                fullscreen: maskRegion.item === scrim,
                x: maskRegion.x,
                y: maskRegion.y,
                width: maskRegion.width,
                height: maskRegion.height,
                bottomRadius: maskRegion.bottomLeftRadius
            };
        }
        Component.onCompleted: {
            const idle = sample();
            isPinned = true;
            const pinned = sample();
            isPinned = false;
            dashboard.expanded = true;
            const expanded = sample();
            dashboard.closing = true;
            dashboard.expanded = false;
            const closing = sample();
            dashboard.closing = false;
            const closed = sample();
            islandContainer.y = 18;
            const shifted = sample();
            console.log("NATIVE_MASK:" + JSON.stringify({idle, pinned, expanded, closing, closed, shifted}));
            Qt.quit();
        }
    }
}
""".replace("@@REGION@@", region)
        values = self.run_native(qml)
        for state in ("idle", "closing", "closed"):
            with self.subTest(state=state):
                self.assertFalse(values[state]["fullscreen"])
                self.assertEqual(values[state]["x"], 327)
                self.assertEqual(values[state]["width"], 300)
                self.assertEqual(values[state]["height"], 90)
                self.assertEqual(values[state]["bottomRadius"], 14)
        for state in ("pinned", "expanded"):
            with self.subTest(state=state):
                self.assertTrue(values[state]["fullscreen"])
                self.assertEqual(values[state]["bottomRadius"], 0)
        self.assertTrue(values["closing"]["showing"])
        self.assertFalse(values["closing"]["modal"])
        self.assertEqual(values["shifted"]["y"], 6)
        self.assertEqual(values["shifted"]["height"], 102)

    def test_native_morph_syncs_size_and_radius_and_retargets_without_jumping(self):
        qml = """
import QtQuick
import Quickshell
import "@@ISLAND_DIR@@" as Island

ShellRoot {
    Item {
        id: probe
        property real started: Date.now()
        property int phase: 0
        property real peakWidth: 138
        property real peakHeight: 32
        property var settled: []
        property real jump: 0
        property real largestProgressDelta: 0
        property real reverseFrom: 0
        property real reverseMinimum: Infinity
        Island.IslandShape {
            id: pill
            targetGeometry: Qt.vector3d(138, 32, 16)
            showAntiCorners: false
        }
        Timer {
            interval: 16; repeat: true; running: true
            onTriggered: {
                const elapsed = Date.now() - probe.started;
                if (probe.phase === 0 && elapsed >= 100) {
                    probe.phase = 1;
                    pill.targetGeometry = Qt.vector3d(390, 88, 24);
                } else if (probe.phase === 1) {
                    probe.peakWidth = Math.max(probe.peakWidth, pill.pillWidth);
                    probe.peakHeight = Math.max(probe.peakHeight, pill.pillHeight);
                    const widthProgress = (pill.pillWidth - 138) / 252;
                    const heightProgress = (pill.pillHeight - 32) / 56;
                    const radiusProgress = (pill.bottomRadius - 16) / 8;
                    probe.largestProgressDelta = Math.max(probe.largestProgressDelta,
                        Math.abs(widthProgress - heightProgress), Math.abs(widthProgress - radiusProgress));
                    if (elapsed >= 1100) {
                        probe.settled = [pill.pillWidth, pill.pillHeight, pill.bottomRadius];
                        pill.contracting = true;
                        probe.phase = 2;
                        pill.targetGeometry = Qt.vector3d(138, 32, 16);
                    }
                } else if (probe.phase === 2 && elapsed >= 1180) {
                    const width = pill.pillWidth, height = pill.pillHeight, radius = pill.bottomRadius;
                    probe.reverseFrom = width;
                    pill.contracting = false;
                    pill.targetGeometry = Qt.vector3d(420, 160, 26);
                    probe.jump = Math.max(Math.abs(pill.pillWidth - width),
                                          Math.abs(pill.pillHeight - height),
                                          Math.abs(pill.bottomRadius - radius));
                    probe.phase = 3;
                } else if (probe.phase === 3 && elapsed < 2200) {
                    probe.reverseMinimum = Math.min(probe.reverseMinimum, pill.pillWidth);
                } else if (probe.phase === 3) {
                    console.log("NATIVE_MASK:" + JSON.stringify({
                        peakWidth: probe.peakWidth, peakHeight: probe.peakHeight,
                        settled: probe.settled, jump: probe.jump,
                        reverseFrom: probe.reverseFrom, reverseMinimum: probe.reverseMinimum,
                        largestProgressDelta: probe.largestProgressDelta,
                        final: [pill.pillWidth, pill.pillHeight, pill.bottomRadius]
                    }));
                    Qt.quit();
                }
            }
        }
    }
}
""".replace("@@ISLAND_DIR@@", SHAPE.parent.as_uri())
        values = self.run_native(qml)
        self.assertGreater(values["peakWidth"], 390.5, values)
        self.assertLess(values["peakWidth"], 390 + (390 - 138) * 0.08, values)
        self.assertGreater(values["peakHeight"], 88.1, values)
        self.assertLess(values["peakHeight"], 88 + (88 - 32) * 0.08, values)
        self.assertEqual(values["settled"], [390, 88, 24], values)
        self.assertEqual(values["jump"], 0, values)
        self.assertLess(values["largestProgressDelta"], 0.04, values)
        self.assertLess(values["reverseFrom"], 390, values)
        self.assertLess(values["reverseMinimum"], values["reverseFrom"], values)
        self.assertEqual(values["final"], [420, 160, 26], values)

    def test_native_outside_tap_logic_dismisses_modal_only(self):
        scrim = self.island.index("id: scrim")
        handler = qml_block(self.island[scrim:], "TapHandler {")
        self.assertIn("enabled: islandWindow.modalOpen", handler)
        self.assertIn("!dashboard.containsDrawer(p.x, p.y)", handler)
        callback = qml_block(handler, "onTapped: (eventPoint) => {")
        body = callback[callback.index("{") + 1:-1]
        qml = """
import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: islandWindow
        property bool isPinned: false
        property int collapsed: 0
        readonly property bool modalOpen: isPinned || dashboard.expanded
        function collapse() { collapsed++; isPinned = false; }
        QtObject {
            id: dashboard
            property bool expanded: false
            property bool closing: false
            property int dismissed: 0
            function dismiss() { dismissed++; closing = true; expanded = false; }
            function containsDrawer(x, y) { return x >= 700 && x <= 950 && y <= 300; }
        }
        Item { id: islandContainer; x: 300; y: 0; width: 320; height: 100 }
        Item { id: islandShape; property real pillHeight: 100 }
        function tap(x, y) {
            if (!modalOpen) return;
            const eventPoint = {position: Qt.point(x, y)};
            @@BODY@@
        }
        Component.onCompleted: {
            tap(30, 200); // idle: no modal to dismiss
            const idle = dashboard.dismissed + collapsed;
            dashboard.expanded = true;
            tap(320, 50); // island content
            tap(750, 50); // side drawer
            const inside = dashboard.dismissed;
            tap(30, 200); // outside: dismiss dashboard
            const outside = dashboard.dismissed;
            tap(30, 200); // closing: no second dismiss
            const closing = dashboard.dismissed;
            dashboard.closing = false;
            isPinned = true;
            tap(30, 200); // outside: collapse pinned island
            console.log("NATIVE_MASK:" + JSON.stringify({idle, inside, outside, closing, collapsed}));
            Qt.quit();
        }
    }
}
""".replace("@@BODY@@", body)
        self.assertEqual(self.run_native(qml), {
            "idle": 0, "inside": 0, "outside": 1, "closing": 1, "collapsed": 1,
        })

    def test_dashboard_closing_does_not_leave_mousearea_click_blocker(self):
        self.assertIn("visible: expanded || closing", self.dashboard)
        content = self.dashboard[self.dashboard.index("id: morphContainer"):]
        blocker = qml_block(content, "MouseArea {").replace(
            "MouseArea {", "MouseArea { id: blockerArea;", 1
        )
        qml = """
import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: dashboardWindow
        property bool expanded: true
        property bool closing: false
        visible: expanded || closing
        Item {
            id: morphContainer
            visible: dashboardWindow.visible
            width: 760; height: 440
            @@BLOCKER@@
        }
        Component.onCompleted: {
            const expandedBlocks = blockerArea.enabled && morphContainer.visible;
            closing = true;
            expanded = false;
            const closingBlocks = blockerArea.enabled && morphContainer.visible;
            console.log("NATIVE_MASK:" + JSON.stringify({expandedBlocks, closingBlocks}));
            Qt.quit();
        }
    }
}
""".replace("@@BLOCKER@@", blocker)
        values = self.run_native(qml)
        self.assertTrue(values["expandedBlocks"])
        self.assertFalse(values["closingBlocks"], "Dashboard MouseArea absorbs clicks while closing")

    def test_media_hover_resumes_only_after_dashboard_finishes_closing(self):
        handler = qml_block(self.island, "onDashboardShowingChanged: {")
        qml = """
import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: islandWindow
        property bool isPinned: false
        property bool hasMedia: true
        property var activeAlert: null
        readonly property bool dashboardShowing: dashboard.expanded || dashboard.closing
        readonly property bool modalOpen: isPinned || dashboard.expanded
        function reconcileLayerHeight() {}
        QtObject { id: dashboard; property bool expanded: false; property bool closing: false }
        QtObject { id: hoverHandler; property bool hovered: true }
        QtObject { id: hoverDwell; property int restarts: 0; function restart() { restarts++; } }
        @@HANDLER@@
        Component.onCompleted: {
            const initial = hoverDwell.restarts;
            dashboard.expanded = true;
            dashboard.closing = true;
            dashboard.expanded = false;
            const closing = hoverDwell.restarts - initial;
            dashboard.closing = false;
            const resumed = hoverDwell.restarts - initial;
            dashboard.expanded = true;
            hasMedia = false;
            dashboard.expanded = false;
            const noMedia = hoverDwell.restarts - initial;
            console.log("NATIVE_MASK:" + JSON.stringify({closing, resumed, noMedia}));
            Qt.quit();
        }
    }
}
""".replace("@@HANDLER@@", handler)
        self.assertEqual(self.run_native(qml), {"closing": 0, "resumed": 1, "noMedia": 1})
    def test_morph_advances_on_consecutive_144_hz_frames(self):
        qml = """
import QtQuick
import Quickshell
import "@@ISLAND_DIR@@" as Island

ShellRoot {
    Island.IslandSpring {
        id: spring
        target: Qt.vector3d(138, 32, 16)
        Component.onCompleted: Qt.callLater(() => {
            spring.target = Qt.vector3d(390, 88, 20);
            const initial = spring.position.x;
            spring.advance(1 / 144);
            const first = spring.position.x;
            spring.advance(1 / 144);
            console.log("NATIVE_MASK:" + JSON.stringify({
                initial, first, second: spring.position.x
            }));
            Qt.quit();
        })
    }
}
""".replace("@@ISLAND_DIR@@", SHAPE.parent.as_uri())
        frames = self.run_native(qml)
        self.assertLess(frames["initial"], frames["first"])
        self.assertLess(frames["first"], frames["second"])
        self.assertLess(frames["second"], 390)

    def test_content_motion_loads_in_native_quickshell(self):
        qml = """
import QtQuick
import Quickshell
import "@@ISLAND_DIR@@" as Island

ShellRoot {
    Island.IslandShape {
        id: pill
        targetGeometry: Qt.vector3d(390, 88, 20)
    }
    Island.IslandContentMotion {
        id: motion
        shape: pill
        active: true
        contentWidth: 358
        contentHeight: 64
    }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            const before = motion.opacity;
            motion.active = false;
            console.log("NATIVE_MASK:" + JSON.stringify({
                before, after: motion.opacity
            }));
            Qt.quit();
        }
    }
}
""".replace("@@ISLAND_DIR@@", SHAPE.parent.as_uri())
        self.assertEqual(self.run_native(qml), {"before": 1, "after": 1})

if __name__ == "__main__":
    unittest.main()
