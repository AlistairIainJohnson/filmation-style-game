#!/usr/bin/env python3
"""Stage C: Deterministic headless Blender 5.3.0 GLB normalizer.
Supports --mode static (props/blocks) and --mode rigged (armature-preserving characters)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


def _clamp_pbr_materials() -> None:
    for mat in bpy.data.materials:
        if not mat.use_nodes or mat.node_tree is None:
            continue
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is None:
            continue
        if "Roughness" in bsdf.inputs:
            r = float(bsdf.inputs["Roughness"].default_value)
            bsdf.inputs["Roughness"].default_value = max(0.18, min(0.95, r))
        if "Metallic" in bsdf.inputs:
            m = float(bsdf.inputs["Metallic"].default_value)
            bsdf.inputs["Metallic"].default_value = max(0.0, min(0.98, m))


def _compute_world_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    min_co = Vector((float("inf"), float("inf"), float("inf")))
    max_co = Vector((float("-inf"), float("-inf"), float("-inf")))
    for obj in meshes:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            min_co.x = min(min_co.x, w.x)
            min_co.y = min(min_co.y, w.y)
            min_co.z = min(min_co.z, w.z)
            max_co.x = max(max_co.x, w.x)
            max_co.y = max(max_co.y, w.y)
            max_co.z = max(max_co.z, w.z)
    return min_co, max_co


def _decimate_to_budget(meshes: list[bpy.types.Object], max_tris: int) -> None:
    total_tris = sum(sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons) for obj in meshes)
    if total_tris <= max_tris or total_tris <= 0:
        return
    ratio = max(0.05, max_tris / float(total_tris))
    for obj in meshes:
        tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        if tri_count <= 24:
            continue
        mod = obj.modifiers.new(name="AutoDecimate", type="DECIMATE")
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def normalize_static(meshes: list[bpy.types.Object], target_height: float, max_tris: int, col_suffix: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    min_co, max_co = _compute_world_bounds(meshes)
    height = max_co.z - min_co.z
    scale_factor = target_height / height if height > 1e-5 else 1.0
    bottom_center = Vector(((min_co.x + max_co.x) * 0.5, (min_co.y + max_co.y) * 0.5, min_co.z))

    for obj in meshes:
        for v in obj.data.vertices:
            v.co = (v.co - bottom_center) * scale_factor
        obj.data.update()

    _decimate_to_budget(meshes, max_tris)

    if col_suffix:
        for idx, obj in enumerate(meshes):
            if not obj.name.endswith(col_suffix):
                obj.name = f"{obj.name}{col_suffix}" if idx == 0 else f"{obj.name}{col_suffix}"


def normalize_rigged(meshes: list[bpy.types.Object], armatures: list[bpy.types.Object], target_height: float, max_tris: int) -> None:
    min_co, max_co = _compute_world_bounds(meshes)
    height = max_co.z - min_co.z
    scale_factor = target_height / height if height > 1e-5 else 1.0
    bottom_center = Vector(((min_co.x + max_co.x) * 0.5, (min_co.y + max_co.y) * 0.5, min_co.z))

    roots = [o for o in (armatures + meshes) if o.parent is None]
    xform = Matrix.Scale(scale_factor, 4) @ Matrix.Translation(-bottom_center)
    for root_obj in roots:
        root_obj.matrix_world = xform @ root_obj.matrix_world

    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in armatures + meshes:
        obj.select_set(True)
    if armatures:
        bpy.context.view_layer.objects.active = armatures[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _decimate_to_budget(meshes, max_tris)


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="inp", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--mode", choices=["static", "rigged"], default="static")
    parser.add_argument("--target-height", type=float, default=1.0)
    parser.add_argument("--max-tris", type=int, default=6000)
    parser.add_argument("--add-col-suffix", default="")
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.inp).resolve()))

    meshes = [
        o for o in bpy.context.scene.objects
        if o.type == "MESH" and all("glTF_not_exported" not in c.name for c in o.users_collection)
    ]
    armatures = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if not meshes:
        raise RuntimeError("No mesh objects found in input GLB.")

    if args.mode == "rigged" and armatures:
        normalize_rigged(meshes, armatures, args.target_height, args.max_tris)
    else:
        normalize_static(meshes, args.target_height, args.max_tris, args.add_col_suffix)

    _clamp_pbr_materials()

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_yup=True,
        export_apply=(args.mode != "rigged"),
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=True,
        export_skins=True,
    )
    print(f"Normalized GLB ({args.mode}, h={args.target_height}m) -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
