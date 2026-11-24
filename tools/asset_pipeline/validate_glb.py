#!/usr/bin/env python3
"""Stage C acceptance gate: validates normalized GLB metric scale, bottom-center pivot,
triangle budget, file size, PBR materials, and skeleton presence for rigged characters."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import trimesh
from pygltflib import GLTF2


def validate_single_glb(
    glb_path: Path,
    mode: str,
    target_height: float,
    max_tris: int,
    max_size_kb: int = 4096,
) -> tuple[list[str], dict]:
    errors: list[str] = []
    if not glb_path.exists():
        return [f"Missing GLB file: {glb_path}"], {}

    size_kb = glb_path.stat().st_size / 1024.0
    if size_kb > max_size_kb:
        errors.append(f"{glb_path.name}: size {size_kb:.1f} KB exceeds budget {max_size_kb} KB")

    scene = trimesh.load(str(glb_path), force="scene")
    geoms = list(scene.geometry.values())
    if not geoms:
        return [f"{glb_path.name}: contains no geometry"], {}

    total_tris = sum(len(g.faces) for g in geoms if hasattr(g, "faces"))
    if total_tris <= 0 or total_tris > max_tris:
        errors.append(f"{glb_path.name}: tri_count={total_tris} outside (1..{max_tris})")

    bounds = scene.bounds
    min_pt, max_pt = bounds[0], bounds[1]
    height = float(max_pt[1] - min_pt[1])
    min_y = float(min_pt[1])
    center_x = float((min_pt[0] + max_pt[0]) * 0.5)
    center_z = float((min_pt[2] + max_pt[2]) * 0.5)

    if abs(min_y) > 0.025:
        errors.append(f"{glb_path.name}: bottom Y={min_y:.4f} not grounded at 0.0 (+/-0.025)")
    if abs(height - target_height) > max(0.03, target_height * 0.03):
        errors.append(f"{glb_path.name}: height={height:.4f} differs from target {target_height:.4f}")
    if abs(center_x) > 0.08 or abs(center_z) > 0.08:
        errors.append(f"{glb_path.name}: XZ center=({center_x:.4f}, {center_z:.4f}) not centered at (0,0)")

    gltf = GLTF2().load(str(glb_path))
    if not gltf.materials:
        errors.append(f"{glb_path.name}: missing glTF PBR materials")

    skins_count = len(gltf.skins or [])
    joints_count = len(gltf.skins[0].joints) if skins_count > 0 else 0
    if mode == "rigged":
        if skins_count < 1 or joints_count < 10:
            errors.append(f"{glb_path.name}: rigged asset missing valid skeleton (skins={skins_count}, joints={joints_count})")

    stats = {
        "file": glb_path.name,
        "size_kb": round(size_kb, 1),
        "tris": total_tris,
        "height": round(height, 4),
        "min_y": round(min_y, 4),
        "skins": skins_count,
        "joints": joints_count,
    }
    return errors, stats


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(description="Validate normalized GLB assets against Filmation budgets")
    parser.add_argument("--manifest", default="")
    parser.add_argument("--glb", default="")
    parser.add_argument("--mode", choices=["static", "rigged"], default="static")
    parser.add_argument("--target-height", type=float, default=1.0)
    parser.add_argument("--max-tris", type=int, default=6000)
    parser.add_argument("--max-size-kb", type=int, default=4096)
    args = parser.parse_args(argv)

    all_errors: list[str] = []
    summaries: list[dict] = []

    if args.manifest:
        manifest_path = Path(args.manifest).resolve()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in manifest.get("assets", []):
            glb_path = root / entry["output_glb"]
            errs, stats = validate_single_glb(
                glb_path,
                entry.get("mode", "static"),
                float(entry.get("target_height", 1.0)),
                int(entry.get("max_tris", 6000)),
                int(entry.get("max_size_kb", 4096)),
            )
            all_errors.extend(errs)
            if stats:
                summaries.append(stats)
    elif args.glb:
        errs, stats = validate_single_glb(
            Path(args.glb).resolve(),
            args.mode,
            args.target_height,
            args.max_tris,
            args.max_size_kb,
        )
        all_errors.extend(errs)
        if stats:
            summaries.append(stats)
    else:
        print("ERROR: Specify either --manifest or --glb", file=sys.stderr)
        return 2

    if all_errors:
        for e in all_errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    for s in summaries:
        print(f"  GLB OK: {s['file']} (h={s['height']}m, min_y={s['min_y']}, tris={s['tris']}, {s['size_kb']} KB, joints={s['joints']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
