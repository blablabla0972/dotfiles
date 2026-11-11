import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "tests/validate.py"


def load_validator():
    if not VALIDATOR.is_file():
        raise AssertionError("tests/validate.py is missing")
    spec = importlib.util.spec_from_file_location("tracked_file_validator", VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ValidatorTests(unittest.TestCase):
    def write(self, root, name, contents):
        path = Path(root, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def assert_invalid(self, suffix, contents):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            path = self.write(directory, "bad" + suffix, contents)
            failures = validator.validate([path])
        self.assertEqual(len(failures), 1)
        self.assertIn(path.name, failures[0])

    def init_repository(self, directory, files):
        root = Path(directory)
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        for name, contents in files.items():
            self.write(root, name, contents)
        return root

    def test_accepts_valid_supported_files_and_ignores_other_data(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            paths = [
                self.write(directory, "valid.py", "answer = 42\n"),
                self.write(directory, "valid.toml", 'answer = 42\n'),
                self.write(directory, "valid.json", json.dumps({"answer": 42})),
                self.write(directory, "valid-tool", "#!/usr/bin/env bash\ntrue\n"),
                self.write(directory, "notes.txt", "not parsed { [\n"),
            ]
            self.assertEqual(validator.validate(paths), [])

    def test_rejects_invalid_python(self):
        self.assert_invalid(".py", "if True print('broken')\n")

    def test_rejects_invalid_toml(self):
        self.assert_invalid(".toml", "value = [\n")

    def test_rejects_invalid_json(self):
        self.assert_invalid(".json", '{"value":\n')

    def test_rejects_invalid_bash(self):
        self.assert_invalid(".sh", "#!/usr/bin/env bash\nif true; then\n")

    def test_skips_symlinks_instead_of_following_them(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            target = self.write(directory, "bad.py", "if True print('broken')\n")
            link = Path(directory, "linked.py")
            link.symlink_to(target)
            self.assertEqual(validator.validate([link]), [])

    def test_tracked_paths_excludes_untracked_files(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            root = self.init_repository(directory, {
                "tracked.py": "answer = 42\n",
                "untracked.py": "answer = 0\n",
            })
            subprocess.run(["git", "-C", str(root), "add", "tracked.py"], check=True)
            self.assertEqual(validator.tracked_paths(root), [root / "tracked.py"])

    def test_main_reports_invalid_tracked_file_and_returns_nonzero(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            root = self.init_repository(directory, {"bad.json": "{"})
            subprocess.run(["git", "-C", str(root), "add", "bad.json"], check=True)
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                code = validator.main(root)
            self.assertEqual(code, 1)
            self.assertIn("bad.json", stderr.getvalue())

    def test_main_accepts_valid_tracked_files(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            root = self.init_repository(directory, {"valid.json": "{}"})
            subprocess.run(["git", "-C", str(root), "add", "valid.json"], check=True)
            self.assertEqual(validator.main(root), 0)


if __name__ == "__main__":
    unittest.main()
