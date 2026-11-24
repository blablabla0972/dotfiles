"""Guarded Hyprland display previews. Only Keep publishes a startup rule."""

import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time

from preferences import Conflict, Invalid, LIMIT, encode, lock, open_store, parse, read_member, revision, write_member

OVERRIDES = "hypr-overrides.lua"
PENDING = "display-preview.json"
PREVIEW_SECONDS = 15
SCALES = (0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3)
NAME = r"[A-Za-z0-9_-]{1,64}"
MODE = r"(\d{2,5})x(\d{2,5})@(\d{1,4}(?:\.\d{1,6})?)Hz"
NUMBER = r"\d(?:\.\d{1,6})?"
SESSION = r"[a-zA-Z0-9_-]{1,160}"
TOKEN = r"[0-9a-f]{24}"
RULE = re.compile(r'hl\.monitor\(\{output="(' + NAME + r')",mode="(' + MODE
                  + r')",position="(-?\d{1,6})x(-?\d{1,6})",scale=(' + NUMBER + r'),transform=([0-7])\}\)')


def clock():
    return time.clock_gettime(time.CLOCK_BOOTTIME)


def session():
    value = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not re.fullmatch(SESSION, value):
        raise Invalid("session_unavailable")
    return value


def command(*args, timeout=3, env=None):
    try:
        result = subprocess.run(args, check=True, capture_output=True, timeout=timeout, env=env)
    except (OSError, subprocess.SubprocessError) as error:
        raise Invalid("compositor_unavailable") from error
    if len(result.stdout) > LIMIT:
        raise Invalid("invalid_inventory")
    return result.stdout.decode("utf-8").strip()


def inventory():
    data = parse(command("hyprctl", "-j", "monitors"))
    if not isinstance(data, list) or not all(isinstance(item, dict)
            and isinstance(item.get("name"), str) and re.fullmatch(NAME, item["name"]) for item in data):
        raise Invalid("invalid_inventory")
    if len({item["name"] for item in data}) != len(data):
        raise Invalid("invalid_inventory")
    return data


def config_errors():
    return command("hyprctl", "configerrors")


def reload_config():
    if command("hyprctl", "-r", "reload") != "ok":
        raise Invalid("recovery_unconfirmed")


def hook_exists():
    try:
        return (command("hyprctl", "eval",
                        'assert(package.loaded["config.rice-settings-outputs"], "missing display hook")') == "ok"
                and all(shutil.which(tool) for tool in ("systemctl", "systemd-run")))
    except Invalid:
        return False


def parse_mode(value):
    match = re.fullmatch(MODE, value) if isinstance(value, str) else None
    if not match:
        raise Invalid("invalid_mode")
    width, height, refresh = match.groups()
    return int(width), int(height), float(refresh)


def lua_rule(rule):
    name, mode, scale = rule["name"], rule["mode"], rule["scale"]
    parse_mode(mode)
    if (not isinstance(name, str) or not re.fullmatch(NAME, name)
            or type(scale) not in (int, float) or not 0.25 <= scale <= 5
            or any(type(rule[key]) is not int or abs(rule[key]) > 999999 for key in ("x", "y", "transform"))
            or not 0 <= rule["transform"] <= 7):
        raise Invalid("invalid_rule")
    return (f'hl.monitor({{output="{name}",mode="{mode}",position="{rule["x"]}x{rule["y"]}",'
            f'scale={scale:.6f},transform={rule["transform"]}}})')


def apply_rule(rule):
    # A Lua monitor rule is applied at the next render pre-check.
    if command("hyprctl", "-r", "eval", lua_rule(rule)) != "ok":
        raise Invalid("mode_rejected")


def confirmed_rules(raw):
    if raw is None:
        return {}
    try:
        rows = raw.decode("ascii").splitlines()
    except UnicodeDecodeError as error:
        raise Invalid("invalid_overrides") from error
    return parse_rules(rows)


def parse_rules(rows):
    rules = {}
    for row in rows:
        match = RULE.fullmatch(row)
        if not match:
            raise Invalid("invalid_overrides")
        name, mode, _width, _height, _hz, x, y, scale, transform = match.groups()
        if name in rules:
            raise Invalid("invalid_overrides")
        rule = dict(name=name, mode=mode, x=int(x), y=int(y), scale=float(scale), transform=int(transform))
        lua_rule(rule)
        rules[name] = rule
    return rules


def bytes_for(rules):
    return "".join(lua_rule(rules[name]) + "\n" for name in sorted(rules)).encode("ascii")


def identity(output):
    return [output.get(key) for key in ("name", "make", "model", "serial")]


def topology(outputs):
    return [identity(output) for output in sorted(outputs, key=lambda output: output["name"])]


def matches_mode(output, rule):
    width, height, rate = parse_mode(rule["mode"])
    try:
        return (output["width"] == width and output["height"] == height
                and abs(output["refreshRate"] - rate) < 0.08
                and abs(output["scale"] - rule["scale"]) < 0.006)
    except (KeyError, TypeError):
        return False


