"""Pure adaptive tokens, with no image decoding, file writes, or runtime effects.

Compositing assumes sRGB channel blending with nearest-byte, half-up rounding.
This renderer assumption is NOT screenshot-verified; contrast includes a 0.3
safety margin. Callers must inspect ``contrast.satisfied``, even for solid output.
"""

import math
import re


_ALPHAS = (0.72, 0.82, 0.90, 0.96, 1.0)
_MARGIN = 0.3
_NATIVE_ROLES = {
    "mPrimary": "primary",
    "mOnPrimary": "on_primary",
    "mSurface": "surface",
    "mOnSurface": "on_surface",
    "mSurfaceVariant": "surface_variant",
    "mOnSurfaceVariant": "on_surface_variant",
    "mOutline": "outline",
    "mError": "error",
    "mHover": "hover",
}
_MINIMUMS = {
    "text_primary": 4.5 + _MARGIN,
    "text_secondary": 4.5 + _MARGIN,
    "accent": 3.0 + _MARGIN,
    "focus_ring": 3.0 + _MARGIN,
    "danger": 3.0 + _MARGIN,
}


def hex_to_srgb(color: str) -> tuple[float, float, float]:
    """Validate strict #RRGGBB and return encoded sRGB channels in [0, 1]."""
    if not isinstance(color, str) or re.fullmatch(r"#[0-9a-fA-F]{6}", color) is None:
        raise ValueError("color must be strict #RRGGBB")
    return tuple(int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))


def relative_luminance(color: str) -> float:
    """WCAG relative luminance, using the 0.04045 sRGB breakpoint."""
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
              for c in hex_to_srgb(color)]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast_ratio(foreground: str, background: str) -> float:
    """Symmetric WCAG contrast ratio in [1, 21]."""
    a, b = relative_luminance(foreground), relative_luminance(background)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def _number(value, lower, upper, name):
    if (isinstance(value, bool) or not isinstance(value, (int, float))
            or not lower <= value <= upper or not math.isfinite(value)):
        raise ValueError(f"{name} must be finite and in [{lower}, {upper}]")
    return float(value)


def composite_rgb(foreground: str, background: str, alpha: float) -> str:
    """Blend encoded sRGB channels, then quantize to uppercase #RRGGBB."""
    front, back = hex_to_srgb(foreground), hex_to_srgb(background)
    alpha = _number(alpha, 0, 1, "alpha")
    channels = [math.floor((f * alpha + b * (1 - alpha)) * 255 + 0.5)
                for f, b in zip(front, back)]
    return "#" + "".join(f"{c:02X}" for c in channels)


def _samples(samples):
    if samples is None:
        return ()
    if not isinstance(samples, (list, tuple)):
        raise ValueError("samples must be a list of #RRGGBB colors or None")
    for color in samples:
        hex_to_srgb(color)
    return tuple(samples)


def _worst_ratio(text, surface, samples, alpha):
    return min(contrast_ratio(text, composite_rgb(surface, sample, alpha))
               for sample in samples or (surface,))


def choose_surface_alpha(
    text: str,
    surface: str,
    wallpaper_samples: list[str],
    candidates: tuple[float, ...] = _ALPHAS,
    min_ratio: float = 4.5,
) -> float:
    """Smallest candidate passing every sample at min_ratio + 0.3, else 1.0.

    No samples also returns 1.0. Opaque is a fallback, NOT a passing assertion;
    use derive_tokens' contrast diagnostics to detect an unsatisfied palette.
    """
    hex_to_srgb(text)
    hex_to_srgb(surface)
    samples = _samples(wallpaper_samples)
    minimum = _number(min_ratio, 1, 21, "min_ratio") + _MARGIN
    if not isinstance(candidates, (list, tuple)) or not candidates:
        raise ValueError("candidates must be a nonempty sequence of opacities")
    candidates = sorted({_number(a, 0, 1, "candidate") for a in candidates})
    if samples:
        for alpha in candidates:
            if _worst_ratio(text, surface, samples, alpha) >= minimum:
                return alpha
    return 1.0


def _check_envelope(palette, mode):
    if not isinstance(palette, dict):
        raise ValueError("palette must be a dictionary")
    if "schema_version" in palette:
        version = palette["schema_version"]
        if type(version) is not int or version != 1:
            raise ValueError("unsupported palette schema_version")
    if "mode" in palette and palette["mode"] != mode:
        raise ValueError("palette mode mismatch")


