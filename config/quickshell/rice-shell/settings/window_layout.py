"""Apply bounded window spacing through the existing Hyprland config loader."""

import json
import os
import re
import sys
import time

from displays import PENDING, command, config_errors
from preferences import Conflict, Invalid, LIMIT, lock, open_store, parse, read_member, revision, write_member

FILENAME = "window-layout.conf"
HOOK = 'package.loaded["config.rice-settings-window-layout"]'
PATTERN = re.compile(rb"gaps_in ((?:[0-9]{1,2} ){3}[0-9]{1,2})\n"
                     rb"gaps_out ((?:[0-9]{1,2} ){3}[0-9]{1,2})\nborder_size ([0-9]{1,2})\n")


def valid(layout):
    return (isinstance(layout, dict) and layout.keys() == {"inner", "outer", "border"}
            and type(layout["border"]) is int and 0 <= layout["border"] <= 12
            and all(isinstance(layout[key], list) and len(layout[key]) == 4
                    and all(type(value) is int and 0 <= value <= 40 for value in layout[key])
                    for key in ("inner", "outer")))


def encode(layout):
    if layout is None:
        return b""
    if not valid(layout):
        raise Invalid("invalid_layout")
    inner, outer = (" ".join(map(str, layout[key])) for key in ("inner", "outer"))
    return f'gaps_in {inner}\ngaps_out {outer}\nborder_size {layout["border"]}\n'.encode("ascii")


def decode(content):
    if not content:
        return None
    match = PATTERN.fullmatch(content)
    if not match:
        raise Invalid("invalid_layout_file")
    inner, outer, border = match.groups()
    values = {"inner": list(map(int, inner.split())), "outer": list(map(int, outer.split())), "border": int(border)}
    if not valid(values):
        raise Invalid("invalid_layout_file")
    return values


def getoption(key, value_type):
    reply = parse(command("hyprctl", "-j", "getoption", key))
    if not isinstance(reply, dict) or reply.get("option") != key or type(reply.get(value_type)) is not {
            "css": str, "int": int, "bool": bool}[value_type]:
        raise Invalid("option_unavailable")
    return reply[value_type]


def current():
    def gaps(key):
        value = getoption(key, "css")
        if not re.fullmatch(r"\d{1,4} \d{1,4} \d{1,4} \d{1,4}", value):
            raise Invalid("unknown_gaps")
        return list(map(int, value.split()))

    return {"inner": gaps("general:gaps_in"), "outer": gaps("general:gaps_out"),
            "border": getoption("general:border_size", "int")}


def effects():
    specs = (
        ("rounding", "decoration:rounding", "int"), ("blur", "decoration:blur:enabled", "bool"),
        ("shadows", "decoration:shadow:enabled", "bool"), ("animation", "animations:enabled", "bool"),
    )
    values = {}
    for flag, option, kind in specs:
        try:
            values[flag] = getoption(option, kind)
        except Invalid:
            values[flag] = None
    return values


def supported():
    try:
        return command("hyprctl", "eval", f'assert(type({HOOK}) == "table")') == "ok"
    except Invalid:
        return False


def reload(profile):
    if command("hyprctl", "reload", "config-only") != "ok":
        raise Invalid("reload_failed")
    deadline = time.monotonic() + 2.5
    expected = json.dumps(encode(profile).decode("ascii")) if profile else "nil"
    while time.monotonic() < deadline:
        if command("hyprctl", "eval", f"assert({HOOK}.profile == {expected})") == "ok":
            if config_errors():
                raise Invalid("reload_failed")
            return
        time.sleep(0.10)
    raise Invalid("reload_unconfirmed")


def snapshot(directory, status="ok"):
    raw = read_member(directory, FILENAME)
    return {"status": status, "active": current(), "saved": decode(raw),
            "effects": effects(), "writable": supported(), "revision": revision(raw)}


def rollback(directory, raw, staged, before):
    if raw is None:
        if read_member(directory, FILENAME) != staged:
            raise Conflict
        os.unlink(FILENAME, dir_fd=directory)
        os.fsync(directory)
    else:
        write_member(directory, FILENAME, raw, staged)
    reload(decode(raw))
    if current() != before:
        raise Invalid("recovery_unconfirmed")


def execute(action, payload):
    if action == "read":
        with open_store(False) as directory:
            return snapshot(directory)
    if action not in ("save", "reset") or not isinstance(payload, dict):
        raise Invalid("invalid_request")
    layout = payload.get("layout") if action == "save" else None
    if action == "save" and not valid(layout):
        raise Invalid("invalid_layout")
    if not supported() or config_errors():
        raise Invalid("hook_unavailable")
    with open_store(True) as directory, lock(directory, ".display.lock"), lock(directory, ".layout.lock"):
        if read_member(directory, PENDING) is not None:
            raise Invalid("display_preview")
        original = read_member(directory, FILENAME)
        before = current()
        if payload.get("revision") != revision(original) or payload.get("active") != before:
            raise Conflict
        decode(original)
        staged = encode(layout)
        write_member(directory, FILENAME, staged, original, create_only=original is None)
        try:
            reload(layout)
            reply = snapshot(directory, "applied" if layout else "reset")
            if reply["revision"] != revision(staged):
                raise Conflict
            if layout is not None and reply["active"] != layout:
                raise Invalid("unconfirmed")
        except (Invalid, Conflict, OSError):
            try:
                rollback(directory, original, staged, before)
            except (Invalid, Conflict, OSError) as error:
                raise Invalid("recovery_unconfirmed") from error
            raise Invalid("layout_reverted") from None
        return reply


def main():
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ""
        payload = {} if action == "read" else parse(sys.stdin.buffer.readline(LIMIT + 1))
        result = execute(action, payload)
    except Conflict:
        result = {"status": "error", "reason": "conflict"}
    except Invalid as error:
        result = {"status": "error", "reason": str(error)}
    except (OSError, ValueError):
        result = {"status": "error", "reason": "layout_unavailable"}
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
