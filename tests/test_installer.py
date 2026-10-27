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
        backup_file = first_dir / 'starship.toml'
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
        second_backup_file = second_dir / 'starship.toml'
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
        self.assertTrue((bdir / 'starship.toml').exists())
        self.assertTrue((bdir / 'kdeglobals').exists())
        self.assertEqual((bdir / 'starship.toml').read_text(), 'STARSHIP_DATA')
        self.assertEqual((bdir / 'kdeglobals').read_text(), 'KDE_DATA')

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


if __name__ == '__main__':
    unittest.main()
