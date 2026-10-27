"""Regressions for transparent bars with independently painted capsules."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('palette_matrix', Path(__file__).with_name('check_palette_matrix.py'))
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class CapsuleContrastTest(unittest.TestCase):
    def test_accent_capsule_checks_the_actual_on_primary_foreground(self):
        palette = {'mSurface': '#0f1512', 'mPrimary': '#8ad6b6', 'mOnPrimary': '#003828'}
        config = {'bar': {'default': {'background_opacity': 0, 'capsule': True,
                  'capsule_fill': 'primary', 'capsule_opacity': 1, 'start': ['launcher']}},
                  'widget': {'launcher': {'color': 'on_primary'}}}
        samples = matrix.bar_contrast_samples(palette, config)
        self.assertEqual({role for _, role, _, _ in samples}, {'on_primary'})
        self.assertGreaterEqual(min(matrix.contrast(fg, bg) for _, _, fg, bg in samples), 4.5)

    def test_transparent_bar_uses_group_surface_and_checks_secondary_text(self):
        palette = {'mSurface': '#f5fbf5', 'mSurfaceVariant': '#eff5f0', 'mOnSurface': '#171d1a',
                   'mOnSurfaceVariant': '#404944', 'mSecondary': '#4c6359'}
        config = {'bar': {'default': {'background_opacity': 0, 'capsule': True,
                  'capsule_opacity': .92, 'start': ['group:clock'], 'capsule_group': [
                  {'id': 'clock', 'members': ['clock'], 'fill': 'surface_variant', 'opacity': .82}]}},
                  'widget': {'clock': {'color': 'secondary'}}}
        low = [matrix.contrast(fg, bg) for _, role, fg, bg in matrix.bar_contrast_samples(palette, config) if role == 'secondary']
        self.assertLess(min(low), 4.5)
        fixed = copy.deepcopy(config)
        fixed['bar']['default']['capsule_group'][0]['opacity'] = .92
        self.assertGreaterEqual(min(matrix.contrast(fg, bg) for _, _, fg, bg in matrix.bar_contrast_samples(palette, fixed)), 4.5)

    def test_zero_bar_opacity_does_not_hide_capsule_background(self):
        palette = {'mSurface': '#101010', 'mSurfaceVariant': '#181818',
                   'mOnSurface': '#eeeeee', 'mOnSurfaceVariant': '#cccccc',
                   'mPrimary': '#8ad6b6', 'mOnPrimary': '#003828',
                   'mSecondary': '#b3ccbf', 'mOnSecondary': '#1e352c',
                   'mError': '#ffb4ab', 'mOnError': '#690005'}
        config = {'bar': {'default': {'background_opacity': 0, 'capsule': True,
                  'capsule_opacity': .92, 'center': ['workspaces']}},
                  'widget': {'workspaces': {'empty_color': 'surface_variant', 'occupied_color': 'secondary'}}}
        self.assertGreaterEqual(min(matrix.contrast(fg, bg) for _, _, fg, bg in matrix.bar_contrast_samples(palette, config)), 4.5)
        config['widget']['workspaces']['occupied_color'] = 'on_surface'
        samples = matrix.bar_contrast_samples(palette, config)
        self.assertEqual(min(matrix.contrast(fg, bg) for name, _, fg, bg in samples if name == 'workspaces.occupied_color'), 1)
