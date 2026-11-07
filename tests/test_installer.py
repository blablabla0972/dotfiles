import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class InstallerSafetyTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix='dotfiles-installer-test-')
        self.home = Path(self.temp_dir) / 'home'
        self.home.mkdir()
        self.repo = Path(__file__).resolve().parent.parent
        self.install_script = self.repo / 'install.sh'
        self.env = os.environ.copy()
        self.env['HOME'] = str(self.home)
        stub = Path(self.temp_dir) / 'stub'
        stub.mkdir()
        # --all must not reload the host's daemon, even with an isolated HOME.
        (stub / 'systemctl').write_text('#!/bin/sh\nexit 0\n')
        (stub / 'systemctl').chmod(0o700)
        self.env['PATH'] = str(stub) + os.pathsep + self.env['PATH']

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def make_installer_repo(self, name):
        repo = Path(self.temp_dir) / name
        (repo / 'config/btop').mkdir(parents=True)
        (repo / 'config/btop/btop.conf').write_text('BTOP_CONFIG')
        (repo / 'config/starship.toml').write_text('STARSHIP_CONFIG')
        (repo / 'root').mkdir()
        (repo / 'root/kdeglobals').write_text('KDE_CONFIG')
        (repo / 'state/noctalia').mkdir(parents=True)
        (repo / 'state/noctalia/settings.toml').write_text('STATE_CONFIG')
        (repo / 'bin').mkdir()
        (repo / 'bin/test-command').write_text('#!/bin/sh\n')
        shutil.copy2(self.install_script, repo / 'install.sh')
        return repo

    def test_symlinked_destination_parents_preserve_sources(self):
        for category, destination, selectors, payload in (
            ('config', '.config', ['btop', 'starship.toml'], 'btop/btop.conf'),
            ('root', '.config', ['kdeglobals'], 'kdeglobals'),
            ('state', '.local/state', ['noctalia'], 'noctalia/settings.toml'),
            ('bin', '.local/bin', ['test-command'], 'test-command'),
        ):
            with self.subTest(category=category):
                repo = self.make_installer_repo(category)
                home = Path(self.temp_dir) / f'home-{category}'
                dst = home / destination
                dst.parent.mkdir(parents=True)
                dst.symlink_to(repo / category, target_is_directory=True)
                source = repo / category / payload
                content = source.read_text()
                proc = subprocess.run(
                    ['bash', str(repo / 'install.sh'), *selectors],
                    capture_output=True, text=True, env={**self.env, 'HOME': str(home)},
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertFalse(source.is_symlink(), 'Installer replaced its own source')
                if category == 'config':
                    self.assertFalse((repo / 'config/btop').is_symlink())
                    self.assertEqual((repo / 'config/starship.toml').read_text(), 'STARSHIP_CONFIG')
                self.assertTrue(source.is_file(), 'Installer removed its own source')
                self.assertEqual(source.read_text(), content)
                self.assertFalse((home / '.config/backups').exists())

    def test_same_file_destinations_need_no_backup(self):
        repo = self.make_installer_repo('same-file')
        target = self.home / '.config/starship.toml'
        target.parent.mkdir()
        source = repo / 'config/starship.toml'
        for kind in ('symlink', 'hardlink'):
            with self.subTest(kind=kind):
                if kind == 'symlink':
                    target.symlink_to(source)
                else:
                    os.link(source, target)
                inode = target.lstat().st_ino
                proc = subprocess.run(
                    ['bash', str(repo / 'install.sh'), 'starship.toml'],
                    capture_output=True, text=True, env=self.env,
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(target.lstat().st_ino, inode)
                self.assertFalse((self.home / '.config/backups').exists())
                target.unlink()

    def test_selected_installs_preserve_unrelated_bin_links(self):
        repo = self.make_installer_repo('selected')
        bin_dir = self.home / '.local/bin'
        bin_dir.mkdir(parents=True)
        # Include a config-only name to catch category-blind selection checks.
        orphans = [bin_dir / name for name in ('deleted-command', 'btop')]
        for selectors in (['btop'], ['--all', 'btop'], ['test-command']):
            with self.subTest(selectors=selectors):
                for orphan in orphans:
                    if not orphan.is_symlink():
                        orphan.symlink_to(repo / 'bin' / orphan.name)
                proc = subprocess.run(
                    ['bash', str(repo / 'install.sh'), *selectors],
                    capture_output=True, text=True, env=self.env,
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                for orphan in orphans:
                    self.assertTrue(orphan.is_symlink(), f'Unselected link pruned: {orphan}')
                if selectors == ['test-command']:
                    self.assertEqual((bin_dir / 'test-command').resolve(), repo / 'bin/test-command')
                else:
                    self.assertTrue((self.home / '.config/btop').is_symlink())

    def test_full_installs_prune_only_repo_orphans(self):
        for index, args in enumerate(([], ['--all'], ['--dry-run'])):
            with self.subTest(args=args):
                repo = self.make_installer_repo(f'prune-{index}')
                home = Path(self.temp_dir) / f'prune-home-{index}'
                bin_dir = home / '.local/bin'
                bin_dir.mkdir(parents=True)
                orphan = bin_dir / 'deleted-command'
                orphan.symlink_to(repo / 'bin/deleted-command')
                foreign = bin_dir / 'foreign-command'
                foreign.symlink_to(home / 'missing-command')
                regular = bin_dir / 'local-command'
                regular.write_text('LOCAL')
                proc = subprocess.run(
                    ['bash', str(repo / 'install.sh'), *args],
                    capture_output=True, text=True, env={**self.env, 'HOME': str(home)},
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(orphan.is_symlink(), args == ['--dry-run'])
                self.assertTrue(foreign.is_symlink())
                self.assertEqual(regular.read_text(), 'LOCAL')

    def test_path_selectors_are_rejected_before_mutation(self):
        repo = self.make_installer_repo('selectors')
        for selector in ('btop/', './btop', 'btop/../btop', '../root', '.', '..', ''):
            with self.subTest(selector=selector):
                proc = subprocess.run(
                    ['bash', str(repo / 'install.sh'), 'btop', selector],
                    capture_output=True, text=True, env=self.env,
                )
                self.assertNotEqual(proc.returncode, 0, f'Accepted non-installable selector: {selector!r}')
                self.assertIn('hợp lệ', proc.stderr)
                self.assertFalse((self.home / '.config').exists())
                self.assertFalse((self.home / '.local').exists())

    def test_invalid_selector_exits_with_error(self):
        proc = subprocess.run(
            ['bash', str(self.install_script), 'nonexistent_selector_xyz'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertNotEqual(proc.returncode, 0, 'Installer should fail on invalid selector')
        output = (proc.stderr + proc.stdout).lower()
        self.assertTrue('hợp lệ' in output or 'hop le' in output)

    def test_consecutive_installs_do_not_clobber_backups(self):
        # Create an existing regular file in target
        target_file = self.home / '.config/starship.toml'
        target_file.parent.mkdir(parents=True, exist_ok=True)
        target_file.write_text('INITIAL_USER_CONTENT')

        # First install of starship.toml
        proc1 = subprocess.run(
            ['bash', str(self.install_script), 'starship.toml'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc1.returncode, 0, f'Install 1 failed: {proc1.stderr}')

        # Find backup dir from first install
        backup_root = self.home / '.config/backups'
        self.assertTrue(backup_root.exists(), 'Backup root should exist')
        backup_dirs_first = set(backup_root.glob('dotfiles-*'))
        self.assertEqual(len(backup_dirs_first), 1)
        first_dir = next(iter(backup_dirs_first))
        backup_file = first_dir / '.config/starship.toml'
        self.assertTrue(backup_file.exists())
        self.assertEqual(backup_file.read_text(), 'INITIAL_USER_CONTENT')

        # Now replace the symlink with another regular file as if another profile was written
        target_file.unlink()
        target_file.write_text('SECOND_PROFILE_CONTENT')

        # Second install in rapid succession
        proc2 = subprocess.run(
            ['bash', str(self.install_script), 'starship.toml'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc2.returncode, 0, f'Install 2 failed: {proc2.stderr}')

        # Verify that original backup was NOT overwritten
        self.assertEqual(backup_file.read_text(), 'INITIAL_USER_CONTENT')

        # And a second backup dir was created with second content
        backup_dirs_after = set(backup_root.glob('dotfiles-*'))
        new_dirs = backup_dirs_after - backup_dirs_first
        self.assertEqual(len(new_dirs), 1)
        second_dir = next(iter(new_dirs))
        second_backup_file = second_dir / '.config/starship.toml'
        self.assertTrue(second_backup_file.exists())
        self.assertEqual(second_backup_file.read_text(), 'SECOND_PROFILE_CONTENT')

    def test_wt_prep_safe_when_source_missing(self):
        wt_dir = Path(self.temp_dir) / 'mock_worktree'
        (wt_dir / 'config/hypr').mkdir(parents=True)
        # Put an existing file in worktree
        (wt_dir / 'config/hypr/current_wallpaper').write_text('EXISTING_WT_WALLPAPER')

        source = Path(self.temp_dir) / 'source'
        (source / 'config/hypr').mkdir(parents=True)
        prep_script = source / 'wt-prep.sh'
        shutil.copy2(self.repo / 'wt-prep.sh', prep_script)
        proc = subprocess.run(
            ['bash', str(prep_script), str(wt_dir)],
            capture_output=True,
            text=True,
            cwd=str(self.repo)
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn('prepped', proc.stdout)
        # Verify the file was not deleted or replaced with valid source
        self.assertTrue((wt_dir / 'config/hypr/current_wallpaper').exists())

    def test_wt_prep_rejects_source_aliases_without_deleting_files(self):
        for target in ('relative', 'absolute', 'symlink', 'hypr_alias', 'gpu_only'):
            with self.subTest(target=target):
                source = Path(self.temp_dir) / target / 'source'
                hypr = source / 'config/hypr'
                (hypr / 'gpu').mkdir(parents=True)
                gpu = hypr / 'gpu/intel'
                gpu.write_text('GPU_CONFIG')
                wallpaper = hypr / 'current_wallpaper'
                if target != 'gpu_only':
                    wallpaper.symlink_to('/missing/test-wallpaper.png')
                script = source / 'wt-prep.sh'
                shutil.copy2(self.repo / 'wt-prep.sh', script)
                destination = source
                if target == 'symlink':
                    destination = source.parent / 'alias'
                    destination.symlink_to(source, target_is_directory=True)
                elif target == 'hypr_alias':
                    destination = source.parent / 'other'
                    (destination / 'config').mkdir(parents=True)
                    (destination / 'config/hypr').symlink_to(hypr, target_is_directory=True)
                proc = subprocess.run(
                    ['bash', str(script), '.' if target == 'relative' else str(destination)],
                    capture_output=True, text=True, cwd=self.temp_dir,
                )
                self.assertNotEqual(proc.returncode, 0)
                self.assertEqual(gpu.read_text(), 'GPU_CONFIG')
                if target != 'gpu_only':
                    self.assertTrue(wallpaper.is_symlink(), proc.stderr)
                    self.assertEqual(os.readlink(wallpaper), '/missing/test-wallpaper.png')
                self.assertIn('repo nguon', proc.stderr)

    def test_wt_prep_copies_machine_files_to_distinct_destination(self):
        source = Path(self.temp_dir) / 'source'
        hypr = source / 'config/hypr'
        (hypr / 'gpu').mkdir(parents=True)
        (hypr / 'gpu/intel').symlink_to('/dev/dri/missing-test-gpu')
        (hypr / 'current_wallpaper').symlink_to('/missing/test-wallpaper.png')
        script = source / 'wt-prep.sh'
        shutil.copy2(self.repo / 'wt-prep.sh', script)
        destination = Path(self.temp_dir) / 'destination/config/hypr'
        (destination / 'gpu').mkdir(parents=True)
        (destination / 'gpu/stale').write_text('OLD')
        (destination / 'current_wallpaper').write_text('OLD')
        proc = subprocess.run(
            ['bash', str(script), str(destination.parents[1])],
            capture_output=True, text=True, cwd=self.temp_dir,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(os.readlink(destination / 'current_wallpaper'), '/missing/test-wallpaper.png')
        self.assertEqual(os.readlink(destination / 'gpu/intel'), '/dev/dri/missing-test-gpu')
        self.assertFalse((destination / 'gpu/stale').exists())
        self.assertTrue((hypr / 'gpu/intel').is_symlink())
        self.assertTrue((hypr / 'current_wallpaper').is_symlink())


    def test_multiple_conflicts_share_single_backup_dir(self):
        # Create two conflicting target files
        f1 = self.home / '.config/starship.toml'
        f2 = self.home / '.config/kdeglobals'
        f1.parent.mkdir(parents=True, exist_ok=True)
        f1.write_text('STARSHIP_DATA')
        f2.write_text('KDE_DATA')

        proc = subprocess.run(
            ['bash', str(self.install_script), 'starship.toml', 'kdeglobals'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc.returncode, 0, f'Install failed: {proc.stderr}')

        backup_root = self.home / '.config/backups'
        backup_dirs = list(backup_root.glob('dotfiles-*'))
        # Must be EXACTLY 1 backup dir, not 2 separate dirs
        self.assertEqual(len(backup_dirs), 1, f'Expected 1 backup directory, got {len(backup_dirs)}')
        bdir = backup_dirs[0]
        self.assertTrue((bdir / '.config/starship.toml').exists())
        self.assertTrue((bdir / '.config/kdeglobals').exists())
        self.assertEqual((bdir / '.config/starship.toml').read_text(), 'STARSHIP_DATA')
        self.assertEqual((bdir / '.config/kdeglobals').read_text(), 'KDE_DATA')

        # Verify that output reports the backup directory correctly
        self.assertIn(str(bdir), proc.stdout)

    def test_default_install_excludes_snapshot_systemd(self):
        # Default install should NOT link systemd
        proc = subprocess.run(
            ['bash', str(self.install_script)],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc.returncode, 0)
        self.assertFalse((self.home / '.config/systemd').exists(), 'Default install should not link systemd')
        # Core configs should be linked
        self.assertTrue((self.home / '.config/hypr').is_symlink())
        self.assertTrue((self.home / '.config/noctalia').is_symlink())
        self.assertTrue((self.home / '.local/bin/toggle-desktop').is_symlink())

        # When explicitly requested or with --all, systemd is linked
        proc_all = subprocess.run(
            ['bash', str(self.install_script), '--all'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc_all.returncode, 0)
        self.assertTrue((self.home / '.config/systemd').is_symlink(), '--all should link systemd')

    def test_cleanup_orphaned_bin_symlinks(self):
        bin_dir = self.home / '.local/bin'
        bin_dir.mkdir(parents=True, exist_ok=True)
        # Create an orphaned symlink pointing to a deleted script in REPO/bin
        orphaned = bin_dir / 'deleted_old_script'
        orphaned.symlink_to(self.repo / 'bin/deleted_old_script')
        self.assertTrue(orphaned.is_symlink())
        self.assertFalse(orphaned.exists()) # Broken link

        proc = subprocess.run(
            ['bash', str(self.install_script)],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc.returncode, 0)
        # Verify the orphaned symlink was cleaned up
        self.assertFalse(orphaned.is_symlink())

    def test_dry_run_messaging_no_writes_and_preview_status(self):
        # 1. Clean run without conflicts: preview only, never claims synchronized or created
        proc_clean = subprocess.run(
            ['bash', str(self.install_script), '--dry-run'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc_clean.returncode, 0)
        out_clean = proc_clean.stdout
        self.assertIn('preview only', out_clean.lower())
        self.assertNotIn('linked:', out_clean)
        self.assertNotIn('đồng bộ', out_clean.lower())
        self.assertNotIn('backup nằm trong', out_clean.lower())
        self.assertFalse((self.home / '.config/backups').exists())

        # 2. Run with conflicting file: mentions planned backup directory, creates nothing
        target_file = self.home / '.config/starship.toml'
        target_file.parent.mkdir(parents=True, exist_ok=True)
        target_file.write_text('EXISTING_CONTENT')

        proc_conflict = subprocess.run(
            ['bash', str(self.install_script), '--dry-run', 'starship.toml'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc_conflict.returncode, 0)
        out_conflict = proc_conflict.stdout
        self.assertIn('preview only', out_conflict.lower())
        self.assertNotIn('linked:', out_conflict)
        self.assertNotIn('đồng bộ', out_conflict.lower())
        self.assertNotIn('backup nằm trong', out_conflict.lower())
        self.assertTrue('dự kiến' in out_conflict.lower() or 'planned' in out_conflict.lower())
        self.assertIn('.config/backups/dotfiles-', out_conflict)
        # Verify no backup directory or files created on disk
        self.assertFalse((self.home / '.config/backups').exists())
        self.assertEqual(target_file.read_text(), 'EXISTING_CONTENT')
        self.assertFalse(target_file.is_symlink())

    def test_hierarchical_backup_and_restoration_of_same_basename_conflicts(self):
        self.home = Path(self.temp_dir) / 'home [literal]'
        self.home.mkdir()
        self.env['HOME'] = str(self.home)
        repo = self.make_installer_repo('hierarchical')
        # Introduce same basename 'sample-item' across config and bin
        (repo / 'config/sample-item').write_text('NEW_CONFIG_ITEM')
        (repo / 'bin/sample-item').write_text('#!/bin/sh\necho new_bin\n')

        # Create conflicting pre-existing files in destinations
        cfg_dst = self.home / '.config/sample-item'
        cfg_dst.parent.mkdir(parents=True, exist_ok=True)
        cfg_dst.write_text('ORIGINAL_CONFIG_CONTENT')

        bin_dst = self.home / '.local/bin/sample-item'
        bin_dst.parent.mkdir(parents=True, exist_ok=True)
        bin_dst.write_text('ORIGINAL_BIN_CONTENT')

        state_dst = self.home / '.local/state/noctalia/settings.toml'
        state_dst.parent.mkdir(parents=True)
        state_dst.write_text('ORIGINAL_STATE_CONTENT')

        # Also create a pre-existing historical backup directory that should stay untouched
        hist_backup = self.home / '.config/backups/dotfiles-historical'
        hist_backup.mkdir(parents=True)
        (hist_backup / 'legacy.txt').write_text('LEGACY_BACKUP')

        proc = subprocess.run(
            ['bash', str(repo / 'install.sh'), 'sample-item', 'noctalia'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(repo)
        )
        self.assertEqual(proc.returncode, 0, f'Install failed: {proc.stderr}')

        # Verify historical backup is completely untouched
        self.assertTrue((hist_backup / 'legacy.txt').exists())
        self.assertEqual((hist_backup / 'legacy.txt').read_text(), 'LEGACY_BACKUP')

        # Verify single new backup root created
        backup_root = self.home / '.config/backups'
        new_bdirs = [d for d in backup_root.glob('dotfiles-*') if d.name != 'dotfiles-historical']
        self.assertEqual(len(new_bdirs), 1)
        bdir = new_bdirs[0]

        # Verify mirrored HOME-relative paths under bdir
        backed_cfg = bdir / '.config/sample-item'
        backed_bin = bdir / '.local/bin/sample-item'
        self.assertTrue(backed_cfg.exists(), f'Expected {backed_cfg} to exist')
        self.assertTrue(backed_bin.exists(), f'Expected {backed_bin} to exist')
        self.assertEqual(backed_cfg.read_text(), 'ORIGINAL_CONFIG_CONTENT')
        self.assertEqual(backed_bin.read_text(), 'ORIGINAL_BIN_CONTENT')
        self.assertEqual((bdir / '.local/state/noctalia/settings.toml').read_text(), 'ORIGINAL_STATE_CONTENT')

        # Remove installed links before restoring; never copy through them into sources.
        cfg_dst.unlink()
        bin_dst.unlink()
        state_dst.unlink()
        shutil.copytree(bdir, self.home, dirs_exist_ok=True)
        self.assertEqual(cfg_dst.read_text(), 'ORIGINAL_CONFIG_CONTENT')
        self.assertEqual(bin_dst.read_text(), 'ORIGINAL_BIN_CONTENT')
        self.assertEqual(state_dst.read_text(), 'ORIGINAL_STATE_CONTENT')
        self.assertEqual((repo / 'config/sample-item').read_text(), 'NEW_CONFIG_ITEM')
        self.assertEqual((repo / 'bin/sample-item').read_text(), '#!/bin/sh\necho new_bin\n')

    def test_help_formatting_and_selectors(self):
        proc = subprocess.run(
            ['bash', str(self.install_script), '--help'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(self.repo)
        )
        self.assertEqual(proc.returncode, 0)
        help_text = proc.stdout
        # Noctalia must not be duplicated in default list
        default_lines = [line for line in help_text.splitlines() if 'Mặc định' in line]
        self.assertTrue(len(default_lines) >= 1)
        for line in default_lines:
            self.assertEqual(line.count('noctalia'), 1, f"Duplicated noctalia in default help line: {line}")
            self.assertFalse(line.rstrip().endswith('bin).'), f"Default line suggests literal 'bin' selector: {line}")
        # Literal 'bin' must not be suggested as a selector; scripts in bin/ should be distinguished
        self.assertIn('bin/', help_text)

    def test_selected_with_all_reports_selected_mode_and_preserves_precedence(self):
        repo = self.make_installer_repo('selected-all')
        proc = subprocess.run(
            ['bash', str(repo / 'install.sh'), '--all', 'btop'],
            capture_output=True,
            text=True,
            env=self.env,
            cwd=str(repo)
        )
        self.assertEqual(proc.returncode, 0, f"Install failed: {proc.stderr}")
        # Must report selected mode, NOT 'Toàn bộ'
        self.assertIn('Chọn lọc', proc.stdout)
        self.assertNotIn('Toàn bộ', proc.stdout)
        # Writes must not broaden beyond selected 'btop'
        self.assertTrue((self.home / '.config/btop').is_symlink())
        self.assertFalse((self.home / '.config/starship.toml').exists())
        self.assertFalse((self.home / '.config/kdeglobals').exists())
        self.assertFalse((self.home / '.local/bin/test-command').exists())


if __name__ == '__main__':
    unittest.main()
