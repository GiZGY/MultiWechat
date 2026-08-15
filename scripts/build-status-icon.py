#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "WxMultiStatusTemplate.png"
PREVIEW = ROOT / "assets" / "WxMultiStatusTemplate-preview.png"


def scaled_box(box: tuple[float, float, float, float], scale: int) -> tuple[int, int, int, int]:
    return tuple(round(value * scale) for value in box)


def scaled_points(points: list[tuple[float, float]], scale: int) -> list[tuple[int, int]]:
    return [(round(x * scale), round(y * scale)) for x, y in points]


def draw_circle(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], scale: int, fill: int) -> None:
    draw.ellipse(scaled_box(box, scale), fill=fill)


def draw_bubble(
    draw: ImageDraw.ImageDraw,
    body: tuple[float, float, float, float],
    tail: list[tuple[float, float]],
    scale: int,
    fill: int,
) -> None:
    draw.ellipse(scaled_box(body, scale), fill=fill)
    draw.polygon(scaled_points(tail, scale), fill=fill)


def draw_template_icon(size: int = 44, scale: int = 8) -> Image.Image:
    canvas = size * scale
    mask = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(mask)

    draw_bubble(
        draw,
        body=(13.4, 6.2, 38.8, 26.5),
        tail=[(32.5, 22.9), (38.6, 26.4), (31.7, 27.0)],
        scale=scale,
        fill=255,
    )

    for box in [
        (23.2, 15.0, 25.9, 17.7),
        (31.1, 15.0, 33.8, 17.7),
    ]:
        draw_circle(draw, box, scale, 0)

    draw_bubble(
        draw,
        body=(2.2, 11.9, 34.3, 37.2),
        tail=[(10.8, 30.5), (4.6, 38.2), (18.6, 34.8)],
        scale=scale,
        fill=0,
    )

    draw_bubble(
        draw,
        body=(4.0, 13.2, 32.6, 35.5),
        tail=[(11.7, 31.3), (6.4, 37.6), (17.3, 33.9)],
        scale=scale,
        fill=255,
    )

    for box in [
        (13.0, 22.8, 16.4, 26.2),
        (23.0, 22.8, 26.4, 26.2),
    ]:
        draw_circle(draw, box, scale, 0)

    draw_circle(draw, (25.1, 24.3, 43.3, 42.5), scale, 0)
    draw_circle(draw, (27.0, 26.2, 41.4, 40.6), scale, 255)
    draw.rounded_rectangle(scaled_box((33.2, 29.2, 35.2, 37.6), scale), radius=round(1.0 * scale), fill=0)
    draw.rounded_rectangle(scaled_box((30.0, 32.4, 38.4, 34.4), scale), radius=round(1.0 * scale), fill=0)

    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    icon.putalpha(mask)
    return icon


def checkerboard(size: tuple[int, int], cell: int) -> Image.Image:
    image = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            color = (226, 226, 226, 255) if (x // cell + y // cell) % 2 == 0 else (246, 246, 246, 255)
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=color)
    return image


def render_on_bar(icon: Image.Image, background: tuple[int, int, int, int], tint: tuple[int, int, int, int]) -> Image.Image:
    bar = Image.new("RGBA", (360, 76), background)
    slot = Image.new("RGBA", icon.size, tint)
    slot.putalpha(icon.getchannel("A"))
    rendered = slot.resize((36, 36), Image.Resampling.LANCZOS)
    bar.alpha_composite(rendered, ((bar.width - rendered.width) // 2, 20))
    return bar


def write_preview(icon: Image.Image) -> None:
    sheet = Image.new("RGBA", (760, 360), (244, 244, 244, 255))
    large_panel = checkerboard((260, 260), 13)
    large_panel.alpha_composite(icon.resize((220, 220), Image.Resampling.NEAREST), (20, 20))
    sheet.alpha_composite(large_panel, (28, 50))

    light = render_on_bar(icon, (246, 246, 246, 255), (28, 28, 28, 255))
    dark = render_on_bar(icon, (36, 36, 38, 255), (246, 246, 246, 255))
    sheet.alpha_composite(light, (340, 78))
    sheet.alpha_composite(dark, (340, 192))
    sheet.save(PREVIEW)


def main() -> None:
    icon = draw_template_icon()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT)
    write_preview(icon)
    print(OUTPUT)
    print(PREVIEW)


if __name__ == "__main__":
    main()
