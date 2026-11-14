import copy
import json
import sys
import unittest
from pathlib import Path


SERVICE_DIR = (
    Path(__file__).resolve().parents[1]
    / "config"
    / "quickshell"
    / "rice-shell"
    / "services"
)
sys.path.insert(0, str(SERVICE_DIR))

import hotspot_backend


WIFI_DEVICE = "/org/freedesktop/NetworkManager/Devices/7"
CLIENT_ACTIVE = "/org/freedesktop/NetworkManager/ActiveConnection/4"
HOTSPOT_ACTIVE = "/org/freedesktop/NetworkManager/ActiveConnection/8"


class FakeNetworkManager:
    def __init__(self):
        self.state = {
            "networking_enabled": True,
            "wireless_enabled": True,
            "wireless_hardware_enabled": True,
            "permissions": {
                "network-control": "yes",
                "settings.modify.system": "yes",
            },
            "devices": [
                {
                    "path": WIFI_DEVICE,
                    "interface": "wlan0",
                    "device_type": 2,
                    "managed": True,
                    "state": 100,
                    "mode": 2,
                    "capabilities": 0x68,
                    "active_connection": CLIENT_ACTIVE,
                }
            ],
            "active_connections": [
                {
                    "path": CLIENT_ACTIVE,
                    "uuid": "existing-client-profile",
                    "type": "802-11-wireless",
                    "devices": [WIFI_DEVICE],
                    "state": 2,
                    "default": True,
                    "default6": False,
                }
            ],
            "profiles": [
                {
                    "path": "/org/freedesktop/NetworkManager/Settings/4",
                    "settings": {
                        "connection": {
                            "uuid": "existing-client-profile",
                            "id": "Home Wi-Fi",
                            "type": "802-11-wireless",
                        }
                    },
                }
            ],
        }
        self.add_calls = []
        self.update_calls = []
        self.activate_calls = []
        self.deactivate_calls = []

    def snapshot(self):
        return copy.deepcopy(self.state)

    def add_profile(self, settings):
        self.add_calls.append(copy.deepcopy(settings))
        path = "/org/freedesktop/NetworkManager/Settings/42"
        self.state["profiles"].append({"path": path, "settings": copy.deepcopy(settings)})
        return path

    def update_profile(self, path, settings):
        self.update_calls.append((path, copy.deepcopy(settings)))
        for profile in self.state["profiles"]:
            if profile["path"] == path:
                profile["settings"] = copy.deepcopy(settings)
                return
        raise AssertionError("attempted to update an unknown profile")

    def activate(self, profile_path, device_path):
        self.activate_calls.append((profile_path, device_path))
        profile = next(p for p in self.state["profiles"] if p["path"] == profile_path)
        self.state["active_connections"] = [
            active
            for active in self.state["active_connections"]
            if device_path not in active["devices"]
        ]
        self.state["active_connections"].append(
            {
                "path": HOTSPOT_ACTIVE,
                "uuid": profile["settings"]["connection"]["uuid"],
                "type": "802-11-wireless",
                "devices": [device_path],
                "state": 2,
                "default": False,
                "default6": False,
            }
        )
        device = next(d for d in self.state["devices"] if d["path"] == device_path)
        device["active_connection"] = HOTSPOT_ACTIVE
        device["mode"] = hotspot_backend.WIFI_MODE_AP
        return HOTSPOT_ACTIVE

    def deactivate(self, active_path):
        self.deactivate_calls.append(active_path)
        self.state["active_connections"] = [
            active for active in self.state["active_connections"]
            if active["path"] != active_path
        ]


