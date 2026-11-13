import json
from pathlib import Path
import shutil
import subprocess
import unittest

STATE = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/island/IslandState.js"

@unittest.skipUnless(shutil.which("node"), "Node.js required")
class IslandStateTests(unittest.TestCase):
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

if __name__ == "__main__":
    unittest.main()
