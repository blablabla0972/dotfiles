import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


BACKEND = Path(__file__).resolve().parents[1] / "config/quickshell/clipboard-history/clipboard.py"
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")


@unittest.skipUnless(shutil.which("cliphist") and shutil.which("file"), "cliphist and file required")
class ClipboardHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        bindir = self.home / "bin"
        bindir.mkdir()
        copier = bindir / "wl-copy"
        copier.write_text(f"#!{sys.executable}\nimport json, os, pathlib, sys\n"
                          "root = pathlib.Path(os.environ['HOME'])\n"
                          "(root / 'copied').write_bytes(sys.stdin.buffer.read())\n"
                          "(root / 'copy-args').write_text(json.dumps(sys.argv[1:]))\n")
        copier.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CACHE_HOME": str(self.home / "cache"),
                    "XDG_CONFIG_HOME": str(self.home / "config"), "PATH": f"{bindir}:{os.environ['PATH']}"}
        self.env.pop("CLIPHIST_DB_PATH", None)

    def backend(self, action, entry=None):
        command = [sys.executable, str(BACKEND), action]
        if entry is not None:
            command.append(entry)
        result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        return json.loads(result.stdout)

    def store(self, payload):
        subprocess.run(["cliphist", "store"], input=payload, env=self.env, check=True, capture_output=True)
        return self.backend("list")["entries"][0]["id"]

    def test_empty_history(self):
        self.assertEqual(self.backend("list"), {"entries": []})

    def test_text_preview_never_executes_content_or_changes_clipboard(self):
        text = "Tiếng Việt\n$(touch unsafe); <b>plain text</b>\t'quoted'"
        entry = self.store(text.encode())
        preview = self.backend("preview", entry)
        self.assertEqual(preview["text"], text)
        self.assertEqual(preview["kind"], "text")
        self.assertFalse((self.home / "copied").exists())

    def test_image_preview_and_copy_keep_original_bytes(self):
        entry = self.store(PNG)
        preview = self.backend("preview", entry)
        self.assertEqual(base64.b64decode(preview["source"].split(",", 1)[1]), PNG)
        self.assertEqual(preview["kind"], "image")
        self.backend("copy", entry)
        self.assertEqual((self.home / "copied").read_bytes(), PNG)
        self.assertEqual(json.loads((self.home / "copy-args").read_text()), ["--type", "image/png"])

    def test_text_copy_keeps_newlines(self):
        for payload in ("Tiếng Việt\nline two\n".encode(), b'{"message": "clipboard"}\n'):
            with self.subTest(payload=payload):
                self.backend("copy", self.store(payload))
                self.assertEqual((self.home / "copied").read_bytes(), payload)
                self.assertEqual(json.loads((self.home / "copy-args").read_text()), ["--type", "text/plain;charset=utf-8"])

    def test_delete_preserves_other_entries(self):
        keep = self.store(b"keep this")
        remove = self.store(b"delete this")
        self.backend("delete", remove)
        self.assertEqual([entry["id"] for entry in self.backend("list")["entries"]], [keep])

    def test_clear_only_affects_isolated_history(self):
        self.store(b"first")
        self.store(b"second")
        self.backend("wipe")
        self.assertEqual(self.backend("list"), {"entries": []})

    def test_invalid_id_does_not_delete_history(self):
        self.store(b"keep")
        result = subprocess.run([sys.executable, str(BACKEND), "delete", "1; echo unsafe"],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("error", json.loads(result.stdout))
        self.assertEqual(len(self.backend("list")["entries"]), 1)


if __name__ == "__main__":
    unittest.main()
