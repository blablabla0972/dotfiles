"""Isolated helper regressions; never contact the running compositor or UI."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
SWITCHER = ROOT / "config/quickshell/wallpaper-switcher"


class IsolatedHome(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CACHE_HOME=str(self.home / "cache"),
                        XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_RUNTIME_DIR=str(self.home / "runtime"),
                        HYPRLAND_INSTANCE_SIGNATURE="test",
                        PATH=f"{self.bin}:{os.environ['PATH']}")

    def executable(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_helper(self, path):
        return subprocess.run(["bash", str(path)], env=self.env,
                              capture_output=True, text=True, timeout=20)


@unittest.skipUnless(shutil.which("jq") and shutil.which("lua"), "jq and Lua required")
class ToggleDesktopTests(IsolatedHome):
    def setUp(self):
        super().setUp()
        # Execute the generated Lua in an environment containing only fake dispatchers.
        # Splitting at semicolons also models hyprctl's batch framing.
        self.executable("hyprctl", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, subprocess, sys
home = pathlib.Path(os.environ["HOME"])
if sys.argv[1:] == ["monitors", "-j"]:
    print((home / "monitors.json").read_text())
    sys.exit(0)
if sys.argv[1] != "--batch":
    sys.exit("unexpected hyprctl invocation")
if (home / "fail-dispatch").exists():
    print("error: simulated dispatch failure")
    sys.exit(0)
prelude = r"""
local function record(kind, value)
    local hex = (value or ""):gsub(".", function(c) return string.format("%02x", c:byte()) end)
    print(kind .. ":" .. hex)
