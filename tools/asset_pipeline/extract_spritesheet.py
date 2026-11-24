#!/usr/bin/env python3
"""Extracts the ZX Spectrum Knight Lore Explorer (Sabreman) and Werewolf sprites
from concept-art/knight-lore-sprites.jpg using the top ink pass + middle 1-bit
mask pass, composites full-body frames, measures chibi silhouette proportions,
and outputs colorized reference sprites aligned to concept-art/inspiration.png."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

MASK_Y_OFFSET = 480

BANDS = {
    "explorer_legs": (62, 84),
    "explorer_body": (94, 123),
    "werewolf_legs": (124, 155),
    "werewolf_body": (156, 189),
}

INSPIRATION_PALETTES = {
    "explorer": {
        "helmet": [0.784, 0.663, 0.431],      # Warm khaki pith helmet (#C8A96E)
        "hatband": [0.278, 0.180, 0.106],     # Dark leather band (#472E1B)
        "tunic": [0.788, 0.643, 0.361],       # Safari tunic (#C9A45C)
        "skin": [0.839, 0.624, 0.494],        # Warm skin (#D69F7E)
        "boots": [0.278, 0.180, 0.106],       # Brown boots & belt (#472E1B)
        "brass": [0.851, 0.659, 0.259],       # Brass belt buckle (#D9A842)
    },
    "werewolf": {
        "fur": [0.294, 0.208, 0.153],         # Dark wolf fur (#4B3527)
        "ruff": [0.431, 0.325, 0.251],        # Lighter chest ruff (#6E5340)
        "tattered_tunic": [0.722, 0.588, 0.333],  # Tattered safari shorts (#B89655)
        "amber_eye": [0.961, 0.706, 0.153],   # Glowing amber eyes (#F5B427)
        "claws": [0.140, 0.115, 0.105],       # Dark snout & claws (#241D1B)
    },
}


def detect_cells_in_band(arr: np.ndarray, y_top: int, y_bot: int) -> list[tuple[int, int, int, int]]:
    band = arr[y_top : y_bot + 1]
    is_content = (band.max(axis=2) < 55) | (band.min(axis=2) > 195)
    col_has_content = is_content.mean(axis=0) > 0.35
    cells: list[tuple[int, int, int, int]] = []
    in_c = False
    start = 0
    for x, has in enumerate(col_has_content):
        if has and not in_c:
            start = x
            in_c = True
        elif not has and in_c:
            if x - start >= 10:
                sub = is_content[:, start:x]
                ys = np.where(sub.mean(axis=1) > 0.5)[0]
                if len(ys):
                    cells.append((start, y_top + int(ys[0]), x, y_top + int(ys[-1]) + 1))
            in_c = False
    if in_c and len(col_has_content) - start >= 10:
        sub = is_content[:, start:]
        ys = np.where(sub.mean(axis=1) > 0.5)[0]
        if len(ys):
            cells.append((start, y_top + int(ys[0]), len(col_has_content), y_top + int(ys[-1]) + 1))
    return cells


def detect_all_boxes_by_row(arr: np.ndarray, top_limit: int = 470) -> list[list[tuple[int, int, int, int]]]:
    """Connected-component detector across the entire top ink pass (12 rows, ~187 sprites)."""
    top = arr[:top_limit]
    is_content = (top.max(axis=2) < 55) | (top.min(axis=2) > 195)
    h, w = is_content.shape
    visited = np.zeros((h, w), dtype=bool)
    boxes: list[tuple[int, int, int, int]] = []

    for y in range(h):
        for x in range(w):
            if is_content[y, x] and not visited[y, x]:
                stack = [(y, x)]
                visited[y, x] = True
                min_y = max_y = y
                min_x = max_x = x
                area = 0
                while stack:
                    cy, cx = stack.pop()
                    area += 1
                    if cy < min_y:
                        min_y = cy
                    if cy > max_y:
                        max_y = cy
                    if cx < min_x:
                        min_x = cx
                    if cx > max_x:
                        max_x = cx
                    for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                        if 0 <= ny < h and 0 <= nx < w and is_content[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            stack.append((ny, nx))
                bw = max_x - min_x + 1
                bh = max_y - min_y + 1
                if bw >= 6 and bh >= 6 and area >= 30:
                    boxes.append((min_x, min_y, max_x + 1, max_y + 1))

    boxes.sort(key=lambda b: (b[1], b[0]))
    rows: list[list[tuple[int, int, int, int]]] = []
    for b in boxes:
        placed = False
        for r in rows:
            r_y0 = min(item[1] for item in r)
            r_y1 = max(item[3] for item in r)
            overlap = min(r_y1, b[3]) - max(r_y0, b[1])
            min_h = min(r_y1 - r_y0, b[3] - b[1])
            if overlap > 0.3 * min_h or abs(b[1] - r_y0) <= 8:
                r.append(b)
                placed = True
                break
        if not placed:
            rows.append([b])

    for r in rows:
        r.sort(key=lambda b: b[0])
    return rows


def extract_clean_rgba_cell(arr: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    x0, y0, x1, y1 = box
    ink = arr[y0:y1, x0:x1].mean(axis=2)
    mask = arr[y0 + MASK_Y_OFFSET : y1 + MASK_Y_OFFSET, x0:x1].mean(axis=2)

    h, w = ink.shape
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    mask_on = mask > 128.0
    ink_on = ink > 128.0

    # White body pixels inside mask
    white_px = mask_on & ink_on
    rgba[white_px] = [245, 245, 245, 255]
    # Crisp 1-bit detail lines (outline / facial features inside mask)
    black_px = mask_on & (~ink_on)
    rgba[black_px] = [20, 20, 20, 255]
    return Image.fromarray(rgba, mode="RGBA")


def composite_body_and_legs(body: Image.Image, legs: Image.Image, overlap_px: int = 4) -> Image.Image:
    cw = max(body.width, legs.width)
    ch = max(1, body.height + legs.height - overlap_px)
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    lx = (cw - legs.width) // 2
    ly = body.height - overlap_px
    bx = (cw - body.width) // 2
    canvas.paste(legs, (lx, ly), legs)
    canvas.paste(body, (bx, 0), body)
    bbox = canvas.getbbox()
    return canvas.crop(bbox) if bbox else canvas


def colorize_composite(composite: Image.Image, role: str) -> Image.Image:
    """Applies semantic colors matched to concept-art/inspiration.png onto a monochrome
    extracted full-body composite so preprocess_sprite extracts accurate PBR palettes."""
    arr = np.array(composite.convert("RGBA"))
    alpha = arr[:, :, 3] > 128
    is_fill = alpha & (arr[:, :, 0] > 160)
    h, _w = arr.shape[:2]

    if role == "explorer":
        pal = INSPIRATION_PALETTES["explorer"]
        col_helmet = [int(c * 255) for c in pal["helmet"]]
        col_skin = [int(c * 255) for c in pal["skin"]]
        col_tunic = [int(c * 255) for c in pal["tunic"]]
        col_boots = [int(c * 255) for c in pal["boots"]]

        y_grid = np.arange(h)[:, None] / max(1.0, float(h))
        out = arr.copy()
        for mask_cond, rgb in [
            (is_fill & (y_grid < 0.30), col_helmet),
            (is_fill & (y_grid >= 0.30) & (y_grid < 0.45), col_skin),
            (is_fill & (y_grid >= 0.45) & (y_grid < 0.72), col_tunic),
            (is_fill & (y_grid >= 0.72), col_boots),
        ]:
            out[mask_cond, 0] = rgb[0]
            out[mask_cond, 1] = rgb[1]
            out[mask_cond, 2] = rgb[2]
        return Image.fromarray(out, mode="RGBA")

    pal = INSPIRATION_PALETTES["werewolf"]
    col_fur = [int(c * 255) for c in pal["fur"]]
    col_ruff = [int(c * 255) for c in pal["ruff"]]
    col_tunic = [int(c * 255) for c in pal["tattered_tunic"]]
    y_grid = np.arange(h)[:, None] / max(1.0, float(h))
    out = arr.copy()
    for mask_cond, rgb in [
        (is_fill & (y_grid < 0.38), col_fur),
        (is_fill & (y_grid >= 0.38) & (y_grid < 0.65), col_ruff),
        (is_fill & (y_grid >= 0.65) & (y_grid < 0.80), col_tunic),
        (is_fill & (y_grid >= 0.80), col_fur),
    ]:
        out[mask_cond, 0] = rgb[0]
        out[mask_cond, 1] = rgb[1]
        out[mask_cond, 2] = rgb[2]
    return Image.fromarray(out, mode="RGBA")


def measure_character_proportions(body: Image.Image, legs: Image.Image, composite: Image.Image) -> dict:
    total_h = float(max(1, composite.height))
    legs_ratio = round(legs.height / total_h, 4)
    upper_ratio = round(max(0.1, (total_h - legs.height) / total_h), 4)
    return {
        "composite_px": [composite.width, composite.height],
        "legs_cell_px": [legs.width, legs.height],
        "body_cell_px": [body.width, body.height],
        "legs_ratio": legs_ratio,
        "head_and_torso_ratio": upper_ratio,
        "aspect_width_to_height": round(composite.width / total_h, 4),
    }


def extract_knight_lore_characters(
    sheet_path: Path,
    out_dir: Path,
    source_sprites_dir: Path,
) -> dict:
    im = Image.open(sheet_path).convert("RGB")
    arr = np.array(im)

    bands_cells = {name: detect_cells_in_band(arr, yt, yb) for name, (yt, yb) in BANDS.items()}
    for name, cells in bands_cells.items():
        if len(cells) != 16:
            raise RuntimeError(f"Expected 16 cells in band '{name}', found {len(cells)}")

    out_dir.mkdir(parents=True, exist_ok=True)
    source_sprites_dir.mkdir(parents=True, exist_ok=True)

    extracted_frames: list[tuple[str, Image.Image]] = []

    def _build_pair(body_band: str, body_idx0: int, legs_band: str, legs_idx0: int, fname: str) -> Image.Image:
        body_img = extract_clean_rgba_cell(arr, bands_cells[body_band][body_idx0])
        legs_img = extract_clean_rgba_cell(arr, bands_cells[legs_band][legs_idx0])
        comp = composite_body_and_legs(body_img, legs_img)
        comp.save(out_dir / f"{fname}.png", format="PNG")
        extracted_frames.append((fname, comp))
        return comp

    # Explorer NW (cols 1-6 walk, 7-8 look L/R) & SE (cols 9-14 walk, 15-16 look L/R)
    for i in range(6):
        _build_pair("explorer_body", i, "explorer_legs", i, f"explorer_nw_walk_{i + 1:02d}")
    _build_pair("explorer_body", 6, "explorer_legs", 0, "explorer_nw_look_left")
    _build_pair("explorer_body", 7, "explorer_legs", 0, "explorer_nw_look_right")

    se_walk_1 = None
    for i in range(6):
        c = _build_pair("explorer_body", 8 + i, "explorer_legs", 8 + i, f"explorer_se_walk_{i + 1:02d}")
        if i == 0:
            se_walk_1 = c
    _build_pair("explorer_body", 14, "explorer_legs", 8, "explorer_se_look_left")
    _build_pair("explorer_body", 15, "explorer_legs", 8, "explorer_se_look_right")

    # Werewolf NW (cols 1-6) & SE (cols 9-14)
    for i in range(6):
        _build_pair("werewolf_body", i, "werewolf_legs", i, f"werewolf_nw_walk_{i + 1:02d}")
    wolf_se_1 = None
    for i in range(6):
        c = _build_pair("werewolf_body", 8 + i, "werewolf_legs", 8 + i, f"werewolf_se_walk_{i + 1:02d}")
        if i == 0:
            wolf_se_1 = c

    # Save colorized SE reference PNGs consumed by asset_manifest.json
    assert se_walk_1 is not None and wolf_se_1 is not None
    explorer_colored = colorize_composite(se_walk_1, "explorer")
    explorer_colored.save(source_sprites_dir / "hero_explorer.png", format="PNG")
    werewolf_colored = colorize_composite(wolf_se_1, "werewolf")
    werewolf_colored.save(source_sprites_dir / "hero_werewolf.png", format="PNG")

    # Build a crisp 4x upscaled contact sheet for human visual inspection
    scale = 4
    cols = 8
    rows_n = (len(extracted_frames) + cols - 1) // cols
    tile_w, tile_h = 128, 176
    sheet_img = Image.new("RGBA", (cols * tile_w, rows_n * tile_h), (38, 40, 48, 255))
    draw = ImageDraw.Draw(sheet_img)
    for idx, (label, frame) in enumerate(extracted_frames):
        gx, gy = idx % cols, idx // cols
        ox, oy = gx * tile_w, gy * tile_h
        up = frame.resize((frame.width * scale, frame.height * scale), Image.Resampling.NEAREST)
        px = ox + (tile_w - up.width) // 2
        py = oy + (tile_h - 24 - up.height) // 2
        sheet_img.paste(up, (px, py), up)
        short_label = label.replace("explorer_", "exp_").replace("werewolf_", "wolf_")
        draw.text((ox + 6, oy + tile_h - 18), short_label, fill=(220, 224, 232, 255))
    sheet_img.save(out_dir / "knight_lore_character_sheet.png", format="PNG")

    # Measure & store proportions + inspiration palette metadata
    exp_body_0 = extract_clean_rgba_cell(arr, bands_cells["explorer_body"][8])
    exp_legs_0 = extract_clean_rgba_cell(arr, bands_cells["explorer_legs"][8])
    wolf_body_0 = extract_clean_rgba_cell(arr, bands_cells["werewolf_body"][8])
    wolf_legs_0 = extract_clean_rgba_cell(arr, bands_cells["werewolf_legs"][8])

    proportions = {
        "source_sheet": str(sheet_path),
        "explorer": {
            "proportions": measure_character_proportions(exp_body_0, exp_legs_0, se_walk_1),
            "palette": INSPIRATION_PALETTES["explorer"],
        },
        "werewolf": {
            "proportions": measure_character_proportions(wolf_body_0, wolf_legs_0, wolf_se_1),
            "palette": INSPIRATION_PALETTES["werewolf"],
        },
        "extracted_frames_count": len(extracted_frames),
    }
    prop_path = out_dir / "character_proportions.json"
    prop_path.write_text(json.dumps(proportions, indent=2) + "\n", encoding="utf-8")
    return proportions


def extract_all_inspiration_sprites(
    sheet_path: Path,
    all_out_dir: Path,
    sheet_out_path: Path,
    catalog_out_path: Path,
) -> dict:
    """Extracts all 12 rows (~187 sprites) from knight-lore-sprites.jpg as crisp
    transparent RGBA inspiration assets plus a 3x labeled visual contact sheet."""
    im = Image.open(sheet_path).convert("RGB")
    arr = np.array(im)
    rows = detect_all_boxes_by_row(arr)

    all_out_dir.mkdir(parents=True, exist_ok=True)
    sheet_out_path.parent.mkdir(parents=True, exist_ok=True)

    catalog_rows: list[dict] = []
    total_sprites = 0
    max_cols = max((len(r) for r in rows), default=1)
    scale = 3
    cell_w, cell_h = 108, 198
    contact = Image.new("RGBA", (max_cols * cell_w, len(rows) * cell_h), (34, 37, 45, 255))
    draw = ImageDraw.Draw(contact)

    for r_idx, row_boxes in enumerate(rows, 1):
        row_items: list[dict] = []
        for c_idx, box in enumerate(row_boxes, 1):
            rgba = extract_clean_rgba_cell(arr, box)
            fname = f"r{r_idx:02d}_c{c_idx:02d}.png"
            rgba.save(all_out_dir / fname, format="PNG")
            total_sprites += 1
            row_items.append(
                {
                    "file": fname,
                    "row": r_idx,
                    "col": c_idx,
                    "box": list(box),
                    "size_px": [rgba.width, rgba.height],
                }
            )

            up = rgba.resize((rgba.width * scale, rgba.height * scale), Image.Resampling.NEAREST)
            ox = (c_idx - 1) * cell_w
            oy = (r_idx - 1) * cell_h
            if up.width > cell_w - 8 or up.height > cell_h - 24:
                fit = min((cell_w - 8) / float(up.width), (cell_h - 24) / float(up.height))
                up = up.resize((max(1, int(up.width * fit)), max(1, int(up.height * fit))), Image.Resampling.NEAREST)
            px = ox + (cell_w - up.width) // 2
            py = oy + (cell_h - 20 - up.height) // 2
            contact.paste(up, (px, py), up)
            draw.text((ox + 6, oy + cell_h - 16), f"R{r_idx:02d}C{c_idx:02d}", fill=(215, 220, 230, 255))

        catalog_rows.append({"row": r_idx, "count": len(row_items), "sprites": row_items})

    contact.save(sheet_out_path, format="PNG")
    catalog = {
        "source_sheet": str(sheet_path),
        "total_rows": len(rows),
        "total_sprites": total_sprites,
        "rows": catalog_rows,
    }
    catalog_out_path.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    return catalog


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(description="Extract Knight Lore characters and all inspiration sprites from spritesheet")
    parser.add_argument("--sheet", default=str(root / "concept-art" / "knight-lore-sprites.jpg"))
    parser.add_argument("--out-dir", default=str(root / "assets" / "source_sprites" / "extracted"))
    parser.add_argument("--source-sprites-dir", default=str(root / "assets" / "source_sprites"))
    args = parser.parse_args(argv)

    out_dir = Path(args.out_dir).resolve()
    sheet_path = Path(args.sheet).resolve()
    summary = extract_knight_lore_characters(
        sheet_path,
        out_dir,
        Path(args.source_sprites_dir).resolve(),
    )
    catalog = extract_all_inspiration_sprites(
        sheet_path,
        out_dir / "all",
        out_dir / "knight_lore_all_sprites_sheet.png",
        out_dir / "all_sprites_catalog.json",
    )
    print(
        f"Extracted {summary['extracted_frames_count']} character frames and "
        f"{catalog['total_sprites']} all-sheet sprites ({catalog['total_rows']} rows) -> {out_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
