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

        prep_script = self.repo / 'wt-prep.sh'
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