def _normalize_palette(palette, mode):
    _check_envelope(palette, mode)
    role_keys = set(_NATIVE_ROLES) | set(_NATIVE_ROLES.values())
    if "dark" in palette or "light" in palette:
        if role_keys.intersection(palette):
            raise ValueError("ambiguous flat and mode-wrapped palette")
        if mode not in palette:
            raise ValueError("requested palette mode is missing")
        selected = palette[mode]
        _check_envelope(selected, mode)
    else:
        if palette.get("mode") != mode:
            raise ValueError("flat palette must declare its mode")
        selected = palette
    custom = set(_NATIVE_ROLES).intersection(selected)
    native = set(_NATIVE_ROLES.values()).intersection(selected)
    if custom and native:
        raise ValueError("ambiguous mixed custom and native palette roles")
    roles = {}
    for custom_role, native_role in _NATIVE_ROLES.items():
        key = custom_role if custom else native_role
        if custom_role == "mHover" and key not in selected:
            continue
        if key not in selected:
            raise ValueError(f"missing palette role: {key}")
        hex_to_srgb(selected[key])
        roles[custom_role] = selected[key].upper()
    return roles


def _sha256(value, name):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{64}", value) is None:
        raise ValueError(f"{name} must be a full 64-hex SHA-256")
    return value.lower()


def _contrast_check(ratio, minimum):
    return {"ratio": ratio, "minimum": minimum, "satisfied": ratio >= minimum}


def derive_tokens(
    matugen_palette: dict,
    wallpaper_sha: str,
    palette_sha: str,
    mode: str,
    samples: list[str] = None,
) -> dict:
    """Return schema v1 tokens and explicit effective-contrast diagnostics.

    Accept mode-wrapped custom/native roles, or flat roles tagged with mode.
    Hashes identify caller-validated bytes; this pure function cannot verify
    their provenance. Samples are caller-supplied regional colors, never decoded
    here. Missing samples forces every material solid. No colors are repaired.
    """
    if mode not in ("dark", "light"):
        raise ValueError("mode must be dark or light")
    wallpaper_sha = _sha256(wallpaper_sha, "wallpaper_sha")
    palette_sha = _sha256(palette_sha, "palette_sha")
    roles = _normalize_palette(matugen_palette, mode)
    samples = _samples(samples)
    colors = {
        "background": roles["mSurface"],
        "surface_low": roles["mSurfaceVariant"],
        "surface": roles["mSurfaceVariant"],
        "surface_high": roles.get("mHover", roles["mSurfaceVariant"]),
        "text_primary": roles["mOnSurface"],
        "text_secondary": roles["mOnSurfaceVariant"],
        "accent": roles["mPrimary"],
        "on_accent": roles["mOnPrimary"],
        "outline": roles["mOutline"],
        "focus_ring": roles["mPrimary"],
        "danger": roles["mError"],
    }
    checks = {"on_accent": _contrast_check(
        contrast_ratio(colors["on_accent"], colors["accent"]), 4.5 + _MARGIN)}
    materials = {}
    for material, surface_role in (("bar", "surface_low"), ("panel", "surface"),
                                   ("notification", "surface_high")):
        surface = colors[surface_role]
        alpha = 1.0
        if samples and checks["on_accent"]["satisfied"]:
            for candidate in _ALPHAS:
                if all(_worst_ratio(colors[role], surface, samples, candidate) >= minimum
                       for role, minimum in _MINIMUMS.items()):
                    alpha = candidate
                    break
        materials[material] = {"opacity": alpha, "style": "solid" if alpha == 1 else "balanced"}
        for role, minimum in _MINIMUMS.items():
            checks[f"{material}.{role}"] = _contrast_check(
                _worst_ratio(colors[role], surface, samples, alpha), minimum)
    unsatisfied = sorted(role for role, check in checks.items() if not check["satisfied"])
    return {
        "schema_version": 1,
        "source_palette_sha256": palette_sha,
        "wallpaper_sha256": wallpaper_sha,
        "mode": mode,
        "colors": colors,
        "materials": materials,
        "motion": {"hover_ms": 120, "popup_ms": 190, "overlay_ms": 240},
        "quality": "balanced",
        "contrast": {
            "basis": "samples" if samples else "opaque",
            "sample_count": len(samples),
            "safety_margin": _MARGIN,
            "renderer_model": "srgb_channel_blend",
            "renderer_verified": False,
            "satisfied": not unsatisfied,
            "unsatisfied_roles": unsatisfied,
            "checks": checks,
        },
    }
