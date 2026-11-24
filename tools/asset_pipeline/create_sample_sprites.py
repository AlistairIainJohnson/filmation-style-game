#!/usr/bin/env python3
"""Generates 6 crisp retro pixel-art source sprites (RGBA PNGs) for Stage 6 pipeline demos."""

from __future__ import annotations

from pathlib import Path
from PIL import Image


def _make_canvas(w: int, h: int, rows: list[str], palette: dict[str, tuple[int, int, int, int]]) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row[:w]):
            if ch in palette:
                img.putpixel((x, y), palette[ch])
    return img


def _fill_rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, rgba: tuple[int, int, int, int]) -> None:
    for y in range(max(0, y0), min(img.height, y1 + 1)):
        for x in range(max(0, x0), min(img.width, x1 + 1)):
            img.putpixel((x, y), rgba)


def create_all_sprites(out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    # 1. Hero Knight (32x32)
    knight = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    steel = (145, 165, 195, 255)
    cobalt = (52, 96, 175, 255)
    gold = (232, 188, 66, 255)
    leather = (110, 68, 38, 255)
    _fill_rect(knight, 11, 2, 20, 9, steel)      # Helm
    _fill_rect(knight, 12, 5, 19, 6, gold)       # Gold visor
    _fill_rect(knight, 14, 1, 17, 2, gold)       # Crest
    _fill_rect(knight, 9, 10, 22, 19, cobalt)    # Tunic / chestplate
    _fill_rect(knight, 6, 10, 9, 18, steel)      # Left arm
    _fill_rect(knight, 22, 10, 25, 18, steel)    # Right arm
    _fill_rect(knight, 10, 17, 21, 18, gold)     # Belt
    _fill_rect(knight, 10, 20, 14, 29, steel)    # Left leg
    _fill_rect(knight, 17, 20, 21, 29, steel)    # Right leg
    _fill_rect(knight, 9, 28, 14, 30, leather)   # Left boot
    _fill_rect(knight, 17, 28, 22, 30, leather)  # Right boot
    p = out_dir / "hero_knight.png"
    knight.save(p)
    written.append(p)

    # 2. Patrol Sentinel (32x32)
    sentinel = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    iron = (62, 66, 76, 255)
    crimson = (178, 42, 46, 255)
    ember = (255, 84, 52, 255)
    _fill_rect(sentinel, 11, 2, 20, 9, iron)     # Helm
    _fill_rect(sentinel, 12, 5, 19, 6, ember)    # Glowing eye slit
    _fill_rect(sentinel, 10, 1, 12, 4, crimson)  # Left horn
    _fill_rect(sentinel, 19, 1, 21, 4, crimson)  # Right horn
    _fill_rect(sentinel, 8, 10, 23, 20, crimson) # Cuirass
    _fill_rect(sentinel, 5, 10, 8, 19, iron)     # Left pauldron/arm
    _fill_rect(sentinel, 23, 10, 26, 19, iron)   # Right pauldron/arm
    _fill_rect(sentinel, 10, 21, 14, 30, iron)   # Left leg
    _fill_rect(sentinel, 17, 21, 21, 30, iron)   # Right leg
    p = out_dir / "patrol_sentinel.png"
    sentinel.save(p)
    written.append(p)

    # 3. Pushable Chest (32x32)
    chest = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    oak = (142, 86, 44, 255)
    oak_dark = (104, 60, 28, 255)
    band = (58, 62, 70, 255)
    brass = (218, 170, 62, 255)
    _fill_rect(chest, 3, 6, 28, 28, oak)
    _fill_rect(chest, 3, 6, 28, 12, oak_dark)
    _fill_rect(chest, 6, 6, 8, 28, band)
    _fill_rect(chest, 23, 6, 25, 28, band)
    _fill_rect(chest, 3, 13, 28, 14, band)
    _fill_rect(chest, 14, 12, 17, 17, brass)
    p = out_dir / "pushable_chest.png"
    chest.save(p)
    written.append(p)

    # 4. Cauldron (32x32)
    cauldron = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    cast_iron = (44, 48, 54, 255)
    rim = (76, 82, 92, 255)
    brew = (52, 235, 136, 255)
    _fill_rect(cauldron, 6, 10, 25, 25, cast_iron)
    _fill_rect(cauldron, 4, 13, 27, 22, cast_iron)
    _fill_rect(cauldron, 5, 8, 26, 10, rim)
    _fill_rect(cauldron, 7, 6, 24, 8, brew)
    _fill_rect(cauldron, 7, 25, 10, 29, cast_iron)
    _fill_rect(cauldron, 21, 25, 24, 29, cast_iron)
    p = out_dir / "cauldron.png"
    cauldron.save(p)
    written.append(p)

    # 5. Collectible Key (24x24)
    key = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    gold_hi = (248, 206, 68, 255)
    gold_lo = (188, 138, 32, 255)
    _fill_rect(key, 6, 2, 17, 9, gold_hi)
    _fill_rect(key, 9, 4, 14, 7, (0, 0, 0, 0))  # Key ring hole
    _fill_rect(key, 10, 9, 13, 21, gold_lo)
    _fill_rect(key, 13, 15, 18, 17, gold_hi)
    _fill_rect(key, 13, 19, 17, 21, gold_hi)
    p = out_dir / "collectible_key.png"
    key.save(p)
    written.append(p)

    # 6. Stone Pillar (32x32)
    pillar = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    stone_hi = (146, 142, 136, 255)
    stone_mid = (118, 114, 110, 255)
    stone_lo = (88, 86, 84, 255)
    _fill_rect(pillar, 6, 27, 25, 30, stone_lo)    # Plinth
    _fill_rect(pillar, 9, 5, 22, 26, stone_mid)    # Shaft
    _fill_rect(pillar, 12, 6, 14, 25, stone_hi)    # Fluting highlight
    _fill_rect(pillar, 17, 6, 19, 25, stone_hi)
    _fill_rect(pillar, 6, 2, 25, 5, stone_hi)      # Capital
    p = out_dir / "stone_pillar.png"
    pillar.save(p)
    written.append(p)

    return written


def main() -> int:
    root = Path(__file__).resolve().parent.parent.parent
    written = create_all_sprites(root / "assets" / "source_sprites")
    print(f"Generated {len(written)} retro sample sprites in assets/source_sprites/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
