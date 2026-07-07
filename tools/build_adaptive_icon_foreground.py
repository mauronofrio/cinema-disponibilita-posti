"""Rebuilds a transparent, foreground-only PNG from assets/cinema_icon.svg
(the clapperboard icon the user supplied, already used for the flat/legacy
launcher icon), for Android's adaptive icon foreground layer.

The SVG bakes its dark background and rounded-square clip directly into the
art, which is exactly right for a flat icon but wrong for an adaptive one -
the OS supplies its own background/mask and expects just the glyph, scaled
down within a centered ~66% "safe zone" so it isn't clipped by the mask on
launchers that use a circle/squircle/whatever shape.

No SVG rendering library was available in this environment (cairosvg needs
a native libcairo the machine doesn't have), so this replicates the SVG's
own flat shapes directly with PIL - it only uses rects, one rotated+skewed
group, a circle and a triangle, so a 1:1 manual port is straightforward and
exact, not an approximation.

Not part of the app; a one-off to regenerate assets/icon/icon_foreground.png
from the supplied SVG. Re-run if assets/cinema_icon.svg changes.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

GOLD = (0xD4, 0xA0, 0x17, 255)
DARK = (0x14, 0x14, 0x14, 255)

# The SVG's own viewBox content box (x, y, w, h) - shapes below are given in
# these same coordinates, straight out of the SVG source.
VIEWBOX = (140, 40, 400, 400)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "assets" / "icon" / "icon_foreground.png"

SIZE = 1024
# How much of the final canvas the SVG's own 400x400 content box occupies.
# Android's guaranteed-visible-on-every-mask-shape "safe zone" is only
# ~61%, but at that size the icon reads as small with a lot of bare
# background around it once actually on a launcher - bigger looks better
# in practice, at the cost of the very corners of the clapperboard
# potentially being cropped by the most aggressive (circular) masks.
CONTENT_SCALE = 0.78


def rotate(px: float, py: float, cx: float, cy: float, degrees: float) -> tuple[float, float]:
    rad = math.radians(degrees)
    dx, dy = px - cx, py - cy
    return (
        cx + dx * math.cos(rad) - dy * math.sin(rad),
        cy + dx * math.sin(rad) + dy * math.cos(rad),
    )


def skew_x(px: float, py: float, degrees: float) -> tuple[float, float]:
    return (px + py * math.tan(math.radians(degrees)), py)


def rect_corners(x: float, y: float, w: float, h: float) -> list[tuple[float, float]]:
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def build_foreground() -> Image.Image:
    vb_x, vb_y, vb_w, vb_h = VIEWBOX
    content_size = SIZE * CONTENT_SCALE
    scale = content_size / vb_w  # SVG content box is square (400x400)
    offset = (SIZE - content_size) / 2

    def to_canvas(svg_x: float, svg_y: float) -> tuple[float, float]:
        return (
            offset + (svg_x - vb_x) * scale,
            offset + (svg_y - vb_y) * scale,
        )

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas, "RGBA")

    def poly(points_svg: list[tuple[float, float]], fill) -> None:
        draw.polygon([to_canvas(x, y) for x, y in points_svg], fill=fill)

    def rounded_rect(x, y, w, h, radius, fill) -> None:
        (x0, y0) = to_canvas(x, y)
        (x1, y1) = to_canvas(x + w, y + h)
        draw.rounded_rectangle((x0, y0, x1, y1), radius=radius * scale, fill=fill)

    # Film perforations, left and right columns.
    for base_x in (156, 514):
        for i in range(15):
            y = 56 + i * 26
            rounded_rect(base_x, y, 10, 14, 2.5, (0x2A, 0x2A, 0x2A, 255))

    # Clapperboard, translated to (340, 215) in the SVG.
    tx, ty = 340, 215

    # Back/body rect (gold) and inner dark screen.
    rounded_rect(tx - 95, ty + 0, 190, 110, 5, GOLD)
    rounded_rect(tx - 84, ty + 10, 168, 90, 3, DARK)

    # Rotated top clapper bar + stripes: rotate(-14) about (tx - 95, ty) in
    # the SVG (i.e. about (-95, 0) in the clapperboard's local frame).
    pivot = (tx - 95, ty + 0)

    def clapper_point(local_x: float, local_y: float) -> tuple[float, float]:
        return rotate(tx + local_x, ty + local_y, pivot[0], pivot[1], -14)

    bar_corners_local = rect_corners(-95, -30, 190, 30)
    poly([clapper_point(*p) for p in bar_corners_local], GOLD)

    for stripe_x in (-76, -42, -8, 26, 60):
        local_corners = rect_corners(stripe_x, -27, 17, 24)
        skewed = [skew_x(px, py, -8) for px, py in local_corners]
        poly([clapper_point(*p) for p in skewed], DARK)

    # Faint "text line" rects on the board face.
    for y, w, alpha in (
        (22, 85, 0.35),
        (34, 58, 0.25),
        (46, 74, 0.35),
        (58, 48, 0.25),
    ):
        rounded_rect(tx - 72, ty + y, w, 2.5, 1.2, GOLD[:3] + (int(255 * alpha),))

    # Play button: circle outline + triangle.
    ccx, ccy = to_canvas(tx + 46, ty + 54)
    r = 22 * scale
    draw.ellipse((ccx - r, ccy - r, ccx + r, ccy + r), outline=GOLD, width=max(2, round(2 * scale)))
    poly([(tx + 39, ty + 41), (tx + 39, ty + 67), (tx + 59, ty + 54)], GOLD)

    return canvas


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    build_foreground().save(OUT_PATH)
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