end
local env = {hl = {dsp = {
    focus = function(args) record("focus", args.workspace) end,
    workspace = {toggle_special = function(name) record("special", name) end}
}}}
local chunk, err = load(io.read("*a"), "dispatch", "t", env)
assert(chunk, err)
chunk()
"""
for command in sys.argv[2].split(";"):
    command = command.strip()
    if not command.startswith("dispatch "):
        sys.exit("error: unexpected batch command")
    result = subprocess.run(["lua", "-e", prelude], input=command[9:],
                            text=True, capture_output=True)
    if result.returncode:
        sys.exit("error: " + result.stderr)
    with (home / "calls.jsonl").open("a") as log:
        for line in result.stdout.splitlines():
            kind, value = line.split(":", 1)
            log.write(json.dumps([kind, bytes.fromhex(value).decode()]) + "\n")
print("ok")
''')
        self.state = self.home / "runtime/hypr/test/toggle-desktop.state"

    def monitor(self, workspace, special="", special_id=0):
        (self.home / "monitors.json").write_text(json.dumps([{
            "focused": True, "activeWorkspace": {"name": workspace},
            "specialWorkspace": {"id": special_id, "name": special},
        }]))

    def calls(self):
        return [json.loads(line) for line in
                (self.home / "calls.jsonl").read_text().splitlines()]

    def test_special_workspaces_round_trip(self):
        for special, expected in [("special:notes", "notes"), ("special", ""),
                                  ("special:", ""), ("", ""),
                                  ('special:Ảnh "x"\\; ) | 7\x01', 'Ảnh "x"\\; ) | 7\x01')]:
            with self.subTest(special=special):
                (self.home / "calls.jsonl").write_text("")
                self.monitor("3", special, -99)
                result = self.run_helper(ROOT / "bin/toggle-desktop")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls(), [["special", expected], ["focus", "10"]])
                self.monitor("10")
                result = self.run_helper(ROOT / "bin/toggle-desktop")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls()[-2:], [["focus", "3"], ["special", expected]])
                self.assertFalse(self.state.exists())

    def test_normal_workspace_names_are_lua_and_batch_safe(self):
        workspace = 'Ảnh "quoted"\\; hl.dsp.workspace.toggle_special("injected")\x01'
        desktop = 'desk "top"\\; 9'
        self.env["HYPR_DESKTOP_WS"] = desktop
        self.monitor(workspace)
        result = self.run_helper(ROOT / "bin/toggle-desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.monitor(desktop)
        result = self.run_helper(ROOT / "bin/toggle-desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [["focus", desktop], ["focus", workspace]])

    def test_failed_restore_preserves_state(self):
        self.state.parent.mkdir(parents=True)
        self.state.write_text("3|special:special:notes")
        self.monitor("10")
        (self.home / "fail-dispatch").touch()
        result = self.run_helper(ROOT / "bin/toggle-desktop")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "3|special:special:notes")


@unittest.skipUnless(shutil.which("magick") and shutil.which("md5sum"),
                     "ImageMagick and md5sum required")
class ThumbnailTests(IsolatedHome):
    def setUp(self):
        super().setUp()
        self.wallpapers = self.home / "Ảnh/Wallpaper"
        self.wallpapers.mkdir(parents=True)
        self.cache = self.home / "cache/wallpaper-switcher-thumbs-v3"

    def image(self, name, color="red"):
        path = self.wallpapers / name
        subprocess.run(["magick", "-size", "4x3", f"xc:{color}", str(path)],
                       env=self.env, check=True, capture_output=True)
        return path

    def thumb(self, image):
        return self.cache / (hashlib.md5(image.name.encode()).hexdigest() + ".jpg")

    def test_spaces_unicode_long_names_and_qml_keys(self):
        images = [self.image(name) for name in
                  ["spaces here.png", "Ảnh 🌄.png", "a" * 251 + ".png", "ảnh" * 35 + ".png"]]
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        for image in images:
            self.assertTrue(self.thumb(image).is_file(), image.name)
        if not shutil.which("node"):
            self.skipTest("Node required to execute the QML model function without a UI")
        qml = (SWITCHER / "shell.qml").read_text()
        function = re.search(r"    function updateDisplayModel\(\) \{.*?\n    \}", qml, re.S).group()
        # Run the actual model function with Qt's UTF-8 MD5 semantics and fake models.
        javascript = r'''
const crypto = require("crypto");
const names = JSON.parse(process.argv[1]);
const Qt = {md5: name => crypto.createHash("md5").update(name, "utf8").digest("hex")};
const Quickshell = {env: key => process.env[key]};
const folderModel = {count: names.length, get: (i, role) => role === "fileName" ? names[i] : names[i]};
const urls = [];
const displayModel = {clear: () => {}, append: item => urls.push(item.thumbUrl)};
''' + function + '\nupdateDisplayModel(); console.log(JSON.stringify(urls));'
        result = subprocess.run(["node", "-e", javascript, json.dumps([p.name for p in images])],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        urls = json.loads(result.stdout)
        for image, url in zip(images, urls):
            self.assertEqual(Path(unquote(urlparse(url).path)), self.thumb(image))

    def test_corrupt_first_image_does_not_stop_remaining_images(self):
        corrupt = self.wallpapers / "broken.png"
        corrupt.write_bytes(b"not an image")
        valid = self.image("valid after broken.png")
        # Ensure iteration order instead of depending on filesystem enumeration.
        self.executable("find", f"#!{sys.executable}\nimport os, sys\n" +
                        f"sys.stdout.buffer.write(os.fsencode({str(corrupt)!r}) + b'\\0' + " +
                        f"os.fsencode({str(valid)!r}) + b'\\0')\n")
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.thumb(valid).is_file(), result.stderr)
        self.assertFalse(self.thumb(corrupt).exists())
        self.assertEqual(list(self.cache.glob(".thumbnail-*")), [])

    def test_stale_refresh_and_fresh_cache_reuse(self):
        image = self.image("refresh.png")
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        thumb = self.thumb(image)
        self.assertTrue(thumb.exists())
        first = thumb.read_bytes()
        stamp = thumb.stat().st_mtime_ns
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(thumb.stat().st_mtime_ns, stamp)
        self.image(image.name, "blue")
        os.utime(thumb, (1, 1))
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(thumb.read_bytes(), first)

    def test_failed_refresh_keeps_old_thumbnail_and_removes_temporary(self):
        image = self.image("refresh.png")
        self.cache.mkdir(parents=True)
        thumb = self.thumb(image)
        thumb.write_bytes(b"previous cached thumbnail")
        os.utime(thumb, (1, 1))
        self.executable("magick", "#!/bin/sh\nfor output do :; done\nprintf partial > \"$output\"\nexit 1\n")
        result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(thumb.read_bytes(), b"previous cached thumbnail")
        self.assertEqual(list(self.cache.glob(".thumbnail-*")), [])

    def test_lock_skips_generation(self):
        image = self.image("locked.png")
        self.cache.mkdir(parents=True)
        with (self.cache / "generate.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_helper(SWITCHER / "generate-thumbs.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.thumb(image).exists())


if __name__ == "__main__":
    unittest.main()