def matches(output, rule):
    return matches_mode(output, rule) and all(output.get(key) == rule[key] for key in ("x", "y", "transform"))


def compatible(output):
    return (not output.get("disabled") and output.get("dpmsStatus") is True
            and output.get("mirrorOf", "none") == "none" and not output.get("vrr")
            and output.get("currentFormat", "XRGB8888") == "XRGB8888"
            and output.get("colorManagementPreset", "srgb") == "srgb"
            and output.get("sdrBrightness", 1) == 1 and output.get("sdrSaturation", 1) == 1)


def safe_scales(mode):
    w, h, _ = parse_mode(mode)
    return [scale for scale in SCALES if all(abs(axis / scale - round(axis / scale)) < 0.001
                                           for axis in (w, h))]


def rules_for(output, request):
    if not compatible(output):
        raise Invalid("output_profile_unsupported")
    modes = output.get("availableModes")
    if not isinstance(modes, list):
        raise Invalid("invalid_inventory")
    mode, scale = request.get("mode"), request.get("scale")
    if mode not in modes or type(scale) not in (int, float) or scale not in safe_scales(mode):
        raise Invalid("invalid_mode")
    base = {key: output.get(key) for key in ("name", "x", "y", "transform", "scale")}
    old = None
    for offered in modes:
        if isinstance(offered, str) and re.fullmatch(MODE, offered):
            candidate = {**base, "mode": offered}
            if matches(output, candidate):
                old = candidate
                break
    if old is None:
        raise Invalid("current_mode_unverified")
    new = {**base, "mode": mode, "scale": scale}
    lua_rule(old)
    lua_rule(new)
    if matches(output, new):
        raise Invalid("already_active")
    return old, new


def arm_guard(token):
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    env = [f"XDG_CONFIG_HOME={base}", f"HYPRLAND_INSTANCE_SIGNATURE={session()}",
           f"XDG_RUNTIME_DIR={os.environ.get('XDG_RUNTIME_DIR', '')}"]
    unit = "rice-display-" + token
    manager_env = dict(os.environ, XDG_RUNTIME_DIR=f"/run/user/{os.getuid()}")
    try:
        command("systemd-run", "--user", "--quiet", "--collect", "--unit=" + unit,
                "--on-active=1s", "--timer-property=AccuracySec=100ms", "--property=RuntimeMaxSec=45s",
                *("--setenv=" + item for item in env),
                sys.executable, str(Path(__file__).resolve()), "watch", token, env=manager_env)
    except Invalid as error:
        raise Invalid("guard_unavailable") from error


def read_pending(directory):
    raw = read_member(directory, PENDING)
    if raw is None:
        return None, None
    data = parse(raw)
    if (not isinstance(data, dict) or not isinstance(data.get("token"), str) or not re.fullmatch(TOKEN, data["token"])
            or not isinstance(data.get("session"), str) or not re.fullmatch(SESSION, data["session"])
            or not isinstance(data.get("topology"), list) or not isinstance(data.get("targetIdentity"), list)
            or type(data.get("until")) not in (int, float) or not math.isfinite(data["until"])):
        raise Invalid("invalid_journal")
    try:
        lua_rule(data["old"])
        lua_rule(data["new"])
        if not all(isinstance(data[key], str) and re.fullmatch(r"missing|[0-9a-f]{64}", data[key])
                   for key in ("originalRevision", "committedRevision")):
            raise Invalid("invalid_journal")
    except (KeyError, TypeError):
        raise Invalid("invalid_journal") from None
    return raw, data


def clear_pending(directory, raw):
    if read_member(directory, PENDING) != raw:
        raise Conflict
    os.unlink(PENDING, dir_fd=directory)
    os.fsync(directory)


def output_for(outputs, name):
    return next((item for item in outputs if item["name"] == name), None)


def verify_rule(rule, expected_identity, *, limit=2.8, require_position=True):
    until = time.monotonic() + limit
    while time.monotonic() < until:
        output = output_for(inventory(), rule["name"])
        predicate = matches if require_position else matches_mode
        if output and identity(output) == expected_identity and predicate(output, rule) and not config_errors():
            return True
        time.sleep(0.13)
    return False


def pending_status(data):
    return {"status": "preview", "token": data["token"], "name": data["new"]["name"],
            "seconds": max(0, math.ceil(data["until"] - clock()))}


