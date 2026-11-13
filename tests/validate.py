#!/usr/bin/env python3
"""Validate tracked source files using the available local syntax tools."""

import ast
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib


def _is_bash(path):
    with path.open("rb") as stream:
        first_line = stream.readline(256)
    return first_line.startswith(b"#!") and b"bash" in first_line


def _parse_jsonc(source):
    """Allow JSONC comments and trailing commas without changing error positions."""
    chars = list(source)
    index = 0
    quoted = False
    while index < len(chars):
        if quoted:
            if chars[index] == "\\":
                index += 2
                continue
            if chars[index] == '"':
                quoted = False
        elif chars[index] == '"':
            quoted = True
        elif chars[index:index + 2] == ["/", "/"]:
            while index < len(chars) and chars[index] != "\n":
                chars[index] = " "
                index += 1
            continue
        elif chars[index:index + 2] == ["/", "*"]:
            start = index
            while index + 1 < len(chars) and chars[index:index + 2] != ["*", "/"]:
                if chars[index] != "\n":
                    chars[index] = " "
                index += 1
            if index + 1 == len(chars):
                raise ValueError(f"Unterminated JSONC comment at offset {start}")
            chars[index:index + 2] = [" ", " "]
            index += 2
            continue
        index += 1

    index = 0
    quoted = False
    while index < len(chars):
        if quoted:
            if chars[index] == "\\":
                index += 2
                continue
            if chars[index] == '"':
                quoted = False
        elif chars[index] == '"':
            quoted = True
        elif chars[index] == ",":
            following = index + 1
            while following < len(chars) and chars[following].isspace():
                following += 1
            if following < len(chars) and chars[following] in "}]":
                chars[index] = " "
        index += 1
    return json.loads("".join(chars))


def _qmllint_options(tool):
    # Quickshell types are absent in the CI Qt installation: check syntax only.
    help_text = subprocess.check_output([tool, "--help"], text=True)
    categories = re.findall(r"(?m)^\s+--([a-z][a-z-]*)\s+<level>", help_text)
    return [f"--{name}=disable" for name in categories if name != "syntax"]


def validate(paths):
    failures = []
    luac = shutil.which("luac")
    qmllint = shutil.which("qmllint")
    if not qmllint and Path("/usr/lib/qt6/bin/qmllint").is_file():
        qmllint = "/usr/lib/qt6/bin/qmllint"
    qml_options = _qmllint_options(qmllint) if qmllint else []
    for value in paths:
        path = Path(value)
        if path.is_symlink() or not path.is_file():
            continue
        try:
            if path.suffix == ".py":
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            elif path.suffix == ".toml":
                tomllib.loads(path.read_text(encoding="utf-8"))
            elif path.suffix == ".json":
                json.loads(path.read_text(encoding="utf-8"))
            elif path.suffix == ".jsonc":
                _parse_jsonc(path.read_text(encoding="utf-8"))
            elif path.suffix == ".lua" and luac:
                subprocess.run(
                    [luac, "-p", str(path)], check=True, capture_output=True, text=True
                )
            elif path.suffix == ".qml" and qmllint:
                subprocess.run(
                    [qmllint, *qml_options, str(path)],
                    check=True, capture_output=True, text=True,
                )
            elif _is_bash(path):
                subprocess.run(
                    ["bash", "-n", str(path)],
                    check=True,
                    capture_output=True,
                    text=True,
                )
        except (OSError, SyntaxError, UnicodeError, ValueError, subprocess.CalledProcessError) as error:
            detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
            failures.append(f"{path}: {detail}")
    return failures


def tracked_paths(root):
    root = Path(root).resolve()
    output = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
    return [root / os.fsdecode(name) for name in output.split(b"\0") if name]


def main(root=None):
    root = Path(root).resolve() if root else Path(__file__).resolve().parents[1]
    if not shutil.which("qmllint") and not Path("/usr/lib/qt6/bin/qmllint").is_file():
        print("SKIP QML syntax check: qmllint unavailable", file=sys.stderr)
    if not shutil.which("luac"):
        print("SKIP Lua syntax check: luac unavailable", file=sys.stderr)
    failures = validate(tracked_paths(root))
    for failure in failures:
        print(failure, file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
