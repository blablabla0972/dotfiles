"""Static contracts for the page-content Wi-Fi drawer.

These checks intentionally do not instantiate NetworkManager or change radio
state; runtime operations require a private native test backend.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "config/quickshell/rice-shell/dashboard/WifiDrawer.qml").read_text(
    encoding="utf-8"
)


class WifiDrawerRedesignTests(unittest.TestCase):
    def require(self, snippet, source=SOURCE):
        if snippet not in source:
            self.fail(f"Missing QML contract: {snippet!r}")

    def forbid(self, snippet, source=SOURCE):
        if snippet in source:
            self.fail(f"Unexpected QML contract: {snippet!r}")

    def require_regex(self, pattern, source=SOURCE):
        if not re.search(pattern, source):
            self.fail(f"Missing QML pattern: {pattern!r}")

    def forbid_regex(self, pattern, source=SOURCE):
        if re.search(pattern, source):
            self.fail(f"Unexpected QML pattern: {pattern!r}")

    def test_is_transparent_page_content_with_nested_escape_contract(self):
        root_header = SOURCE[: SOURCE.index("readonly property var wifiDevices")]

        self.require_regex(r"\bItem\s*\{\s*id:\s*root", root_header)
        self.forbid("radius:", root_header)
        self.forbid("border.", root_header)
        self.forbid("color:", root_header)
        self.require("signal closeRequested()", root_header)
        self.require("Keys.onEscapePressed")
        self.require("root.cancelPassword()")
        self.require("root.closeRequested()")
        self.forbid_regex(r'text:\s*"(?:Back|Close)"')

    def test_wifi_power_and_connectivity_show_native_state(self):
        self.require("checked: Networking.wifiEnabled")
        self.require("Networking.wifiEnabled = enabled")
        self.require("Networking.wifiHardwareEnabled")
        self.require("root.radioOffBlocked")
        self.require("NetworkConnectivity.Full")
        self.require("NetworkConnectivity.Limited")
        self.require("NetworkConnectivity.Portal")
        self.require("NetworkConnectivity.None")
        self.require('text: "Internet"')

    def test_connection_and_available_networks_are_separate_and_identity_based(self):
        self.require("readonly property var connectedNetwork")
        self.require("return network.known && !network.connected")
        self.require("return !network.known && !network.connected")
        self.require('text: "Current connection"')
        self.require('text: "Saved & in range"')
        self.require('text: "Nearby networks"')
        self.require("root.selectedNetwork === network")
        self.require("root.pendingNetwork === network")
        self.require("network.device.name")
        self.require("Text.PlainText")

    def test_password_flow_only_submits_supported_psks_and_clears_secret(self):
        self.require("WifiSecurityType.WpaPsk")
        self.require("WifiSecurityType.Wpa2Psk")
        self.require("WifiSecurityType.Sae")
        self.require("network.connectWithPsk(secret)")
        self.require("else network.connect()")
        self.require("ConnectionFailReason.NoSecrets")
        self.require("echoMode: root.showPassword ? TextInput.Normal : TextInput.Password")
        self.require('text: "Cancel"')
        self.require('text: root.showPassword ? "Hide" : "Show"')
        self.require("function clearPassword()")
        self.require("root.clearPassword()")
        self.require("root.promptForPassword(network")

    def test_forget_is_confirmed_and_uses_native_network_object(self):
        self.require('text: "Forget saved profiles…"')
        self.require('text: "Remove all saved profiles for this network?"')
        self.require("function requestForget(network)")
        self.require("function forgetNetwork(network)")
        self.require_regex(r"function forgetNetwork\(network\)[\s\S]*?network\.forget\(\)")
        self.require("function finishForget(success)")
        self.require("onKnownChanged()")
        self.forbid("nmcli")
        self.forbid("Process {")

    def test_scan_ownership_hotspot_and_adapter_lifecycle_are_guarded(self):
        self.require('import "../services"')
        self.require('typeof Hotspot === "undefined"')
        self.require("root.hotspotService.devicePath")
        self.require("root.hotspotService.active")
        self.require("device.name === root.hotspotDevicePath")
        self.require("device.address === root.hotspotDevicePath")
        self.require("root.hotspotDeviceIdentityUnknown")
        self.require("WifiDeviceMode.AccessPoint")
        self.require("signal hotspotPageRequested()")
        self.require("root.hotspotPageRequested()")
        self.require("property var scanOwnedDevice")
        self.require('property: "scannerEnabled"')
        self.require("root.scanOwnedDevice = root.wifiDevice")
        self.require("root.wifiDevice.mode !== WifiDeviceMode.Station")
        self.require("onNetworksChanged")
        self.require("networkIsAvailable(root.selectedNetwork)")
        self.require("function reconcilePendingOperation()")
        self.require("root.pendingNetwork.stateChanging")
        self.require("Component.onDestruction")

    def test_focusable_controls_and_no_external_network_commands(self):
        self.require('Accessible.name: "Wi-Fi power"')
        self.require('Accessible.name: "Refresh nearby Wi-Fi networks"')
        self.require('Accessible.name: "Open Hotspot tab"')
        self.require("if (visible) forceActiveFocus()")
        self.forbid_regex(r"\b(?:bash|sh)\s+-c\b")
        self.forbid("eval(")


if __name__ == "__main__":
    unittest.main()
