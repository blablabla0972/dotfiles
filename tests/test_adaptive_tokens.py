"""Offline public-contract tests; no renderer, decoder, or live configuration."""

import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from config.rice.theme.derive_tokens import (
    choose_surface_alpha,
    composite_rgb,
    contrast_ratio,
    derive_tokens,
    hex_to_srgb,
    relative_luminance,
)


WALLPAPER_SHA = "a" * 64
PALETTE_SHA = "b" * 64
PALETTE = json.loads((ROOT / "config/noctalia/palettes/matugen.json").read_text())
NATIVE_ROLES = {
    "mPrimary": "primary", "mOnPrimary": "on_primary",
    "mSurface": "surface", "mOnSurface": "on_surface",
    "mSurfaceVariant": "surface_variant",
    "mOnSurfaceVariant": "on_surface_variant",
    "mOutline": "outline", "mError": "error", "mHover": "hover",
}
SAMPLE_CASES = {
    "dark": ["#000000", "#101820", "#242038"],
    "bright": ["#FFFFFF", "#FFFBE6", "#E8FFFF"],
    "pastel": ["#F8C8DC", "#C1E1C1", "#C7CEEA"],
    "neon": ["#00FF00", "#FF00FF", "#00FFFF"],
    "grayscale": ["#000000", "#777777", "#FFFFFF"],
    "muddy": ["#565043", "#5B5550", "#4D514B"],
    "complementary": ["#FF0000", "#00FFFF"],
    "high_frequency": ["#000000", "#FFFFFF"] * 8,
    "warm": ["#FF2400", "#FFA500", "#FFFF00"],
    "cool": ["#0000FF", "#4B0082", "#0088AA"],
    "midtones": ["#777777", "#888888", "#999999"],
    "isolated_bright_patch": ["#111111"] * 20 + ["#FFFFFF"],
}


def tokens(palette=None, mode="dark", samples=None, **kwargs):
    return derive_tokens(
        PALETTE if palette is None else palette,
        kwargs.get("wallpaper_sha", WALLPAPER_SHA),
        kwargs.get("palette_sha", PALETTE_SHA), mode, samples,
    )


class ColorMathTests(unittest.TestCase):
    def test_hex_normalizes_to_srgb_channels(self):
        self.assertEqual(hex_to_srgb("#00ff80"), (0.0, 1.0, 128 / 255))

    def test_black_white_and_same_color_contrast(self):
        self.assertEqual(relative_luminance("#000000"), 0)
        self.assertEqual(relative_luminance("#FFFFFF"), 1)
        self.assertEqual(contrast_ratio("#000000", "#FFFFFF"), 21)
        self.assertEqual(contrast_ratio("#FFFFFF", "#000000"), 21)
        self.assertEqual(contrast_ratio("#abcdef", "#abcdef"), 1)

    def test_wcag_linearization_and_channel_weights(self):
        self.assertAlmostEqual(relative_luminance("#0A0A0A"), 0.003035269835488375)
        self.assertAlmostEqual(relative_luminance("#0B0B0B"), 0.003346535763899161)
        self.assertAlmostEqual(relative_luminance("#FF0000"), 0.2126)
        self.assertAlmostEqual(relative_luminance("#00FF00"), 0.7152)
        self.assertAlmostEqual(relative_luminance("#0000FF"), 0.0722)
        self.assertAlmostEqual(contrast_ratio("#777777", "#FFFFFF"), 4.478089453577214)

    def test_strict_hex_rejected_by_all_color_entry_points(self):
        for invalid in ("", "#fff", "123456", "#12345678", "#GG0000", " #123456",
                        "#123456\n", None, 123456):
            for function, args in (
                (hex_to_srgb, (invalid,)), (relative_luminance, (invalid,)),
                (contrast_ratio, (invalid, "#000000")),
                (contrast_ratio, ("#000000", invalid)),
                (composite_rgb, (invalid, "#000000", 0.5)),
                (composite_rgb, ("#000000", invalid, 0.5)),
            ):
                with self.subTest(invalid=invalid, function=function.__name__, args=args):
                    with self.assertRaises(ValueError):
                        function(*args)

    def test_srgb_composite_endpoints_and_half_up_rounding(self):
        self.assertEqual(composite_rgb("#ab12cd", "#12ef34", 0), "#12EF34")
        self.assertEqual(composite_rgb("#ab12cd", "#12ef34", 1), "#AB12CD")
        self.assertEqual(composite_rgb("#FFFFFF", "#000000", 0.5), "#808080")
        self.assertEqual(composite_rgb("#000000", "#FFFFFF", 0.5), "#808080")
        self.assertEqual(composite_rgb("#FE0000", "#FF0000", 0.5), "#FF0000")

    def test_invalid_opacity_rejected(self):
        for alpha in (-0.1, 1.01, float("nan"), float("inf"), "0.5", None, True):
            with self.subTest(alpha=alpha), self.assertRaises(ValueError):
                composite_rgb("#FFFFFF", "#000000", alpha)