def revert(directory, raw, data, outputs, *, force=False):
    committed = read_member(directory, OVERRIDES)
    if revision(committed) == data["committedRevision"]:
        clear_pending(directory, raw)
        return {"status": "kept"}
    if session() != data["session"]:
        clear_pending(directory, raw)
        return {"status": "reverted"}
    old = data["old"]
    same_topology = topology(outputs) == data["topology"]
    output = output_for(outputs, old["name"])
    if not same_topology:
        reload_config()
        if config_errors():
            raise Invalid("recovery_unconfirmed")
        output = output_for(inventory(), old["name"])
    predicate = matches if same_topology else matches_mode
    if output and identity(output) == data["targetIdentity"] and not predicate(output, old):
        if force or predicate(output, data["new"]):
            restored = old if same_topology else {**old, **{key: output[key] for key in ("x", "y", "transform")}}
            apply_rule(restored)
            if not verify_rule(restored, data["targetIdentity"], require_position=same_topology):
                raise Invalid("recovery_unconfirmed")
        else:
            raise Invalid("external_display_change")
    clear_pending(directory, raw)
    return {"status": "reverted"}


def begin(directory, request, outputs):
    if not hook_exists() or config_errors():
        raise Invalid("display_hook_unavailable")
    output = output_for(outputs, request.get("name"))
    if not output:
        raise Invalid("output_unavailable")
    old, new = rules_for(output, request)
    original = read_member(directory, OVERRIDES)
    rules = confirmed_rules(original)
    rules[new["name"]] = new
    data = {"token": secrets.token_hex(12), "session": session(), "until": clock() + PREVIEW_SECONDS,
            "topology": topology(outputs), "targetIdentity": identity(output), "old": old, "new": new,
            "originalRevision": revision(original), "committedRevision": revision(bytes_for(rules))}
    if data["originalRevision"] == data["committedRevision"]:
        raise Invalid("already_saved")
    raw = encode(data)
    write_member(directory, PENDING, raw, None, create_only=True)
    try:
        arm_guard(data["token"])
    except Invalid:
        clear_pending(directory, raw)
        raise
    try:
        apply_rule(new)
        if not verify_rule(new, data["targetIdentity"]):
            raise Invalid("mode_unconfirmed")
    except Invalid:
        revert(directory, raw, data, inventory(), force=True)
        raise
    return pending_status(data)


def execute(action, request):
    if action not in ("available", "status", "preview", "keep", "revert", "recover") or not isinstance(request, dict):
        raise Invalid("invalid_request")
    if action == "available":
        return {"status": "available", "scales": SCALES} if hook_exists() else {"status": "unavailable"}
    with open_store(action == "preview") as directory:
        if directory is None:
            return {"status": "idle"}
        with lock(directory, ".display.lock"):
            raw, data = read_pending(directory)
            if data is None:
                if action == "preview":
                    return begin(directory, request, inventory())
                return {"status": "idle"}
            if action == "preview":
                raise Invalid("preview_in_progress")
            if action in ("keep", "revert") and request.get("token") != data["token"]:
                raise Invalid("invalid_token")
            if action == "status" and request.get("token") not in (None, data["token"]):
                return {"status": "idle"}
            outputs = inventory()
            if (action in ("revert", "recover") or session() != data["session"]
                    or clock() >= data["until"] or topology(outputs) != data["topology"]):
                return revert(directory, raw, data, outputs, force=action == "recover")
            target = output_for(outputs, data["new"]["name"])
            if action == "status":
                if not target or not matches(target, data["new"]):
                    return revert(directory, raw, data, outputs)
                return pending_status(data)
            if not target or not matches(target, data["new"]) or config_errors():
                return revert(directory, raw, data, outputs)
            original = read_member(directory, OVERRIDES)
            if revision(original) != data["originalRevision"]:
                revert(directory, raw, data, outputs)
                raise Conflict
            rules = confirmed_rules(original)
            rules[data["new"]["name"]] = data["new"]
            write_member(directory, OVERRIDES, bytes_for(rules), original, create_only=original is None)
            clear_pending(directory, raw)
            return {"status": "kept"}


def watch(token):
    until = clock() + PREVIEW_SECONDS + 10
    while clock() < until:
        try:
            if execute("status", {"token": token})["status"] != "preview":
                return
        except Invalid as error:
            if str(error) not in ("busy", "compositor_unavailable"):
                raise
        time.sleep(0.38)
    raise Invalid("recovery_unconfirmed")


def main():
    try:
        action = sys.argv[1] if len(sys.argv) >= 2 else ""
        if action == "watch" and len(sys.argv) == 3 and re.fullmatch(TOKEN, sys.argv[2]):
            watch(sys.argv[2])
            return
        if action == "cancel" and len(sys.argv) == 3 and re.fullmatch(TOKEN, sys.argv[2]):
            action, payload = "revert", {"token": sys.argv[2]}
        else:
            payload = {} if action in ("available", "recover") else parse(sys.stdin.buffer.readline(LIMIT + 1))
        result = execute(action, payload)
    except Conflict:
        result = {"status": "error", "reason": "overrides_changed"}
    except Invalid as error:
        result = {"status": "error", "reason": str(error)}
    except (OSError, ValueError, KeyError, TypeError):
        result = {"status": "error", "reason": "display_state_unavailable"}
    print(json.dumps(result, separators=(",", ":")))
    if action == "watch":
        sys.exit(1)


if __name__ == "__main__":
    main()
