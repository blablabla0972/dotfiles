#!/usr/bin/env python3
"""Narrow NetworkManager D-Bus owner for the Rice Shell hotspot profile."""

import hashlib
import json
import os
import sys
import time


OWNED_UUID = "b9beef9b-89c9-4118-92e4-f18f07c8ef72"
PROFILE_ID = "Rice Shell Hotspot"
NM_SERVICE = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
NM_SETTINGS_PATH = "/org/freedesktop/NetworkManager/Settings"
NM_IFACE = "org.freedesktop.NetworkManager"
NM_DEVICE_IFACE = "org.freedesktop.NetworkManager.Device"
NM_WIFI_IFACE = "org.freedesktop.NetworkManager.Device.Wireless"
NM_ACTIVE_IFACE = "org.freedesktop.NetworkManager.Connection.Active"
NM_SETTINGS_IFACE = "org.freedesktop.NetworkManager.Settings"
NM_PROFILE_IFACE = "org.freedesktop.NetworkManager.Settings.Connection"
DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
WIFI_DEVICE_TYPE = 2
WIFI_CAP_CCMP = 0x08
WIFI_CAP_RSN = 0x20
WIFI_CAP_AP = 0x40
ACTIVE_STATE_ACTIVATED = 2
WIFI_MODE_AP = 3


class HotspotError(Exception):
    """A safe, user-facing error that contains no profile secret."""


def validate_configuration(ssid, password):
    if not isinstance(ssid, str) or not isinstance(password, str):
        raise HotspotError("Enter a network name and password.")
    try:
        ssid_bytes = ssid.encode("utf-8")
        password_bytes = password.encode("utf-8")
    except UnicodeEncodeError as error:
        raise HotspotError("The network name or password contains invalid text.") from error
    if not 1 <= len(ssid_bytes) <= 32:
        raise HotspotError("The network name must use 1 to 32 UTF-8 bytes.")
    if not 8 <= len(password_bytes) <= 63:
        raise HotspotError("The WPA2 password must use 8 to 63 UTF-8 bytes.")
    return ssid_bytes


def build_profile_settings(ssid, password, interface_name):
    ssid_bytes = validate_configuration(ssid, password)
    if not isinstance(interface_name, str) or not interface_name:
        raise HotspotError("No suitable Wi-Fi adapter is available.")
    return {
        "connection": {
            "id": PROFILE_ID,
            "uuid": OWNED_UUID,
            "type": "802-11-wireless",
            "interface-name": interface_name,
            "autoconnect": False,
        },
        "802-11-wireless": {
            "mode": "ap",
            "ssid": ssid_bytes,
            "security": "802-11-wireless-security",
            "hidden": False,
        },
        "802-11-wireless-security": {
            "key-mgmt": "wpa-psk",
            "auth-alg": "open",
            "proto": ["rsn"],
            "pairwise": ["ccmp"],
            "group": ["ccmp"],
            "psk": password,
            "psk-flags": 0,
        },
        "ipv4": {"method": "shared"},
        "ipv6": {"method": "ignore"},
    }


def _setting(settings, name):
    return settings.get(name, {}) if isinstance(settings, dict) else {}


def _ssid_is_valid(value):
    try:
        raw = bytes(value)
        return 1 <= len(raw) <= 32 and bool(raw.decode("utf-8"))
    except (TypeError, ValueError, UnicodeDecodeError):
        return False


def _profile_is_valid(settings):
    connection = _setting(settings, "connection")
    wireless = _setting(settings, "802-11-wireless")
    security = _setting(settings, "802-11-wireless-security")
    ipv4 = _setting(settings, "ipv4")
    wireless_sec = wireless.get("security")
    return (
        connection.get("uuid") == OWNED_UUID
        and connection.get("type") == "802-11-wireless"
        and connection.get("autoconnect") is False
        and bool(connection.get("interface-name"))
        and wireless.get("mode") == "ap"
        and _ssid_is_valid(wireless.get("ssid"))
        and (wireless_sec is None or wireless_sec == "802-11-wireless-security")
        and security.get("key-mgmt") == "wpa-psk"
        and security.get("proto") == ["rsn"]
        and security.get("pairwise") == ["ccmp"]
        and security.get("group") == ["ccmp"]
        and security.get("psk-flags", 0) == 0
        and ipv4.get("method") == "shared"
    )


