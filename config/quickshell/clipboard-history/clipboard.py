#!/usr/bin/env python3
"""JSON bridge to the existing cliphist database; never log clipboard contents."""

import argparse
import base64
import json
import subprocess


def history(action, entry=None):
    result = subprocess.run(["cliphist", action], input=(entry + "\t\n").encode() if entry else None,
                            capture_output=True, timeout=10)
    if action == "list" and result.stderr.strip() == b"opening db: please store something first":
        return b""
    result.check_returncode()
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("list", "preview", "copy", "delete", "wipe"))
    parser.add_argument("entry", nargs="?")
    args = parser.parse_args()
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
    if args.action == "copy":
        if mime.startswith("text/") or mime == "application/json":
            mime = "text/plain;charset=utf-8"
        subprocess.run(["wl-copy", "--type", mime], input=payload, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, check=True, timeout=10)
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