class HotspotBackendTests(unittest.TestCase):
    def setUp(self):
        self.nm = FakeNetworkManager()
        self.manager = hotspot_backend.HotspotManager(self.nm)

    def configure(self, ssid="Rice Test", password="safe-test-passphrase"):
        return self.manager.handle(
            {"op": "configure", "ssid": ssid, "password": password}
        )

    def test_ssid_limit_uses_encoded_byte_length(self):
        valid = "é" * 16
        too_long = "é" * 17
        hotspot_backend.validate_configuration(valid, "12345678")
        with self.assertRaises(hotspot_backend.HotspotError):
            hotspot_backend.validate_configuration(too_long, "12345678")

    def test_profile_uses_exact_uuid_wpa2_rsn_shared_ipv4_and_no_autoconnect(self):
        response = self.configure()
        self.assertTrue(response["ok"])
        profile = self.nm.add_calls[0]
        security = profile["802-11-wireless-security"]
        self.assertEqual(profile["connection"]["uuid"], hotspot_backend.OWNED_UUID)
        self.assertFalse(profile["connection"]["autoconnect"])
        self.assertEqual(profile["802-11-wireless"]["mode"], "ap")
        self.assertEqual(security["key-mgmt"], "wpa-psk")
        self.assertEqual(security["proto"], ["rsn"])
        self.assertEqual(profile["ipv4"]["method"], "shared")

    def test_start_waits_for_confirmation_before_displacing_wifi_client(self):
        self.configure()
        first = self.manager.handle({"op": "start"})
        self.assertTrue(first["confirmationRequired"])
        self.assertEqual(self.nm.activate_calls, [])

        started = self.manager.handle(
            {"op": "start", "confirmationToken": first["confirmationToken"]}
        )
        self.assertTrue(started["ok"])
        self.assertTrue(started["snapshot"]["active"])
        self.assertEqual(len(self.nm.activate_calls), 1)

    def test_changed_wifi_client_requires_a_new_confirmation(self):
        self.configure()
        first = self.manager.handle({"op": "start"})
        client = self.nm.state["active_connections"][0]
        client["path"] = "/org/freedesktop/NetworkManager/ActiveConnection/replaced"
        client["uuid"] = "a-different-client-profile"

        second = self.manager.handle(
            {"op": "start", "confirmationToken": first["confirmationToken"]}
        )
        self.assertTrue(second["confirmationRequired"])
        self.assertNotEqual(first["confirmationToken"], second["confirmationToken"])
        self.assertEqual(self.nm.activate_calls, [])

    def test_foreign_ap_mode_adapter_is_not_selected(self):
        self.configure()
        self.nm.state["devices"][0]["mode"] = hotspot_backend.WIFI_MODE_AP
        self.nm.state["active_connections"][0]["uuid"] = "foreign-hotspot-profile"
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertFalse(status["available"])
        self.assertFalse(status["canStart"])

    def test_profile_valid_when_networkmanager_omits_default_psk_flags(self):
        self.configure()
        owned_profile = next(
            p for p in self.nm.state["profiles"]
            if p["settings"]["connection"]["uuid"] == hotspot_backend.OWNED_UUID
        )
        # NetworkManager GetSettings often omits psk-flags when default 0
        del owned_profile["settings"]["802-11-wireless-security"]["psk-flags"]
        self.assertTrue(hotspot_backend._profile_is_valid(owned_profile["settings"]))
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertTrue(status["profileConfigured"])

    def test_stop_deactivates_only_owned_active_connection_and_keeps_profiles(self):
        self.configure()
        owned_profile_path = next(
            profile["path"] for profile in self.nm.state["profiles"]
            if profile["settings"]["connection"]["uuid"] == hotspot_backend.OWNED_UUID
        )
        self.nm.state["active_connections"].append(
            {
                "path": HOTSPOT_ACTIVE,
                "uuid": hotspot_backend.OWNED_UUID,
                "type": "802-11-wireless",
                "devices": [WIFI_DEVICE],
                "state": 2,
                "default": False,
                "default6": False,
            }
        )
        self.nm.state["active_connections"].append(
            {
                "path": "/org/freedesktop/NetworkManager/ActiveConnection/foreign",
                "uuid": "foreign-profile",
                "type": "802-11-wireless",
                "devices": ["/org/freedesktop/NetworkManager/Devices/9"],
                "state": 2,
                "default": False,
                "default6": False,
            }
        )

        stopped = self.manager.handle({"op": "stop"})
        self.assertTrue(stopped["ok"])
        self.assertEqual(self.nm.deactivate_calls, [HOTSPOT_ACTIVE])
        self.assertEqual(len(self.nm.state["profiles"]), 2)
        self.assertIn(owned_profile_path, [p["path"] for p in self.nm.state["profiles"]])

    def test_owned_connection_is_not_reported_verified_until_device_is_in_ap_mode(self):
        self.configure()
        self.nm.state["active_connections"].append(
            {
                "path": HOTSPOT_ACTIVE,
                "uuid": hotspot_backend.OWNED_UUID,
                "type": "802-11-wireless",
                "devices": [WIFI_DEVICE],
                "state": 2,
                "default": False,
                "default6": False,
            }
        )
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertTrue(status["active"])
        self.assertFalse(status["verifiedActive"])
        self.assertEqual(status["tileStatus"], "Active profile needs review")

    def test_wrong_profile_attributes_at_owned_uuid_are_not_rewritten(self):
        self.nm.state["profiles"].append(
            {
                "path": "/org/freedesktop/NetworkManager/Settings/foreign",
                "settings": {
                    "connection": {
                        "uuid": hotspot_backend.OWNED_UUID,
                        "id": "User profile",
                        "type": "802-11-wireless",
                    },
                    "802-11-wireless": {"mode": "infrastructure"},
                    "ipv4": {"method": "auto"},
                },
            }
        )
        response = self.configure()
        self.assertFalse(response["ok"])
        self.assertEqual(self.nm.update_calls, [])
        self.assertEqual(self.nm.add_calls, [])

    def test_duplicate_owned_uuid_profiles_fail_closed(self):
        self.configure()
        owned = next(
            profile for profile in self.nm.state["profiles"]
            if profile["settings"]["connection"]["uuid"] == hotspot_backend.OWNED_UUID
        )
        duplicate = copy.deepcopy(owned)
        duplicate["path"] = "/org/freedesktop/NetworkManager/Settings/duplicate"
        self.nm.state["profiles"].append(duplicate)
        add_count = len(self.nm.add_calls)

        result = self.configure(ssid="Changed name", password="another-safe-pass")
        self.assertFalse(result["ok"])
        self.assertEqual(len(self.nm.add_calls), add_count)
        self.assertEqual(self.nm.update_calls, [])

    def test_foreign_profile_name_does_not_establish_ownership(self):
        foreign = {
            "path": "/org/freedesktop/NetworkManager/Settings/foreign-hotspot",
            "settings": {
                "connection": {
                    "uuid": "foreign-hotspot-uuid",
                    "id": "Rice Shell Hotspot",
                    "type": "802-11-wireless",
                }
            },
        }
        self.nm.state["profiles"].append(copy.deepcopy(foreign))
        response = self.configure()
        self.assertTrue(response["ok"])
        self.assertEqual(self.nm.update_calls, [])
        preserved = next(
            profile for profile in self.nm.state["profiles"]
            if profile["path"] == foreign["path"]
        )
        self.assertEqual(preserved, foreign)

    def test_missing_bound_adapter_does_not_activate_on_another_adapter(self):
        self.configure()
        self.nm.state["devices"][0]["managed"] = False
        self.nm.state["devices"].append(
            {
                "path": "/org/freedesktop/NetworkManager/Devices/8",
                "interface": "wlan1",
                "device_type": 2,
                "managed": True,
                "state": 30,
                "mode": 1,
                "capabilities": 0x68,
                "active_connection": "/",
            }
        )

        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertEqual(status["deviceName"], "wlan1")
        self.assertFalse(status["canStart"])
        self.manager.handle({"op": "start"})
        self.assertEqual(self.nm.activate_calls, [])

    def test_start_is_unavailable_without_default_upstream(self):
        self.configure()
        self.nm.state["active_connections"] = []
        status = self.manager.handle({"op": "status"})
        self.assertFalse(status["snapshot"]["canStart"])
        result = self.manager.handle({"op": "start"})
        self.assertFalse(result["ok"])
        self.assertEqual(self.nm.activate_calls, [])

    def test_wifi_radio_off_is_never_enabled_by_hotspot_start(self):
        self.configure()
        self.nm.state["wireless_enabled"] = False
        result = self.manager.handle({"op": "start"})
        self.assertFalse(result["ok"])
        self.assertFalse(result["snapshot"]["canStart"])
        self.assertFalse(self.nm.state["wireless_enabled"])
        self.assertEqual(self.nm.activate_calls, [])

    def test_network_control_permission_is_required_to_start(self):
        self.configure()
        self.nm.state["permissions"]["network-control"] = "no"
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertFalse(status["canStart"])
        self.manager.handle({"op": "start"})
        self.assertEqual(self.nm.activate_calls, [])

    def test_missing_secure_ap_capability_prevents_profile_creation(self):
        self.nm.state["devices"][0]["capabilities"] = 0x48
        status = self.manager.handle({"op": "status"})["snapshot"]
        result = self.configure()
        self.assertFalse(status["available"])
        self.assertFalse(result["ok"])
        self.assertEqual(self.nm.add_calls, [])

    def test_ipv6_only_default_does_not_satisfy_shared_ipv4_upstream(self):
        self.configure()
        self.nm.state["active_connections"][0]["default"] = False
        self.nm.state["active_connections"][0]["default6"] = True
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertFalse(status["canStart"])

    def test_existing_profile_can_start_without_profile_edit_permission(self):
        self.configure()
        self.nm.state["permissions"]["settings.modify.system"] = "no"
        status = self.manager.handle({"op": "status"})["snapshot"]
        self.assertFalse(status["canConfigure"])
        self.assertTrue(status["canStart"])

    def test_password_is_not_returned_in_backend_response(self):
        password = "sensitive-local-only"
        response = self.manager.handle(
            {"op": "configure", "ssid": "Rice Test", "password": password}
        )
        self.assertNotIn(password, json.dumps(response))

    def test_profile_is_marshaled_as_networkmanager_dbus_settings_without_bus_access(self):
        try:
            import gi
            gi.require_version("GLib", "2.0")
            from gi.repository import GLib
        except Exception:
            self.skipTest("PyGObject is unavailable")

        password = "variant-test-pass"
        settings = hotspot_backend.build_profile_settings("Rice Test", password, "wlan0")
        profile_data = hotspot_backend.GioNetworkManager._profile_data(settings, GLib)
        variant = GLib.Variant("a{sa{sv}}", profile_data)
        unpacked = hotspot_backend._deep_unpack(variant)
        call_args = GLib.Variant(
            "(a{sa{sv}}ua{sv})",
            (profile_data, 1, {}),
        )
        self.assertEqual(variant.get_type_string(), "a{sa{sv}}")
        self.assertEqual(call_args.get_type_string(), "(a{sa{sv}}ua{sv})")
        self.assertEqual(bytes(unpacked["802-11-wireless"]["ssid"]), b"Rice Test")
        self.assertEqual(unpacked["802-11-wireless-security"]["psk"], password)


if __name__ == "__main__":
    unittest.main()