def _decode_ssid(value):
    if isinstance(value, (bytes, bytearray, list, tuple)):
        try:
            return bytes(value).decode("utf-8")
        except (UnicodeDecodeError, ValueError):
            return ""
    return ""


def _permission(permissions, name):
    full_name = "org.freedesktop.NetworkManager." + name
    return permissions.get(full_name, permissions.get(name, "no")) in ("yes", "auth")


def _owned_profile(state):
    matches = []
    for profile in state.get("profiles", []):
        settings = profile.get("settings", {})
        if _setting(settings, "connection").get("uuid") == OWNED_UUID:
            matches.append(profile)
    if len(matches) > 1:
        raise HotspotError("Multiple profiles use the Rice Shell UUID; no profile was changed.")
    return matches[0] if matches else None


def _owned_active(state):
    return next(
        (active for active in state.get("active_connections", [])
         if active.get("uuid") == OWNED_UUID),
        None,
    )


class HotspotManager:
    """Implements the profile lifecycle against a small NetworkManager adapter."""

    def __init__(self, network_manager):
        self.nm = network_manager

    def handle(self, request):
        request_id = request.get("requestId")
        try:
            operation = request.get("op", "status")
            if operation == "status":
                result = {"ok": True, "snapshot": self.snapshot()}
            elif operation == "configure":
                result = self._configure(request)
            elif operation == "start":
                result = self._start(request)
            elif operation == "stop":
                result = self._stop()
            else:
                raise HotspotError("Unsupported hotspot request.")
        except HotspotError as error:
            result = {"ok": False, "error": str(error)}
            try:
                result["snapshot"] = self.snapshot()
            except Exception:
                result["snapshot"] = self._unavailable_snapshot()
        except Exception:
            # D-Bus errors may contain a serialized method payload. Never forward them.
            result = {
                "ok": False,
                "error": "NetworkManager could not complete the hotspot request.",
                "snapshot": self._unavailable_snapshot(),
            }
        if request_id is not None:
            result["requestId"] = request_id
        return result

    def snapshot(self, state=None):
        if state is None:
            state = self.nm.snapshot()
        profile = _owned_profile(state)
        profile_settings = profile.get("settings", {}) if profile else {}
        profile_valid = bool(profile and _profile_is_valid(profile_settings))
        owned_active = _owned_active(state)
        active = bool(owned_active and owned_active.get("state", ACTIVE_STATE_ACTIVATED)
                      in (1, ACTIVE_STATE_ACTIVATED, 3))

        active_device_paths = set(owned_active.get("devices", [])) if owned_active else set()
        devices = [
            device for device in state.get("devices", [])
            if device.get("device_type") == WIFI_DEVICE_TYPE and device.get("managed", True)
            and (device.get("capabilities", 0) & (WIFI_CAP_AP | WIFI_CAP_RSN | WIFI_CAP_CCMP))
            == (WIFI_CAP_AP | WIFI_CAP_RSN | WIFI_CAP_CCMP)
            and (device.get("mode") != WIFI_MODE_AP or device.get("path") in active_device_paths)
        ]
        bound_interface = _setting(profile_settings, "connection").get("interface-name")
        device = next((item for item in devices if item["path"] in active_device_paths), None)
        if device is None and bound_interface:
            device = next((item for item in devices
                           if item.get("interface") == bound_interface), None)
        if device is None:
            def device_priority(item):
                has_client = any(
                    active_item.get("type") == "802-11-wireless"
                    and item["path"] in active_item.get("devices", [])
                    and active_item.get("uuid") != OWNED_UUID
                    and active_item.get("state", ACTIVE_STATE_ACTIVATED)
                    in (1, ACTIVE_STATE_ACTIVATED)
                    for active_item in state.get("active_connections", [])
                )
                return (has_client, item.get("interface", "").casefold())

            device = next(iter(sorted(devices, key=device_priority)), None)

        active_client = None
        if device:
            active_client = next(
                (item for item in state.get("active_connections", [])
                 if item.get("type") == "802-11-wireless"
                 and item.get("uuid") != OWNED_UUID
                 and device["path"] in item.get("devices", [])
                 and item.get("state", ACTIVE_STATE_ACTIVATED)
                 in (1, ACTIVE_STATE_ACTIVATED)),
                None,
            )

        verified_active = bool(
            active and owned_active
            and owned_active.get("state") == ACTIVE_STATE_ACTIVATED
            and profile_valid and device
            and device.get("path") in active_device_paths
            and device.get("mode") == WIFI_MODE_AP
        )

        upstream = next(
            (item for item in state.get("active_connections", [])
             if item.get("uuid") != OWNED_UUID
             and item.get("state", ACTIVE_STATE_ACTIVATED) == ACTIVE_STATE_ACTIVATED
             and item.get("default")),
            None,
        )

        independent_upstream = None
        if upstream and device:
            if device.get("path") not in upstream.get("devices", []):
                independent_upstream = upstream
        elif upstream and not device:
            independent_upstream = upstream

        permissions = state.get("permissions", {})
        modify_allowed = state.get("can_modify", True) and _permission(
            permissions, "settings.modify.system"
        )
        network_allowed = _permission(permissions, "network-control")
        wifi_share_allowed = _permission(permissions, "wifi.share.protected")
        wifi_ready = bool(
            state.get("networking_enabled")
            and state.get("wireless_enabled")
            and state.get("wireless_hardware_enabled")
        )
        configured = bool(profile_valid)
        profile_device_matches = bool(
            configured and device and bound_interface == device.get("interface")
        )
        can_configure = bool(device and modify_allowed)
        can_start = bool(
            device and wifi_ready and network_allowed and wifi_share_allowed and configured
            and profile_device_matches and (independent_upstream or (active_client and active_client.get("default"))) and not active
        )

        if active and verified_active:
            tile_status, lifecycle_state = "On", "active"
        elif active and owned_active.get("state") == 1:
            tile_status, lifecycle_state = "Starting…", "starting"
        elif active and owned_active.get("state") == 3:
            tile_status, lifecycle_state = "Stopping…", "stopping"
        elif active:
            tile_status, lifecycle_state = "Active profile needs review", "error"
        elif not state.get("networking_enabled", False):
            tile_status, lifecycle_state = "Unavailable", "unavailable"
        elif not state.get("wireless_hardware_enabled", False):
            tile_status, lifecycle_state = "Hardware blocked", "unavailable"
        elif not state.get("wireless_enabled", False):
            tile_status, lifecycle_state = "Turn Wi-Fi on", "off"
        elif not devices:
            tile_status, lifecycle_state = "Secure AP unavailable", "unavailable"
        elif not configured and not modify_allowed:
            tile_status, lifecycle_state = "Permission required", "unavailable"
        elif not network_allowed or not wifi_share_allowed:
            tile_status, lifecycle_state = "Permission required", "unavailable"
        elif profile and not profile_valid:
            tile_status, lifecycle_state = "Profile needs repair", "error"
        elif configured and not profile_device_matches:
            tile_status, lifecycle_state = "Saved adapter unavailable", "error"
        elif not configured:
            tile_status, lifecycle_state = "Set up hotspot", "off"
        elif not upstream and not independent_upstream:
            tile_status, lifecycle_state = "No upstream", "off"
        elif not independent_upstream:
            tile_status, lifecycle_state = "Local AP only", "off"
        else:
            tile_status, lifecycle_state = "Ready", "off"

        upstream_type = ""
        effective_upstream = independent_upstream if independent_upstream else (upstream if not active else None)
        if effective_upstream:
            upstream_type = {
                "802-3-ethernet": "Ethernet",
                "802-11-wireless": "Wi-Fi",
            }.get(effective_upstream.get("type"), "Other network")

        if active and verified_active:
            if independent_upstream:
                upstream_status = upstream_type + " route available; internet reachability is unverified."
                upstream_available = True
            else:
                upstream_status = "No active upstream route; internet sharing is unavailable."
                upstream_available = False
        elif active:
            upstream_status = "NetworkManager status is unverified; internet sharing is unavailable."
            upstream_available = False
        elif independent_upstream:
            upstream_status = upstream_type + " route available."
            upstream_available = True
        elif active_client and active_client.get("default"):
            upstream_status = "Wi-Fi client on " + (device.get("interface", "this adapter")) + " will disconnect. Starting will provide a local network with no Internet sharing."
            upstream_available = False
        else:
            upstream_status = "Connect an upstream network before starting."
            upstream_available = False

        profile_ssid = _decode_ssid(_setting(profile_settings, "802-11-wireless").get("ssid"))
        interface_name = device.get("interface", "") if device else ""
        return {
            "available": bool(devices),
            "state": lifecycle_state,
            "active": active,
            "verifiedActive": verified_active,
            "canStart": can_start,
            "canConfigure": can_configure,
            "busy": False,
            "tileStatus": tile_status,
            "deviceName": interface_name,
            # WifiDrawer.qml matches this string to NetworkDevice.name/address.
            "devicePath": interface_name,
            "ssid": profile_ssid,
            "profileConfigured": configured,
            "security": "WPA2-Personal (RSN)" if configured and verified_active
            else ("Unverified active profile" if active else "WPA2-Personal (RSN) required"),
            "upstreamAvailable": upstream_available,
            "upstreamStatus": upstream_status,
            "clientConflict": bool(active_client),
            "error": "The owned profile settings do not match the secure hotspot configuration."
            if profile and not profile_valid else (
                "NetworkManager has not verified the owned adapter in AP mode."
                if active and not verified_active else ""
            ),
        }

    @staticmethod
    def _unavailable_snapshot():
        return {
            "available": False,
            "state": "unavailable",
            "active": False,
            "verifiedActive": False,
            "canStart": False,
            "canConfigure": False,
            "busy": False,
            "tileStatus": "NetworkManager unavailable",
            "deviceName": "",
            "devicePath": "",
            "ssid": "",
            "profileConfigured": False,
            "security": "",
            "upstreamAvailable": False,
            "upstreamStatus": "NetworkManager status is unavailable.",
            "clientConflict": False,
            "error": "NetworkManager is unavailable.",
        }

    def _configure(self, request):
        ssid = request.get("ssid")
        password = request.get("password", "")
        state = self.nm.snapshot()
        status = self.snapshot(state)
        if status["active"]:
            raise HotspotError("Stop the hotspot before changing its profile.")
        if not status["canConfigure"]:
            raise HotspotError("A permitted, secure-capable Wi-Fi adapter is unavailable.")
        profile = _owned_profile(state)
        if profile and not _profile_is_valid(profile.get("settings", {})):
            raise HotspotError("The exact Rice Shell profile has unexpected settings; it was left unchanged.")
        if profile and password == "":
            existing_ssid = _decode_ssid(
                _setting(profile.get("settings", {}), "802-11-wireless").get("ssid")
            )
            existing_interface = _setting(profile.get("settings", {}), "connection").get(
                "interface-name"
            )
            if ssid != existing_ssid or existing_interface != status["deviceName"]:
                raise HotspotError("Enter the saved password to change the network name or adapter.")
            return {"ok": True, "snapshot": self.snapshot(state)}
        if not password:
            raise HotspotError("Enter a WPA2 password to save this hotspot.")
        profile_settings = build_profile_settings(ssid, password, status["deviceName"])
        if profile:
            self.nm.update_profile(profile["path"], profile_settings)
        else:
            self.nm.add_profile(profile_settings)
        fresh_state = self.nm.snapshot()
        fresh_profile = _owned_profile(fresh_state)
        fresh_status = self.snapshot(fresh_state)
        if not fresh_profile or not _profile_is_valid(fresh_profile.get("settings", {})):
            raise HotspotError("NetworkManager did not accept the profile settings.")
        return {"ok": True, "snapshot": fresh_status}

    def _confirmation_token(self, device, client):
        identity = "\0".join((
            OWNED_UUID,
            device.get("path", "") if device else "",
            client.get("path", "") if client else "",
            client.get("uuid", "") if client else "",
        ))
        return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:32]

    def _start(self, request):
        state = self.nm.snapshot()
        status = self.snapshot(state)
        if status["active"]:
            return {"ok": True, "snapshot": status}
        profile = _owned_profile(state)
        if profile and not _profile_is_valid(profile.get("settings", {})):
            raise HotspotError("The exact Rice Shell profile has unexpected settings; it was left unchanged.")
        if not profile:
            raise HotspotError("Set up and save the protected hotspot first.")
        if not status["canStart"]:
            raise HotspotError(status["tileStatus"] + ". Hotspot was not started.")
        device = next(
            (item for item in state.get("devices", [])
             if item.get("interface") == status["deviceName"]
             and item.get("device_type") == WIFI_DEVICE_TYPE),
            None,
        )
        if not device:
            raise HotspotError("The Wi-Fi adapter was removed before the hotspot could start.")
        conflict = next(
            (item for item in state.get("active_connections", [])
             if item.get("type") == "802-11-wireless"
             and item.get("uuid") != OWNED_UUID
             and device["path"] in item.get("devices", [])
             and item.get("state", ACTIVE_STATE_ACTIVATED)
             in (1, ACTIVE_STATE_ACTIVATED)),
            None,
        )
        token = self._confirmation_token(device, conflict) if conflict else ""
        if conflict and request.get("confirmationToken") != token:
            return {
                "ok": False,
                "confirmationRequired": True,
                "confirmationToken": token,
                "error": "Starting will disconnect the Wi-Fi client on this adapter.",
                "snapshot": status,
            }

        previous_profile_path = conflict.get("connection", "") if conflict else ""
        try:
            self.nm.activate(profile["path"], device["path"])
            deadline = time.monotonic() + 10.0
            while time.monotonic() < deadline:
                fresh_state = self.nm.snapshot()
                verified = self.snapshot(fresh_state)
                if verified.get("verifiedActive"):
                    return {"ok": True, "snapshot": verified}
                time.sleep(0.2)
            raise HotspotError("NetworkManager did not confirm the hotspot became active.")
        except Exception as error:
            self._rollback_partial_start(device["path"], previous_profile_path)
            if isinstance(error, HotspotError):
                raise
            raise HotspotError("Hotspot activation failed; unrelated connections and profiles were preserved.")

    def _rollback_partial_start(self, device_path, previous_profile_path):
        try:
            state = self.nm.snapshot()
            for active in state.get("active_connections", []):
                if active.get("uuid") == OWNED_UUID and device_path in active.get("devices", []):
                    self.nm.deactivate(active["path"])
            if not previous_profile_path:
                return
            state = self.nm.snapshot()
            device = next((item for item in state.get("devices", [])
                           if item.get("path") == device_path), None)
            if not device or not state.get("wireless_enabled") or not state.get("wireless_hardware_enabled"):
                return
            if any(item.get("type") == "802-11-wireless"
                   and device_path in item.get("devices", [])
                   and item.get("uuid") != OWNED_UUID
                   and item.get("state", ACTIVE_STATE_ACTIVATED)
                   == ACTIVE_STATE_ACTIVATED
                   for item in state.get("active_connections", [])):
                return
            self.nm.activate(previous_profile_path, device_path)
        except Exception:
            # Leave the actual state for the next status update; never broaden rollback.
            return

    def _stop(self):
        state = self.nm.snapshot()
        active = _owned_active(state)
        if active and active.get("state", ACTIVE_STATE_ACTIVATED) in (1, ACTIVE_STATE_ACTIVATED):
            self.nm.deactivate(active["path"])
        if active and active.get("state", ACTIVE_STATE_ACTIVATED) in (1, ACTIVE_STATE_ACTIVATED, 3):
            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                fresh_state = self.nm.snapshot()
                status = self.snapshot(fresh_state)
                if not status["active"]:
                    return {"ok": True, "snapshot": status}
                time.sleep(0.2)
            raise HotspotError("NetworkManager did not confirm the hotspot stopped.")
        return {"ok": True, "snapshot": self.snapshot(state)}


