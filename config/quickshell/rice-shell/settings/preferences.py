"""Atomic, revision-checked storage for Rice Settings preferences."""

from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import stat
import sys
from urllib.parse import unquote, urlsplit

LIMIT = 65536
FILE = "preferences.json"
BACKUP = "last-good.json"
DEFAULTS = {"reduceMotion": False, "compactRows": False}


class Invalid(ValueError):
    pass


class Conflict(ValueError):
    pass


def unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise Invalid("invalid_document")
    return result


def reject_constant(_value):
    raise Invalid("invalid_document")


def finite_float(raw):
    value = float(raw)
    if not math.isfinite(value):
        raise Invalid("invalid_document")
    return value


def parse(raw):
    if len(raw) > LIMIT:
        raise Invalid("too_large")
    try:
        return json.loads(raw, object_pairs_hook=unique_object,
                          parse_constant=reject_constant, parse_float=finite_float)
    except (UnicodeError, json.JSONDecodeError, RecursionError, OverflowError) as error:
        raise Invalid("invalid_document") from error


def validate(raw):
    if raw is None:
        return {"version": 1, "ui": DEFAULTS.copy()}
    document = parse(raw)
    if not isinstance(document, dict) or type(document.get("version")) is not int:
        raise Invalid("invalid_document")
    if document["version"] != 1:
        raise Invalid("unsupported_version")
    ui = document.setdefault("ui", {})
    if not isinstance(ui, dict) or any(key in ui and type(ui[key]) is not bool for key in DEFAULTS):
        raise Invalid("invalid_document")
    return document


def revision(raw):
    return "missing" if raw is None else hashlib.sha256(raw).hexdigest()


def encode(document):
    return (json.dumps(document, ensure_ascii=True, allow_nan=False, indent=2) + "\n").encode()


def require_owner(info, kind, private):
    if not kind(info.st_mode) or info.st_uid != os.getuid() or (private and info.st_mode & 0o077):
        raise Invalid("unsafe_file")


