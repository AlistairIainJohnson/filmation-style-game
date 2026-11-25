#!/usr/bin/env python3
"""End-to-end orchestrator converting retro 2D sprites declared in asset_manifest.json
into validated, normalized PBR .glb models inside assets/."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

from create_sample_sprites import create_all_sprites
from generate_3d import generate_3d
from preprocess_sprite import preprocess_sprite
from validate_glb import validate_single_glb


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build and normalize manifest assets.")
    parser.add_argument(
        "--only",
        default="",
        help="Comma-separated list of asset IDs to build (default: all).",
    )
    args = parser.parse_args(argv)
    only_ids = {s.strip() for s in args.only.split(",") if s.strip()}

    root = Path(__file__).resolve().parent.parent.parent
    manifest_path = root / "assets" / "asset_manifest.json"
    sprites_dir = root / "assets" / "source_sprites"
    raw_dir = root / "raw_assets"
    raw_dir.mkdir(parents=True, exist_ok=True)

    # Ensure sample retro sprites exist
    if not list(sprites_dir.glob("*.png")):
        create_all_sprites(sprites_dir)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    blender_bin = shutil.which("blender")
    if not blender_bin:
        print("ERROR: Blender CLI not found on PATH.", file=sys.stderr)
        return 1

    norm_script = Path(__file__).resolve().parent / "normalize_glb.py"

    for entry in manifest.get("assets", []):
        aid = entry["id"]
        if only_ids and aid not in only_ids:
            continue
        src_sprite = root / entry["source_sprite"]
        conditioned_png = raw_dir / f"{aid}_conditioned.png"
        raw_glb = raw_dir / f"{aid}_raw.glb"
        out_glb = root / entry["output_glb"]

        print(f"==> Building asset '{aid}' ({entry['mode']})...")
        preprocess_sprite(src_sprite, conditioned_png, target_size=1024, padding=0.15)
        generate_3d(
            conditioned_png,
            raw_glb,
            entry.get("provider", "local_blender_sculpt"),
            entry.get("asset_kind", "sprite_sculpt"),
            float(entry.get("target_height", 1.0)),
        )

        norm_cmd = [
            blender_bin,
            "-b",
            "-P",
            str(norm_script),
            "--",
            "--in",
            str(raw_glb),
            "--out",
            str(out_glb),
            "--mode",
            entry.get("mode", "static"),
            "--target-height",
            str(entry.get("target_height", 1.0)),
            "--max-tris",
            str(entry.get("max_tris", 6000)),
        ]
        if entry.get("add_col_suffix"):
            norm_cmd.append(f"--add-col-suffix={entry['add_col_suffix']}")
        subprocess.run(norm_cmd, check=True)

        errs, stats = validate_single_glb(
            out_glb,
            entry.get("mode", "static"),
            float(entry.get("target_height", 1.0)),
            int(entry.get("max_tris", 6000)),
            int(entry.get("max_size_kb", 4096)),
        )
        if errs:
            for e in errs:
                print(f"ERROR: {e}", file=sys.stderr)
            return 1
        print(f"  Verified {stats}")

    print("All manifest assets built and validated cleanly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
