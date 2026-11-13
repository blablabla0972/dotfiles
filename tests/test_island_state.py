import json
from pathlib import Path
import shutil
import subprocess
import unittest

STATE = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/island/IslandState.js"

@unittest.skipUnless(shutil.which("node"), "Node.js required")
class IslandStateTests(unittest.TestCase):
    def test_dashboard_ipc_values_normalize_to_supported_options(self):
        script = """
const fs = require("node:fs");
const vm = require("node:vm");
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], "utf8"), c);
console.log(JSON.stringify({
  tabs: ["Home", "System", "Notifications", "Config", "bogus", null]
    .map(value => c.normalizeDashboardTab(value)),
  drawers: ["wifi", "Bluetooth", "bogus", null]
    .map(value => c.normalizeSideDrawer(value))
}));
"""
        result = subprocess.run(["node", "-e", script, str(STATE)], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["tabs"], ["Home", "System", "Notifications", "Config", "Home", "Home"])
        self.assertEqual(data["drawers"], ["wifi", "bluetooth", "", ""])

    def test_osd_values_keep_volume_amplification_separate_from_fill(self):
        script = """
const fs = require("node:fs");
const vm = require("node:vm");
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], "utf8"), c);
console.log(JSON.stringify({
  volume: [0, 0.45, 1, 1.25, 1.5, -0.1, 2].map(v => c.normalizeOsdProgress(v, "volume")),
  brightness: [0, 0.45, 1, 1.25, -0.1].map(v => c.normalizeOsdProgress(v, "brightness")),
  nonFinite: c.normalizeOsdProgress(NaN, "volume") === 0
    && c.normalizeOsdProgress(Infinity, "brightness") === 0,
  fill: [0, 0.45, 1, 1.25, 1.5].map(v => c.osdFill(v))
}));
"""
        result = subprocess.run(["node", "-e", script, str(STATE)], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["volume"], [0, 0.45, 1, 1.25, 1.5, 0, 1.5])
        self.assertEqual(data["brightness"], [0, 0.45, 1, 1, 0])
        self.assertTrue(data["nonFinite"])
        self.assertEqual(data["fill"], [0, 0.45, 1, 1, 1])

    def test_state_priority_and_rest_geometry(self):
        script = """
const fs = require("node:fs");
const vm = require("node:vm");
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], "utf8"), c);
const s = c.State;
console.log(JSON.stringify({
  dashboard: c.resolveState(null, true, true, true, true),
  dashboardDims: c.targetDimensions(s.DASHBOARD),
  idle: c.resolveState(null, false, false, false),
  media: c.resolveState(null, true, false, false),
  preview: c.resolveState(null, true, true, false),
  alert: c.resolveState({type:s.NOTIFICATION}, true, true, false),
  pin: c.resolveState({type:s.OSD}, true, true, true),
  rest: c.targetDimensions(s.IDLE),
  compact: c.targetDimensions(s.MEDIA),
  expanded: c.targetDimensions(s.EXPANDED)
}));
"""
        result = subprocess.run(["node", "-e", script, str(STATE)], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["dashboard"], "dashboard")
        self.assertEqual(data["dashboardDims"], {"width": 760, "height": 440, "radius": 22})
        self.assertEqual(data["idle"], "idle")
        self.assertEqual(data["media"], "media")
        self.assertEqual(data["preview"], "expanded")
        self.assertEqual(data["alert"], "notification")
        self.assertEqual(data["pin"], "expanded")
        self.assertGreater(data["rest"]["width"], 0)
        self.assertEqual(data["rest"]["height"], data["compact"]["height"])
        self.assertGreater(data["expanded"]["height"], data["compact"]["height"])

    def test_dashboard_geometry_fits_logical_viewports_and_scales(self):
        script = """
const fs = require("node:fs");
const vm = require("node:vm");
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], "utf8"), c);
const sizes = [[1920,1080],[1280,720],[1080,600],[960,540],[768,480],[640,360]];
const viewports = sizes.map(([w,h]) => c.dashboardGeometry(w,h,7));
const scales = [1,1.25,1.5,2].map(scale => c.dashboardGeometry(1920/scale,1080/scale,7));
console.log(JSON.stringify({viewports, scales}));
"""
        result = subprocess.run(["node", "-e", script, str(STATE)], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        expected = [(1920,1080,760,440,True),(1280,720,760,440,True),
                    (1080,600,760,440,False),(960,540,760,440,False),
                    (768,480,730,440,False),(640,360,602,344,False)]
        for (screen_width, screen_height, width, height, side_by_side), geometry in zip(expected, data["viewports"]):
            self.assertEqual((geometry["width"], geometry["height"], geometry["sideBySide"]),
                             (width, height, side_by_side))
            self.assertLessEqual(geometry["width"] + 14, screen_width - 24)
            self.assertLessEqual(geometry["height"], screen_height - 16)
        self.assertEqual([item["sideBySide"] for item in data["scales"]], [True, True, True, False])

if __name__ == "__main__":
    unittest.main()