@contextmanager
def open_store(create):
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    if not base.is_absolute():
        raise Invalid("unsafe_file")
    if create:
        base.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        root = os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except FileNotFoundError:
        yield None
        return
    try:
        require_owner(os.fstat(root), stat.S_ISDIR, private=False)
        if create:
            try:
                os.mkdir("rice-settings", mode=0o700, dir_fd=root)
            except FileExistsError:
                pass
        try:
            directory = os.open("rice-settings", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
        except FileNotFoundError:
            yield None
        else:
            try:
                require_owner(os.fstat(directory), stat.S_ISDIR, private=True)
                yield directory
            finally:
                os.close(directory)
    finally:
        os.close(root)


@contextmanager
def lock(directory, name=".lock"):
    if directory is None:
        raise Invalid("unsafe_file")
    fd = os.open(name, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
    try:
        require_owner(os.fstat(fd), stat.S_ISREG, private=True)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Invalid("busy") from error
        yield
    finally:
        os.close(fd)


def read_member(directory, name, *, private=True):
    if directory is None:
        return None
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require_owner(info, stat.S_ISREG, private=private)
        if info.st_nlink != 1:
            raise Invalid("unsafe_file")
        if info.st_size > LIMIT:
            raise Invalid("too_large")
        raw = stream.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise Invalid("too_large")
        return raw


def write_member(directory, name, data, expected, *, create_only=False):
    if len(data) > LIMIT:
        raise Invalid("too_large")
    staged = ".stage-" + secrets.token_hex(12)
    fd = os.open(staged, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode=0o600, dir_fd=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if create_only:
            try:
                os.link(staged, name, src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
            except FileExistsError as error:
                raise Invalid("destination_exists") from error
            os.unlink(staged, dir_fd=directory)
        else:
            if read_member(directory, name) != expected:
                raise Conflict
            os.replace(staged, name, src_dir_fd=directory, dst_dir_fd=directory)
        os.fsync(directory)
        if read_member(directory, name) != data:
            raise Conflict
    finally:
        try:
            os.unlink(staged, dir_fd=directory)
        except FileNotFoundError:
            pass


def valid_backup(directory):
    try:
        backup = read_member(directory, BACKUP)
        return backup if backup is not None and validate(backup) else None
    except (Invalid, OSError):
        return None


def snapshot(directory, status="ok"):
    raw = read_member(directory, FILE)
    backup = valid_backup(directory)
    try:
        doc = validate(raw)
    except Invalid as error:
        return {"status": "invalid", "reason": str(error), "revision": revision(raw),
                "canRestore": backup is not None and str(error) != "unsupported_version"}
    return {"status": status, "revision": revision(raw), "values": DEFAULTS | {
        key: value for key, value in doc["ui"].items() if key in DEFAULTS
    }, "canRestore": backup is not None}


def transfer(action, url, expected):
    if not isinstance(url, str) or len(url) > 8192:
        raise Invalid("invalid_path")
    parts = urlsplit(url)
    decoded = unquote(parts.path, errors="strict")
    path = Path(decoded)
    if (parts.scheme != "file" or parts.netloc not in ("", "localhost") or parts.query or parts.fragment
            or "\x00" in decoded or not path.is_absolute() or not path.name):
        raise Invalid("invalid_path")
    with open_store(False) as directory:
        current = snapshot(directory)
        if current["status"] != "ok":
            return current
        if current["revision"] != expected:
            raise Conflict
        external = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if action == "inspect":
                raw = read_member(external, path.name, private=False)
                if raw is None:
                    raise Invalid("invalid_path")
                doc = validate(raw)
                if set(doc) - {"version", "ui"} or set(doc["ui"]) - DEFAULTS.keys():
                    raise Invalid("invalid_document")
                return {"status": "preview", "revision": expected, "values": DEFAULTS | doc["ui"]}
            if directory is not None and os.path.samestat(os.fstat(directory), os.fstat(external)):
                raise Invalid("invalid_path")
            data = encode({"version": 1, "ui": current["values"]})
            write_member(external, path.name, data, None, create_only=True)
            return {"status": "exported"}
        finally:
            os.close(external)


def execute(action, request):
    if action == "read":
        with open_store(False) as directory:
            return snapshot(directory)
    if action not in ("update", "restore", "inspect", "export") or not isinstance(request, dict):
        raise Invalid("invalid_request")
    expected = request.get("revision")
    if not isinstance(expected, str) or not re.fullmatch(r"missing|[0-9a-f]{64}", expected):
        raise Invalid("invalid_request")
    if action in ("inspect", "export"):
        return transfer(action, request.get("url"), expected)
    patch = request.get("patch")
    if action == "update" and (not isinstance(patch, dict) or not patch
            or any(key not in DEFAULTS or type(value) is not bool for key, value in patch.items())):
        raise Invalid("invalid_request")

    with open_store(True) as directory, lock(directory):
        current = read_member(directory, FILE)
        if revision(current) != expected:
            raise Conflict
        try:
            document = validate(current)
        except Invalid as error:
            if action != "restore" or str(error) == "unsupported_version":
                raise
            document = None
        backup = read_member(directory, BACKUP)
        if action == "restore":
            if backup is None:
                raise Invalid("no_backup")
            replacement = encode(validate(backup))
        else:
            replacement = encode({**document, "ui": document["ui"] | patch})
        if document is not None:
            write_member(directory, BACKUP, current if current is not None else encode(document), backup)
        write_member(directory, FILE, replacement, current)
        result = snapshot(directory, "applied")
        if result["revision"] != revision(replacement):
            raise Conflict
        return result


def main():
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ""
        request = None if action == "read" else parse(sys.stdin.buffer.readline(LIMIT + 1))
        result = execute(action, request)
    except Conflict:
        result = {"status": "conflict", "reason": "changed"}
    except Invalid as error:
        reason = str(error)
        result = {"status": "busy" if reason == "busy" else "invalid", "reason": reason}
    except (OSError, ValueError, RecursionError):
        result = {"status": "invalid", "reason": "unsafe_file"}
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
