#!/usr/bin/env python3
"""Generate the Optimizr app icon (PNG + ICNS) without external SVG renderers."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "app" / "Resources"
SIZE = 1024


def diagonal_gradient() -> Image.Image:
    start = (0x74, 0x66, 0xF3)
    middle = (0x4F, 0x46, 0xE5)
    end = (0x0E, 0xA5, 0xA4)
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    denominator = 2 * (SIZE - 1)
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / denominator
            if t < 0.55:
                local = t / 0.55
                color = tuple(round(a + (b - a) * local) for a, b in zip(start, middle))
            else:
                local = (t - 0.55) / 0.45
                color = tuple(round(a + (b - a) * local) for a, b in zip(middle, end))
            pixels[x, y] = (*color, 255)
    return image


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([40, 40, SIZE - 40, SIZE - 40], radius=212, fill=255)
    return mask


def bolt_points() -> list[tuple[int, int]]:
    return [
        (576, 204),
        (334, 556),
        (486, 556),
        (448, 820),
        (690, 468),
        (538, 468),
    ]


def build_icon() -> Image.Image:
    base = diagonal_gradient()

    # Soft spotlight in the upper-left.
    glow = Image.new("L", (SIZE, SIZE), 0)
    glow_draw = ImageDraw.Draw(glow)
    for radius in range(760, 0, -8):
        alpha = int(46 * (1 - radius / 760))
        glow_draw.ellipse(
            [330 - radius, 250 - radius, 330 + radius, 250 + radius],
            fill=alpha,
        )
    white = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    base = Image.composite(white, base, glow.point(lambda value: value // 2))

    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse([182, 182, 842, 842], outline=(255, 255, 255, 32), width=16)
    draw.ellipse([266, 266, 758, 758], outline=(255, 255, 255, 22), width=10)

    # Bolt shadow.
    shadow_mask = Image.new("L", (SIZE, SIZE), 0)
    shadow_draw = ImageDraw.Draw(shadow_mask)
    shadow_draw.polygon(bolt_points(), fill=255)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(20))
    shadow = Image.new("RGBA", (SIZE, SIZE), (11, 16, 32, 90))
    shadow.putalpha(shadow_mask.point(lambda value: int(value * 0.55)))
    base.alpha_composite(shadow, (0, 18))

    # Bolt.
    bolt_mask = Image.new("L", (SIZE, SIZE), 0)
    bolt_draw = ImageDraw.Draw(bolt_mask)
    bolt_draw.polygon(bolt_points(), fill=255)
    bolt = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    base.alpha_composite(Image.composite(bolt, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), bolt_mask))

    # Rounded corners.
    mask = rounded_mask()
    result = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(base, (0, 0), mask)
    return result


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    icon = build_icon()
    master = RESOURCES / "AppIcon-1024.png"
    icon.save(master)

    with tempfile.TemporaryDirectory() as temporary:
        iconset = Path(temporary) / "Optimizr.iconset"
        iconset.mkdir()
        variants = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        ]
        for pixels, name in variants:
            icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")],
            check=True,
        )

    print(f"Wrote {RESOURCES / 'AppIcon.icns'} and {master}")


if __name__ == "__main__":
    main()
