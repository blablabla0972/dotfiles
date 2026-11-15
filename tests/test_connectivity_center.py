import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class ConnectivityCenterTest(unittest.TestCase):
    def test_connectivity_center_loads_only_selected_menu_and_routes_escape_offscreen(self):
        qs = shutil.which("qs")
        if qs is None:
            self.skipTest("Quickshell executable is unavailable")

        repository = Path(__file__).resolve().parents[1]
        component = repository / "config/quickshell/rice-shell/dashboard/ConnectivityCenter.qml"

        with tempfile.TemporaryDirectory(prefix="connectivity-center-test-") as temporary:
            temporary = Path(temporary)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            component_url = json.dumps(component.as_uri())
            harness = temporary / "ConnectivityCenterTest.qml"
            harness.write_text(
                f'''import Quickshell
    import QtQuick
    
    Scope {{
        function findObject(object, predicate) {{
            if (!object) return null;
            if (predicate(object)) return object;
            const children = object.children || [];
            for (let index = 0; index < children.length; index++) {{
                const found = findObject(children[index], predicate);
                if (found) return found;
            }}
            return null;
        }}
    
        Loader {{
            id: centerLoader
            source: {component_url}
        }}
    
        Timer {{
            property int step: 0
            property int closeRequests: 0
            interval: 200
            running: true
            repeat: true
            onTriggered: {{
                function fail(message) {{
                    console.error("CONNECTIVITY_CENTER_FAIL: " + message);
                    Qt.quit();
                }}
    
                const center = centerLoader.item;
                if (centerLoader.status !== Loader.Ready || !center)
                    return fail("ConnectivityCenter did not load");
    
                const wifiPage = findObject(center, object => typeof object.cancelPassword === "function");
                const bluetoothPage = findObject(center, object => object.objectName === "bluetoothDrawerPage");
                const hotspotLoader = findObject(center, object => typeof object.active === "boolean"
                    && String(object.source).endsWith("HotspotDrawer.qml"));
                const page = step === 1 ? "bluetooth" : step === 3 ? "hotspot" : "wifi";
                if (center.activePage !== page || center.wifiLoaded !== (page === "wifi")
                        || center.bluetoothLoaded !== (page === "bluetooth")
                        || center.hotspotLoaded !== (page === "hotspot"))
                    return fail("only the selected menu should be loaded: " + page);
                if (findObject(center, object => object.modelData && object.modelData.id === "wifi"))
                    return fail("the combined tab strip should not exist");
                if (step === 0) {{
                    if (!wifiPage || bluetoothPage || !hotspotLoader || hotspotLoader.active)
                        return fail("Wi-Fi should load without Bluetooth or Hotspot");
                    center.closeRequested.connect(() => closeRequests++);
                    center.pageSelected.connect(selected => center.currentPage = selected);
                    if (center.handleEscape() !== false || closeRequests !== 0)
                        return fail("idle Wi-Fi Escape should pass through to the owner");
                    center.selectPage("bluetooth");
                }} else if (step === 1) {{
                    if (!bluetoothPage || wifiPage) return fail("Bluetooth menu should be isolated");
                    bluetoothPage.expandedDeviceKey = "test-device";
                    if (center.handleEscape() !== true || bluetoothPage.expandedDeviceKey !== "")
                        return fail("Escape should collapse Bluetooth details first");
                    if (center.handleEscape() !== false || closeRequests !== 1)
                        return fail("idle Bluetooth Escape should request close and pass through");
                    center.selectPage("wifi");
                }} else if (step === 2) {{
                    if (!wifiPage || bluetoothPage) return fail("Wi-Fi should reopen independently");
                    center.selectPage("hotspot");
                }} else {{
                    const hotspotPage = hotspotLoader && hotspotLoader.item;
                    if (!hotspotPage || wifiPage || bluetoothPage)
                        return fail("Hotspot menu should be isolated");
                    if (center.handleEscape() !== false)
                        return fail("idle Hotspot Escape should pass through");
                    hotspotPage.passwordText = "secret123";
                    hotspotPage.revealPassword = true;
                    hotspotPage.visible = false;
                    if (hotspotPage.passwordText !== "" || hotspotPage.revealPassword !== false)
                        return fail("HotspotDrawer should clear secrets on invisible");
                    console.log("CONNECTIVITY_CENTER_PASS");
                    Qt.quit();
                }}
                step++;
            }}
        }}
    }}
    ''',
                encoding="utf-8",
            )
    
            environment = os.environ.copy()
            for key in ("DBUS_STARTER_ADDRESS", "DBUS_STARTER_BUS_TYPE"):
                environment.pop(key, None)
            environment.update(
                {
                    "QT_QPA_PLATFORM": "offscreen",
                    "XDG_CONFIG_HOME": str(temporary / "config"),
                    "XDG_CACHE_HOME": str(temporary / "cache"),
                    "XDG_DATA_HOME": str(temporary / "data"),
                    "XDG_RUNTIME_DIR": str(runtime),
                    "DBUS_SESSION_BUS_ADDRESS": f"unix:path={temporary / 'no-session-bus'}",
                    "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={temporary / 'no-system-bus'}",
                }
            )
            completed = subprocess.run(
                [qs, "--path", str(harness)],
                cwd=repository,
                env=environment,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
    
        output = completed.stdout + completed.stderr
        errors = "\n".join(
            line
            for line in output.splitlines()
            if re.search(r"error|failed|failure|warning|CONNECTIVITY_CENTER_FAIL", line, re.IGNORECASE)
        )
        self.assertEqual(completed.returncode, 0, f"Quickshell exited {completed.returncode} without pass marker\n{errors}")
        self.assertIn("CONNECTIVITY_CENTER_PASS", output, errors)


if __name__ == "__main__":
    unittest.main()