class SurfaceAlphaTests(unittest.TestCase):
    def test_selects_smallest_passing_candidate_regardless_of_order(self):
        self.assertEqual(choose_surface_alpha(
            "#FFFFFF", "#000000", ["#FFFFFF"], (1.0, 0.5, 0.72)), 0.72)

    def test_checks_worst_sample_instead_of_average(self):
        self.assertEqual(choose_surface_alpha("#808080", "#000000", ["#000000"]), 0.72)
        self.assertEqual(choose_surface_alpha(
            "#808080", "#000000", ["#000000"] * 20 + ["#FFFFFF"]), 0.96)

    def test_adds_safety_margin_to_requested_ratio(self):
        self.assertEqual(choose_surface_alpha(
            "#000000", "#FFFFFF", ["#000000"], (119 / 255, 0.5, 1.0)), 0.5)
        self.assertEqual(choose_surface_alpha(
            "#000000", "#FFFFFF", ["#000000"], (0.4, 0.5, 1.0), 3), 0.4)

    def test_unknown_wallpaper_and_impossible_contrast_return_opaque(self):
        for samples in (None, []):
            self.assertEqual(choose_surface_alpha("#FFFFFF", "#000000", samples), 1)
        self.assertEqual(choose_surface_alpha("#777777", "#777777", ["#000000"]), 1)
        self.assertEqual(choose_surface_alpha(
            "#777777", "#777777", ["#000000"], (0.96, 0.99)), 1)

    def test_invalid_alpha_policy_and_samples_rejected(self):
        for kwargs in ({"candidates": ()}, {"candidates": (-0.1, 1)},
                       {"candidates": (0.9, float("nan"))}, {"candidates": (True,)},
                       {"min_ratio": 0}, {"min_ratio": 22},
                       {"min_ratio": float("inf")}, {"min_ratio": True}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                choose_surface_alpha("#FFFFFF", "#000000", ["#FFFFFF"], **kwargs)
        for samples in (["#fff"], [None], "#FFFFFF", {}):
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                choose_surface_alpha("#FFFFFF", "#000000", samples)


class AdaptiveTokensTests(unittest.TestCase):
    def test_real_palette_maps_semantic_roles_in_both_modes(self):
        for mode in ("dark", "light"):
            with self.subTest(mode=mode):
                result = tokens(mode=mode)
                source = PALETTE[mode]
                mapping = {
                    "background": "mSurface", "surface_low": "mSurfaceVariant",
                    "surface": "mSurfaceVariant", "surface_high": "mHover",
                    "text_primary": "mOnSurface", "text_secondary": "mOnSurfaceVariant",
                    "accent": "mPrimary", "on_accent": "mOnPrimary",
                    "outline": "mOutline", "focus_ring": "mPrimary", "danger": "mError",
                }
                self.assertEqual(result["colors"], {k: source[v].upper() for k, v in mapping.items()})
                self.assertEqual(result["schema_version"], 1)
                self.assertEqual(result["mode"], mode)
                self.assertEqual(result["wallpaper_sha256"], WALLPAPER_SHA)
                self.assertEqual(result["source_palette_sha256"], PALETTE_SHA)
                self.assertEqual(result["motion"], {"hover_ms": 120, "popup_ms": 190, "overlay_ms": 240})
                self.assertEqual(result["quality"], "balanced")

    def test_native_snake_case_normalizes_equivalently(self):
        for mode in ("dark", "light"):
            native = {v: PALETTE[mode][k] for k, v in NATIVE_ROLES.items()}
            self.assertEqual(tokens({mode: native}, mode), tokens(mode=mode))
            self.assertEqual(tokens({"mode": mode, **native}, mode), tokens(mode=mode))

    def test_optional_hover_falls_back_without_inventing_a_color(self):
        palette = copy.deepcopy(PALETTE)
        del palette["dark"]["mHover"]
        result = tokens(palette)
        self.assertEqual(result["colors"]["surface_high"], PALETTE["dark"]["mSurfaceVariant"].upper())

    def test_unknown_wallpaper_is_solid_without_image_awareness(self):
        for mode in ("dark", "light"):
            for samples in (None, []):
                with self.subTest(mode=mode, samples=samples):
                    result = tokens(mode=mode, samples=samples)
                    self.assertEqual(set(result["materials"]), {"bar", "panel", "notification"})
                    for material in result["materials"].values():
                        self.assertEqual(material, {"opacity": 1.0, "style": "solid"})
                    self.assertEqual(result["contrast"]["basis"], "opaque")
                    self.assertEqual(result["contrast"]["sample_count"], 0)
                    self.assertFalse(result["contrast"]["renderer_verified"])
                    self.assertTrue(result["contrast"]["satisfied"])

    def test_twelve_sample_cases_check_effective_contrast_in_both_modes(self):
        surfaces = {"bar": "surface_low", "panel": "surface", "notification": "surface_high"}
        minimums = {"text_primary": 4.8, "text_secondary": 4.8,
                    "accent": 3.3, "focus_ring": 3.3, "danger": 3.3}
        for mode in ("dark", "light"):
            for name, samples in SAMPLE_CASES.items():
                with self.subTest(mode=mode, samples=name):
                    result = tokens(mode=mode, samples=samples)
                    self.assertTrue(result["contrast"]["satisfied"])
                    self.assertEqual(result["contrast"]["unsatisfied_roles"], [])
                    self.assertEqual(result["contrast"]["sample_count"], len(samples))
                    self.assertEqual(result["contrast"]["basis"], "samples")
                    colors = result["colors"]
                    for material, surface in surfaces.items():
                        alpha = result["materials"][material]["opacity"]
                        for role, minimum in minimums.items():
                            ratio = min(contrast_ratio(colors[role], composite_rgb(colors[surface], s, alpha))
                                        for s in samples)
                            self.assertGreaterEqual(ratio, minimum)
                            check = result["contrast"]["checks"][f"{material}.{role}"]
                            self.assertAlmostEqual(check["ratio"], ratio)
                            self.assertEqual(check["minimum"], minimum)
                            self.assertTrue(check["satisfied"])
                    self.assertGreaterEqual(contrast_ratio(colors["on_accent"], colors["accent"]), 4.8)

    def test_focus_uses_icon_threshold_with_margin(self):
        palette = copy.deepcopy(PALETTE)
        palette["dark"].update(mSurface="#000000", mSurfaceVariant="#000000", mHover="#000000",
                               mOnSurface="#FFFFFF", mOnSurfaceVariant="#FFFFFF",
                               mPrimary="#666666", mOnPrimary="#FFFFFF", mError="#FFFFFF")
        result = tokens(palette, samples=["#FFFFFF"])
        self.assertTrue(result["contrast"]["satisfied"])
        self.assertEqual(result["materials"]["bar"], {"opacity": 0.96, "style": "balanced"})
        self.assertEqual(result["contrast"]["checks"]["bar.focus_ring"]["minimum"], 3.3)
        palette["dark"]["mPrimary"] = "#5A5A5A"
        result = tokens(palette, samples=["#000000"])
        self.assertFalse(result["contrast"]["satisfied"])
        self.assertIn("bar.focus_ring", result["contrast"]["unsatisfied_roles"])

    def test_unachievable_palette_reports_failures_at_opaque(self):
        palette = {"dark": {key: "#808080" for key in NATIVE_ROLES}}
        for samples in (None, ["#FFFFFF", "#000000"]):
            result = tokens(palette, samples=samples)
            self.assertFalse(result["contrast"]["satisfied"])
            for material in result["materials"].values():
                self.assertEqual(material, {"opacity": 1.0, "style": "solid"})
            self.assertIn("on_accent", result["contrast"]["unsatisfied_roles"])
            self.assertIn("bar.text_primary", result["contrast"]["unsatisfied_roles"])
            self.assertEqual(result["contrast"]["checks"]["bar.text_primary"]["ratio"], 1)

    def test_on_accent_failure_cannot_be_hidden_by_surface_opacity(self):
        palette = copy.deepcopy(PALETTE)
        palette["dark"]["mOnPrimary"] = palette["dark"]["mPrimary"]
        result = tokens(palette, samples=["#000000"])
        self.assertEqual(result["contrast"]["unsatisfied_roles"], ["on_accent"])
        self.assertFalse(result["contrast"]["satisfied"])
        self.assertTrue(all(m == {"opacity": 1.0, "style": "solid"} for m in result["materials"].values()))

    def test_empty_palette_and_every_missing_required_role_rejected(self):
        for palette in ({}, None, [], {"dark": {}}, {"dark": None}):
            with self.subTest(palette=palette), self.assertRaises(ValueError):
                derive_tokens(palette, WALLPAPER_SHA, PALETTE_SHA, "dark", None)
        for role in set(NATIVE_ROLES) - {"mHover"}:
            palette = copy.deepcopy(PALETTE)
            del palette["dark"][role]
            with self.subTest(role=role), self.assertRaises(ValueError):
                tokens(palette)

    def test_invalid_role_colors_and_samples_rejected(self):
        for role in NATIVE_ROLES:
            for color in ("", "#abc", "#12345678", None):
                palette = copy.deepcopy(PALETTE)
                palette["dark"][role] = color
                with self.subTest(role=role, color=color), self.assertRaises(ValueError):
                    tokens(palette)
        for samples in (["#FFFFFF", "invalid"], "#FFFFFF", {}):
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                tokens(samples=samples)

    def test_mode_mismatch_unlabelled_and_mixed_schemes_rejected(self):
        cases = [(PALETTE, "auto"), (PALETTE, None), ({"light": PALETTE["light"]}, "dark"),
                 ({"mode": "light", **PALETTE["dark"]}, "dark"),
                 (PALETTE["dark"], "dark"),
                 ({"mode": "light", **PALETTE}, "dark"),
                 ({"dark": {"mode": "light", **PALETTE["dark"]}}, "dark"),
                 ({"dark": {"primary": "#FFFFFF", **PALETTE["dark"]}}, "dark"),
                 ({"mode": "dark", **PALETTE["dark"], **PALETTE}, "dark")]
        for palette, mode in cases:
            with self.subTest(mode=mode, keys=list(palette)), self.assertRaises(ValueError):
                tokens(palette, mode)

    def test_invalid_hashes_rejected_and_valid_hashes_canonicalized(self):
        for value in ("", "a" * 63, "a" * 65, "g" * 64, "a" * 64 + "\n", None, 123):
            for key in ("wallpaper_sha", "palette_sha"):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    tokens(**{key: value})
        result = tokens(wallpaper_sha="A" * 64, palette_sha="B" * 64)
        self.assertEqual(result["wallpaper_sha256"], WALLPAPER_SHA)
        self.assertEqual(result["source_palette_sha256"], PALETTE_SHA)

    def test_explicit_input_schema_version_checked(self):
        self.assertEqual(tokens({"schema_version": 1, **PALETTE}), tokens())
        for version in (0, 2, "1", True, None):
            with self.subTest(version=version), self.assertRaises(ValueError):
                tokens({"schema_version": version, **PALETTE})

    def test_stable_json_is_order_independent_and_inputs_are_unchanged(self):
        palette = copy.deepcopy(PALETTE)
        samples = list(SAMPLE_CASES["pastel"])
        before = copy.deepcopy((palette, samples))
        first = tokens(palette, samples=samples)
        reordered = {mode: dict(reversed(list(roles.items()))) for mode, roles in reversed(list(palette.items()))}
        second = tokens(reordered, samples=list(reversed(samples)))
        self.assertEqual(json.dumps(first, allow_nan=False), json.dumps(second, allow_nan=False))
        self.assertEqual(json.loads(json.dumps(first, allow_nan=False)), first)
        self.assertEqual((palette, samples), before)
        self.assertEqual(first, tokens(palette, samples=samples))


if __name__ == "__main__":
    unittest.main()