def _deep_unpack(value):
    if hasattr(value, "unpack"):
        return _deep_unpack(value.unpack())
    if isinstance(value, dict):
        return {key: _deep_unpack(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_deep_unpack(item) for item in value]
    return value


class GioNetworkManager:
    """Small Gio D-Bus adapter; profile secrets never leave this process via stdout."""

    def __init__(self, connection, gio, glib):
        self.connection = connection
        self.gio = gio
        self.glib = glib

    @classmethod
    def connect(cls):
        import gi

        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib

        connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        return cls(connection, Gio, GLib)

    def _call(self, path, interface, method, signature="", values=()):
        parameters = self.glib.Variant("(" + signature + ")", tuple(values))
        result = self.connection.call_sync(
            NM_SERVICE,
            path,
            interface,
            method,
            parameters,
            None,
            self.gio.DBusCallFlags.NONE,
            8000,
            None,
        )
        return _deep_unpack(result)

    def _properties(self, path, interface):
        return self._call(
            path, DBUS_PROPERTIES_IFACE, "GetAll", "s", (interface,)
        )[0]

    def snapshot(self):
        manager = self._properties(NM_PATH, NM_IFACE)
        settings = self._properties(NM_SETTINGS_PATH, NM_SETTINGS_IFACE)
        permissions = self._call(NM_PATH, NM_IFACE, "GetPermissions")[0]
        devices = []
        for path in manager.get("Devices", []):
            props = self._properties(path, NM_DEVICE_IFACE)
            if props.get("DeviceType") != WIFI_DEVICE_TYPE:
                continue
            wireless = self._properties(path, NM_WIFI_IFACE)
            devices.append({
                "path": path,
                "interface": props.get("Interface", ""),
                "device_type": props.get("DeviceType", 0),
                "managed": props.get("Managed", False),
                "state": props.get("State", 0),
                "mode": wireless.get("Mode", 0),
                "capabilities": wireless.get("WirelessCapabilities", 0),
                "active_connection": props.get("ActiveConnection", "/"),
            })

        active_connections = []
        for path in manager.get("ActiveConnections", []):
            try:
                props = self._properties(path, NM_ACTIVE_IFACE)
            except self.glib.Error as error:
                # A replaced Wi-Fi client may disappear after the list was read.
                if self.gio.DBusError.get_remote_error(error) in (
                    "org.freedesktop.DBus.Error.UnknownObject",
                    "org.freedesktop.DBus.Error.UnknownMethod",
                ):
                    continue
                raise
            active_connections.append({
                "path": path,
                "connection": props.get("Connection", "/"),
                "uuid": props.get("Uuid", ""),
                "type": props.get("Type", ""),
                "devices": props.get("Devices", []),
                "state": props.get("State", 0),
                "default": props.get("Default", False),
                "default6": props.get("Default6", False),
            })

        profiles = []
        try:
            owned_path = self._call(
                NM_SETTINGS_PATH, NM_SETTINGS_IFACE, "GetConnectionByUuid", "s", (OWNED_UUID,)
            )[0]
            if owned_path:
                profile_settings = self._call(
                    owned_path, NM_PROFILE_IFACE, "GetSettings"
                )[0]
                profiles.append({"path": owned_path, "settings": profile_settings})
        except Exception as error:
            err_msg = str(error).lower()
            if "no connection with the uuid" in err_msg or "invalidconnection" in err_msg or "not found" in err_msg:
                profiles = []
            else:
                raise

        return {
            "networking_enabled": manager.get("NetworkingEnabled", False),
            "wireless_enabled": manager.get("WirelessEnabled", False),
            "wireless_hardware_enabled": manager.get("WirelessHardwareEnabled", False),
            "can_modify": settings.get("CanModify", False),
            "permissions": permissions,
            "devices": devices,
            "active_connections": active_connections,
            "profiles": profiles,
        }

    @staticmethod
    def _variant(value, glib):
        if isinstance(value, bool):
            return glib.Variant("b", value)
        if isinstance(value, int):
            return glib.Variant("u", value)
        if isinstance(value, str):
            return glib.Variant("s", value)
        if isinstance(value, bytes):
            return glib.Variant("ay", list(value))
        if isinstance(value, (list, tuple)):
            if all(isinstance(item, str) for item in value):
                return glib.Variant("as", list(value))
            if all(isinstance(item, int) for item in value):
                return glib.Variant("au", list(value))
        raise HotspotError("Unsupported NetworkManager profile setting.")

    @classmethod
    def _profile_data(cls, settings, glib):
        return {
            name: {
                key: cls._variant(value, glib) for key, value in values.items()
            }
            for name, values in settings.items()
        }

    @classmethod
    def _profile_variant(cls, settings, glib):
        return glib.Variant("a{sa{sv}}", cls._profile_data(settings, glib))

    def add_profile(self, settings):
        profile_data = self._profile_data(settings, self.glib)
        args = self.glib.Variant("(a{sa{sv}}ua{sv})", (profile_data, 1, {}))
        result = self.connection.call_sync(
            NM_SERVICE,
            NM_SETTINGS_PATH,
            NM_SETTINGS_IFACE,
            "AddConnection2",
            args,
            None,
            self.gio.DBusCallFlags.NONE,
            8000,
            None,
        )
        return _deep_unpack(result)[0]

    def update_profile(self, path, settings):
        profile_data = self._profile_data(settings, self.glib)
        args = self.glib.Variant("(a{sa{sv}}ua{sv})", (profile_data, 1, {}))
        self.connection.call_sync(
            NM_SERVICE,
            path,
            NM_PROFILE_IFACE,
            "Update2",
            args,
            None,
            self.gio.DBusCallFlags.NONE,
            8000,
            None,
        )

    def activate(self, profile_path, device_path):
        return self._call(
            NM_PATH,
            NM_IFACE,
            "ActivateConnection",
            "ooo",
            (profile_path, device_path, "/"),
        )[0]

    def deactivate(self, active_path):
        self._call(NM_PATH, NM_IFACE, "DeactivateConnection", "o", (active_path,))


def _emit(result):
    sys.stdout.write(json.dumps(result, ensure_ascii=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def _main():
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        nm = GioNetworkManager.connect()
    except Exception:
        _emit({
            "ok": False,
            "error": "GIO D-Bus support or the NetworkManager system bus is unavailable.",
            "snapshot": HotspotManager._unavailable_snapshot(),
        })
        return 1

    manager = HotspotManager(nm)
    main_loop = GLib.MainLoop()
    input_buffer = bytearray()
    pending_refresh = [False]

    def emit_snapshot():
        pending_refresh[0] = False
        _emit(manager.handle({"op": "status"}))
        return GLib.SOURCE_REMOVE

    def on_nm_signal(_connection, _sender, object_path, signal_interface,
                     signal_name, parameters, _user_data):
        if signal_interface == DBUS_PROPERTIES_IFACE and signal_name == "PropertiesChanged":
            try:
                changed_interface, changed_properties, _invalidated = _deep_unpack(parameters)
            except Exception:
                return
            changed = set(changed_properties)
            if object_path == NM_PATH and changed_interface == NM_IFACE:
                relevant = {
                    "NetworkingEnabled", "WirelessEnabled", "WirelessHardwareEnabled",
                    "ActiveConnections", "Devices",
                }
            elif object_path == NM_SETTINGS_PATH and changed_interface == NM_SETTINGS_IFACE:
                relevant = {"CanModify", "Connections"}
            elif object_path.startswith(NM_PATH + "/Devices/") \
                    and changed_interface == NM_DEVICE_IFACE:
                relevant = {"State", "ActiveConnection", "Managed", "DeviceType"}
            elif object_path.startswith(NM_PATH + "/Devices/") \
                    and changed_interface == NM_WIFI_IFACE:
                relevant = {"Mode", "WirelessCapabilities"}
            elif object_path.startswith(NM_PATH + "/ActiveConnection/") \
                    and changed_interface == NM_ACTIVE_IFACE:
                relevant = {"State", "Default", "Default6", "Devices", "Uuid", "Type"}
            else:
                return
            if not changed.intersection(relevant):
                return
        if not pending_refresh[0]:
            pending_refresh[0] = True
            GLib.timeout_add(150, emit_snapshot)

    def on_input(_fd, condition):
        try:
            chunk = os.read(sys.stdin.fileno(), 4096)
        except BlockingIOError:
            return GLib.SOURCE_CONTINUE
        if not chunk:
            main_loop.quit()
            return GLib.SOURCE_REMOVE
        input_buffer.extend(chunk)
        if len(input_buffer) > 8192 and b"\n" not in input_buffer:
            input_buffer.clear()
            _emit({"ok": False, "error": "Hotspot request is too large."})
            return GLib.SOURCE_CONTINUE
        while b"\n" in input_buffer:
            line, _, remainder = input_buffer.partition(b"\n")
            input_buffer[:] = remainder
            if len(line) > 8192:
                _emit({"ok": False, "error": "Hotspot request is too large."})
                continue
            try:
                request = json.loads(line.decode("utf-8"))
                if not isinstance(request, dict):
                    raise ValueError
                _emit(manager.handle(request))
            except Exception:
                _emit({"ok": False, "error": "Invalid hotspot request."})
        return GLib.SOURCE_CONTINUE

    try:
        nm.connection.signal_subscribe(
            NM_SERVICE,
            DBUS_PROPERTIES_IFACE,
            "PropertiesChanged",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_nm_signal,
            None,
        )
        for interface, member, path in (
            (NM_PROFILE_IFACE, "Updated", None),
            (NM_PROFILE_IFACE, "Removed", None),
            (NM_SETTINGS_IFACE, "NewConnection", NM_SETTINGS_PATH),
            (NM_SETTINGS_IFACE, "ConnectionRemoved", NM_SETTINGS_PATH),
            (NM_IFACE, "CheckPermissions", NM_PATH),
            (NM_IFACE, "StateChanged", NM_PATH),
            (NM_IFACE, "DeviceAdded", NM_PATH),
            (NM_IFACE, "DeviceRemoved", NM_PATH),
            (NM_DEVICE_IFACE, "StateChanged", None),
            (NM_ACTIVE_IFACE, "StateChanged", None),
        ):
            nm.connection.signal_subscribe(
                NM_SERVICE,
                interface,
                member,
                path,
                None,
                Gio.DBusSignalFlags.NONE,
                on_nm_signal,
                None,
            )
        nm.connection.signal_subscribe(
            "org.freedesktop.DBus",
            "org.freedesktop.DBus",
            "NameOwnerChanged",
            "/org/freedesktop/DBus",
            NM_SERVICE,
            Gio.DBusSignalFlags.NONE,
            on_nm_signal,
            None,
        )
        os.set_blocking(sys.stdin.fileno(), False)
        GLib.io_add_watch(
            sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_input
        )
        emit_snapshot()
        main_loop.run()
    except Exception:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
