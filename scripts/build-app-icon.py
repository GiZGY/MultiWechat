#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "WxMultiIcon-source.png"

ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def remove_edge_background(source: Image.Image, threshold: int = 248) -> Image.Image:
    image = source.convert("RGBA")
    rgb = image.convert("RGB")
    width, height = image.size
    pixels = rgb.load()
    background = Image.new("L", image.size, 0)
    background_pixels = background.load()
    queue = deque()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= width or y >= height or background_pixels[x, y]:
            continue
        red, green, blue = pixels[x, y]
        if min(red, green, blue) < threshold:
            continue
        background_pixels[x, y] = 255
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    alpha = image.getchannel("A")
    alpha_pixels = alpha.load()
    for y in range(height):
        for x in range(width):
            if background_pixels[x, y]:
                alpha_pixels[x, y] = 0
    image.putalpha(alpha)
    return image


def crop_to_square_bounds(image: Image.Image) -> Image.Image:
    bbox = image.getbbox()
    if bbox is None:
        raise ValueError("source icon became empty after background removal")

    left, top, right, bottom = bbox
    width = right - left
    height = bottom - top
    edge = max(width, height)
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2

    square_left = round(center_x - edge / 2)
    square_top = round(center_y - edge / 2)
    square_right = square_left + edge
    square_bottom = square_top + edge

    output = Image.new("RGBA", (edge, edge), (0, 0, 0, 0))
    crop_left = max(0, square_left)
    crop_top = max(0, square_top)
    crop_right = min(image.width, square_right)
    crop_bottom = min(image.height, square_bottom)
    cropped = image.crop((crop_left, crop_top, crop_right, crop_bottom))
    output.alpha_composite(cropped, (crop_left - square_left, crop_top - square_top))
    return output


def build_source_icon(source_path: Path, bleed: float) -> Image.Image:
    source = Image.open(source_path)
    trimmed = crop_to_square_bounds(remove_edge_background(source))
    scaled_size = round(1024 * bleed)
    scaled = trimmed.resize((scaled_size, scaled_size), Image.Resampling.LANCZOS)
    if bleed <= 1:
        icon = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        icon.alpha_composite(scaled, ((1024 - scaled_size) // 2, (1024 - scaled_size) // 2))
        return icon

    left = (scaled_size - 1024) // 2
    top = (scaled_size - 1024) // 2
    return scaled.crop((left, top, left + 1024, top + 1024))


def write_iconset(icon: Image.Image, output_dir: Path, name: str, keep_iconset: bool) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    png_path = output_dir / f"{name}-1024.png"
    icns_path = output_dir / f"{name}.icns"
    iconset_path = output_dir / f"{name}.iconset"

    icon.save(png_path)
    if iconset_path.exists():
        shutil.rmtree(iconset_path)
    iconset_path.mkdir(parents=True)

    for filename, size in ICON_SIZES.items():
        icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset_path / filename)

    subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(iconset_path), "-o", str(icns_path)], check=True)
    if not keep_iconset:
        shutil.rmtree(iconset_path)
    return png_path, icns_path


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, height, cell):
        for x in range(0, width, cell):
            color = (226, 226, 226, 255) if (x // cell + y // cell) % 2 == 0 else (247, 247, 247, 255)
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=color)
    return image


def write_preview(icon: Image.Image, output_dir: Path, name: str) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    preview_path = output_dir / f"{name}-preview.png"
    sheet = Image.new("RGBA", (980, 430), (242, 242, 242, 255))

    large_panel = checkerboard((360, 360), cell=18)
    large = icon.resize((320, 320), Image.Resampling.LANCZOS)
    large_panel.alpha_composite(large, (20, 20))
    sheet.alpha_composite(large_panel, (24, 34))

    small_panel = Image.new("RGBA", (552, 360), (255, 255, 255, 255))
    x = 26
    y = 34
    for size in [16, 32, 64, 128, 256]:
        rendered = icon.resize((size, size), Image.Resampling.LANCZOS)
        shadow_alpha = rendered.getchannel("A").filter(ImageFilter.GaussianBlur(max(1, size // 36)))
        shadow = Image.new("RGBA", rendered.size, (0, 0, 0, 65))
        shadow.putalpha(shadow_alpha)
        top = y + (256 - size)
        small_panel.alpha_composite(shadow, (x, top + max(1, size // 24)))
        small_panel.alpha_composite(rendered, (x, top))
        x += size + 24
    sheet.alpha_composite(small_panel, (404, 34))
    sheet.save(preview_path)
    return preview_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the MultiWechat macOS app icon.")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "assets")
    parser.add_argument("--name", default="WxMultiIcon")
    parser.add_argument("--bleed", type=float, default=1.0)
    parser.add_argument("--keep-iconset", action="store_true")
    parser.add_argument("--preview", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.source.exists():
        raise SystemExit(f"missing source icon: {args.source}")

    icon = build_source_icon(args.source, bleed=args.bleed)
    png_path, icns_path = write_iconset(icon, args.output_dir, args.name, args.keep_iconset)
    print(png_path)
    print(icns_path)
    if args.preview:
        print(write_preview(icon, args.output_dir, args.name))


if __name__ == "__main__":
    main()
