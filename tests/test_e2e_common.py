"""Hermetic opaque-box E2E test support and fixtures for dotfiles testing."""

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

__test__ = False  # Instruct pytest not to collect tests from this support module

REPO_ROOT = Path(__file__).resolve().parent.parent


class E2EEnvironment:
    """Hermetic execution environment with isolated HOME, XDG paths, and mock binaries."""

    def __init__(self, temp_dir: str):
        self.root = Path(temp_dir)
        self.home = self.root / "home"
        self.bin = self.root / "stubs"
        self.config = self.home / ".config"
        self.state = self.home / ".local/state"
        self.cache = self.home / ".cache"
        self.runtime = self.root / "runtime"

        for p in (self.home, self.bin, self.config, self.state, self.cache, self.runtime):
            p.mkdir(parents=True, exist_ok=True)

        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CACHE_HOME": str(self.cache),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "PATH": f"{self.bin}:{os.environ.get('PATH', '')}",
            "HYPRLAND_INSTANCE_SIGNATURE": "e2e_test_instance",
            "DOTFILES_REPO": str(REPO_ROOT),
        })

        self._setup_stubs()

    def make_executable(self, name: str, content: str):
        path = self.bin / name
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        return path

    def _setup_stubs(self):
        # 1. systemctl stub
        self.make_executable(
            "systemctl",
            "#!/bin/sh\n"
            "echo \"$@\" >> \"$HOME/.systemctl_calls.log\"\n"
            "exit 0\n",
        )

        # 2. swww stub
        self.make_executable(
            "swww",
            "#!/bin/sh\n"
            "echo \"$@\" >> \"$HOME/.swww_calls.log\"\n"
            "exit 0\n",
        )

        # 3. noctalia stub
        noctalia_script = r'''#!/usr/bin/env python3
import sys, os, json
home = os.path.expanduser("~")
log_path = os.path.join(home, ".noctalia_calls.log")
with open(log_path, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")

fail_file = os.path.join(home, ".noctalia_fail")
if os.path.exists(fail_file):
    print("Injected Noctalia failure", file=sys.stderr)
    sys.exit(1)

cmd = sys.argv[1:]
if cmd[:2] == ["config", "export"]:
    print('[theme]\nmode="dark"\nsource="wallpaper"\nmatugen_palette="matugen"\n[wallpaper]\nenabled=false\n[theme.templates]\nbuiltin_ids=["hyprland"]')
    sys.exit(0)
if len(cmd) > 0 and cmd[0] == "theme":
    for i, arg in enumerate(cmd):
        if arg == "-r" and i + 1 < len(cmd):
            spec = cmd[i + 1]
            if ":" in spec:
                src, dst = spec.split(":", 1)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "w", encoding="utf-8") as df:
                    df.write("-- rendered template\n")
    target_lua = os.path.join(home, ".config/hypr/noctalia.lua")
    if os.path.exists(os.path.dirname(target_lua)):
        with open(target_lua, "w", encoding="utf-8") as lf:
            lf.write("-- rendered template\n")
    roles = ('primary', 'surface', 'on_surface', 'secondary', 'on_secondary', 'error', 'on_error')
    print(json.dumps({mode: {k: '#112233' for k in roles} for mode in ('dark', 'light')}))
    sys.exit(0)
if cmd[:2] == ["theme", "palette-roles"]:
    roles = ('primary', 'surface', 'on_surface', 'secondary', 'on_secondary', 'error', 'on_error')
    print(json.dumps({mode: {k: '#ffffff' for k in roles} for mode in ('dark', 'light')}))
    sys.exit(0)
if cmd[:2] == ["msg", "theme-mode-get"]:
    mode_file = os.path.join(home, ".noctalia_mode")
    if os.path.exists(mode_file):
        print(open(mode_file).read().strip())
    else:
        print("dark")
    sys.exit(0)
if cmd[:2] == ["msg", "wallpaper-get"]:
    wall_file = os.path.join(home, ".noctalia_wallpaper")
    if os.path.exists(wall_file):
        print(open(wall_file).read().strip())
    else:
        cw = os.path.join(home, ".config/hypr/current_wallpaper")
        if os.path.islink(cw) or os.path.exists(cw):
            print(os.path.realpath(cw))
        else:
            print(os.path.join(home, "current_wall.png"))
    sys.exit(0)
if cmd[:2] == ["msg", "wallpaper-set"]:
    if len(cmd) > 2:
        with open(os.path.join(home, ".noctalia_wallpaper"), "w") as wf:
            wf.write(cmd[2])
    sys.exit(0)
if cmd[:2] == ["msg", "templates-apply"]:
    target_lua = os.path.join(home, ".config/hypr/noctalia.lua")
    if os.path.exists(os.path.dirname(target_lua)):
        with open(target_lua, "w", encoding="utf-8") as lf:
            lf.write("-- rendered template\n")
    sys.exit(0)
if cmd[:2] == ["msg", "color-palette-reload"]:
    sys.exit(0)
if cmd[:2] == ["config", "validate"]:
    print("✓ Config is valid")
    sys.exit(0)
sys.exit(0)
'''
        self.make_executable("noctalia", noctalia_script)

        # 4. hyprctl stub
        hyprctl_script = r'''#!/usr/bin/env python3
import sys, os, json
home = os.path.expanduser("~")
fail_file = os.path.join(home, ".hyprctl_fail")
if os.path.exists(fail_file):
    print("error: simulated hyprctl failure", file=sys.stderr)
    sys.exit(1)

if sys.argv[1:] == ["monitors", "-j"]:
    mon_file = os.path.join(home, "monitors.json")
    if os.path.exists(mon_file):
        sys.stdout.write(open(mon_file).read())
    else:
        print(json.dumps([{"focused": True, "activeWorkspace": {"name": "1"}, "specialWorkspace": {"id": 0, "name": ""}}]))
    sys.exit(0)

if len(sys.argv) >= 3 and sys.argv[1] == "--batch":
    batch_arg = sys.argv[2]
    with open(os.path.join(home, "hyprctl_batch.log"), "a") as f:
        f.write(batch_arg + "\n")
    print("ok")
    sys.exit(0)

if sys.argv[1:] == ["configerrors"]:
    print("")
    sys.exit(0)

sys.exit(0)
'''
        self.make_executable("hyprctl", hyprctl_script)

        # 5. matugen stub
        matugen_script = r'''#!/usr/bin/env python3
import sys, os, json
home = os.path.expanduser("~")
fail_file = os.path.join(home, ".matugen_fail")
if os.path.exists(fail_file):
    print("error: simulated matugen failure", file=sys.stderr)
    sys.exit(1)

# Matugen dry-run hex mode (called by preview-palette.py)
if "--dry-run" in sys.argv and "--json" in sys.argv:
    mode = "dark"
    if "--mode" in sys.argv:
        idx = sys.argv.index("--mode") + 1
        if idx < len(sys.argv):
            mode = sys.argv[idx]
    swatches = {
        "dark": ["#112233", "#223344", "#334455", "#445566", "#556677"],
        "light": ["#aabbcc", "#bbccdd", "#ccddee", "#ddeeff", "#eeffff"],
    }
    chosen = swatches.get(mode, swatches["dark"])
    roles = ("primary", "secondary", "tertiary", "surface", "on_surface")
    colors = {role: {mode: {"color": chosen[i]}} for i, role in enumerate(roles)}
    print(json.dumps({"colors": colors}))
    sys.exit(0)

# Matugen config render mode (called by generate-theme.py)
if "--config" in sys.argv:
    cfg_idx = sys.argv.index("--config") + 1
    cfg_path = sys.argv[cfg_idx]
    mode = "dark"
    if "--mode" in sys.argv:
        idx = sys.argv.index("--mode") + 1
        if idx < len(sys.argv):
            mode = sys.argv[idx]
    import tomllib
    with open(cfg_path, "rb") as f:
        cfg = tomllib.load(f)
    for tname, tval in cfg.get("templates", {}).items():
        out_p = tval.get("output_path")
        if out_p:
            os.makedirs(os.path.dirname(out_p), exist_ok=True)
            ref_content = None
            ref = os.path.join(os.environ.get("DOTFILES_REPO", ""), "config/noctalia/palettes/matugen.json")
            if os.path.exists(ref):
                try:
                    with open(ref, "r", encoding="utf-8") as rf:
                        ref_content = rf.read()
                except Exception:
                    pass
            with open(out_p, "w", encoding="utf-8") as out_f:
                if out_p.endswith(".json"):
                    out_f.write(ref_content or "{}")
                else:
                    out_f.write(f"# generated for {mode}\n")
    sys.exit(0)

sys.exit(0)
'''
        self.make_executable("matugen", matugen_script)

    def set_monitors(self, workspace: str = "1", special: str = "", special_id: int = 0, focused: bool = True):
        monitors_file = self.home / "monitors.json"
        monitors_file.write_text(
            json.dumps([{
                "focused": focused,
                "activeWorkspace": {"name": str(workspace)},
                "specialWorkspace": {"id": special_id, "name": special},
            }]),
            encoding="utf-8",
        )

    def get_hyprctl_batches(self):
        log_file = self.home / "hyprctl_batch.log"
        if not log_file.exists():
            return []
        return [line.strip() for line in log_file.read_text(encoding="utf-8").splitlines() if line.strip()]

    def create_test_image(self, rel_path: str = "wallpaper.png", data: bytes = b"dummy_image_data_bytes_123"):
        img_path = self.home / rel_path
        img_path.parent.mkdir(parents=True, exist_ok=True)
        img_path.write_bytes(data)
        return img_path

    def create_sandbox_repo(self):
        repo = self.root / "sandbox_repo"
        if repo.exists():
            return repo
        repo.mkdir(parents=True, exist_ok=True)
        for d in ("config", "root", "state", "bin"):
            src = REPO_ROOT / d
            if src.is_dir():
                shutil.copytree(src, repo / d, symlinks=True, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        shutil.copy2(REPO_ROOT / "install.sh", repo / "install.sh")
        return repo

    def run_installer(self, *args, check: bool = False, use_sandbox: bool = False):
        if use_sandbox:
            sandbox = self.create_sandbox_repo()
            installer = sandbox / "install.sh"
            cwd = str(sandbox)
        else:
            installer = REPO_ROOT / "install.sh"
            cwd = str(REPO_ROOT)
        cmd = ["bash", str(installer), *args]
        return subprocess.run(
            cmd,
            cwd=cwd,
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
        )

    def run_toggle_desktop(self, *args, check: bool = False):
        script = REPO_ROOT / "bin/toggle-desktop"
        cmd = ["bash", str(script), *args]
        return subprocess.run(
            cmd,
            cwd=str(REPO_ROOT),
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
        )

    def run_generate_theme(self, *args, check: bool = False):
        script = REPO_ROOT / "config/hypr/scripts/generate-theme.py"
        cmd = ["python3", str(script), *args]
        return subprocess.run(
            cmd,
            cwd=str(REPO_ROOT),
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
        )

    def run_preview_palette(self, *args, check: bool = False):
        script = REPO_ROOT / "config/quickshell/wallpaper-switcher/preview-palette.py"
        cmd = ["python3", str(script), *args]
        return subprocess.run(
            cmd,
            cwd=str(REPO_ROOT),
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
        )


class E2EBaseTestCase(unittest.TestCase):
    """Base test case initializing and tearing down a hermetic E2E environment."""

    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory(prefix="dotfiles-e2e-")
        self.addCleanup(self._temp_dir.cleanup)
        self.e2e = E2EEnvironment(self._temp_dir.name)
