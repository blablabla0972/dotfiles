#!/usr/bin/env python3
"""Validate tracked Bash, Python, TOML and JSON files without dependencies."""

import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib


def _is_bash(path):
    with path.open("rb") as stream:
        first_line = stream.readline(256)
    return first_line.startswith(b"#!") and b"bash" in first_line


def validate(paths):
    failures = []
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
    failures = validate(tracked_paths(root))
    for failure in failures:
        print(failure, file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
