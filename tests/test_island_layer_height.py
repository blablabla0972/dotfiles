"""Focused checks for the island layer-height reconciliation."""

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "config/quickshell/rice-shell/island/Island.qml"
STATE = ROOT / "config/quickshell/rice-shell/island/IslandState.js"


class IslandLayerHeightTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ISLAND.read_text()
        marker = "function reconcileLayerHeight(): void {"
        begin = cls.source.index(marker)
        body_begin = begin + len(marker)
        depth = 1
        end = body_begin
        while depth:
            if cls.source[end] == "{":
                depth += 1
            elif cls.source[end] == "}":
                depth -= 1
            end += 1
        cls.function = "function reconcileLayerHeight() {" + cls.source[body_begin:end]

    def simulate(self, steps):
        # Execute the actual QML JavaScript function against an isolated timer mock.
        script = f"""
            let requestedLayerHeight = 40, retainedLayerHeight = 40;
            let isPinned = false, dashboardShowing = false;
            const layerShrinkTimer = {{
                running: false,
                stop() {{ this.running = false; }},
                restart() {{ this.running = true; }}
            }};
            {self.function}
            for (const step of {json.dumps(steps)}) {{
                if (step.requested !== undefined) requestedLayerHeight = step.requested;
                if (step.pinned !== undefined) isPinned = step.pinned;
                if (step.dashboard !== undefined) dashboardShowing = step.dashboard;
                reconcileLayerHeight();
                if (step.fire && layerShrinkTimer.running) {{
                    layerShrinkTimer.running = false;
                    if (!isPinned && !dashboardShowing)
                        retainedLayerHeight = requestedLayerHeight;
                }}
            }}
            console.log(JSON.stringify({{
                retained: retainedLayerHeight,
                effective: Math.max(requestedLayerHeight, retainedLayerHeight),
                pending: layerShrinkTimer.running
            }}));
        """
        result = subprocess.run(
            ["node", "-e", script], capture_output=True, text=True, check=True
        )
        return json.loads(result.stdout)

    def test_instant_growth_and_stale_shrink_cancellation(self):
        result = self.simulate([
            {"requested": 96},  # notification
            {"requested": 40},  # idle; shrink scheduled
            {"requested": 164},  # expanded hover before timer fires
        ])
        self.assertEqual(result, {"retained": 164, "effective": 164, "pending": False})

    def test_shrink_after_timer(self):
        before = self.simulate([{"requested": 164}, {"requested": 40}])
        after = self.simulate([{"requested": 164}, {"requested": 40, "fire": True}])
        self.assertEqual(before, {"retained": 164, "effective": 164, "pending": True})
        self.assertEqual(after, {"retained": 40, "effective": 40, "pending": False})

    def test_fullscreen_modal_blocks_pending_shrink(self):
        for modal in ("pinned", "dashboard"):
            with self.subTest(modal=modal):
                blocked = self.simulate([
                    {"requested": 164}, {"requested": 40},
                    {modal: True, "fire": True},
                ])
                self.assertEqual(blocked, {"retained": 164, "effective": 164, "pending": False})
                released = self.simulate([
                    {"requested": 164}, {modal: True},
                    {"requested": 40}, {modal: False, "fire": True},
                ])
                self.assertEqual(released["effective"], 40)

    def test_geometry_and_input_contract(self):
        self.assertIn("Math.max(currentDims.height, islandShape.pillHeight) + 8", self.source)
        self.assertIn("implicitHeight: Math.max(requestedLayerHeight, retainedLayerHeight)", self.source)
        self.assertIn("onRequestedLayerHeightChanged: reconcileLayerHeight()", self.source)
        self.assertIn("onDashboardShowingChanged: {\n        reconcileLayerHeight();", self.source)
        self.assertIn("interval: 1000", self.source)
        self.assertIn("if (!islandWindow.isPinned && !islandWindow.dashboardShowing)", self.source)
        self.assertIn("bottom: islandWindow.isPinned || islandWindow.dashboardShowing", self.source)
        self.assertIn("item: islandWindow.modalOpen ? scrim : null", self.source)
        self.assertIn("width: islandShape.pillWidth", self.source)
        self.assertIn("height: islandShape.pillHeight", self.source)
        self.assertIn("width: 760, height: 440", STATE.read_text())


if __name__ == "__main__":
    unittest.main()
