#!/usr/bin/env python3
"""JSON bridge to the existing cliphist database; never log clipboard contents."""

import argparse
import base64
import json
import re
import subprocess


def history(action, entry=None):
    result = subprocess.run(["cliphist", action], input=(entry + "\t\n").encode() if entry else None,
                            capture_output=True, timeout=10)
    if action == "list" and result.stderr.strip() == b"opening db: please store something first":
        return b""
    result.check_returncode()
    return result.stdout


def paste(address):
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address or ""):
        raise ValueError("Không tìm thấy cửa sổ để dán. Nội dung đã được sao chép.")
    active = json.loads(subprocess.check_output(["hyprctl", "activewindow", "-j"], timeout=2))
    if active.get("address") != address:
        raise ValueError("Cửa sổ đích đã mất focus. Nội dung đã được sao chép.")
    terminal = active["initialClass"].lower() in {"kitty", "alacritty", "foot", "ghostty", "org.wezfurlong.wezterm"}
    modifiers = ["-M", "shift"] if terminal else []
    release = ["-m", "shift"] if terminal else []
    subprocess.run(["wtype", "-M", "ctrl", *modifiers, "-k", "v", *release, "-m", "ctrl"], check=True, timeout=2)
    return {"ok": True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("list", "preview", "thumbnail", "copy", "paste", "delete", "wipe"))
    parser.add_argument("entry", nargs="?")
    args = parser.parse_args()
    if args.action == "paste":
        return paste(args.entry)
    if args.action == "list":
        entries = []
        for line in history("list").decode("utf-8", errors="replace").splitlines():
            entry, separator, preview = line.partition("\t")
            if separator and entry.isascii() and entry.isdecimal():
                entries.append({"id": entry, "preview": preview})
        return {"entries": entries}
    if args.action == "wipe":
        history("wipe")
        return {"ok": True}
    if not args.entry or not args.entry.isascii() or not args.entry.isdecimal():
        raise ValueError("ID clipboard không hợp lệ.")
    if args.action == "delete":
        history("delete", args.entry)
        return {"ok": True}

    payload = history("decode", args.entry)
    mime = subprocess.run(["file", "--mime-type", "--brief", "-"], input=payload,
                          capture_output=True, check=True, timeout=10).stdout.decode().strip()
    if args.action == "thumbnail":
        image_format = mime.removeprefix("image/")
        if image_format not in {"png", "jpeg", "webp", "gif", "bmp", "tiff"}:
            return {}
        thumbnail = subprocess.run(
            ["magick", "-limit", "thread", "1", "-limit", "memory", "64MiB",
             "-limit", "map", "64MiB", "-limit", "disk", "0", f"{image_format}:-[0]",
             "-auto-orient", "-thumbnail", "256x256", "-strip", "png:-"],
            input=payload, capture_output=True, check=True, timeout=3,
        ).stdout
        return {"source": "data:image/png;base64," + base64.b64encode(thumbnail).decode()}
    if args.action == "copy":
        if mime.startswith("text/") or mime == "application/json":
            mime = "text/plain;charset=utf-8"
        # wl-copy keeps serving the selection after its parent returns.
        subprocess.run(["wl-copy", "--type", mime], input=payload, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=True, timeout=10)
        return {"ok": True}
    if mime.startswith("image/"):
        return {"id": args.entry, "kind": "image", "mime": mime,
                "source": f"data:{mime};base64," + base64.b64encode(payload).decode()}
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError:
        text = "\0"
    if "\0" in text:
        return {"id": args.entry, "kind": "binary", "mime": mime, "text": f"{len(payload)} byte · {mime}"}
    # shortcut: text previews stop at 20000 characters; add paging if longer previews are needed.
    return {"id": args.entry, "kind": "text", "mime": mime,
            "text": text[:20000], "truncated": len(text) > 20000}


if __name__ == "__main__":
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        message = str(error) if isinstance(error, ValueError) else "Không thể thực hiện thao tác clipboard."
        print(json.dumps({"error": message}, ensure_ascii=False))
        raise SystemExit(1)
