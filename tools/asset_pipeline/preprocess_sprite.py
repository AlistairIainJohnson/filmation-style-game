#!/usr/bin/env python3
"""Stage A: Conditions retro 2D sprites into centered, high-resolution, evenly lit PNGs
with extracted palette metadata ready for local or cloud 3D model generation."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from PIL import Image


def extract_palette(img: Image.Image, top_k: int = 4) -> list[list[float]]:
    rgba = img.convert("RGBA")
    counts: Counter[tuple[int, int, int]] = Counter()
    for r, g, b, a in rgba.getdata():
        if a >= 128:
            # Quantize to 16-step buckets so subtle noise groups cleanly
            counts[((r // 16) * 16 + 8, (g // 16) * 16 + 8, (b // 16) * 16 + 8)] += 1
    if not counts:
        return [[0.5, 0.5, 0.5]]
    out: list[list[float]] = []
    for (r, g, b), _cnt in counts.most_common(top_k):
        out.append([round(min(255, r) / 255.0, 4), round(min(255, g) / 255.0, 4), round(min(255, b) / 255.0, 4)])
    return out


def preprocess_sprite(
    inp_path: Path,
    out_path: Path,
    target_size: int = 1024,
    padding: float = 0.15,
    bg_mode: str = "transparent",
) -> dict:
    src = Image.open(inp_path).convert("RGBA")
    bbox = src.getbbox()
    if bbox is None:
        raise ValueError(f"Sprite {inp_path} is completely transparent.")

    cropped = src.crop(bbox)
    cw, ch = cropped.size
    inner_max = max(1, int(round(target_size * (1.0 - 2.0 * padding))))
    scale = min(inner_max / float(cw), inner_max / float(ch))
    new_w = max(1, int(round(cw * scale)))
    new_h = max(1, int(round(ch * scale)))

    # Smooth bilinear upscale eliminates harsh retro pixel staircase edges before 3D sculpting
    resized = cropped.resize((new_w, new_h), Image.Resampling.BILINEAR)

    bg_color = (128, 128, 128, 255) if bg_mode == "neutral" else (0, 0, 0, 0)
    canvas = Image.new("RGBA", (target_size, target_size), bg_color)
    offset_x = (target_size - new_w) // 2
    offset_y = (target_size - new_h) // 2
    canvas.paste(resized, (offset_x, offset_y), resized)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, format="PNG")

    palette = extract_palette(cropped)
    meta = {
        "source": str(inp_path),
        "conditioned": str(out_path),
        "source_size": [src.width, src.height],
        "cropped_size": [cw, ch],
        "output_size": [target_size, target_size],
        "dominant_palette_rgb": palette,
    }
    meta_path = out_path.with_suffix(".meta.json")
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return meta


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Condition a 2D sprite PNG for 3D generation")
    parser.add_argument("--in", dest="inp", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--padding", type=float, default=0.15)
    parser.add_argument("--bg-mode", choices=["transparent", "neutral"], default="transparent")
    args = parser.parse_args(argv)

    meta = preprocess_sprite(Path(args.inp), Path(args.out), args.size, args.padding, args.bg_mode)
    print(f"Preprocessed {args.inp} -> {args.out} ({meta['output_size'][0]}x{meta['output_size'][1]}, palette={len(meta['dominant_palette_rgb'])} colors)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
