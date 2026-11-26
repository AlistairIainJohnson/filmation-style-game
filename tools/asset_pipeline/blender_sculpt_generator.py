#!/usr/bin/env python3
"""Headless Blender 5.3.0 generator turning conditioned 2D retro sprites into
modern sculpted PBR 3D meshes (and SkeletonProfileHumanoid rigged characters)."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

HUMANOID_BONES = [
    ("Hips", None, (0.0, 0.0, 0.78), (0.0, 0.0, 0.90)),
    ("Spine", "Hips", (0.0, 0.0, 0.90), (0.0, 0.0, 1.06)),
    ("Chest", "Spine", (0.0, 0.0, 1.06), (0.0, 0.0, 1.24)),
    ("Neck", "Chest", (0.0, 0.0, 1.24), (0.0, 0.0, 1.32)),
    ("Head", "Neck", (0.0, 0.0, 1.32), (0.0, 0.0, 1.54)),
    ("LeftUpperArm", "Chest", (0.20, 0.0, 1.20), (0.36, 0.0, 1.02)),
    ("LeftLowerArm", "LeftUpperArm", (0.36, 0.0, 1.02), (0.48, 0.0, 0.84)),
    ("LeftHand", "LeftLowerArm", (0.48, 0.0, 0.84), (0.54, 0.0, 0.76)),
    ("RightUpperArm", "Chest", (-0.20, 0.0, 1.20), (-0.36, 0.0, 1.02)),
    ("RightLowerArm", "RightUpperArm", (-0.36, 0.0, 1.02), (-0.48, 0.0, 0.84)),
    ("RightHand", "RightLowerArm", (-0.48, 0.0, 0.84), (-0.54, 0.0, 0.76)),
    ("LeftUpperLeg", "Hips", (0.11, 0.0, 0.78), (0.11, 0.0, 0.44)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.11, 0.0, 0.44), (0.11, 0.0, 0.12)),
    ("LeftFoot", "LeftLowerLeg", (0.11, 0.0, 0.12), (0.11, -0.10, 0.0)),
    ("RightUpperLeg", "Hips", (-0.11, 0.0, 0.78), (-0.11, 0.0, 0.44)),
    ("RightLowerLeg", "RightUpperLeg", (-0.11, 0.0, 0.44), (-0.11, 0.0, 0.12)),
    ("RightFoot", "RightLowerLeg", (-0.11, 0.0, 0.12), (-0.11, -0.10, 0.0)),
]


def make_pbr_material(
    name: str,
    rgba: tuple[float, float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.7,
    emission: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = rgba
        if len(rgba) >= 4 and rgba[3] < 0.999 and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = rgba[3]
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
        if emission is not None and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        if emission_strength > 0.0 and "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def load_palette(sprite_path: Path) -> list[tuple[float, float, float]]:
    meta_path = sprite_path.with_suffix(".meta.json")
    if meta_path.exists():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        pal = meta.get("dominant_palette_rgb", [])
        if pal:
            return [(float(c[0]), float(c[1]), float(c[2])) for c in pal]
    return [(0.55, 0.45, 0.35), (0.35, 0.38, 0.44), (0.85, 0.70, 0.25)]


def add_beveled_box(
    name: str,
    center: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel_width: float = 0.03,
    segments: int = 2,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel_width > 0.0:
        mod = obj.modifiers.new(name="Bevel", type="BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if rotation != (0.0, 0.0, 0.0):
        obj.rotation_euler = rotation
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(mat)
    return obj


def add_cylinder(
    name: str,
    center: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    verts: int = 16,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=center, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def add_uv_sphere(
    name: str,
    center: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12, radius=radius, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation != (0.0, 0.0, 0.0):
        obj.rotation_euler = rotation
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(mat)
    return obj


def build_prop_chest(palette: list[tuple[float, float, float]]) -> None:
    c_oak = palette[0] if len(palette) > 0 else (0.52, 0.32, 0.17)
    oak_mat = make_pbr_material("OakWood", (c_oak[0], c_oak[1], c_oak[2], 1.0), metallic=0.05, roughness=0.62)
    iron_mat = make_pbr_material("IronBands", (0.20, 0.22, 0.25, 1.0), metallic=0.85, roughness=0.42)
    brass_mat = make_pbr_material("BrassClasp", (0.86, 0.66, 0.24, 1.0), metallic=0.88, roughness=0.30)

    add_beveled_box("ChestBase", (0.0, 0.34, 0.0), (0.94, 0.90, 0.68), oak_mat, bevel_width=0.03)
    add_beveled_box("ChestLid", (0.0, 0.80, 0.0), (0.96, 0.92, 0.30), oak_mat, bevel_width=0.06, segments=3)
    add_beveled_box("BandLeft", (-0.28, 0.48, 0.0), (0.10, 0.95, 0.97), iron_mat, bevel_width=0.01)
    add_beveled_box("BandRight", (0.28, 0.48, 0.0), (0.10, 0.95, 0.97), iron_mat, bevel_width=0.01)
    add_beveled_box("LockClasp", (0.0, 0.64, -0.47), (0.16, 0.06, 0.20), brass_mat, bevel_width=0.01)


def build_prop_cauldron(palette: list[tuple[float, float, float]]) -> None:
    iron_mat = make_pbr_material("CastIron", (0.15, 0.17, 0.20, 1.0), metallic=0.72, roughness=0.46)
    c_brew = (0.18, 0.92, 0.52)
    for col in palette:
        if col[1] > col[0] * 1.3 and col[1] > col[2] * 1.2:
            c_brew = col
            break
    brew_mat = make_pbr_material(
        "EmeraldBrew",
        (c_brew[0], c_brew[1], c_brew[2], 1.0),
        metallic=0.05,
        roughness=0.22,
        emission=c_brew,
        emission_strength=2.6,
    )

    add_uv_sphere("CauldronBelly", (0.0, 0.46, 0.0), 0.44, iron_mat, scale=(1.0, 1.0, 0.85))
    add_cylinder("CauldronNeck", (0.0, 0.72, 0.0), 0.36, 0.24, iron_mat, verts=20)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.05, location=(0.0, 0.84, 0.0))
    rim = bpy.context.active_object
    rim.name = "CauldronRim"
    rim.data.materials.append(iron_mat)

    add_cylinder("BrewSurface", (0.0, 0.80, 0.0), 0.34, 0.06, brew_mat, verts=20)
    for idx, angle_deg in enumerate([0.0, 120.0, 240.0]):
        rad = math.radians(angle_deg)
        add_cylinder(f"Foot_{idx}", (0.26 * math.cos(rad), 0.10, 0.26 * math.sin(rad)), 0.07, 0.20, iron_mat, verts=10)
    for side in (-1.0, 1.0):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.10,
            minor_radius=0.025,
            location=(side * 0.45, 0.54, 0.0),
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
        ring = bpy.context.active_object
        ring.name = "Handle"
        ring.data.materials.append(iron_mat)


def build_prop_key(palette: list[tuple[float, float, float]]) -> None:
    c_gold = palette[0] if len(palette) > 0 else (0.95, 0.78, 0.22)
    gold_mat = make_pbr_material(
        "OrnateGold",
        (c_gold[0], c_gold[1], c_gold[2], 1.0),
        metallic=0.92,
        roughness=0.24,
        emission=(c_gold[0] * 0.35, c_gold[1] * 0.35, c_gold[2] * 0.2),
        emission_strength=0.6,
    )
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.14,
        minor_radius=0.035,
        location=(0.0, 0.38, 0.0),
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    bow = bpy.context.active_object
    bow.name = "KeyBow"
    bow.data.materials.append(gold_mat)

    add_cylinder("KeyShaft", (0.0, 0.16, 0.0), 0.032, 0.32, gold_mat, verts=14)
    add_beveled_box("KeyToothA", (0.06, 0.08, 0.0), (0.10, 0.04, 0.04), gold_mat, bevel_width=0.005)
    add_beveled_box("KeyToothB", (0.05, 0.02, 0.0), (0.08, 0.04, 0.04), gold_mat, bevel_width=0.005)


def build_prop_pillar(palette: list[tuple[float, float, float]]) -> None:
    c_stone = palette[0] if len(palette) > 0 else (0.47, 0.46, 0.44)
    stone_mat = make_pbr_material("GothicStone", (c_stone[0], c_stone[1], c_stone[2], 1.0), metallic=0.04, roughness=0.78)
    trim_mat = make_pbr_material("StoneTrim", (c_stone[0] * 0.78, c_stone[1] * 0.78, c_stone[2] * 0.78, 1.0), metallic=0.05, roughness=0.84)

    add_beveled_box("PillarPlinth", (0.0, 0.18, 0.0), (0.96, 0.96, 0.36), trim_mat, bevel_width=0.03)
    add_cylinder("PillarShaft", (0.0, 1.75, 0.0), 0.36, 2.86, stone_mat, verts=12)
    add_beveled_box("PillarCapital", (0.0, 3.32, 0.0), (0.96, 0.96, 0.36), trim_mat, bevel_width=0.03)


def _assign_bone_weight(obj: bpy.types.Object, bone_name: str, arm_obj: bpy.types.Object) -> None:
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    obj.parent = arm_obj
    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj


def _assign_smooth_bone_weights(
    obj: bpy.types.Object,
    arm_obj: bpy.types.Object,
    weight_fn,
) -> None:
    """Assign normalized multi-bone vertex weights via weight_fn(Vector) -> dict[str, float]."""
    groups: dict[str, bpy.types.VertexGroup] = {}
    for v in obj.data.vertices:
        wmap: dict[str, float] = weight_fn(v.co)
        total = sum(max(0.0, float(val)) for val in wmap.values())
        if total <= 1e-6:
            continue
        for bname, val in wmap.items():
            w = max(0.0, float(val)) / total
            if w <= 0.001:
                continue
            if bname not in groups:
                groups[bname] = obj.vertex_groups.new(name=bname)
            groups[bname].add([v.index], w, "REPLACE")
    obj.parent = arm_obj
    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj


def _loft_rings(
    name: str,
    rings: list[list[tuple[float, float, float]]],
    mat: bpy.types.Material,
    cap_bottom: bool = True,
    cap_top: bool = True,
    subsurf_levels: int = 0,
    smooth: bool = True,
) -> bpy.types.Object:
    """Loft a closed sequence of same-length 3D rings into a manifold organic mesh."""
    bm = bmesh.new()
    bm_rings: list[list[bmesh.types.BMVert]] = []
    for ring in rings:
        bm_rings.append([bm.verts.new(pt) for pt in ring])
    bm.verts.ensure_lookup_table()

    n = len(bm_rings[0])
    for r_idx in range(len(bm_rings) - 1):
        r0 = bm_rings[r_idx]
        r1 = bm_rings[r_idx + 1]
        for j in range(n):
            jn = (j + 1) % n
            bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))

    if cap_bottom and n >= 3:
        center = sum((Vector(p) for p in rings[0]), Vector((0.0, 0.0, 0.0))) / float(n)
        cv = bm.verts.new(center)
        r0 = bm_rings[0]
        for j in range(n):
            jn = (j + 1) % n
            bm.faces.new((cv, r0[jn], r0[j]))

    if cap_top and n >= 3:
        center = sum((Vector(p) for p in rings[-1]), Vector((0.0, 0.0, 0.0))) / float(n)
        cv = bm.verts.new(center)
        rl = bm_rings[-1]
        for j in range(n):
            jn = (j + 1) % n
            bm.faces.new((cv, rl[j], rl[jn]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.data.materials.append(mat)
    if subsurf_levels > 0:
        sub = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        sub.levels = subsurf_levels
        sub.render_levels = subsurf_levels
        bpy.ops.object.modifier_apply(modifier=sub.name)
    if smooth:
        _set_smooth(obj)
    return obj


def _build_organic_tube(
    name: str,
    spine_pts: list[tuple[float, float, float]],
    radii: list[float],
    mat: bpy.types.Material,
    sides: int = 10,
    flute_amp: float = 0.0,
    flute_freq: int = 5,
    twist: float = 0.0,
    cap_ends: bool = True,
    squash_y: float = 1.0,
) -> bpy.types.Object:
    """Sweep a fluted/twisted cross-section along a 3D spine polyline without kinks."""
    pts = [Vector(p) for p in spine_pts]
    rings: list[list[tuple[float, float, float]]] = []
    u_prev: Vector | None = None
    count = len(pts)
    for k in range(count):
        if k == 0:
            t = (pts[1] - pts[0]).normalized()
        elif k == count - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[k + 1] - pts[k - 1]).normalized()
        if t.length < 1e-6:
            t = Vector((0.0, 0.0, 1.0))

        if u_prev is None:
            ref = Vector((0.0, 1.0, 0.0)) if abs(t.y) < 0.8 else Vector((1.0, 0.0, 0.0))
            u = (ref - t * t.dot(ref)).normalized()
        else:
            u = u_prev - t * t.dot(u_prev)
            if u.length < 1e-5:
                ref = Vector((1.0, 0.0, 0.0)) if abs(t.x) < 0.8 else Vector((0.0, 0.0, 1.0))
                u = (ref - t * t.dot(ref)).normalized()
            else:
                u.normalize()
        v = t.cross(u).normalized()
        u_prev = u

        frac = k / float(max(1, count - 1))
        rad = radii[k]
        ring: list[tuple[float, float, float]] = []
        for j in range(sides):
            ang = 2.0 * math.pi * (j / float(sides))
            r_mod = rad * (1.0 + flute_amp * math.sin(flute_freq * ang + twist * frac))
            pt = pts[k] + u * (r_mod * math.cos(ang)) + v * (r_mod * math.sin(ang) * squash_y)
            ring.append((pt.x, pt.y, pt.z))
        rings.append(ring)

    return _loft_rings(name, rings, mat, cap_bottom=cap_ends, cap_top=cap_ends, subsurf_levels=0, smooth=True)


def _add_leaf_cluster_fronds(
    name: str,
    center: tuple[float, float, float],
    dir_vec: tuple[float, float, float],
    count: int,
    leaf_len: float,
    leaf_w: float,
    mat_a: bpy.types.Material,
    mat_b: bpy.types.Material,
    seed: int = 0,
) -> bpy.types.Object:
    """Create a sculpted spray of cupped, pointed leaf blades radiating from a branch node."""
    import random

    rng = random.Random(seed)
    bm = bmesh.new()
    base_dir = Vector(dir_vec)
    if base_dir.length < 1e-5:
        base_dir = Vector((0.0, -0.35, 0.94))
    base_dir.normalize()
    origin = Vector(center)

    ref_up = Vector((0.0, 0.0, 1.0)) if abs(base_dir.z) < 0.85 else Vector((0.0, -1.0, 0.0))
    ortho_a = base_dir.cross(ref_up).normalized()
    ortho_b = ortho_a.cross(base_dir).normalized()

    for i in range(count):
        az = 2.0 * math.pi * (i / float(max(1, count))) + rng.uniform(-0.35, 0.35)
        spread = rng.uniform(0.30, 0.95)
        fwd = (base_dir * math.cos(spread) + (ortho_a * math.cos(az) + ortho_b * math.sin(az)) * math.sin(spread)).normalized()
        up_ref = Vector((0.0, 0.0, 1.0)) if abs(fwd.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        side = fwd.cross(up_ref).normalized()
        up = side.cross(fwd).normalized()

        root = origin + fwd * rng.uniform(-0.04, 0.06) + Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05)))
        ll = leaf_len * rng.uniform(0.80, 1.20)
        lw = leaf_w * rng.uniform(0.85, 1.15)

        v0 = bm.verts.new(root)
        v_mid = bm.verts.new(root + fwd * (0.45 * ll) + up * (0.05 * ll))
        v_l = bm.verts.new(root + fwd * (0.38 * ll) - side * (0.5 * lw))
        v_r = bm.verts.new(root + fwd * (0.38 * ll) + side * (0.5 * lw))
        v_tip = bm.verts.new(root + fwd * ll - up * (0.07 * ll))

        m_idx = i % 2
        for tri in ((v0, v_l, v_mid), (v0, v_mid, v_r), (v_l, v_tip, v_mid), (v_mid, v_tip, v_r)):
            f = bm.faces.new(tri)
            f.material_index = m_idx

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat_a)
    obj.data.materials.append(mat_b)
    _set_smooth(obj)
    return obj


def _set_smooth(obj: bpy.types.Object) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = True


def _load_proportions(sprite_path: Path) -> dict:
    prop_path = sprite_path.resolve().parent.parent / "assets" / "source_sprites" / "extracted" / "character_proportions.json"
    if not prop_path.exists():
        # Try relative to workspace root
        for p in sprite_path.resolve().parents:
            candidate = p / "assets" / "source_sprites" / "extracted" / "character_proportions.json"
            if candidate.exists():
                prop_path = candidate
                break
    if prop_path.exists():
        return json.loads(prop_path.read_text(encoding="utf-8"))
    return {}


def _create_armature_from_bones(bone_defs: list[tuple[str, str | None, tuple[float, float, float], tuple[float, float, float]]]) -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("HumanoidArmature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    created_bones: dict[str, bpy.types.EditBone] = {}
    for bname, parent_name, head_pt, tail_pt in bone_defs:
        eb = arm_data.edit_bones.new(bname)
        eb.head = Vector(head_pt)
        eb.tail = Vector(tail_pt)
        if parent_name and parent_name in created_bones:
            eb.parent = created_bones[parent_name]
            eb.use_connect = False
        created_bones[bname] = eb

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def build_rigged_character(kind: str, palette: list[tuple[float, float, float]]) -> None:
    is_sentinel = kind == "character_sentinel"
    primary = palette[0] if len(palette) > 0 else ((0.68, 0.18, 0.18) if is_sentinel else (0.22, 0.42, 0.72))
    secondary = palette[1] if len(palette) > 1 else (0.55, 0.62, 0.72)
    accent = (1.0, 0.32, 0.20) if is_sentinel else (0.92, 0.76, 0.28)

    primary_mat = make_pbr_material("ArmorPrimary", (primary[0], primary[1], primary[2], 1.0), metallic=0.45, roughness=0.42)
    metal_mat = make_pbr_material("ArmorSteel", (secondary[0], secondary[1], secondary[2], 1.0), metallic=0.72, roughness=0.35)
    visor_mat = make_pbr_material(
        "VisorAccent",
        (accent[0], accent[1], accent[2], 1.0),
        metallic=0.85,
        roughness=0.25,
        emission=accent if is_sentinel else None,
        emission_strength=1.5 if is_sentinel else 0.0,
    )

    arm_data = bpy.data.armatures.new("HumanoidArmature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    created_bones: dict[str, bpy.types.EditBone] = {}
    for bname, parent_name, head_pt, tail_pt in HUMANOID_BONES:
        eb = arm_data.edit_bones.new(bname)
        # Note: prior to final Z-up -> Y-up export, Blender Z is up; convert (x, y, z) -> (x, y, z)
        eb.head = Vector((head_pt[0], head_pt[1], head_pt[2]))
        eb.tail = Vector((tail_pt[0], tail_pt[1], tail_pt[2]))
        if parent_name and parent_name in created_bones:
            eb.parent = created_bones[parent_name]
            eb.use_connect = False
        created_bones[bname] = eb

    bpy.ops.object.mode_set(mode="OBJECT")

    # Helper creating beveled segment bound to exact humanoid bone
    parts: list[tuple[str, str, tuple[float, float, float], tuple[float, float, float], bpy.types.Material]] = [
        ("PelvisMesh", "Hips", (0.0, 0.0, 0.83), (0.34, 0.24, 0.16), primary_mat),
        ("SpineMesh", "Spine", (0.0, 0.0, 0.98), (0.36, 0.24, 0.18), primary_mat),
        ("ChestMesh", "Chest", (0.0, 0.0, 1.15), (0.44, 0.28, 0.22), primary_mat),
        ("HeadMesh", "Head", (0.0, 0.0, 1.41), (0.28, 0.28, 0.28), metal_mat),
        ("VisorMesh", "Head", (0.0, -0.14, 1.41), (0.22, 0.06, 0.07), visor_mat),
        ("LArmUp", "LeftUpperArm", (0.28, 0.0, 1.11), (0.14, 0.14, 0.24), metal_mat),
        ("LArmLo", "LeftLowerArm", (0.42, 0.0, 0.93), (0.12, 0.12, 0.22), metal_mat),
        ("LHandMesh", "LeftHand", (0.51, 0.0, 0.80), (0.10, 0.10, 0.12), primary_mat),
        ("RArmUp", "RightUpperArm", (-0.28, 0.0, 1.11), (0.14, 0.14, 0.24), metal_mat),
        ("RArmLo", "RightLowerArm", (-0.42, 0.0, 0.93), (0.12, 0.12, 0.22), metal_mat),
        ("RHandMesh", "RightHand", (-0.51, 0.0, 0.80), (0.10, 0.10, 0.12), primary_mat),
        ("LLegUp", "LeftUpperLeg", (0.11, 0.0, 0.61), (0.15, 0.15, 0.32), metal_mat),
        ("LLegLo", "LeftLowerLeg", (0.11, 0.0, 0.28), (0.13, 0.13, 0.30), metal_mat),
        ("LFootMesh", "LeftFoot", (0.11, -0.04, 0.06), (0.14, 0.22, 0.12), primary_mat),
        ("RLegUp", "RightUpperLeg", (-0.11, 0.0, 0.61), (0.15, 0.15, 0.32), metal_mat),
        ("RLegLo", "RightLowerLeg", (-0.11, 0.0, 0.28), (0.13, 0.13, 0.30), metal_mat),
        ("RFootMesh", "RightFoot", (-0.11, -0.04, 0.06), (0.14, 0.22, 0.12), primary_mat),
    ]

    for mname, bone_name, loc, sz, mat in parts:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        obj = bpy.context.active_object
        obj.name = mname
        obj.scale = sz
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = min(sz) * 0.18
        bev.segments = 2
        bpy.ops.object.modifier_apply(modifier=bev.name)
        obj.data.materials.append(mat)
        _assign_bone_weight(obj, bone_name, arm_obj)


EXPLORER_BONES = [
    ("Hips", None, (0.0, 0.0, 0.44), (0.0, 0.0, 0.56)),
    ("Spine", "Hips", (0.0, 0.0, 0.56), (0.0, 0.0, 0.70)),
    ("Chest", "Spine", (0.0, 0.0, 0.70), (0.0, 0.0, 0.86)),
    ("Neck", "Chest", (0.0, 0.0, 0.86), (0.0, 0.0, 0.92)),
    ("Head", "Neck", (0.0, 0.0, 0.92), (0.0, 0.0, 1.38)),
    ("LeftUpperArm", "Chest", (0.21, 0.0, 0.80), (0.26, 0.0, 0.63)),
    ("LeftLowerArm", "LeftUpperArm", (0.26, 0.0, 0.63), (0.28, -0.02, 0.47)),
    ("LeftHand", "LeftLowerArm", (0.28, -0.02, 0.47), (0.28, -0.03, 0.35)),
    ("RightUpperArm", "Chest", (-0.21, 0.0, 0.80), (-0.26, 0.0, 0.63)),
    ("RightLowerArm", "RightUpperArm", (-0.26, 0.0, 0.63), (-0.28, -0.02, 0.47)),
    ("RightHand", "RightLowerArm", (-0.28, -0.02, 0.47), (-0.28, -0.03, 0.35)),
    ("LeftUpperLeg", "Hips", (0.11, 0.0, 0.44), (0.11, 0.0, 0.25)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.11, 0.0, 0.25), (0.11, 0.0, 0.10)),
    ("LeftFoot", "LeftLowerLeg", (0.11, 0.0, 0.10), (0.11, -0.10, 0.0)),
    ("RightUpperLeg", "Hips", (-0.11, 0.0, 0.44), (-0.11, 0.0, 0.25)),
    ("RightLowerLeg", "RightUpperLeg", (-0.11, 0.0, 0.25), (-0.11, 0.0, 0.10)),
    ("RightFoot", "RightLowerLeg", (-0.11, 0.0, 0.10), (-0.11, -0.10, 0.0)),
]

WEREWOLF_BONES = [
    ("Hips", None, (0.0, 0.0, 0.48), (0.0, 0.0, 0.62)),
    ("Spine", "Hips", (0.0, 0.0, 0.62), (0.0, 0.0, 0.78)),
    ("Chest", "Spine", (0.0, 0.0, 0.78), (0.0, 0.0, 0.96)),
    ("Neck", "Chest", (0.0, 0.0, 0.96), (0.0, 0.0, 1.04)),
    ("Head", "Neck", (0.0, 0.0, 1.04), (0.0, 0.0, 1.50)),
    ("LeftUpperArm", "Chest", (0.23, 0.0, 0.89), (0.29, -0.01, 0.70)),
    ("LeftLowerArm", "LeftUpperArm", (0.29, -0.01, 0.70), (0.31, -0.03, 0.51)),
    ("LeftHand", "LeftLowerArm", (0.31, -0.03, 0.51), (0.31, -0.05, 0.39)),
    ("RightUpperArm", "Chest", (-0.23, 0.0, 0.89), (-0.29, -0.01, 0.70)),
    ("RightLowerArm", "RightUpperArm", (-0.29, -0.01, 0.70), (-0.31, -0.03, 0.51)),
    ("RightHand", "RightLowerArm", (-0.31, -0.03, 0.51), (-0.31, -0.05, 0.39)),
    ("LeftUpperLeg", "Hips", (0.125, 0.0, 0.48), (0.125, 0.0, 0.27)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.125, 0.0, 0.27), (0.125, 0.0, 0.10)),
    ("LeftFoot", "LeftLowerLeg", (0.125, 0.0, 0.10), (0.125, -0.11, 0.0)),
    ("RightUpperLeg", "Hips", (-0.125, 0.0, 0.48), (-0.125, 0.0, 0.27)),
    ("RightLowerLeg", "RightUpperLeg", (-0.125, 0.0, 0.27), (-0.125, 0.0, 0.10)),
    ("RightFoot", "RightLowerLeg", (-0.125, 0.0, 0.10), (-0.125, -0.11, 0.0)),
]


def build_rigged_explorer(palette: list[tuple[float, float, float]], prop_data: dict) -> None:
    """Anatomically sculpted Sabreman explorer with continuous lofted torso/limbs,
    human head/face, contoured pith helmet, safari jacket lapels & leather boots."""
    exp_pal = prop_data.get("explorer", {}).get("palette", {})
    c_helmet = tuple(exp_pal.get("helmet", palette[0] if len(palette) > 0 else (0.784, 0.663, 0.431)))
    c_tunic = tuple(exp_pal.get("tunic", (0.788, 0.643, 0.361)))
    c_skin = tuple(exp_pal.get("skin", (0.839, 0.624, 0.494)))
    c_boots = tuple(exp_pal.get("boots", (0.278, 0.180, 0.106)))
    c_brass = tuple(exp_pal.get("brass", (0.851, 0.659, 0.259)))

    helmet_mat = make_pbr_material("ExplorerHelmet", (*c_helmet, 1.0), metallic=0.04, roughness=0.74)
    tunic_mat = make_pbr_material("ExplorerTunic", (*c_tunic, 1.0), metallic=0.03, roughness=0.78)
    skin_mat = make_pbr_material("ExplorerSkin", (*c_skin, 1.0), metallic=0.0, roughness=0.60)
    nose_mat = make_pbr_material("ExplorerNose", (0.84, 0.58, 0.45, 1.0), metallic=0.0, roughness=0.56)
    leather_mat = make_pbr_material("ExplorerLeather", (*c_boots, 1.0), metallic=0.08, roughness=0.50)
    brass_mat = make_pbr_material("ExplorerBrass", (*c_brass, 1.0), metallic=0.88, roughness=0.28)
    eye_white_mat = make_pbr_material("ExplorerEyeWhite", (0.96, 0.95, 0.92, 1.0), metallic=0.0, roughness=0.26)
    eye_mat = make_pbr_material("ExplorerEyes", (0.06, 0.05, 0.05, 1.0), metallic=0.1, roughness=0.22)
    hair_mat = make_pbr_material("ExplorerHair", (0.26, 0.16, 0.09, 1.0), metallic=0.02, roughness=0.70)

    arm_obj = _create_armature_from_bones(EXPLORER_BONES)

    def _ell_ring(cx: float, cy: float, cz: float, rx: float, ry: float, sides: int = 12, pinch_front: float = 0.0) -> list[tuple[float, float, float]]:
        pts: list[tuple[float, float, float]] = []
        for j in range(sides):
            a = 2.0 * math.pi * (j / float(sides))
            ca, sa = math.cos(a), math.sin(a)
            local_rx = rx * (1.0 + pinch_front * max(0.0, -sa))
            pts.append((cx + local_rx * ca, cy + ry * sa, cz))
        return pts

    # 1. Continuous lofted torso/tunic/hips/neck
    torso_rings = [
        _ell_ring(0.0, 0.0, 0.42, 0.18, 0.145, 12),   # Hips hem
        _ell_ring(0.0, 0.0, 0.50, 0.215, 0.175, 12),  # Lower tunic skirt
        _ell_ring(0.0, 0.0, 0.57, 0.195, 0.155, 12),  # Cinched waist
        _ell_ring(0.0, -0.01, 0.68, 0.22, 0.17, 12),  # Ribcage
        _ell_ring(0.0, -0.01, 0.79, 0.24, 0.18, 12),  # Broad chest & shoulders
        _ell_ring(0.0, 0.0, 0.87, 0.175, 0.135, 12),  # Trapezius taper
        _ell_ring(0.0, 0.0, 0.95, 0.078, 0.075, 12),  # Neck into head
    ]
    torso_obj = _loft_rings("ExplorerTorso", torso_rings, tunic_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

    def _torso_weights(co: Vector) -> dict[str, float]:
        z = co.z
        if z <= 0.48:
            return {"Hips": 1.0}
        if z <= 0.60:
            t = (z - 0.48) / 0.12
            return {"Hips": 1.0 - t, "Spine": t}
        if z <= 0.76:
            t = (z - 0.60) / 0.16
            return {"Spine": 1.0 - t, "Chest": t}
        if z <= 0.88:
            t = (z - 0.76) / 0.12
            return {"Chest": 1.0 - t * 0.6, "Neck": t * 0.6}
        return {"Neck": 1.0}

    _assign_smooth_bone_weights(torso_obj, arm_obj, _torso_weights)

    # Tailored leather belt, brass buckle & safari tunic pocket/collar details
    belt = add_cylinder("WaistBelt", (0.0, 0.0, 0.565), 0.212, 0.05, leather_mat, verts=16)
    _set_smooth(belt)
    _assign_bone_weight(belt, "Spine", arm_obj)
    buckle = add_beveled_box("BeltBuckle", (0.0, -0.175, 0.565), (0.075, 0.032, 0.058), brass_mat, bevel_width=0.008)
    _assign_bone_weight(buckle, "Spine", arm_obj)
    for sx in (-1.0, 1.0):
        lapel = add_beveled_box(f"Collar_{sx:.0f}", (sx * 0.065, -0.13, 0.84), (0.065, 0.04, 0.09), tunic_mat, bevel_width=0.01, rotation=(0.0, sx * 0.28, 0.0))
        _assign_bone_weight(lapel, "Chest", arm_obj)
        pkt = add_beveled_box(f"Pocket_{sx:.0f}", (sx * 0.105, -0.172, 0.73), (0.072, 0.025, 0.078), leather_mat, bevel_width=0.006)
        _assign_bone_weight(pkt, "Chest", arm_obj)

    # 2. Contoured Human Head + Face + Tilted Pith Helmet (bound to Head)
    head_rings = [
        _ell_ring(0.0, 0.0, 0.91, 0.072, 0.072, 12),          # Jaw-neck join
        _ell_ring(0.0, -0.015, 0.96, 0.125, 0.132, 12, -0.05), # Chin & jawline
        _ell_ring(0.0, -0.015, 1.03, 0.155, 0.155, 12),        # Cheeks & temples
        _ell_ring(0.0, -0.01, 1.11, 0.162, 0.165, 12),         # Forehead
        _ell_ring(0.0, 0.005, 1.19, 0.135, 0.140, 12),         # Upper cranium
        _ell_ring(0.0, 0.01, 1.24, 0.06, 0.06, 12),            # Crown
    ]
    head_obj = _loft_rings("HeadBase", head_rings, skin_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(head_obj, "Head", arm_obj)

    nose = add_beveled_box("Nose", (0.0, -0.175, 1.015), (0.036, 0.048, 0.052), nose_mat, bevel_width=0.014)
    _set_smooth(nose)
    _assign_bone_weight(nose, "Head", arm_obj)
    mustache = add_beveled_box("Mustache", (0.0, -0.162, 0.968), (0.125, 0.036, 0.026), hair_mat, bevel_width=0.01)
    _set_smooth(mustache)
    _assign_bone_weight(mustache, "Head", arm_obj)
    for side_tag, sx in (("L", 1.0), ("R", -1.0)):
        ew = add_uv_sphere(f"EyeWhite_{side_tag}", (sx * 0.056, -0.155, 1.045), 0.028, eye_white_mat, scale=(1.0, 0.55, 1.05))
        _assign_bone_weight(ew, "Head", arm_obj)
        ep = add_uv_sphere(f"EyePupil_{side_tag}", (sx * 0.056, -0.168, 1.043), 0.015, eye_mat, scale=(1.0, 0.55, 1.05))
        _assign_bone_weight(ep, "Head", arm_obj)
        br = add_beveled_box(f"Brow_{side_tag}", (sx * 0.058, -0.158, 1.080), (0.055, 0.024, 0.016), hair_mat, bevel_width=0.005)
        _assign_bone_weight(br, "Head", arm_obj)
        ear = add_uv_sphere(f"Ear_{side_tag}", (sx * 0.158, -0.005, 1.03), 0.032, skin_mat, scale=(0.45, 0.75, 1.05))
        _assign_bone_weight(ear, "Head", arm_obj)

    # Pith helmet sculpted cleanly with brim flare, crown & leather band tilted around head pivot (0, 0, 1.20)
    tilt = math.radians(14.0)
    ct, st = math.cos(tilt), math.sin(tilt)

    def _tilt_pt(pt: tuple[float, float, float]) -> tuple[float, float, float]:
        dy = pt[1]
        dz = pt[2] - 1.20
        return (pt[0], dy * ct + dz * st, 1.20 + (-dy * st + dz * ct))

    helm_rings = [
        [_tilt_pt(p) for p in _ell_ring(0.0, 0.015, 1.165, 0.255, 0.270, 14)],  # Outer brim edge
        [_tilt_pt(p) for p in _ell_ring(0.0, 0.015, 1.195, 0.180, 0.195, 14)],  # Brim-crown crease
        [_tilt_pt(p) for p in _ell_ring(0.0, 0.015, 1.255, 0.168, 0.180, 14)],  # Crown mid
        [_tilt_pt(p) for p in _ell_ring(0.0, 0.015, 1.335, 0.125, 0.135, 14)],  # Dome shoulder
        [_tilt_pt(p) for p in _ell_ring(0.0, 0.015, 1.385, 0.052, 0.055, 14)],  # Finial base
    ]
    helm_obj = _loft_rings("PithHelmet", helm_rings, helmet_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(helm_obj, "Head", arm_obj)
    hband = add_cylinder("HelmetBand", (0.0, 0.018, 1.21), 0.180, 0.032, leather_mat, verts=16, rotation=(-tilt, 0.0, 0.0))
    _assign_bone_weight(hband, "Head", arm_obj)

    # 3. Close-hanging Safari Sleeves, Forearms & Sculpted Hands (palm + opposing thumb + 4 fingers) per side
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        sleeve_rings = [
            _ell_ring(sign_x * 0.205, 0.0, 0.805, 0.068, 0.076, 10),  # Shoulder socket inside torso
            _ell_ring(sign_x * 0.238, 0.0, 0.750, 0.074, 0.078, 10),  # Rolled sleeve mid
            _ell_ring(sign_x * 0.258, 0.0, 0.680, 0.064, 0.066, 10),  # Sleeve cuff
        ]
        sleeve_mesh = _loft_rings(f"ExplorerSleeve_{side_tag}", sleeve_rings, tunic_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        forearm_rings = [
            _ell_ring(sign_x * 0.254, 0.0, 0.695, 0.050, 0.052, 10),    # Inside sleeve cuff
            _ell_ring(sign_x * 0.264, -0.005, 0.625, 0.048, 0.050, 10), # Elbow
            _ell_ring(sign_x * 0.276, -0.015, 0.545, 0.041, 0.043, 10), # Mid-forearm
            _ell_ring(sign_x * 0.284, -0.022, 0.468, 0.031, 0.034, 10), # Constricted wrist
        ]
        forearm_mesh = _loft_rings(f"ExplorerForearm_{side_tag}", forearm_rings, skin_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        palm_rings = [
            _ell_ring(sign_x * 0.284, -0.022, 0.474, 0.030, 0.033, 10), # Wrist overlap
            _ell_ring(sign_x * 0.287, -0.028, 0.440, 0.034, 0.052, 10), # Palm heel/base
            _ell_ring(sign_x * 0.286, -0.032, 0.402, 0.032, 0.054, 10), # Knuckle ridge
            _ell_ring(sign_x * 0.282, -0.032, 0.390, 0.024, 0.044, 10), # Knuckle cap
        ]
        palm_mesh = _loft_rings(f"ExplorerHandPalm_{side_tag}", palm_rings, skin_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_arm_z_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.66:
                    return {f"{bp}UpperArm": 1.0}
                if z >= 0.60:
                    t = (0.66 - z) / 0.06
                    return {f"{bp}UpperArm": 1.0 - t, f"{bp}LowerArm": t}
                if z >= 0.49:
                    return {f"{bp}LowerArm": 1.0}
                if z >= 0.46:
                    t = (0.49 - z) / 0.03
                    return {f"{bp}LowerArm": 1.0 - t, f"{bp}Hand": t}
                return {f"{bp}Hand": 1.0}
            return _fn

        arm_w_fn = _make_arm_z_w(bone_prefix)
        _assign_smooth_bone_weights(sleeve_mesh, arm_obj, arm_w_fn)
        _assign_smooth_bone_weights(forearm_mesh, arm_obj, arm_w_fn)
        _assign_smooth_bone_weights(palm_mesh, arm_obj, arm_w_fn)

        thumb_obj = _build_organic_tube(
            f"ExplorerThumb_{side_tag}",
            [
                (sign_x * 0.270, -0.062, 0.444),
                (sign_x * 0.256, -0.090, 0.412),
                (sign_x * 0.252, -0.086, 0.382),
            ],
            [0.020, 0.017, 0.013],
            skin_mat,
            sides=7,
        )
        _assign_bone_weight(thumb_obj, f"{bone_prefix}Hand", arm_obj)

        finger_specs = [
            ([(sign_x * 0.284, -0.068, 0.404), (sign_x * 0.278, -0.070, 0.376), (sign_x * 0.266, -0.066, 0.352)], [0.0135, 0.0115, 0.0085]),
            ([(sign_x * 0.286, -0.044, 0.402), (sign_x * 0.280, -0.045, 0.372), (sign_x * 0.268, -0.042, 0.345)], [0.0140, 0.0120, 0.0090]),
            ([(sign_x * 0.284, -0.020, 0.404), (sign_x * 0.278, -0.021, 0.375), (sign_x * 0.266, -0.019, 0.352)], [0.0130, 0.0110, 0.0085]),
            ([(sign_x * 0.280, 0.004, 0.408), (sign_x * 0.274, 0.003, 0.383), (sign_x * 0.264, 0.004, 0.363)], [0.0115, 0.0098, 0.0075]),
        ]
        for f_idx, (f_spine, f_rads) in enumerate(finger_specs):
            finger_obj = _build_organic_tube(f"ExplorerFinger_{side_tag}_{f_idx}", f_spine, f_rads, skin_mat, sides=6)
            _assign_bone_weight(finger_obj, f"{bone_prefix}Hand", arm_obj)

    # 4. Continuous sculpted Leg+Shorts+Boot per side (clean cuff, boot grounded at z = 0.0)
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        cx = sign_x * 0.11
        leg_rings = [
            _ell_ring(cx, 0.0, 0.45, 0.090, 0.095, 10),         # Hip socket inside pelvis
            _ell_ring(cx, 0.0, 0.29, 0.082, 0.084, 10),         # Safari shorts hem
            _ell_ring(cx, 0.0, 0.25, 0.054, 0.056, 10),         # Recessed knee/calf core
            _ell_ring(cx, 0.0, 0.18, 0.068, 0.070, 10),         # Rolled boot cuff rim
            _ell_ring(cx, -0.01, 0.10, 0.065, 0.082, 10),       # Boot ankle
            _ell_ring(cx, -0.045, 0.04, 0.072, 0.115, 10),      # Boot vamp
            _ell_ring(cx, -0.045, 0.00, 0.072, 0.115, 10),      # Boot sole grounded at z=0.0
        ]
        leg_mesh = _loft_rings(f"ExplorerLeg_{side_tag}", leg_rings, leather_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_leg_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.27:
                    return {f"{bp}UpperLeg": 1.0}
                if z >= 0.21:
                    t = (0.27 - z) / 0.06
                    return {f"{bp}UpperLeg": 1.0 - t, f"{bp}LowerLeg": t}
                if z >= 0.13:
                    return {f"{bp}LowerLeg": 1.0}
                if z >= 0.08:
                    t = (0.13 - z) / 0.05
                    return {f"{bp}LowerLeg": 1.0 - t, f"{bp}Foot": t}
                return {f"{bp}Foot": 1.0}
            return _fn

        _assign_smooth_bone_weights(leg_mesh, arm_obj, _make_leg_w(bone_prefix))
        shin_band = add_cylinder(f"ShinSkin_{side_tag}", (cx, 0.0, 0.235), 0.056, 0.095, skin_mat, verts=12)
        _set_smooth(shin_band)
        _assign_bone_weight(shin_band, f"{bone_prefix}LowerLeg", arm_obj)


def build_rigged_werewolf(palette: list[tuple[float, float, float]], prop_data: dict) -> None:
    """Anatomically sculpted Werewolf matching the organic lofted quality of Explorer:
    tapered lupine muzzle with fangs & brow, pointed cupped ears, athletic torso with chest ruff & dorsal mane,
    contoured tattered shorts, muscular tucked arms with clawed hands, digitigrade-curved legs & bushy tail."""
    wolf_pal = prop_data.get("werewolf", {}).get("palette", {})
    c_fur = tuple(wolf_pal.get("fur", palette[0] if len(palette) > 0 else (0.294, 0.208, 0.153)))
    c_ruff = tuple(wolf_pal.get("ruff", (0.431, 0.325, 0.251)))
    c_tunic = tuple(wolf_pal.get("tattered_tunic", (0.722, 0.588, 0.333)))
    c_eye = tuple(wolf_pal.get("amber_eye", (0.961, 0.706, 0.153)))
    c_claw = tuple(wolf_pal.get("claws", (0.140, 0.115, 0.105)))

    fur_mat = make_pbr_material("WolfFur", (*c_fur, 1.0), metallic=0.02, roughness=0.86)
    fur_dark_mat = make_pbr_material(
        "WolfFurDark",
        (c_fur[0] * 0.62, c_fur[1] * 0.62, c_fur[2] * 0.64, 1.0),
        metallic=0.02,
        roughness=0.88,
    )
    ruff_mat = make_pbr_material("WolfRuff", (*c_ruff, 1.0), metallic=0.02, roughness=0.82)
    shorts_mat = make_pbr_material("TatteredShorts", (*c_tunic, 1.0), metallic=0.02, roughness=0.86)
    belt_mat = make_pbr_material("WolfBelt", (0.24, 0.15, 0.09, 1.0), metallic=0.06, roughness=0.56)
    eye_mat = make_pbr_material("WolfAmberEye", (*c_eye, 1.0), metallic=0.1, roughness=0.18, emission=c_eye, emission_strength=1.6)
    pupil_mat = make_pbr_material("WolfPupil", (0.04, 0.03, 0.03, 1.0), metallic=0.05, roughness=0.25)
    nose_mat = make_pbr_material("WolfNosePad", (0.07, 0.06, 0.06, 1.0), metallic=0.04, roughness=0.32)
    claw_mat = make_pbr_material("WolfClaws", (*c_claw, 1.0), metallic=0.18, roughness=0.38)
    fang_mat = make_pbr_material("WolfFangs", (0.92, 0.89, 0.80, 1.0), metallic=0.05, roughness=0.30)

    arm_obj = _create_armature_from_bones(WEREWOLF_BONES)

    def _ell_ring(
        cx: float,
        cy: float,
        cz: float,
        rx: float,
        ry: float,
        sides: int = 12,
        pinch_front: float = 0.0,
        sawtooth_z: float = 0.0,
    ) -> list[tuple[float, float, float]]:
        pts: list[tuple[float, float, float]] = []
        for j in range(sides):
            a = 2.0 * math.pi * (j / float(sides))
            ca, sa = math.cos(a), math.sin(a)
            local_rx = rx * (1.0 + pinch_front * max(0.0, -sa))
            dz = sawtooth_z * (1.0 if (j % 2 == 0) else -1.0) if sawtooth_z != 0.0 else 0.0
            pts.append((cx + local_rx * ca, cy + ry * sa, cz + dz))
        return pts

    # 1. Continuous lofted athletic lupine torso (narrow waist -> deep hunched ribcage -> neck)
    torso_rings = [
        _ell_ring(0.0, 0.005, 0.45, 0.165, 0.135, 12),          # Pelvis base
        _ell_ring(0.0, 0.000, 0.55, 0.175, 0.145, 12),          # Hips / waist join
        _ell_ring(0.0, -0.010, 0.64, 0.168, 0.140, 12),         # Narrow athletic waist
        _ell_ring(0.0, -0.025, 0.74, 0.215, 0.172, 12, 0.06),   # Lower ribcage
        _ell_ring(0.0, -0.032, 0.85, 0.255, 0.195, 12, 0.08),   # Deep muscular chest / lats
        _ell_ring(0.0, -0.018, 0.95, 0.220, 0.168, 12),         # Hunched shoulder trapezius
        _ell_ring(0.0, -0.010, 1.03, 0.125, 0.118, 12),         # Muscular wolf neck
        _ell_ring(0.0, -0.015, 1.09, 0.092, 0.095, 12),         # Cranial base join
    ]
    torso_obj = _loft_rings("WolfTorso", torso_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

    def _wolf_torso_weights(co: Vector) -> dict[str, float]:
        z = co.z
        if z <= 0.52:
            return {"Hips": 1.0}
        if z <= 0.64:
            t = (z - 0.52) / 0.12
            return {"Hips": 1.0 - t, "Spine": t}
        if z <= 0.80:
            t = (z - 0.64) / 0.16
            return {"Spine": 1.0 - t, "Chest": t}
        if z <= 0.96:
            t = (z - 0.80) / 0.16
            return {"Chest": 1.0 - t * 0.55, "Neck": t * 0.55}
        if z <= 1.04:
            t = (z - 0.96) / 0.08
            return {"Chest": 0.45 * (1.0 - t), "Neck": 0.55 + 0.45 * t}
        return {"Neck": 1.0}

    _assign_smooth_bone_weights(torso_obj, arm_obj, _wolf_torso_weights)

    # Lighter sternum fur ruff + dorsal mane tufts
    ruff_rings = [
        _ell_ring(0.0, -0.145, 0.68, 0.055, 0.032, 8),
        _ell_ring(0.0, -0.165, 0.77, 0.115, 0.058, 8),
        _ell_ring(0.0, -0.175, 0.87, 0.145, 0.068, 8),
        _ell_ring(0.0, -0.140, 0.96, 0.110, 0.055, 8),
        _ell_ring(0.0, -0.095, 1.02, 0.055, 0.035, 8),
    ]
    ruff_obj = _loft_rings("WolfChestRuff", ruff_rings, ruff_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_smooth_bone_weights(ruff_obj, arm_obj, _wolf_torso_weights)

    mane_specs = [
        ([(0.0, 0.10, 1.06), (0.0, 0.19, 1.02), (0.0, 0.25, 0.95)], [0.055, 0.042, 0.014], "Neck", fur_dark_mat),
        ([(0.0, 0.12, 0.97), (0.0, 0.22, 0.92), (0.0, 0.28, 0.83)], [0.062, 0.046, 0.015], "Chest", fur_dark_mat),
        ([(0.0, 0.13, 0.87), (0.0, 0.21, 0.81), (0.0, 0.26, 0.72)], [0.052, 0.038, 0.013], "Chest", fur_dark_mat),
        ([(0.12, 0.09, 0.96), (0.19, 0.16, 0.92), (0.24, 0.21, 0.84)], [0.048, 0.036, 0.012], "Chest", ruff_mat),
        ([(-0.12, 0.09, 0.96), (-0.19, 0.16, 0.92), (-0.24, 0.21, 0.84)], [0.048, 0.036, 0.012], "Chest", ruff_mat),
    ]
    for m_idx, (sp, rd, bname, mat) in enumerate(mane_specs):
        tuft = _build_organic_tube(f"WolfManeTuft_{m_idx}", sp, rd, mat, sides=6)
        _assign_bone_weight(tuft, bname, arm_obj)

    # 2. Contoured Tattered Explorer Shorts + Jagged Hem + Per-Leg Cuffs (zero boxes)
    shorts_rings = [
        _ell_ring(0.0, 0.005, 0.42, 0.188, 0.156, 12, sawtooth_z=0.022),  # Torn lower hip hem
        _ell_ring(0.0, 0.003, 0.48, 0.192, 0.160, 12),                    # Pelvis contour
        _ell_ring(0.0, 0.000, 0.56, 0.186, 0.154, 12, sawtooth_z=0.010),  # Waistline top
    ]
    shorts_obj = _loft_rings("WolfShorts", shorts_rings, shorts_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(shorts_obj, "Hips", arm_obj)

    belt_rings = [
        _ell_ring(0.0, 0.000, 0.538, 0.190, 0.158, 12),
        _ell_ring(0.0, 0.000, 0.566, 0.188, 0.156, 12),
    ]
    belt_obj = _loft_rings("WolfBelt", belt_rings, belt_mat, cap_bottom=True, cap_top=True, subsurf_levels=0)
    _assign_bone_weight(belt_obj, "Hips", arm_obj)

    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        cx = sign_x * 0.125
        short_leg_rings = [
            _ell_ring(cx, -0.005, 0.33, 0.108, 0.114, 10, sawtooth_z=0.024),  # Torn ragged thigh cuff
            _ell_ring(cx, -0.002, 0.39, 0.114, 0.120, 10),
            _ell_ring(cx, 0.002, 0.46, 0.116, 0.122, 10),
        ]
        sleg_obj = _loft_rings(f"WolfShortsLeg_{side_tag}", short_leg_rings, shorts_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
        _assign_bone_weight(sleg_obj, f"{bone_prefix}UpperLeg", arm_obj)

    # 3. Anatomical Lupine Head, Tapered Snout, Parted Jaw, Fangs, Brow & Cupped Ears (Head)
    cranium_rings = [
        _ell_ring(0.0, -0.015, 1.04, 0.105, 0.105, 12),          # Neck-skull join
        _ell_ring(0.0, -0.020, 1.11, 0.165, 0.168, 12, 0.10),    # Wide cheekbones
        _ell_ring(0.0, -0.015, 1.19, 0.178, 0.185, 12, 0.06),    # Mid cranium & brow
        _ell_ring(0.0, 0.005, 1.27, 0.145, 0.158, 12),           # Sloped wolf forehead
        _ell_ring(0.0, 0.025, 1.33, 0.078, 0.095, 12),           # Crown / occiput
    ]
    cranium_obj = _loft_rings("WolfCranium", cranium_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(cranium_obj, "Head", arm_obj)

    # Elongated chiseled upper snout extending along -Y
    muzzle_rings = [
        _ell_ring(0.0, -0.110, 1.182, 0.118, 0.072, 10),
        _ell_ring(0.0, -0.185, 1.174, 0.092, 0.060, 10),
        _ell_ring(0.0, -0.265, 1.164, 0.072, 0.048, 10),
        _ell_ring(0.0, -0.335, 1.158, 0.052, 0.036, 10),
        _ell_ring(0.0, -0.358, 1.158, 0.036, 0.026, 10),
    ]
    muzzle_obj = _loft_rings("WolfMuzzle", muzzle_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(muzzle_obj, "Head", arm_obj)

    nose_pad = add_uv_sphere("WolfNose", (0.0, -0.365, 1.168), 0.035, nose_mat, scale=(1.12, 0.85, 0.78))
    _set_smooth(nose_pad)
    _assign_bone_weight(nose_pad, "Head", arm_obj)

    # Slightly parted lower jaw + dark mouth cavity + 4 curved canine fangs
    jaw_rings = [
        _ell_ring(0.0, -0.095, 1.112, 0.088, 0.038, 10),
        _ell_ring(0.0, -0.175, 1.098, 0.068, 0.030, 10),
        _ell_ring(0.0, -0.255, 1.088, 0.050, 0.024, 10),
        _ell_ring(0.0, -0.312, 1.084, 0.034, 0.018, 10),
    ]
    jaw_obj = _loft_rings("WolfJaw", jaw_rings, ruff_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(jaw_obj, "Head", arm_obj)

    mouth_dark = add_uv_sphere("WolfMouthDark", (0.0, -0.205, 1.126), 0.048, pupil_mat, scale=(0.95, 1.95, 0.45))
    _set_smooth(mouth_dark)
    _assign_bone_weight(mouth_dark, "Head", arm_obj)

    for side_tag, sx in (("L", 1.0), ("R", -1.0)):
        up_fang = _build_organic_tube(
            f"WolfFangUp_{side_tag}",
            [(sx * 0.034, -0.295, 1.142), (sx * 0.034, -0.300, 1.120), (sx * 0.032, -0.298, 1.102)],
            [0.011, 0.008, 0.002],
            fang_mat,
            sides=6,
        )
        _assign_bone_weight(up_fang, "Head", arm_obj)
        lo_fang = _build_organic_tube(
            f"WolfFangLo_{side_tag}",
            [(sx * 0.028, -0.275, 1.098), (sx * 0.028, -0.279, 1.118), (sx * 0.027, -0.277, 1.132)],
            [0.009, 0.006, 0.002],
            fang_mat,
            sides=6,
        )
        _assign_bone_weight(lo_fang, "Head", arm_obj)

    # Angled fur brow ridges, recessed sockets, slanted amber eyes & slit pupils + cheek ruff tufts
    for side_tag, sx in (("L", 1.0), ("R", -1.0)):
        brow = _build_organic_tube(
            f"WolfBrow_{side_tag}",
            [(sx * 0.036, -0.168, 1.212), (sx * 0.088, -0.162, 1.234), (sx * 0.132, -0.125, 1.238)],
            [0.022, 0.025, 0.016],
            fur_dark_mat,
            sides=6,
        )
        _assign_bone_weight(brow, "Head", arm_obj)

        socket = add_uv_sphere(f"WolfSocket_{side_tag}", (sx * 0.080, -0.152, 1.202), 0.034, pupil_mat, scale=(1.10, 0.55, 0.78), rotation=(0.0, sx * math.radians(-16.0), 0.0))
        _assign_bone_weight(socket, "Head", arm_obj)
        eye = add_uv_sphere(f"WolfEye_{side_tag}", (sx * 0.082, -0.166, 1.202), 0.024, eye_mat, scale=(1.15, 0.45, 0.72), rotation=(0.0, sx * math.radians(-16.0), 0.0))
        _assign_bone_weight(eye, "Head", arm_obj)
        pupil = add_uv_sphere(f"WolfPupil_{side_tag}", (sx * 0.083, -0.175, 1.202), 0.011, pupil_mat, scale=(0.48, 0.40, 1.15))
        _assign_bone_weight(pupil, "Head", arm_obj)

        # Swept-back cheek fur tufts
        for c_idx, (z_off, tip_z) in enumerate(((1.145, 1.125), (1.105, 1.075))):
            cheek_tuft = _build_organic_tube(
                f"WolfCheekTuft_{side_tag}_{c_idx}",
                [(sx * 0.135, -0.055, z_off), (sx * 0.185, 0.015, z_off - 0.012), (sx * 0.220, 0.075, tip_z)],
                [0.034, 0.025, 0.008],
                ruff_mat,
                sides=6,
            )
            _assign_bone_weight(cheek_tuft, "Head", arm_obj)

        # Pointed swept-back wolf ears (outer fur shell + lighter recessed inner hollow)
        ear_outer_rings = [
            _ell_ring(sx * 0.095, 0.020, 1.280, 0.055, 0.042, 8),
            _ell_ring(sx * 0.118, 0.035, 1.360, 0.048, 0.034, 8),
            _ell_ring(sx * 0.138, 0.055, 1.440, 0.028, 0.020, 8),
            _ell_ring(sx * 0.152, 0.072, 1.495, 0.008, 0.007, 8),
        ]
        ear_outer = _loft_rings(f"WolfEarOuter_{side_tag}", ear_outer_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
        _assign_bone_weight(ear_outer, "Head", arm_obj)

        ear_inner_rings = [
            _ell_ring(sx * 0.092, 0.004, 1.292, 0.034, 0.020, 8),
            _ell_ring(sx * 0.114, 0.020, 1.365, 0.028, 0.016, 8),
            _ell_ring(sx * 0.132, 0.040, 1.432, 0.015, 0.010, 8),
        ]
        ear_inner = _loft_rings(f"WolfEarInner_{side_tag}", ear_inner_rings, ruff_mat, cap_bottom=True, cap_top=True, subsurf_levels=0)
        _assign_bone_weight(ear_inner, "Head", arm_obj)

    # 4. Sculpted Bushy Wolf Tail (bound to Hips, stays >= 0.25m above floor)
    tail_main = _build_organic_tube(
        "WolfTail",
        [
            (0.0, 0.145, 0.50),
            (0.0, 0.255, 0.42),
            (0.0, 0.365, 0.31),
            (0.0, 0.460, 0.27),
        ],
        [0.052, 0.084, 0.094, 0.076],
        fur_mat,
        sides=8,
    )
    _assign_bone_weight(tail_main, "Hips", arm_obj)
    tail_tip = _build_organic_tube(
        "WolfTailTip",
        [
            (0.0, 0.440, 0.272),
            (0.0, 0.515, 0.295),
            (0.0, 0.565, 0.345),
        ],
        [0.072, 0.050, 0.014],
        ruff_mat,
        sides=8,
    )
    _assign_bone_weight(tail_tip, "Hips", arm_obj)

    # 5. Continuous Lofted Muscular Arms + Sculpted Clawed Wolf Hands (per side)
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        arm_rings = [
            _ell_ring(sign_x * 0.215, -0.010, 0.895, 0.088, 0.092, 10),   # Deltoid inside shoulder
            _ell_ring(sign_x * 0.268, -0.005, 0.805, 0.078, 0.082, 10),   # Muscular bicep
            _ell_ring(sign_x * 0.292, -0.005, 0.700, 0.064, 0.066, 10),   # Elbow
            _ell_ring(sign_x * 0.306, -0.020, 0.605, 0.068, 0.070, 10),   # Thick wolf forearm
            _ell_ring(sign_x * 0.312, -0.032, 0.512, 0.044, 0.048, 10),   # Narrow wrist
        ]
        arm_mesh = _loft_rings(f"WolfArm_{side_tag}", arm_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        palm_rings = [
            _ell_ring(sign_x * 0.312, -0.032, 0.518, 0.042, 0.046, 10),   # Wrist overlap
            _ell_ring(sign_x * 0.314, -0.042, 0.476, 0.048, 0.066, 10),   # Furred palm
            _ell_ring(sign_x * 0.312, -0.048, 0.432, 0.044, 0.064, 10),   # Knuckles
            _ell_ring(sign_x * 0.308, -0.048, 0.418, 0.032, 0.052, 10),
        ]
        palm_mesh = _loft_rings(f"WolfPalm_{side_tag}", palm_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_wolf_arm_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.73:
                    return {f"{bp}UpperArm": 1.0}
                if z >= 0.67:
                    t = (0.73 - z) / 0.06
                    return {f"{bp}UpperArm": 1.0 - t, f"{bp}LowerArm": t}
                if z >= 0.53:
                    return {f"{bp}LowerArm": 1.0}
                if z >= 0.50:
                    t = (0.53 - z) / 0.03
                    return {f"{bp}LowerArm": 1.0 - t, f"{bp}Hand": t}
                return {f"{bp}Hand": 1.0}
            return _fn

        w_fn = _make_wolf_arm_w(bone_prefix)
        _assign_smooth_bone_weights(arm_mesh, arm_obj, w_fn)
        _assign_smooth_bone_weights(palm_mesh, arm_obj, w_fn)

        elbow_tuft = _build_organic_tube(
            f"WolfElbowTuft_{side_tag}",
            [(sign_x * 0.295, 0.035, 0.71), (sign_x * 0.315, 0.088, 0.69), (sign_x * 0.325, 0.130, 0.66)],
            [0.030, 0.022, 0.007],
            ruff_mat,
            sides=6,
        )
        _assign_bone_weight(elbow_tuft, f"{bone_prefix}UpperArm", arm_obj)

        # Opposing thumb + 4 curved furry fingers + 5 sharp dark claws
        thumb_obj = _build_organic_tube(
            f"WolfThumb_{side_tag}",
            [(sign_x * 0.294, -0.082, 0.482), (sign_x * 0.278, -0.112, 0.448), (sign_x * 0.274, -0.110, 0.418)],
            [0.022, 0.018, 0.013],
            fur_mat,
            sides=6,
        )
        _assign_bone_weight(thumb_obj, f"{bone_prefix}Hand", arm_obj)
        thumb_claw = _build_organic_tube(
            f"WolfThumbClaw_{side_tag}",
            [(sign_x * 0.274, -0.110, 0.422), (sign_x * 0.268, -0.106, 0.398), (sign_x * 0.262, -0.095, 0.382)],
            [0.011, 0.007, 0.002],
            claw_mat,
            sides=5,
        )
        _assign_bone_weight(thumb_claw, f"{bone_prefix}Hand", arm_obj)

        finger_specs = [
            (-0.086, 0.432, 0.385, 0.016),
            (-0.060, 0.430, 0.376, 0.017),
            (-0.034, 0.432, 0.382, 0.016),
            (-0.008, 0.436, 0.394, 0.014),
        ]
        for f_idx, (fy, fz_top, fz_tip, fr) in enumerate(finger_specs):
            finger_obj = _build_organic_tube(
                f"WolfFinger_{side_tag}_{f_idx}",
                [(sign_x * 0.310, fy, fz_top), (sign_x * 0.302, fy - 0.002, (fz_top + fz_tip) * 0.5), (sign_x * 0.288, fy, fz_tip)],
                [fr, fr * 0.85, fr * 0.68],
                fur_mat,
                sides=5,
            )
            _assign_bone_weight(finger_obj, f"{bone_prefix}Hand", arm_obj)
            claw_obj = _build_organic_tube(
                f"WolfHandClaw_{side_tag}_{f_idx}",
                [(sign_x * 0.288, fy, fz_tip + 0.004), (sign_x * 0.278, fy, fz_tip - 0.016), (sign_x * 0.266, fy, fz_tip - 0.030)],
                [fr * 0.58, fr * 0.38, 0.002],
                claw_mat,
                sides=5,
            )
            _assign_bone_weight(claw_obj, f"{bone_prefix}Hand", arm_obj)

    # 6. Continuous Lofted Athletic Hind Legs (thigh -> bent knee -> subtle hock -> grounded canine paw)
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        cx = sign_x * 0.125
        leg_rings = [
            _ell_ring(cx, 0.000, 0.480, 0.098, 0.105, 10),    # Muscular hip inside pelvis
            _ell_ring(cx, -0.012, 0.365, 0.092, 0.100, 10),   # Powerful thigh
            _ell_ring(cx, -0.028, 0.270, 0.072, 0.078, 10),   # Forward-angled wolf knee
            _ell_ring(cx, 0.018, 0.175, 0.062, 0.070, 10),    # Canine hock sweeping slightly back
            _ell_ring(cx, 0.005, 0.105, 0.056, 0.064, 10),    # Lower ankle / metatarsal
            _ell_ring(cx, -0.048, 0.052, 0.068, 0.112, 10),   # Arched paw bridge
            _ell_ring(cx, -0.052, 0.000, 0.072, 0.118, 10),   # Flat grounded paw pad (z=0.0)
        ]
        leg_mesh = _loft_rings(f"WolfLeg_{side_tag}", leg_rings, fur_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_wolf_leg_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.30:
                    return {f"{bp}UpperLeg": 1.0}
                if z >= 0.24:
                    t = (0.30 - z) / 0.06
                    return {f"{bp}UpperLeg": 1.0 - t, f"{bp}LowerLeg": t}
                if z >= 0.13:
                    return {f"{bp}LowerLeg": 1.0}
                if z >= 0.08:
                    t = (0.13 - z) / 0.05
                    return {f"{bp}LowerLeg": 1.0 - t, f"{bp}Foot": t}
                return {f"{bp}Foot": 1.0}
            return _fn

        _assign_smooth_bone_weights(leg_mesh, arm_obj, _make_wolf_leg_w(bone_prefix))

        # 4 sculpted canine toes + 4 curved claws per foot (all vertices >= 0.006m)
        for t_idx, tx_off in enumerate((-0.050, -0.018, 0.018, 0.050)):
            toe_x = cx + tx_off
            toe_obj = _build_organic_tube(
                f"WolfToe_{side_tag}_{t_idx}",
                [(toe_x, -0.135, 0.034), (toe_x, -0.172, 0.026), (toe_x, -0.195, 0.018)],
                [0.020, 0.017, 0.012],
                fur_mat,
                sides=5,
            )
            _assign_bone_weight(toe_obj, f"{bone_prefix}Foot", arm_obj)
            fclaw_obj = _build_organic_tube(
                f"WolfFootClaw_{side_tag}_{t_idx}",
                [(toe_x, -0.190, 0.020), (toe_x, -0.214, 0.014), (toe_x, -0.228, 0.008)],
                [0.010, 0.006, 0.002],
                claw_mat,
                sides=5,
            )
            _assign_bone_weight(fclaw_obj, f"{bone_prefix}Foot", arm_obj)


def build_rigged_sentinel(palette: list[tuple[float, float, float]]) -> None:
    """Knight Lore Castle Guard (R02C15-16 / R10C07-08) with pointed guard helm,
    crimson surcoat, shoulder pauldrons, and glowing crimson visor eyes."""
    c_crimson = (0.62, 0.14, 0.14)
    c_steel = palette[1] if len(palette) > 1 else (0.48, 0.52, 0.58)
    c_accent = (1.0, 0.22, 0.12)

    steel_mat = make_pbr_material("GuardSteel", (*c_steel, 1.0), metallic=0.82, roughness=0.34)
    surcoat_mat = make_pbr_material("GuardSurcoat", (*c_crimson, 1.0), metallic=0.12, roughness=0.68)
    shadow_mat = make_pbr_material("GuardShadow", (0.06, 0.05, 0.06, 1.0), metallic=0.1, roughness=0.85)
    eye_mat = make_pbr_material("GuardEyeGlow", (*c_accent, 1.0), metallic=0.1, roughness=0.20, emission=c_accent, emission_strength=2.2)

    arm_obj = _create_armature_from_bones(HUMANOID_BONES)

    def _sphere(name: str, bone: str, loc: tuple[float, float, float], r: float, scl: tuple[float, float, float], mat: bpy.types.Material) -> None:
        obj = add_uv_sphere(name, loc, r, mat, scale=scl)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    def _cyl(name: str, bone: str, loc: tuple[float, float, float], r: float, depth: float, mat: bpy.types.Material, rot: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> None:
        obj = add_cylinder(name, loc, r, depth, mat, verts=14, rotation=rot)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    def _box(name: str, bone: str, loc: tuple[float, float, float], sz: tuple[float, float, float], mat: bpy.types.Material, bevel: float = 0.02) -> None:
        obj = add_beveled_box(name, loc, sz, mat, bevel_width=bevel, segments=2)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    # Hooded/pointed Knight Lore guard helm + glowing crimson eyes inside visor shadow
    _sphere("GuardFaceShadow", "Head", (0.0, -0.02, 1.37), 0.145, (1.0, 0.95, 1.0), shadow_mat)
    for side_tag, sx in (("L", 0.055), ("R", -0.055)):
        _sphere(f"GuardEye_{side_tag}", "Head", (sx, -0.155, 1.38), 0.024, (1.1, 0.6, 0.8), eye_mat)
    _cyl("GuardHelmBody", "Head", (0.0, 0.0, 1.41), 0.175, 0.18, steel_mat)
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.185, radius2=0.025, depth=0.19, location=(0.0, 0.0, 1.56))
    crest = bpy.context.active_object
    crest.name = "GuardHelmPoint"
    crest.data.materials.append(steel_mat)
    _set_smooth(crest)
    _assign_bone_weight(crest, "Head", arm_obj)
    _box("GuardVisorBrow", "Head", (0.0, -0.135, 1.445), (0.26, 0.14, 0.055), steel_mat, bevel=0.015)

    # Crimson armored torso & skirted surcoat
    _box("GuardChest", "Chest", (0.0, 0.0, 1.15), (0.44, 0.28, 0.22), surcoat_mat, bevel=0.035)
    _box("GuardBreastplate", "Chest", (0.0, -0.06, 1.16), (0.36, 0.18, 0.17), steel_mat, bevel=0.025)
    _box("GuardSpine", "Spine", (0.0, 0.0, 0.98), (0.38, 0.25, 0.18), surcoat_mat, bevel=0.03)
    _box("GuardPelvis", "Hips", (0.0, 0.0, 0.83), (0.36, 0.25, 0.16), steel_mat, bevel=0.03)

    # Pauldrons, vambraces & gauntlets
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        _sphere(f"GuardPauldron_{side_tag}", f"{bone_prefix}UpperArm", (sign_x * 0.27, 0.0, 1.17), 1.0, (0.115, 0.115, 0.11), steel_mat)
        _cyl(f"GuardArmUp_{side_tag}", f"{bone_prefix}UpperArm", (sign_x * 0.30, 0.0, 1.09), 0.068, 0.18, surcoat_mat, rot=(0.0, -sign_x * math.radians(38.0), 0.0))
        _cyl(f"GuardArmLo_{side_tag}", f"{bone_prefix}LowerArm", (sign_x * 0.42, 0.0, 0.93), 0.060, 0.18, steel_mat, rot=(0.0, -sign_x * math.radians(35.0), 0.0))
        _box(f"GuardGauntlet_{side_tag}", f"{bone_prefix}Hand", (sign_x * 0.51, 0.0, 0.80), (0.10, 0.10, 0.12), steel_mat, bevel=0.02)

    # Steel cuisses, greaves & sabaton boots
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        _cyl(f"GuardThigh_{side_tag}", f"{bone_prefix}UpperLeg", (sign_x * 0.11, 0.0, 0.61), 0.082, 0.30, steel_mat)
        _cyl(f"GuardShin_{side_tag}", f"{bone_prefix}LowerLeg", (sign_x * 0.11, 0.0, 0.28), 0.072, 0.28, steel_mat)
        _box(f"GuardBoot_{side_tag}", f"{bone_prefix}Foot", (sign_x * 0.11, -0.04, 0.06), (0.14, 0.23, 0.12), surcoat_mat, bevel=0.025)


def build_prop_chest_knightlore(palette: list[tuple[float, float, float]]) -> None:
    """Arched barrel-lidded oak treasure chest matching sprite R06C06 & inspiration.png."""
    c_oak = (0.50, 0.31, 0.16)
    oak_mat = make_pbr_material("OakWood", (*c_oak, 1.0), metallic=0.04, roughness=0.64)
    oak_dark_mat = make_pbr_material("OakPanel", (0.36, 0.22, 0.11, 1.0), metallic=0.04, roughness=0.70)
    iron_mat = make_pbr_material("IronBands", (0.19, 0.21, 0.24, 1.0), metallic=0.86, roughness=0.40)
    brass_mat = make_pbr_material("BrassClasp", (0.86, 0.66, 0.24, 1.0), metallic=0.88, roughness=0.28)

    add_beveled_box("ChestBase", (0.0, 0.0, 0.28), (0.94, 0.88, 0.56), oak_mat, bevel_width=0.025)
    add_beveled_box("ChestPanelF", (0.0, -0.445, 0.26), (0.76, 0.03, 0.36), oak_dark_mat, bevel_width=0.008)
    # Barrel-vaulted arched lid (cylinder along X cresting at z = 0.56 + 0.44 = 1.00 m)
    lid = add_cylinder("ChestLidBarrel", (0.0, 0.0, 0.56), 0.44, 0.94, oak_mat, verts=18, rotation=(0.0, math.pi * 0.5, 0.0))
    _set_smooth(lid)
    for sx in (-0.28, 0.28):
        band_top = add_cylinder(f"IronArch_{sx:.2f}", (sx, 0.0, 0.56), 0.452, 0.095, iron_mat, verts=18, rotation=(0.0, math.pi * 0.5, 0.0))
        _set_smooth(band_top)
        add_beveled_box(f"IronStrap_{sx:.2f}", (sx, 0.0, 0.285), (0.095, 0.91, 0.57), iron_mat, bevel_width=0.01)
    add_beveled_box("RimTrim", (0.0, 0.0, 0.55), (0.96, 0.90, 0.06), iron_mat, bevel_width=0.01)
    add_beveled_box("LockClasp", (0.0, -0.46, 0.50), (0.16, 0.06, 0.20), brass_mat, bevel_width=0.012)
    for side in (-1.0, 1.0):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.085, minor_radius=0.02, location=(side * 0.48, 0.0, 0.34), rotation=(0.0, math.pi * 0.5, 0.0))
        ring = bpy.context.active_object
        ring.name = f"ChestHandle_{side:.0f}"
        ring.data.materials.append(iron_mat)
        _set_smooth(ring)


def build_prop_cauldron_knightlore(palette: list[tuple[float, float, float]]) -> None:
    """Squat cast-iron cauldron over hearth stones & embers matching sprite R09C13."""
    iron_mat = make_pbr_material("CastIron", (0.15, 0.17, 0.20, 1.0), metallic=0.72, roughness=0.46)
    stone_mat = make_pbr_material("HearthStone", (0.34, 0.33, 0.32, 1.0), metallic=0.04, roughness=0.86)
    ember_mat = make_pbr_material("HearthEmber", (0.95, 0.34, 0.08, 1.0), metallic=0.0, roughness=0.5, emission=(0.95, 0.34, 0.08), emission_strength=1.8)
    c_brew = (0.18, 0.92, 0.52)
    brew_mat = make_pbr_material("EmeraldBrew", (*c_brew, 1.0), metallic=0.05, roughness=0.22, emission=c_brew, emission_strength=2.6)

    for idx in range(8):
        ang = math.radians(idx * 45.0)
        st = add_uv_sphere(f"HearthStone_{idx}", (0.36 * math.cos(ang), 0.36 * math.sin(ang), 0.075), 0.11, stone_mat, scale=(1.0, 1.0, 0.68))
        _set_smooth(st)
    add_cylinder("EmberBed", (0.0, 0.0, 0.045), 0.28, 0.05, ember_mat, verts=14)

    belly = add_uv_sphere("CauldronBelly", (0.0, 0.0, 0.48), 0.44, iron_mat, scale=(1.04, 1.04, 0.78))
    _set_smooth(belly)
    neck = add_cylinder("CauldronNeck", (0.0, 0.0, 0.76), 0.37, 0.22, iron_mat, verts=20)
    _set_smooth(neck)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.39, minor_radius=0.055, location=(0.0, 0.0, 0.895))
    rim = bpy.context.active_object
    rim.name = "CauldronRim"
    rim.data.materials.append(iron_mat)
    _set_smooth(rim)
    add_cylinder("BrewSurface", (0.0, 0.0, 0.86), 0.35, 0.05, brew_mat, verts=20)
    for b_idx, (bx, by, br) in enumerate([(0.12, -0.10, 0.045), (-0.14, 0.06, 0.038), (0.02, 0.15, 0.030)]):
        bub = add_uv_sphere(f"BrewBubble_{b_idx}", (bx, by, 0.885), br, brew_mat)
        _set_smooth(bub)
    for idx, angle_deg in enumerate([0.0, 120.0, 240.0]):
        rad = math.radians(angle_deg)
        add_cylinder(f"Foot_{idx}", (0.24 * math.cos(rad), 0.24 * math.sin(rad), 0.12), 0.065, 0.24, iron_mat, verts=10)
    for side in (-1.0, 1.0):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.10, minor_radius=0.025, location=(side * 0.46, 0.0, 0.56), rotation=(0.0, math.pi * 0.5, 0.0))
        ring = bpy.context.active_object
        ring.name = f"Handle_{side:.0f}"
        ring.data.materials.append(iron_mat)
        _set_smooth(ring)


def build_prop_pillar_knightlore() -> None:
    """Stepped gothic stone column matching sprite R09C08 & R01C14-16 (3.5 m)."""
    stone_mat = make_pbr_material("GothicStone", (0.47, 0.46, 0.44, 1.0), metallic=0.04, roughness=0.78)
    trim_mat = make_pbr_material("StoneTrim", (0.37, 0.36, 0.34, 1.0), metallic=0.05, roughness=0.84)
    add_beveled_box("PlinthLower", (0.0, 0.0, 0.14), (0.96, 0.96, 0.28), trim_mat, bevel_width=0.025)
    add_beveled_box("PlinthUpper", (0.0, 0.0, 0.35), (0.80, 0.80, 0.14), stone_mat, bevel_width=0.02)
    add_cylinder("PillarShaft", (0.0, 0.0, 1.75), 0.35, 2.66, stone_mat, verts=8)
    for idx, cz in enumerate((1.05, 1.75, 2.45)):
        add_beveled_box(f"ShaftCollar_{idx}", (0.0, 0.0, cz), (0.74, 0.74, 0.10), trim_mat, bevel_width=0.015)
    add_beveled_box("CapitalLower", (0.0, 0.0, 3.15), (0.80, 0.80, 0.14), stone_mat, bevel_width=0.02)
    add_beveled_box("CapitalUpper", (0.0, 0.0, 3.36), (0.96, 0.96, 0.28), trim_mat, bevel_width=0.025)


def build_prop_arch_doorway() -> None:
    """Gothic pointed stone archway matching sprite R01C03-04 & inspiration.png (3.2 m tall)."""
    stone_mat = make_pbr_material("ArchStone", (0.46, 0.44, 0.41, 1.0), metallic=0.04, roughness=0.80)
    trim_mat = make_pbr_material("ArchTrim", (0.34, 0.32, 0.30, 1.0), metallic=0.06, roughness=0.84)

    # Clear 2.0m inner doorway span (x = -1.00 .. +1.00); stone jambs at x = +/- 1.15
    for side, sx in (("L", -1.15), ("R", 1.15)):
        add_beveled_box(f"JambBase_{side}", (sx, 0.0, 0.14), (0.36, 0.62, 0.28), trim_mat, bevel_width=0.02)
        for c_idx in range(4):
            cz = 0.47 + c_idx * 0.38
            mat_c = stone_mat if c_idx % 2 == 0 else trim_mat
            add_beveled_box(f"JambCourse_{side}_{c_idx}", (sx, 0.0, cz), (0.30, 0.56, 0.35), mat_c, bevel_width=0.02)
        add_beveled_box(f"JambImpost_{side}", (sx, 0.0, 1.94), (0.36, 0.62, 0.14), trim_mat, bevel_width=0.02)

    # Semicircular/pointed voussoir arch segments from x=-1.12..+1.12, z=1.98..3.18
    arch_center_z = 2.00
    arch_r = 1.10
    steps = 10
    for i in range(steps + 1):
        t = i / float(steps)
        ang = math.pi * (1.0 - t)
        vx = arch_r * math.cos(ang)
        vz = arch_center_z + 1.06 * math.sin(ang)
        tilt = (ang - math.pi * 0.5)
        is_key = (i == steps // 2)
        w = 0.30 if is_key else 0.26
        h = 0.34 if is_key else 0.26
        add_beveled_box(
            f"Voussoir_{i:02d}",
            (vx, 0.0, vz),
            (w, 0.60 if is_key else 0.56, h),
            trim_mat if is_key else stone_mat,
            bevel_width=0.02,
            rotation=(0.0, tilt, 0.0),
        )


def build_prop_door_trim_to_forest() -> None:
    """Subtle creeping ivy vines, delicate leaf clusters & corner moss hugging stone jambs (3.16m)."""
    vine_mat = make_pbr_material("IvyVineBark", (0.24, 0.18, 0.11, 1.0), metallic=0.02, roughness=0.88)
    moss_mat = make_pbr_material("ThresholdMoss", (0.19, 0.35, 0.15, 1.0), metallic=0.0, roughness=0.90)
    leaf_dark = make_pbr_material("IvyLeafDeep", (0.15, 0.41, 0.17, 1.0), metallic=0.0, roughness=0.78)
    leaf_bright = make_pbr_material("IvyLeafSun", (0.23, 0.52, 0.21, 1.0), metallic=0.0, roughness=0.74)

    # Symmetric low moss cushions tucked strictly around outer jamb plinths so normalize_static keeps (0, 0) centered
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            plinth_moss = _add_ico(
                f"JambMossAnchor_{sx:.0f}_{sy:.0f}",
                (sx * 1.16, sy * 0.29, 0.024),
                0.13,
                moss_mat,
                subdivisions=2,
                scale=(1.15, 0.85, 0.20),
            )
            _set_smooth(plinth_moss)

        # Creeping moss mound spilling softly inward only along the jamb foot corners (no middle lily-pads!)
        for c_idx, (ox, oy, orad, oscl) in enumerate([
            (sx * 1.02, -0.26, 0.12, (1.10, 0.80, 0.16)),
            (sx * 0.90, -0.20, 0.09, (1.25, 0.70, 0.12)),
            (sx * 0.96, -0.04, 0.09, (0.95, 1.10, 0.12)),
        ]):
            cm = _add_ico(f"CornerMoss_{sx:.0f}_{c_idx}", (ox, oy, 0.012), orad, moss_mat, subdivisions=2, scale=oscl)
            _set_smooth(cm)

        # Woody climbing ivy stems hugging flush against the room-facing stone jamb & inner reveal (y = -0.27..-0.18)
        ang_pts = [math.radians(a) for a in ((165, 146, 126, 108, 92) if sx < 0 else (15, 34, 54, 72, 88))]
        arch_spine = [
            (1.03 * math.cos(a), -0.265 if idx % 2 == 0 else -0.225, 2.00 + 1.02 * math.sin(a))
            for idx, a in enumerate(ang_pts)
        ]
        main_spine = [
            (sx * 1.10, -0.28, 0.015),
            (sx * 1.01, -0.27, 0.36),
            (sx * 1.04, -0.21, 0.78),
            (sx * 1.00, -0.27, 1.24),
            (sx * 1.03, -0.22, 1.72),
            (sx * 0.99, -0.26, 2.04),
            *arch_spine,
        ]
        rads = [0.032, 0.027, 0.024, 0.022, 0.020, 0.018, 0.016, 0.014, 0.012, 0.010, 0.008]
        _build_organic_tube(
            f"IvyVineMain_{sx:.0f}",
            main_spine,
            rads,
            vine_mat,
            sides=7,
            flute_amp=0.08,
            flute_freq=4,
            twist=sx * 2.0,
        )

        # Delicate secondary vine tendril hugging outer chamfer of the stone jamb
        sub_spine = [
            (sx * 1.05, -0.27, 0.95),
            (sx * 1.13, -0.28, 1.48),
            (sx * 1.06, -0.27, 1.96),
            (sx * 0.86, -0.275, 2.52),
        ]
        _build_organic_tube(f"IvyVineSub_{sx:.0f}", sub_spine, [0.016, 0.014, 0.012, 0.008], vine_mat, sides=6)

        # Subtle pointed ivy leaf sprays anchored tightly along the stone jambs & arch voussoirs
        leaf_nodes = [
            ((sx * 1.04, -0.29, 0.38), (-sx * 0.25, -0.45, 0.80), 8, 0.125, 0.070),
            ((sx * 1.04, -0.28, 0.94), (-sx * 0.20, -0.45, 0.80), 9, 0.135, 0.075),
            ((sx * 1.02, -0.28, 1.56), (-sx * 0.28, -0.45, 0.75), 9, 0.140, 0.075),
            ((sx * 0.96, -0.28, 2.18), (-sx * 0.32, -0.45, 0.70), 9, 0.140, 0.075),
            ((sx * 0.72, -0.28, 2.72), (-sx * 0.22, -0.45, 0.75), 9, 0.135, 0.075),
            ((sx * 0.26, -0.28, 3.00), (0.0, -0.40, 0.85), 8, 0.125, 0.070),
        ]
        for l_idx, (lc, ld, cnt, ll, lw) in enumerate(leaf_nodes):
            _add_leaf_cluster_fronds(
                f"IvyLeaves_{sx:.0f}_{l_idx}",
                lc,
                ld,
                cnt,
                ll,
                lw,
                leaf_bright if l_idx % 2 == 1 else leaf_dark,
                moss_mat,
                seed=700 + (0 if sx < 0 else 50) + l_idx,
            )

        # Scattered tiny fallen leaves resting cleanly by the jamb threshold corners (symmetric in X)
        _add_leaf_cluster_fronds(
            f"ThresholdCornerLeaves_{sx:.0f}",
            (sx * 0.86, -0.26, 0.014),
            (-sx * 0.7, -0.65, 0.18),
            6,
            0.10,
            0.055,
            leaf_dark,
            leaf_bright,
            seed=860 + (0 if sx < 0 else 10),
        )


def build_prop_door_trim_to_stone() -> None:
    """Weathered ancient ashlar stone jambs, arch keystone fragments & embedded stepping flagstones for Forest->Stone exits (3.12m)."""
    granite_mat = make_pbr_material("TransitionGranite", (0.50, 0.49, 0.46, 1.0), metallic=0.04, roughness=0.80)
    trim_mat = make_pbr_material("TransitionStoneDark", (0.37, 0.36, 0.34, 1.0), metallic=0.05, roughness=0.84)
    moss_mat = make_pbr_material("TransitionStoneMoss", (0.22, 0.38, 0.18, 1.0), metallic=0.0, roughness=0.88)

    # Ruined weathered stone plinth courses flanking inner-base of the tree arch
    left_blocks = [
        ((-1.08, 0.0, 0.14), (0.30, 0.56, 0.28), trim_mat),
        ((-1.10, 0.0, 0.42), (0.26, 0.52, 0.26), granite_mat),
        ((-1.12, 0.0, 0.67), (0.22, 0.46, 0.22), trim_mat),
    ]
    right_blocks = [
        ((1.08, 0.0, 0.14), (0.30, 0.56, 0.28), trim_mat),
        ((1.10, 0.0, 0.40), (0.24, 0.50, 0.24), granite_mat),
    ]
    for b_idx, (pos, sz, mat) in enumerate(left_blocks + right_blocks):
        add_beveled_box(f"RuinJambStone_{b_idx}", pos, sz, mat, bevel_width=0.022)

    # Subtle weathered stone arch voussoirs & keystone peeking from the crown of the living tree arch
    arch_center_z = 2.00
    arch_r = 1.07
    for idx, deg in enumerate((66.0, 78.0, 90.0, 102.0, 114.0)):
        ang = math.radians(deg)
        vx = arch_r * math.cos(ang)
        vz = arch_center_z + 1.04 * math.sin(ang)
        tilt = ang - math.pi * 0.5
        is_key = (deg == 90.0)
        add_beveled_box(
            f"RuinArchVoussoir_{idx}",
            (vx, 0.0, vz),
            (0.26 if is_key else 0.22, 0.52 if is_key else 0.46, 0.22 if is_key else 0.18),
            granite_mat if is_key else trim_mat,
            bevel_width=0.02,
            rotation=(0.0, tilt, 0.0),
        )

    # Symmetric tiny mossy anchor pebbles & mossy ledges so bounding box stays exact around (0, 0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            add_beveled_box(f"AnchorCornerStone_{sx:.0f}_{sy:.0f}", (sx * 1.18, sy * 0.36, 0.018), (0.14, 0.14, 0.036), moss_mat, bevel_width=0.008)

    # Embedded weathered granite stepping flagstones gently surfacing from the woodland floor
    flag_specs = [
        (-0.56, -0.18, 0.50, 0.36, 0.034, 8.0, granite_mat),
        (0.06, -0.22, 0.58, 0.34, 0.036, -5.0, trim_mat),
        (0.60, -0.16, 0.46, 0.34, 0.032, 11.0, granite_mat),
        (-0.52, 0.18, 0.48, 0.34, 0.034, -9.0, trim_mat),
        (0.02, 0.20, 0.56, 0.36, 0.036, 6.0, granite_mat),
        (0.56, 0.18, 0.46, 0.32, 0.032, -7.0, trim_mat),
        (-0.24, 0.01, 0.44, 0.28, 0.028, 4.0, granite_mat),
        (0.30, -0.01, 0.42, 0.28, 0.028, -4.0, granite_mat),
    ]
    for f_idx, (fx, fy, fw, fd, fh, rot_deg, fmat) in enumerate(flag_specs):
        add_beveled_box(
            f"SteppingFlagstone_{f_idx}",
            (fx, fy, fh * 0.5),
            (fw, fd, fh),
            fmat,
            bevel_width=0.012,
            rotation=(0.0, 0.0, math.radians(rot_deg)),
        )


def build_prop_wall_panel() -> None:
    """Modular gothic stone masonry relief panel matching R01C11-16 (2.0w x 6.0h x 0.24d)."""
    wall_mat = make_pbr_material("WallBase", (0.42, 0.40, 0.38, 1.0), metallic=0.0, roughness=0.86)
    stone_mat = make_pbr_material("WallBrickA", (0.46, 0.43, 0.39, 1.0), metallic=0.03, roughness=0.82)
    dark_mat = make_pbr_material("WallBrickB", (0.35, 0.33, 0.31, 1.0), metallic=0.04, roughness=0.88)

    add_beveled_box("BasePlinth", (0.0, 0.0, 0.18), (2.0, 0.24, 0.36), dark_mat, bevel_width=0.02)
    # Staggered relief ashlar stone courses along lower & upper wall faces
    brick_rows = [
        (0.60, [(-0.52, 0.88), (0.48, 0.88)], stone_mat),
        (1.08, [(-0.68, 0.56), (0.0, 0.72), (0.68, 0.56)], dark_mat),
        (1.58, [(-0.46, 0.84), (0.50, 0.80)], stone_mat),
        (2.85, [(-0.60, 0.70), (0.55, 0.74)], dark_mat),
        (4.15, [(-0.50, 0.82), (0.46, 0.84)], stone_mat),
        (5.30, [(-0.64, 0.62), (0.02, 0.68), (0.66, 0.60)], dark_mat),
    ]
    for r_idx, (rz, blocks, bmat) in enumerate(brick_rows):
        for b_idx, (bx, bw) in enumerate(blocks):
            add_beveled_box(f"Brick_{r_idx}_{b_idx}", (bx, 0.0, rz), (bw, 0.18, 0.38), bmat, bevel_width=0.025)

    add_beveled_box("WallBackPlate", (0.0, 0.04, 3.00), (1.98, 0.12, 5.40), wall_mat, bevel_width=0.01)
    add_beveled_box("TopCoping", (0.0, 0.0, 5.84), (2.0, 0.26, 0.32), dark_mat, bevel_width=0.025)


def build_prop_wall_lintel_panel() -> None:
    """Upper stone lintel masonry & coping cornice continuing wall_stone_panel above doorways (2.0w x 3.0h x 0.24d)."""
    wall_mat = make_pbr_material("WallBase", (0.42, 0.40, 0.38, 1.0), metallic=0.0, roughness=0.86)
    stone_mat = make_pbr_material("WallBrickA", (0.46, 0.43, 0.39, 1.0), metallic=0.03, roughness=0.82)
    dark_mat = make_pbr_material("WallBrickB", (0.35, 0.33, 0.31, 1.0), metallic=0.04, roughness=0.88)

    add_beveled_box("WallBackPlate", (0.0, 0.04, 1.42), (1.98, 0.12, 2.84), wall_mat, bevel_width=0.01)
    brick_rows = [
        (1.15, [(-0.50, 0.82), (0.46, 0.84)], stone_mat),
        (2.30, [(-0.64, 0.62), (0.02, 0.68), (0.66, 0.60)], dark_mat),
    ]
    for r_idx, (rz, blocks, bmat) in enumerate(brick_rows):
        for b_idx, (bx, bw) in enumerate(blocks):
            add_beveled_box(f"Brick_{r_idx}_{b_idx}", (bx, 0.0, rz), (bw, 0.18, 0.38), bmat, bevel_width=0.025)

    add_beveled_box("TopCoping", (0.0, 0.0, 2.84), (2.0, 0.26, 0.32), dark_mat, bevel_width=0.025)


def build_prop_portcullis() -> None:
    """Iron spear-tipped lattice portcullis gate matching sprite R01C09-10 (1.9w x 2.6h)."""
    iron_mat = make_pbr_material("PortcullisIron", (0.22, 0.23, 0.26, 1.0), metallic=0.86, roughness=0.44)
    tip_mat = make_pbr_material("PortcullisSteel", (0.40, 0.42, 0.46, 1.0), metallic=0.90, roughness=0.34)

    for sx in (-0.88, 0.88):
        add_beveled_box(f"FrameVert_{sx:.2f}", (sx, 0.0, 1.32), (0.12, 0.18, 2.56), iron_mat, bevel_width=0.012)
    for hz in (0.36, 1.06, 1.78, 2.50):
        add_beveled_box(f"CrossBar_{hz:.2f}", (0.0, 0.0, hz), (1.88, 0.16, 0.11), iron_mat, bevel_width=0.012)
    for bx in (-0.60, -0.30, 0.0, 0.30, 0.60):
        add_cylinder(f"SpikeShaft_{bx:.2f}", (bx, 0.0, 1.34), 0.042, 2.28, iron_mat, verts=10)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.055, radius2=0.005, depth=0.22, location=(bx, 0.0, 0.11), rotation=(math.pi, 0.0, 0.0))
        tip = bpy.context.active_object
        tip.name = f"SpikeTip_{bx:.2f}"
        tip.data.materials.append(tip_mat)
        for hz in (0.36, 1.06, 1.78):
            add_beveled_box(f"Rivet_{bx:.2f}_{hz:.2f}", (bx, 0.0, hz), (0.09, 0.20, 0.09), tip_mat, bevel_width=0.008)


def build_prop_stone_block() -> None:
    """Carved masonry block matching sprites R01C08, R04C07-08 & inspiration.png (1.0 m cube)."""
    stone_mat = make_pbr_material("BlockStone", (0.56, 0.49, 0.40, 1.0), metallic=0.02, roughness=0.76)
    mortar_mat = make_pbr_material("BlockMortar", (0.43, 0.38, 0.32, 1.0), metallic=0.02, roughness=0.84)
    add_beveled_box("BlockLower", (0.0, 0.0, 0.15), (0.98, 0.98, 0.30), stone_mat, bevel_width=0.025)
    add_beveled_box("BlockMortarBand", (0.0, 0.0, 0.36), (0.92, 0.92, 0.12), mortar_mat, bevel_width=0.012)
    add_beveled_box("BlockUpper", (0.0, 0.0, 0.60), (0.98, 0.98, 0.36), stone_mat, bevel_width=0.025)
    add_beveled_box("BlockCap", (0.0, 0.0, 0.89), (1.00, 1.00, 0.22), stone_mat, bevel_width=0.03)


def build_prop_moving_platform() -> None:
    """Carved floating slate platform (1.9w x 0.35h x 1.9d)."""
    slate_mat = make_pbr_material("PlatformSlate", (0.44, 0.50, 0.56, 1.0), metallic=0.15, roughness=0.65)
    trim_mat = make_pbr_material("PlatformTrim", (0.30, 0.35, 0.41, 1.0), metallic=0.25, roughness=0.58)
    brass_mat = make_pbr_material("PlatformRune", (0.82, 0.64, 0.26, 1.0), metallic=0.85, roughness=0.30)
    add_beveled_box("PlatCore", (0.0, 0.0, 0.12), (1.82, 1.82, 0.24), trim_mat, bevel_width=0.03)
    add_beveled_box("PlatTop", (0.0, 0.0, 0.285), (1.90, 1.90, 0.13), slate_mat, bevel_width=0.025)
    for sx in (-0.80, 0.80):
        for sy in (-0.80, 0.80):
            add_beveled_box(f"PlatLug_{sx:.1f}_{sy:.1f}", (sx, sy, 0.305), (0.18, 0.18, 0.09), brass_mat, bevel_width=0.01)


def build_prop_collapsing_tile() -> None:
    """Fractured stone slab made of 4 cracked beveled shards (0.98w x 0.25h x 0.98d)."""
    shard_mat = make_pbr_material("CrackedStone", (0.54, 0.42, 0.34, 1.0), metallic=0.02, roughness=0.88)
    crack_mat = make_pbr_material("FissureCore", (0.20, 0.16, 0.14, 1.0), metallic=0.0, roughness=0.94)
    add_beveled_box("CrackCore", (0.0, 0.0, 0.07), (0.90, 0.90, 0.14), crack_mat, bevel_width=0.01)
    for sx in (-0.23, 0.23):
        for sy in (-0.23, 0.23):
            add_beveled_box(f"Shard_{sx:.2f}_{sy:.2f}", (sx, sy, 0.17), (0.43, 0.43, 0.16), shard_mat, bevel_width=0.022)


def build_prop_pressure_plate() -> None:
    """Stone-beveled brass floor trigger plate (0.86w x 0.10h x 0.86d)."""
    stone_mat = make_pbr_material("PlateSurround", (0.36, 0.35, 0.34, 1.0), metallic=0.05, roughness=0.82)
    brass_mat = make_pbr_material("BrassPad", (0.78, 0.58, 0.24, 1.0), metallic=0.82, roughness=0.34)
    add_beveled_box("PlateFrame", (0.0, 0.0, 0.025), (0.86, 0.86, 0.05), stone_mat, bevel_width=0.012)
    add_beveled_box("BrassTrigger", (0.0, 0.0, 0.07), (0.64, 0.64, 0.06), brass_mat, bevel_width=0.012)
    for sx in (-0.34, 0.34):
        for sy in (-0.34, 0.34):
            add_cylinder(f"CornerRivet_{sx:.2f}_{sy:.2f}", (sx, sy, 0.055), 0.032, 0.025, brass_mat, verts=8)


def _add_cone(
    name: str,
    center: tuple[float, float, float],
    r1: float,
    r2: float,
    depth: float,
    mat: bpy.types.Material,
    verts: int = 12,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=center, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def _add_ico(
    name: str,
    center: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    subdivisions: int = 1,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation != (0.0, 0.0, 0.0):
        obj.rotation_euler = rotation
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(mat)
    return obj


def build_prop_tree_wall_panel() -> None:
    """Modular Knight Lore woodland wall panel with gnarled trunks, crooked branches & leaf sprays (2.0w x 6.0h)."""
    bark_mat = make_pbr_material("ForestBark", (0.30, 0.20, 0.12, 1.0), metallic=0.02, roughness=0.88)
    bark_dark = make_pbr_material("ForestBarkDark", (0.21, 0.14, 0.09, 1.0), metallic=0.02, roughness=0.90)
    moss_mat = make_pbr_material("ForestMoss", (0.20, 0.38, 0.17, 1.0), metallic=0.0, roughness=0.86)
    leaf_mat = make_pbr_material("ForestCanopy", (0.16, 0.46, 0.20, 1.0), metallic=0.0, roughness=0.76)
    leaf_hi = make_pbr_material("ForestCanopyBright", (0.25, 0.56, 0.26, 1.0), metallic=0.0, roughness=0.72)

    # Mossy forest floor edge + recessed dark woodland canopy backdrop
    add_beveled_box("RootPlinth", (0.0, 0.02, 0.11), (2.0, 0.28, 0.22), moss_mat, bevel_width=0.02)
    add_beveled_box("FoliageBack", (0.0, 0.06, 3.00), (1.98, 0.10, 5.70), bark_dark, bevel_width=0.01)

    # Three gnarled S-curved fluted tree trunks with buttress roots & forked branches
    trunk_specs = [
        (
            -0.66,
            [(-0.68, -0.02, 0.02), (-0.72, -0.06, 0.65), (-0.61, -0.04, 1.75), (-0.69, -0.06, 3.05), (-0.60, -0.04, 4.35), (-0.64, -0.02, 5.25)],
            [0.23, 0.17, 0.145, 0.135, 0.115, 0.075],
            bark_mat,
            [
                ([(-0.63, -0.04, 3.70), (-0.82, -0.08, 4.25), (-0.94, -0.10, 4.85)], [0.08, 0.055, 0.03]),
                ([(-0.61, -0.04, 4.20), (-0.36, -0.08, 4.78), (-0.18, -0.10, 5.30)], [0.075, 0.05, 0.025]),
            ],
        ),
        (
            0.02,
            [(0.02, -0.03, 0.02), (-0.04, -0.07, 0.80), (0.07, -0.05, 1.95), (-0.03, -0.07, 3.25), (0.06, -0.05, 4.45), (0.00, -0.03, 5.45)],
            [0.25, 0.19, 0.16, 0.145, 0.12, 0.075],
            bark_dark,
            [
                ([(0.02, -0.05, 3.90), (-0.28, -0.09, 4.52), (-0.48, -0.11, 5.10)], [0.08, 0.052, 0.025]),
                ([(0.04, -0.05, 4.35), (0.34, -0.09, 4.95), (0.52, -0.11, 5.55)], [0.075, 0.05, 0.025]),
            ],
        ),
        (
            0.68,
            [(0.68, -0.02, 0.02), (0.74, -0.06, 0.72), (0.62, -0.04, 1.85), (0.71, -0.06, 3.10), (0.63, -0.04, 4.30), (0.67, -0.02, 5.20)],
            [0.22, 0.165, 0.14, 0.13, 0.11, 0.07],
            bark_mat,
            [
                ([(0.65, -0.04, 3.85), (0.40, -0.08, 4.45), (0.22, -0.10, 5.02)], [0.075, 0.05, 0.025]),
                ([(0.66, -0.04, 4.25), (0.86, -0.08, 4.80), (0.95, -0.10, 5.38)], [0.07, 0.048, 0.022]),
            ],
        ),
    ]
    for t_idx, (_, spine, rads, mat, branches) in enumerate(trunk_specs):
        _build_organic_tube(f"TreeTrunk_{t_idx}", spine, rads, mat, sides=10, flute_amp=0.14, flute_freq=6, twist=1.5)
        for b_idx, (b_spine, b_rads) in enumerate(branches):
            _build_organic_tube(f"Branch_{t_idx}_{b_idx}", b_spine, b_rads, mat, sides=7, flute_amp=0.08, flute_freq=4, twist=0.8)

    # Layered leaf frond sprays anchored at branch tips (z = 4.3..6.0)
    spray_defs = [
        ((-0.82, -0.08, 4.70), (-0.4, -0.4, 0.8), 16, 0.38, 0.18, leaf_mat, moss_mat),
        ((-0.52, -0.09, 5.28), (-0.1, -0.4, 0.9), 18, 0.42, 0.19, leaf_hi, leaf_mat),
        ((-0.18, -0.08, 5.55), (0.1, -0.35, 0.9), 18, 0.44, 0.20, leaf_hi, leaf_mat),
        ((0.20, -0.09, 5.15), (0.0, -0.45, 0.8), 16, 0.40, 0.19, leaf_mat, moss_mat),
        ((0.52, -0.09, 5.48), (0.2, -0.35, 0.9), 18, 0.44, 0.20, leaf_hi, leaf_mat),
        ((0.84, -0.08, 4.92), (0.4, -0.4, 0.8), 16, 0.38, 0.18, leaf_mat, moss_mat),
        ((0.02, -0.05, 5.82), (0.0, -0.25, 0.95), 14, 0.38, 0.18, leaf_hi, leaf_mat),
    ]
    for s_idx, (c_pt, d_vec, cnt, ll, lw, ma, mb) in enumerate(spray_defs):
        _add_leaf_cluster_fronds(f"LeafSpray_{s_idx}", c_pt, d_vec, cnt, ll, lw, ma, mb, seed=100 + s_idx)


def build_prop_tree_lintel_panel() -> None:
    """Upper woodland trunks, branches & top canopy matching tree_wall_panel above doorways (2.0w x 3.0h)."""
    bark_mat = make_pbr_material("ForestBark", (0.30, 0.20, 0.12, 1.0), metallic=0.02, roughness=0.88)
    bark_dark = make_pbr_material("ForestBarkDark", (0.21, 0.14, 0.09, 1.0), metallic=0.02, roughness=0.90)
    moss_mat = make_pbr_material("ForestMoss", (0.20, 0.38, 0.17, 1.0), metallic=0.0, roughness=0.86)
    leaf_mat = make_pbr_material("ForestCanopy", (0.16, 0.46, 0.20, 1.0), metallic=0.0, roughness=0.76)
    leaf_hi = make_pbr_material("ForestCanopyBright", (0.25, 0.56, 0.26, 1.0), metallic=0.0, roughness=0.72)

    # Flush recessed dark backdrop plate matching FoliageBack (z = 3.0..6.0 shifted to 0.0..3.0)
    add_beveled_box("LintelBack", (0.0, 0.06, 1.48), (1.98, 0.10, 2.94), bark_dark, bevel_width=0.01)

    # Three slender vertical upper trunks + forked upper branches matching build_prop_tree_wall_panel()
    upper_trunk_specs = [
        (
            [(-0.69, -0.06, 0.02), (-0.64, -0.05, 0.72), (-0.60, -0.04, 1.38), (-0.64, -0.02, 2.25)],
            [0.135, 0.125, 0.115, 0.075],
            bark_mat,
            [
                ([(-0.63, -0.04, 0.70), (-0.82, -0.08, 1.25), (-0.94, -0.10, 1.85)], [0.08, 0.055, 0.03]),
                ([(-0.61, -0.04, 1.20), (-0.36, -0.08, 1.78), (-0.18, -0.10, 2.30)], [0.075, 0.05, 0.025]),
            ],
        ),
        (
            [(-0.03, -0.07, 0.02), (0.02, -0.06, 0.80), (0.06, -0.05, 1.48), (0.00, -0.03, 2.45)],
            [0.145, 0.132, 0.120, 0.075],
            bark_dark,
            [
                ([(0.02, -0.05, 0.90), (-0.28, -0.09, 1.52), (-0.48, -0.11, 2.10)], [0.08, 0.052, 0.025]),
                ([(0.04, -0.05, 1.35), (0.34, -0.09, 1.95), (0.52, -0.11, 2.55)], [0.075, 0.05, 0.025]),
            ],
        ),
        (
            [(0.71, -0.06, 0.02), (0.66, -0.05, 0.68), (0.63, -0.04, 1.32), (0.67, -0.02, 2.20)],
            [0.130, 0.120, 0.110, 0.070],
            bark_mat,
            [
                ([(0.65, -0.04, 0.85), (0.40, -0.08, 1.45), (0.22, -0.10, 2.02)], [0.075, 0.05, 0.025]),
                ([(0.66, -0.04, 1.25), (0.86, -0.08, 1.80), (0.95, -0.10, 2.38)], [0.07, 0.048, 0.022]),
            ],
        ),
    ]
    for t_idx, (spine, rads, mat, branches) in enumerate(upper_trunk_specs):
        _build_organic_tube(f"LintelTrunk_{t_idx}", spine, rads, mat, sides=10, flute_amp=0.14, flute_freq=6, twist=1.5)
        for b_idx, (b_spine, b_rads) in enumerate(branches):
            _build_organic_tube(f"LintelBranch_{t_idx}_{b_idx}", b_spine, b_rads, mat, sides=7, flute_amp=0.08, flute_freq=4, twist=0.8)

    # Seven upper-canopy leaf sprays matching build_prop_tree_wall_panel() shifted by z - 3.0m
    spray_specs = [
        ((-0.82, -0.08, 1.70), (-0.4, -0.4, 0.8), 16, 0.38, 0.18, leaf_mat, moss_mat),
        ((-0.52, -0.09, 2.28), (-0.1, -0.4, 0.9), 18, 0.42, 0.19, leaf_hi, leaf_mat),
        ((-0.18, -0.08, 2.55), (0.1, -0.35, 0.9), 18, 0.44, 0.20, leaf_hi, leaf_mat),
        ((0.20, -0.09, 2.15), (0.0, -0.45, 0.8), 16, 0.40, 0.19, leaf_mat, moss_mat),
        ((0.52, -0.09, 2.48), (0.2, -0.35, 0.9), 18, 0.44, 0.20, leaf_hi, leaf_mat),
        ((0.84, -0.08, 1.92), (0.4, -0.4, 0.8), 16, 0.38, 0.18, leaf_mat, moss_mat),
        ((0.02, -0.05, 2.82), (0.0, -0.25, 0.95), 14, 0.38, 0.18, leaf_hi, leaf_mat),
    ]
    for s_idx, (c_pt, d_vec, cnt, ll, lw, ma, mb) in enumerate(spray_specs):
        _add_leaf_cluster_fronds(f"LintelSpray_{s_idx}", c_pt, d_vec, cnt, ll, lw, ma, mb, seed=220 + s_idx)


def build_prop_low_wall_stone() -> None:
    """Modular low dungeon masonry parapet wall for foreground South/East room edges (2.0w x 0.44h x 0.50d)."""
    brick_a = make_pbr_material("LowWallBrickA", (0.45, 0.43, 0.40, 1.0), metallic=0.03, roughness=0.82)
    brick_b = make_pbr_material("LowWallBrickB", (0.34, 0.32, 0.30, 1.0), metallic=0.04, roughness=0.86)

    add_beveled_box("LowWallPlinth", (0.0, 0.0, 0.04), (2.00, 0.48, 0.08), brick_b, bevel_width=0.015)

    # Lower staggered ashlar course (z = 0.15)
    for idx, (bx, bw, mat) in enumerate([(-0.67, 0.64, brick_a), (0.0, 0.66, brick_b), (0.67, 0.64, brick_a)]):
        add_beveled_box(f"LowBrickA_{idx}", (bx, 0.0, 0.15), (bw, 0.46, 0.14), mat, bevel_width=0.018)

    # Upper staggered ashlar course (z = 0.29)
    for idx, (bx, bw, mat) in enumerate([(-0.83, 0.32, brick_b), (-0.32, 0.66, brick_a), (0.34, 0.64, brick_b), (0.83, 0.32, brick_a)]):
        add_beveled_box(f"LowBrickB_{idx}", (bx, 0.0, 0.29), (bw, 0.46, 0.14), mat, bevel_width=0.018)

    # Chamfered coping capstones (z = 0.40, height reaches 0.44m)
    for idx, (cx, cw) in enumerate([(-0.66, 0.66), (0.0, 0.64), (0.66, 0.66)]):
        add_beveled_box(f"LowCoping_{idx}", (cx, 0.0, 0.40), (cw, 0.50, 0.08), brick_b, bevel_width=0.018)


def build_prop_low_wall_woodland() -> None:
    """Modular low woodland moss bank, intertwined roots & leafy shrubs for foreground edges (2.0w x 0.54h x 0.52d)."""
    bark_mat = make_pbr_material("LowForestBark", (0.29, 0.20, 0.12, 1.0), metallic=0.02, roughness=0.88)
    bark_dark = make_pbr_material("LowForestBank", (0.21, 0.14, 0.09, 1.0), metallic=0.02, roughness=0.92)
    moss_mat = make_pbr_material("LowForestMoss", (0.19, 0.37, 0.16, 1.0), metallic=0.0, roughness=0.88)
    leaf_mat = make_pbr_material("LowForestLeaf", (0.17, 0.46, 0.19, 1.0), metallic=0.0, roughness=0.76)
    leaf_hi = make_pbr_material("LowForestLeafBright", (0.25, 0.56, 0.25, 1.0), metallic=0.0, roughness=0.72)

    # Symmetric earthen root curb core + mossy cushions centered around (0, 0)
    add_beveled_box("RootCurbBank", (0.0, 0.0, 0.10), (2.00, 0.46, 0.20), bark_dark, bevel_width=0.025)
    for idx, mx in enumerate((-0.78, -0.28, 0.28, 0.78)):
        cushion = _add_ico(f"BankMoss_{idx}", (mx, 0.0, 0.18), 0.20, moss_mat, subdivisions=2, scale=(1.35, 1.10, 0.45))
        _set_smooth(cushion)

    # Two intertwined horizontal creeping gnarled roots / vines spanning full 2.0m width
    _build_organic_tube(
        "CreepingRootA",
        [(-0.98, -0.06, 0.18), (-0.52, -0.14, 0.25), (0.0, 0.04, 0.22), (0.52, -0.14, 0.27), (0.98, -0.06, 0.19)],
        [0.085, 0.078, 0.082, 0.076, 0.085],
        bark_mat,
        sides=7,
        flute_amp=0.10,
        flute_freq=5,
        twist=1.4,
    )
    _build_organic_tube(
        "CreepingRootB",
        [(-0.98, 0.08, 0.20), (-0.48, 0.13, 0.26), (0.02, -0.05, 0.25), (0.48, 0.13, 0.24), (0.98, 0.08, 0.20)],
        [0.075, 0.072, 0.078, 0.070, 0.075],
        bark_dark,
        sides=7,
        flute_amp=0.10,
        flute_freq=5,
        twist=-1.2,
    )

    # Six compact low woodland shrub & fern leaf clusters reaching z ~ 0.54m
    for s_idx, sx in enumerate((-0.82, -0.49, -0.16, 0.16, 0.49, 0.82)):
        _add_leaf_cluster_fronds(
            f"LowShrub_{s_idx}",
            (sx, 0.0, 0.25),
            (0.0, -0.18 if s_idx % 2 == 0 else 0.18, 0.96),
            12,
            0.25,
            0.115,
            leaf_hi if s_idx % 2 == 0 else leaf_mat,
            moss_mat,
            seed=910 + s_idx,
        )


def build_prop_tree_arch_doorway() -> None:
    """Living intertwined gnarled woodland archway with clear 2.0m inner opening (3.2m tall)."""
    bark_mat = make_pbr_material("ArchBark", (0.30, 0.20, 0.12, 1.0), metallic=0.02, roughness=0.88)
    moss_mat = make_pbr_material("ArchMoss", (0.20, 0.42, 0.19, 1.0), metallic=0.0, roughness=0.84)
    leaf_mat = make_pbr_material("ArchLeaf", (0.18, 0.50, 0.22, 1.0), metallic=0.0, roughness=0.76)
    leaf_hi = make_pbr_material("ArchLeafBright", (0.26, 0.58, 0.27, 1.0), metallic=0.0, roughness=0.72)

    # Left and right gnarled root-flared trunks curving smoothly into an arched crest at z ~ 3.0m
    for side, sx in (("L", -1.0), ("R", 1.0)):
        spine = [
            (sx * 1.24, -0.02, 0.0),
            (sx * 1.18, -0.04, 0.42),
            (sx * 1.14, 0.03, 1.10),
            (sx * 1.13, -0.03, 1.78),
            (sx * 0.96, 0.02, 2.38),
            (sx * 0.58, -0.03, 2.82),
            (sx * 0.14, 0.02, 2.98),
            (-sx * 0.24, 0.04, 2.92),
        ]
        radii = [0.28, 0.21, 0.18, 0.165, 0.15, 0.135, 0.11, 0.065]
        _build_organic_tube(f"LivingArchTrunk_{side}", spine, radii, bark_mat, sides=10, flute_amp=0.14, flute_freq=6, twist=sx * 1.8)
        # Flared root tendril & crooked upper branch
        _build_organic_tube(f"ArchRootTendril_{side}", [(sx * 1.16, 0.0, 0.35), (sx * 1.32, -0.14, 0.10), (sx * 1.36, -0.20, 0.01)], [0.11, 0.08, 0.04], moss_mat, sides=7)
        _build_organic_tube(f"ArchSideTwig_{side}", [(sx * 0.92, -0.02, 2.40), (sx * 1.16, -0.10, 2.75), (sx * 1.24, -0.12, 3.04)], [0.065, 0.042, 0.02], bark_mat, sides=6)

    for s_idx, (c_pt, d_vec, cnt) in enumerate([
        ((-0.98, -0.05, 2.52), (-0.4, -0.3, 0.85), 14),
        ((-0.62, -0.04, 2.86), (-0.2, -0.3, 0.9), 14),
        ((-0.18, -0.03, 3.04), (0.0, -0.2, 0.98), 16),
        ((0.24, -0.03, 3.02), (0.0, -0.2, 0.98), 16),
        ((0.68, -0.04, 2.84), (0.2, -0.3, 0.9), 14),
        ((1.00, -0.05, 2.50), (0.4, -0.3, 0.85), 14),
    ]):
        _add_leaf_cluster_fronds(f"ArchLeafSpray_{s_idx}", c_pt, d_vec, cnt, 0.32, 0.15, leaf_hi if s_idx % 2 == 0 else leaf_mat, moss_mat, seed=310 + s_idx)


def build_prop_table() -> None:
    """Clean medieval planked oak table with turned legs & apron rails (zero under-table floaters, 0.75h)."""
    oak_mat = make_pbr_material("TableOak", (0.48, 0.30, 0.16, 1.0), metallic=0.04, roughness=0.66)
    oak_dark = make_pbr_material("TableApron", (0.34, 0.21, 0.11, 1.0), metallic=0.04, roughness=0.72)

    # Multi-plank tabletop with subtle dark seam plate
    add_beveled_box("TableUnderFrame", (0.0, 0.0, 0.65), (0.90, 0.90, 0.04), oak_dark, bevel_width=0.008)
    for idx, px in enumerate((-0.315, 0.0, 0.315)):
        add_beveled_box(f"TablePlank_{idx}", (px, 0.0, 0.70), (0.305, 0.94, 0.10), oak_mat, bevel_width=0.018)

    # Flush perimeter apron rails connecting corners (no loose middle crossbars!)
    add_beveled_box("ApronN", (0.0, 0.36, 0.565), (0.76, 0.075, 0.13), oak_dark, bevel_width=0.012)
    add_beveled_box("ApronS", (0.0, -0.36, 0.565), (0.76, 0.075, 0.13), oak_dark, bevel_width=0.012)
    add_beveled_box("ApronW", (-0.36, 0.0, 0.565), (0.075, 0.76, 0.13), oak_dark, bevel_width=0.012)
    add_beveled_box("ApronE", (0.36, 0.0, 0.565), (0.075, 0.76, 0.13), oak_dark, bevel_width=0.012)

    # Four sculpted turned legs cleanly grounded from z=0.0 up into apron corners
    def _leg_ring(cx: float, cy: float, cz: float, r: float, sides: int = 8) -> list[tuple[float, float, float]]:
        return [(cx + r * math.cos(2.0 * math.pi * j / sides), cy + r * math.sin(2.0 * math.pi * j / sides), cz) for j in range(sides)]

    for sx in (-0.36, 0.36):
        for sy in (-0.36, 0.36):
            rings = [
                _leg_ring(sx, sy, 0.00, 0.062),
                _leg_ring(sx, sy, 0.07, 0.072),
                _leg_ring(sx, sy, 0.14, 0.048),
                _leg_ring(sx, sy, 0.32, 0.058),
                _leg_ring(sx, sy, 0.45, 0.046),
                _leg_ring(sx, sy, 0.52, 0.068),
                _leg_ring(sx, sy, 0.65, 0.068),
            ]
            _loft_rings(f"TableTurnedLeg_{sx:.2f}_{sy:.2f}", rings, oak_dark, cap_bottom=True, cap_top=True, subsurf_levels=0)


def build_prop_rock() -> None:
    """Craggy sculpted Knight Lore dungeon boulder (0.75m)."""
    rock_a = make_pbr_material("BoulderSlate", (0.42, 0.41, 0.39, 1.0), metallic=0.03, roughness=0.88)
    rock_b = make_pbr_material("BoulderDark", (0.31, 0.30, 0.29, 1.0), metallic=0.04, roughness=0.92)
    moss_mat = make_pbr_material("BoulderMoss", (0.28, 0.38, 0.24, 1.0), metallic=0.0, roughness=0.88)

    _add_ico("BoulderMain", (0.0, 0.0, 0.34), 0.40, rock_a, subdivisions=2, scale=(1.12, 1.05, 0.85))
    _add_ico("BoulderShoulderL", (-0.22, 0.12, 0.24), 0.26, rock_b, subdivisions=1, scale=(1.0, 0.9, 0.85))
    _add_ico("BoulderShoulderR", (0.23, -0.10, 0.22), 0.24, rock_b, subdivisions=1, scale=(0.95, 1.0, 0.82))
    _add_ico("BoulderCap", (0.04, 0.02, 0.56), 0.22, moss_mat, subdivisions=1, scale=(1.1, 0.95, 0.55))


def build_prop_dropping_block() -> None:
    """Rune-carved amber sandstone dropping block (0.95 x 0.95 x 0.75 m)."""
    stone_mat = make_pbr_material("DropStone", (0.64, 0.50, 0.34, 1.0), metallic=0.04, roughness=0.76)
    trim_mat = make_pbr_material("DropTrim", (0.44, 0.32, 0.20, 1.0), metallic=0.06, roughness=0.84)
    rune_mat = make_pbr_material("DropRune", (0.88, 0.58, 0.22, 1.0), metallic=0.72, roughness=0.35, emission=(0.88, 0.48, 0.14), emission_strength=0.45)

    add_beveled_box("DropCore", (0.0, 0.0, 0.36), (0.92, 0.92, 0.66), stone_mat, bevel_width=0.03)
    add_beveled_box("DropBottomCollar", (0.0, 0.0, 0.09), (0.96, 0.96, 0.18), trim_mat, bevel_width=0.02)
    add_beveled_box("DropTopCap", (0.0, 0.0, 0.68), (0.96, 0.96, 0.14), trim_mat, bevel_width=0.02)
    add_beveled_box("DropRuneBand", (0.0, 0.0, 0.38), (0.95, 0.95, 0.12), rune_mat, bevel_width=0.01)


def clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


MELKHIOR_BONES = [
    ("Hips", None, (0.0, 0.0, 0.72), (0.0, 0.0, 0.84)),
    ("Spine", "Hips", (0.0, 0.0, 0.84), (0.0, 0.0, 1.00)),
    ("Chest", "Spine", (0.0, 0.0, 1.00), (0.0, 0.0, 1.18)),
    ("Neck", "Chest", (0.0, 0.0, 1.18), (0.0, 0.0, 1.25)),
    ("Head", "Neck", (0.0, 0.0, 1.25), (0.0, 0.0, 1.50)),
    ("LeftUpperArm", "Chest", (0.175, 0.0, 1.14), (0.210, -0.015, 0.94)),
    ("LeftLowerArm", "LeftUpperArm", (0.210, -0.015, 0.94), (0.220, -0.045, 0.76)),
    ("LeftHand", "LeftLowerArm", (0.220, -0.045, 0.76), (0.222, -0.055, 0.65)),
    ("RightUpperArm", "Chest", (-0.175, 0.0, 1.14), (-0.210, -0.025, 0.94)),
    ("RightLowerArm", "RightUpperArm", (-0.210, -0.025, 0.94), (-0.225, -0.085, 0.77)),
    ("RightHand", "RightLowerArm", (-0.225, -0.085, 0.77), (-0.228, -0.095, 0.66)),
    ("LeftUpperLeg", "Hips", (0.10, 0.0, 0.72), (0.10, 0.0, 0.40)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.10, 0.0, 0.40), (0.10, 0.0, 0.11)),
    ("LeftFoot", "LeftLowerLeg", (0.10, 0.0, 0.11), (0.10, -0.09, 0.0)),
    ("RightUpperLeg", "Hips", (-0.10, 0.0, 0.72), (-0.10, 0.0, 0.40)),
    ("RightLowerLeg", "RightUpperLeg", (-0.10, 0.0, 0.40), (-0.10, 0.0, 0.11)),
    ("RightFoot", "RightLowerLeg", (-0.10, 0.0, 0.11), (-0.10, -0.09, 0.0)),
]


def build_rigged_melkhior(palette: list[tuple[float, float, float]]) -> None:
    """Anatomically sculpted humanoid Melkhior the Wizard with tucked natural arms,
    sculpted hands, tapered flowing robes, contoured face/beard, curved hat,
    and upright crystal staff on 17-bone MELKHIOR_BONES."""
    robe_mat = make_pbr_material("WizardRobe", (0.30, 0.16, 0.54, 1.0), metallic=0.06, roughness=0.66)
    robe_deep = make_pbr_material("WizardRobeDeep", (0.21, 0.11, 0.40, 1.0), metallic=0.06, roughness=0.72)
    robe_trim = make_pbr_material("WizardGoldTrim", (0.86, 0.68, 0.24, 1.0), metallic=0.85, roughness=0.30)
    beard_mat = make_pbr_material("WizardBeard", (0.93, 0.92, 0.90, 1.0), metallic=0.0, roughness=0.74)
    skin_mat = make_pbr_material("WizardSkin", (0.82, 0.66, 0.55, 1.0), metallic=0.0, roughness=0.60)
    eye_white_mat = make_pbr_material("WizardEyeWhite", (0.95, 0.94, 0.90, 1.0), metallic=0.0, roughness=0.28)
    eye_mat = make_pbr_material("WizardEye", (0.98, 0.80, 0.22, 1.0), metallic=0.1, roughness=0.2, emission=(0.98, 0.78, 0.20), emission_strength=1.5)
    staff_mat = make_pbr_material("WizardStaffWood", (0.32, 0.20, 0.11, 1.0), metallic=0.05, roughness=0.72)
    orb_mat = make_pbr_material("WizardOrb", (0.22, 0.92, 0.98, 1.0), metallic=0.1, roughness=0.18, emission=(0.22, 0.92, 0.98), emission_strength=2.6)
    boot_mat = make_pbr_material("WizardBoots", (0.18, 0.12, 0.24, 1.0), metallic=0.10, roughness=0.58)

    arm_obj = _create_armature_from_bones(MELKHIOR_BONES)

    def _ell(cx: float, cy: float, cz: float, rx: float, ry: float, sides: int = 12, pleat: float = 0.0) -> list[tuple[float, float, float]]:
        pts: list[tuple[float, float, float]] = []
        for j in range(sides):
            a = 2.0 * math.pi * (j / float(sides))
            r_mod = 1.0 + pleat * math.sin(6.0 * a)
            pts.append((cx + rx * r_mod * math.cos(a), cy + ry * r_mod * math.sin(a), cz))
        return pts

    # 1. Humanoid tapered flowing wizard robe from ankle hem (z=0.22) up to neck (z=1.24)
    robe_rings = [
        _ell(0.0, 0.0, 0.22, 0.225, 0.185, 14, pleat=0.05),   # Draped lower hem
        _ell(0.0, 0.0, 0.50, 0.195, 0.160, 14, pleat=0.03),   # Knee/thigh
        _ell(0.0, 0.0, 0.74, 0.175, 0.145, 14, pleat=0.015),  # Hip
        _ell(0.0, 0.0, 0.87, 0.148, 0.122, 14),               # Cinched waist
        _ell(0.0, -0.008, 1.02, 0.178, 0.142, 14),            # Ribcage
        _ell(0.0, -0.008, 1.13, 0.192, 0.148, 14),            # Humanoid shoulders
        _ell(0.0, 0.0, 1.19, 0.140, 0.112, 14),               # Trapezius slope
        _ell(0.0, 0.0, 1.24, 0.072, 0.070, 14),               # Neck collar
    ]
    robe_obj = _loft_rings("WizardRobeMesh", robe_rings, robe_mat, cap_bottom=False, cap_top=True, subsurf_levels=1)

    def _robe_weights(co: Vector) -> dict[str, float]:
        z = co.z
        if z <= 0.72:
            t_leg = clamp01((0.72 - z) / 0.46)
            w_l = clamp01((co.x + 0.07) / 0.14)
            w_r = 1.0 - w_l
            return {"Hips": 1.0 - t_leg * 0.75, "LeftUpperLeg": t_leg * 0.75 * w_l, "RightUpperLeg": t_leg * 0.75 * w_r}
        if z <= 0.88:
            t = (z - 0.72) / 0.16
            return {"Hips": 1.0 - t, "Spine": t}
        if z <= 1.12:
            t = (z - 0.88) / 0.24
            return {"Spine": 1.0 - t, "Chest": t}
        t = clamp01((z - 1.12) / 0.12)
        return {"Chest": 1.0 - t * 0.55, "Neck": t * 0.55}

    _assign_smooth_bone_weights(robe_obj, arm_obj, _robe_weights)

    # Shoulder mantle capelet, golden waist sash & contoured stole
    mantle_rings = [
        _ell(0.0, 0.01, 1.07, 0.205, 0.162, 14, pleat=0.04),
        _ell(0.0, 0.0, 1.15, 0.195, 0.152, 14, pleat=0.02),
        _ell(0.0, 0.0, 1.21, 0.125, 0.105, 14),
    ]
    mantle = _loft_rings("WizardMantle", mantle_rings, robe_deep, cap_bottom=False, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(mantle, "Chest", arm_obj)

    sash = add_cylinder("WizardSash", (0.0, 0.0, 0.87), 0.155, 0.045, robe_trim, verts=16)
    _set_smooth(sash)
    _assign_bone_weight(sash, "Spine", arm_obj)
    stole = _loft_rings("WizardStole", [
        [(-0.045, -0.198, 0.24), (0.045, -0.198, 0.24), (0.045, -0.168, 0.24), (-0.045, -0.168, 0.24)],
        [(-0.042, -0.168, 0.54), (0.042, -0.168, 0.54), (0.042, -0.138, 0.54), (-0.042, -0.138, 0.54)],
        [(-0.038, -0.145, 0.85), (0.038, -0.145, 0.85), (0.038, -0.115, 0.85), (-0.038, -0.115, 0.85)],
    ], robe_trim, subsurf_levels=1)
    _assign_bone_weight(stole, "Hips", arm_obj)

    # 2. Anatomical Humanoid Head, Contoured Face, Layered Beard & Curved Hat (Head)
    wiz_head_rings = [
        _ell(0.0, 0.0, 1.22, 0.068, 0.068, 12),
        _ell(0.0, -0.012, 1.28, 0.102, 0.112, 12),
        _ell(0.0, -0.012, 1.34, 0.122, 0.128, 12),
        _ell(0.0, -0.005, 1.40, 0.120, 0.124, 12),
        _ell(0.0, 0.005, 1.44, 0.072, 0.078, 12),
    ]
    w_head = _loft_rings("WizardHead", wiz_head_rings, skin_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(w_head, "Head", arm_obj)

    w_nose = add_beveled_box("WizardNose", (0.0, -0.138, 1.335), (0.028, 0.040, 0.042), skin_mat, bevel_width=0.011)
    _set_smooth(w_nose)
    _assign_bone_weight(w_nose, "Head", arm_obj)
    w_must = add_beveled_box("WizardMustache", (0.0, -0.130, 1.295), (0.105, 0.030, 0.022), beard_mat, bevel_width=0.009)
    _set_smooth(w_must)
    _assign_bone_weight(w_must, "Head", arm_obj)
    for side_tag, sx in (("L", 1.0), ("R", -1.0)):
        ew = add_uv_sphere(f"WizardEyeWhite_{side_tag}", (sx * 0.044, -0.124, 1.355), 0.022, eye_white_mat, scale=(1.0, 0.55, 1.0))
        _assign_bone_weight(ew, "Head", arm_obj)
        eye = add_uv_sphere(f"WizardEye_{side_tag}", (sx * 0.044, -0.133, 1.354), 0.013, eye_mat, scale=(1.0, 0.60, 1.0))
        _assign_bone_weight(eye, "Head", arm_obj)
        brow = add_beveled_box(f"WizardBrow_{side_tag}", (sx * 0.046, -0.126, 1.384), (0.048, 0.020, 0.014), beard_mat, bevel_width=0.005)
        _assign_bone_weight(brow, "Head", arm_obj)
        ear = add_uv_sphere(f"WizardEar_{side_tag}", (sx * 0.124, -0.005, 1.345), 0.026, skin_mat, scale=(0.45, 0.72, 1.0))
        _assign_bone_weight(ear, "Head", arm_obj)

    beard_rings = [
        [(-0.068, -0.110, 1.295), (0.068, -0.110, 1.295), (0.048, -0.062, 1.295), (-0.048, -0.062, 1.295)],
        [(-0.072, -0.138, 1.215), (0.072, -0.138, 1.215), (0.045, -0.090, 1.215), (-0.045, -0.090, 1.215)],
        [(-0.048, -0.150, 1.120), (0.048, -0.150, 1.120), (0.030, -0.110, 1.120), (-0.030, -0.110, 1.120)],
        [(-0.015, -0.148, 1.030), (0.015, -0.148, 1.030), (0.010, -0.124, 1.030), (-0.010, -0.124, 1.030)],
    ]
    beard_obj = _loft_rings("WizardBeard", beard_rings, beard_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)
    _assign_bone_weight(beard_obj, "Head", arm_obj)

    hat_brim_rings = [
        _ell(0.0, 0.01, 1.395, 0.22, 0.23, 14, pleat=0.04),
        _ell(0.0, 0.015, 1.422, 0.132, 0.138, 14),
    ]
    hat_brim = _loft_rings("HatBrim", hat_brim_rings, robe_deep, cap_bottom=False, cap_top=False, subsurf_levels=1)
    _assign_bone_weight(hat_brim, "Head", arm_obj)
    hat_band = add_cylinder("HatBand", (0.0, 0.015, 1.434), 0.132, 0.028, robe_trim, verts=16)
    _assign_bone_weight(hat_band, "Head", arm_obj)
    hat_crown = _build_organic_tube(
        "HatCurvedSpire",
        [(0.0, 0.015, 1.425), (0.0, 0.03, 1.505), (0.02, 0.065, 1.565), (0.055, 0.12, 1.595)],
        [0.128, 0.084, 0.042, 0.010],
        robe_mat,
        sides=12,
    )
    _assign_bone_weight(hat_crown, "Head", arm_obj)

    # 3. Natural Tucked Humanoid Sleeves, Forearms & Sculpted Hands + Upright Crystal Staff
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        fwd_wrist = -0.085 if side_tag == "R" else -0.045
        fwd_elbow = -0.025 if side_tag == "R" else -0.015
        sleeve_rings = [
            _ell(sign_x * 0.168, 0.0, 1.145, 0.056, 0.062, 10),
            _ell(sign_x * 0.196, fwd_elbow * 0.5, 1.045, 0.062, 0.066, 10),
            _ell(sign_x * 0.210, fwd_elbow, 0.945, 0.060, 0.064, 10),
            _ell(sign_x * 0.220, fwd_wrist * 0.85, 0.805, 0.066, 0.070, 10),
            _ell(sign_x * 0.223, fwd_wrist, 0.775, 0.052, 0.054, 10),
        ]
        sleeve_obj = _loft_rings(f"WizardSleeve_{side_tag}", sleeve_rings, robe_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        cuff = add_cylinder(f"WizardCuff_{side_tag}", (sign_x * 0.222, fwd_wrist, 0.778), 0.055, 0.024, robe_trim, verts=12)
        _set_smooth(cuff)

        palm_rings = [
            _ell(sign_x * 0.223, fwd_wrist, 0.772, 0.028, 0.032, 10),
            _ell(sign_x * 0.226, fwd_wrist - 0.008, 0.735, 0.030, 0.044, 10),
            _ell(sign_x * 0.225, fwd_wrist - 0.010, 0.702, 0.028, 0.044, 10),
            _ell(sign_x * 0.222, fwd_wrist - 0.010, 0.690, 0.020, 0.035, 10),
        ]
        palm_obj = _loft_rings(f"WizardPalm_{side_tag}", palm_rings, skin_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_wiz_arm_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.96:
                    return {f"{bp}UpperArm": 1.0}
                if z >= 0.91:
                    t = (0.96 - z) / 0.05
                    return {f"{bp}UpperArm": 1.0 - t, f"{bp}LowerArm": t}
                if z >= 0.78:
                    return {f"{bp}LowerArm": 1.0}
                if z >= 0.74:
                    t = (0.78 - z) / 0.04
                    return {f"{bp}LowerArm": 1.0 - t, f"{bp}Hand": t}
                return {f"{bp}Hand": 1.0}
            return _fn

        wiz_arm_w = _make_wiz_arm_w(bone_prefix)
        _assign_smooth_bone_weights(sleeve_obj, arm_obj, wiz_arm_w)
        _assign_bone_weight(cuff, f"{bone_prefix}LowerArm", arm_obj)
        _assign_smooth_bone_weights(palm_obj, arm_obj, wiz_arm_w)

        thumb = _build_organic_tube(
            f"WizardThumb_{side_tag}",
            [(sign_x * 0.214, fwd_wrist - 0.030, 0.736), (sign_x * 0.205, fwd_wrist - 0.048, 0.708), (sign_x * 0.202, fwd_wrist - 0.045, 0.684)],
            [0.016, 0.013, 0.010],
            skin_mat,
            sides=7,
        )
        _assign_bone_weight(thumb, f"{bone_prefix}Hand", arm_obj)
        for f_idx, dy_f in enumerate((-0.028, -0.010, 0.008, 0.025)):
            finger = _build_organic_tube(
                f"WizardFinger_{side_tag}_{f_idx}",
                [(sign_x * 0.226, fwd_wrist + dy_f, 0.702), (sign_x * 0.222, fwd_wrist + dy_f, 0.676), (sign_x * 0.214, fwd_wrist + dy_f, 0.654)],
                [0.011, 0.0095, 0.007],
                skin_mat,
                sides=6,
            )
            _assign_bone_weight(finger, f"{bone_prefix}Hand", arm_obj)

    staff = _build_organic_tube(
        "WizardGnarledStaff",
        [(-0.232, -0.105, 0.02), (-0.234, -0.112, 0.44), (-0.236, -0.105, 0.74), (-0.232, -0.112, 1.15), (-0.235, -0.120, 1.38)],
        [0.018, 0.020, 0.021, 0.024, 0.028],
        staff_mat,
        sides=8,
        flute_amp=0.08,
        flute_freq=5,
        twist=1.4,
    )
    _assign_bone_weight(staff, "RightHand", arm_obj)
    orb = add_uv_sphere("WizardStaffOrb", (-0.235, -0.120, 1.44), 0.056, orb_mat)
    _set_smooth(orb)
    _assign_bone_weight(orb, "RightHand", arm_obj)

    # 4. Sculpted Legs & Boots under skirt (grounded cleanly at z = 0.0)
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        cx = sign_x * 0.10
        leg_rings = [
            _ell(cx, 0.0, 0.38, 0.058, 0.062, 10),
            _ell(cx, 0.0, 0.22, 0.054, 0.058, 10),
            _ell(cx, -0.01, 0.10, 0.058, 0.072, 10),
            _ell(cx, -0.040, 0.04, 0.062, 0.098, 10),
            _ell(cx, -0.040, 0.00, 0.062, 0.098, 10),
        ]
        leg_mesh = _loft_rings(f"WizardBootLeg_{side_tag}", leg_rings, boot_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

        def _make_wiz_leg_w(bp: str):
            def _fn(co: Vector) -> dict[str, float]:
                z = co.z
                if z >= 0.28:
                    return {f"{bp}UpperLeg": 1.0}
                if z >= 0.13:
                    return {f"{bp}LowerLeg": 1.0}
                if z >= 0.08:
                    t = (0.13 - z) / 0.05
                    return {f"{bp}LowerLeg": 1.0 - t, f"{bp}Foot": t}
                return {f"{bp}Foot": 1.0}
            return _fn

        _assign_smooth_bone_weights(leg_mesh, arm_obj, _make_wiz_leg_w(bone_prefix))


def build_prop_gargoyle() -> None:
    """Realistic gothic cathedral crouched horned gargoyle with articulated bat wings (0.85m)."""
    stone_mat = make_pbr_material("GargoyleStone", (0.36, 0.35, 0.38, 1.0), metallic=0.10, roughness=0.76)
    dark_mat = make_pbr_material("GargoyleWing", (0.25, 0.24, 0.28, 1.0), metallic=0.12, roughness=0.80)
    eye_mat = make_pbr_material("GargoyleEye", (0.98, 0.22, 0.14, 1.0), metallic=0.1, roughness=0.22, emission=(0.98, 0.22, 0.14), emission_strength=2.2)

    # Stepped gothic plinth
    add_beveled_box("PlinthBase", (0.0, 0.0, 0.055), (0.76, 0.76, 0.11), dark_mat, bevel_width=0.02)
    add_beveled_box("PlinthCornice", (0.0, 0.0, 0.145), (0.68, 0.68, 0.07), stone_mat, bevel_width=0.015)

    def _ell(cx: float, cy: float, cz: float, rx: float, ry: float, sides: int = 10) -> list[tuple[float, float, float]]:
        return [(cx + rx * math.cos(2.0 * math.pi * j / sides), cy + ry * math.sin(2.0 * math.pi * j / sides), cz) for j in range(sides)]

    # Crouched muscular spine & chest leaning forward over plinth
    body_rings = [
        _ell(0.0, 0.16, 0.20, 0.14, 0.12, 10),   # Haunches
        _ell(0.0, 0.08, 0.31, 0.155, 0.14, 10),  # Abdomen
        _ell(0.0, -0.02, 0.44, 0.175, 0.155, 10), # Ribcage & shoulders
        _ell(0.0, -0.08, 0.54, 0.110, 0.105, 10), # Muscular neck
        _ell(0.0, -0.14, 0.60, 0.125, 0.140, 10), # Cranium/jaw base
        _ell(0.0, -0.16, 0.69, 0.110, 0.135, 10), # Brow ridge
        _ell(0.0, -0.11, 0.74, 0.065, 0.080, 10), # Skull top
    ]
    _loft_rings("GargoyleBody", body_rings, stone_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

    # Sculpted protruding snout, glowing crimson eyes & pointed demon ears
    snout = _loft_rings("GargoyleSnout", [
        [(-0.075, -0.18, 0.59), (0.075, -0.18, 0.59), (0.075, -0.18, 0.66), (-0.075, -0.18, 0.66)],
        [(-0.055, -0.29, 0.58), (0.055, -0.29, 0.58), (0.052, -0.28, 0.64), (-0.052, -0.28, 0.64)],
    ], stone_mat, cap_bottom=True, cap_top=True, subsurf_levels=1)

    # Swept-back curved ridged horns, glowing eyes, crouched forelegs gripping front edge, curled tail
    _build_organic_tube("GargoyleTail", [(0.0, 0.18, 0.22), (0.08, 0.28, 0.21), (0.20, 0.26, 0.20), (0.26, 0.16, 0.22)], [0.05, 0.036, 0.024, 0.012], dark_mat, sides=8)
    for sx in (-1.0, 1.0):
        _build_organic_tube(
            f"GargHorn_{sx:.0f}",
            [(sx * 0.07, -0.10, 0.71), (sx * 0.11, -0.02, 0.79), (sx * 0.13, 0.08, 0.84), (sx * 0.11, 0.15, 0.85)],
            [0.036, 0.028, 0.018, 0.006],
            dark_mat,
            sides=8,
            flute_amp=0.12,
            flute_freq=5,
        )
        add_uv_sphere(f"GargEye_{sx:.0f}", (sx * 0.058, -0.24, 0.665), 0.022, eye_mat, scale=(1.1, 0.65, 0.85))
        _add_cone(f"GargEar_{sx:.0f}", (sx * 0.115, -0.08, 0.69), 0.032, 0.005, 0.11, stone_mat, verts=6, rotation=(math.radians(-45.0), -sx * 0.8, 0.0))

        # Crouched muscular forelegs & clawed talons gripping front plinth
        _build_organic_tube(
            f"GargForeleg_{sx:.0f}",
            [(sx * 0.15, -0.02, 0.42), (sx * 0.20, -0.14, 0.32), (sx * 0.19, -0.22, 0.19)],
            [0.065, 0.052, 0.048],
            stone_mat,
            sides=8,
        )
        add_beveled_box(f"GargTalon_{sx:.0f}", (sx * 0.19, -0.24, 0.19), (0.09, 0.11, 0.05), dark_mat, bevel_width=0.01)

        # Articulated bat wing: leading arm bone + 3 radiating finger ribs + thin scalloped membrane
        p_sh = Vector((sx * 0.12, 0.04, 0.45))
        p_el = Vector((sx * 0.22, 0.14, 0.62))
        p_wr = Vector((sx * 0.30, 0.08, 0.78))
        p_f1 = Vector((sx * 0.36, 0.22, 0.72))
        p_f2 = Vector((sx * 0.34, 0.30, 0.55))
        p_f3 = Vector((sx * 0.24, 0.30, 0.36))
        _build_organic_tube(f"WingArm_{sx:.0f}", [tuple(p_sh), tuple(p_el), tuple(p_wr)], [0.036, 0.030, 0.024], dark_mat, sides=7)
        for f_idx, f_tip in enumerate((p_f1, p_f2, p_f3)):
            _build_organic_tube(f"WingFinger_{sx:.0f}_{f_idx}", [tuple(p_wr), tuple(f_tip)], [0.018, 0.007], dark_mat, sides=6)

        bm_w = bmesh.new()
        v_sh = bm_w.verts.new(p_sh)
        v_el = bm_w.verts.new(p_el)
        v_wr = bm_w.verts.new(p_wr)
        v_f1 = bm_w.verts.new(p_f1)
        v_f2 = bm_w.verts.new(p_f2)
        v_f3 = bm_w.verts.new(p_f3)
        v_hip = bm_w.verts.new((sx * 0.11, 0.16, 0.24))
        for tri in ((v_wr, v_f1, v_f2), (v_wr, v_f2, v_f3), (v_wr, v_f3, v_el), (v_el, v_f3, v_sh), (v_sh, v_f3, v_hip)):
            bm_w.faces.new(tri)
        bmesh.ops.recalc_face_normals(bm_w, faces=bm_w.faces)
        mesh_w = bpy.data.meshes.new(f"WingMembrane_{sx:.0f}")
        bm_w.to_mesh(mesh_w)
        bm_w.free()
        obj_w = bpy.data.objects.new(f"WingMembrane_{sx:.0f}", mesh_w)
        bpy.context.collection.objects.link(obj_w)
        obj_w.data.materials.append(dark_mat)
        solid = obj_w.modifiers.new(name="WingThickness", type="SOLIDIFY")
        solid.thickness = 0.022
        bpy.context.view_layer.objects.active = obj_w
        bpy.ops.object.modifier_apply(modifier=solid.name)
        _set_smooth(obj_w)


def build_prop_spikes() -> None:
    """Iron floor spike hazard cluster on beveled stone base (0.65m)."""
    base_mat = make_pbr_material("SpikePlinth", (0.34, 0.33, 0.32, 1.0), metallic=0.08, roughness=0.82)
    steel_mat = make_pbr_material("SpikeSteel", (0.58, 0.62, 0.68, 1.0), metallic=0.88, roughness=0.28)
    tip_mat = make_pbr_material("SpikeTipCrimson", (0.76, 0.22, 0.20, 1.0), metallic=0.55, roughness=0.35)

    add_beveled_box("SpikeBase", (0.0, 0.0, 0.06), (0.82, 0.82, 0.12), base_mat, bevel_width=0.02)
    coords = [(0.0, 0.0, 0.54, 0.11), (-0.23, -0.23, 0.42, 0.085), (0.23, -0.23, 0.42, 0.085), (-0.23, 0.23, 0.42, 0.085), (0.23, 0.23, 0.42, 0.085)]
    for idx, (sx, sy, sh, sr) in enumerate(coords):
        _add_cone(f"SpikeShaft_{idx}", (sx, sy, 0.12 + sh * 0.5), sr, sr * 0.22, sh, steel_mat, verts=10)
        _add_cone(f"SpikeTip_{idx}", (sx, sy, 0.12 + sh + 0.045), sr * 0.24, 0.004, 0.10, tip_mat, verts=8)


def build_prop_spiked_ball() -> None:
    """Suspended/bouncing iron morningstar sphere with steel radial spikes (0.75m)."""
    iron_mat = make_pbr_material("SpikedIron", (0.20, 0.22, 0.26, 1.0), metallic=0.84, roughness=0.40)
    spike_mat = make_pbr_material("SpikedSteel", (0.68, 0.72, 0.78, 1.0), metallic=0.92, roughness=0.24)

    core = add_uv_sphere("MorningstarCore", (0.0, 0.0, 0.375), 0.26, iron_mat)
    _set_smooth(core)
    dirs = [
        (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1),
        (0.7, 0.7, 0.7), (-0.7, 0.7, 0.7), (0.7, -0.7, 0.7), (-0.7, -0.7, 0.7),
        (0.7, 0.7, -0.7), (-0.7, 0.7, -0.7), (0.7, -0.7, -0.7), (-0.7, -0.7, -0.7),
    ]
    for idx, dv in enumerate(dirs):
        v = Vector(dv).normalized()
        pos = Vector((0.0, 0.0, 0.375)) + v * 0.27
        quat = v.to_track_quat("Z", "Y")
        _add_cone(f"BallSpike_{idx}", (pos.x, pos.y, pos.z), 0.065, 0.006, 0.18, spike_mat, verts=8, rotation=tuple(quat.to_euler()))


def build_prop_ball() -> None:
    """Enchanted crimson & brass bouncing energy orb (0.75m)."""
    orb_mat = make_pbr_material("BouncingCrimson", (0.78, 0.16, 0.18, 1.0), metallic=0.35, roughness=0.28, emission=(0.75, 0.14, 0.14), emission_strength=0.9)
    brass_mat = make_pbr_material("BouncingBrass", (0.86, 0.66, 0.24, 1.0), metallic=0.88, roughness=0.26)

    sphere = add_uv_sphere("HazardBallSphere", (0.0, 0.0, 0.375), 0.355, orb_mat)
    _set_smooth(sphere)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.365, minor_radius=0.032, location=(0.0, 0.0, 0.375))
    ring_a = bpy.context.active_object
    ring_a.name = "BallBrassRingA"
    ring_a.data.materials.append(brass_mat)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.365, minor_radius=0.028, location=(0.0, 0.0, 0.375), rotation=(math.pi * 0.5, 0.0, 0.0))
    ring_b = bpy.context.active_object
    ring_b.name = "BallBrassRingB"
    ring_b.data.materials.append(brass_mat)


def build_prop_fire() -> None:
    """Iron brazier tripod bowl with glowing embers & sculpted flame tongues (0.80m)."""
    iron_mat = make_pbr_material("BrazierIron", (0.18, 0.19, 0.22, 1.0), metallic=0.82, roughness=0.46)
    ember_mat = make_pbr_material("BrazierEmber", (0.95, 0.28, 0.06, 1.0), metallic=0.0, roughness=0.5, emission=(0.95, 0.28, 0.06), emission_strength=2.2)
    flame_mat = make_pbr_material("BrazierFlame", (1.0, 0.64, 0.12, 1.0), metallic=0.0, roughness=0.35, emission=(1.0, 0.58, 0.10), emission_strength=3.0)

    bowl = _add_cone("BrazierBowl", (0.0, 0.0, 0.22), 0.22, 0.36, 0.22, iron_mat, verts=14)
    _set_smooth(bowl)
    for idx in range(3):
        ang = math.radians(idx * 120.0)
        add_cylinder(f"BrazierLeg_{idx}", (0.22 * math.cos(ang), 0.22 * math.sin(ang), 0.09), 0.04, 0.18, iron_mat, verts=8)
    add_cylinder("EmberBed", (0.0, 0.0, 0.33), 0.28, 0.06, ember_mat, verts=14)
    for idx, (fx, fy, fh, fr) in enumerate([(0.0, 0.0, 0.48, 0.15), (-0.11, 0.07, 0.34, 0.10), (0.12, -0.06, 0.36, 0.11)]):
        fl = _add_cone(f"FlameTongue_{idx}", (fx, fy, 0.32 + fh * 0.5), fr, 0.012, fh, flame_mat, verts=10)
        _set_smooth(fl)


def build_prop_ghost() -> None:
    """Hooded floating Knight Lore ghost wraith with cyan eyes (0.90m)."""
    shroud_mat = make_pbr_material("GhostShroud", (0.76, 0.88, 0.96, 1.0), metallic=0.05, roughness=0.45, emission=(0.35, 0.62, 0.85), emission_strength=0.65)
    cowl_mat = make_pbr_material("GhostVoid", (0.08, 0.10, 0.14, 1.0), metallic=0.0, roughness=0.90)
    eye_mat = make_pbr_material("GhostEyes", (0.20, 0.98, 1.0, 1.0), metallic=0.0, roughness=0.18, emission=(0.20, 0.98, 1.0), emission_strength=2.8)

    tail = _add_cone("GhostTail", (0.0, 0.03, 0.20), 0.04, 0.26, 0.38, shroud_mat, verts=14)
    _set_smooth(tail)
    body = add_uv_sphere("GhostBody", (0.0, 0.0, 0.48), 0.26, shroud_mat, scale=(1.0, 0.90, 1.20))
    _set_smooth(body)
    hood = add_uv_sphere("GhostHood", (0.0, 0.0, 0.74), 0.19, shroud_mat, scale=(0.95, 1.05, 1.05))
    _set_smooth(hood)
    face = add_uv_sphere("GhostVoidFace", (0.0, -0.10, 0.72), 0.12, cowl_mat)
    _set_smooth(face)
    for sx in (-0.055, 0.055):
        eye = add_uv_sphere(f"GhostEye_{sx:.2f}", (sx, -0.20, 0.73), 0.025, eye_mat)
        _set_smooth(eye)
        arm = _add_cone(f"GhostSleeve_{sx:.2f}", (sx * 4.4, -0.10, 0.52), 0.075, 0.025, 0.28, shroud_mat, verts=10, rotation=(math.radians(65.0), -sx * 4.0, 0.0))
        _set_smooth(arm)


def build_prop_item_diamond() -> None:
    """Ruby-red faceted Diamond charm (#FF0000, 0.55m)."""
    ruby_mat = make_pbr_material("RubyDiamond", (0.94, 0.12, 0.16, 1.0), metallic=0.18, roughness=0.18, emission=(0.92, 0.10, 0.14), emission_strength=0.9)
    brass_mat = make_pbr_material("DiamondSetting", (0.86, 0.68, 0.24, 1.0), metallic=0.88, roughness=0.25)

    add_cylinder("DiamondBase", (0.0, 0.0, 0.03), 0.16, 0.06, brass_mat, verts=8)
    _add_cone("DiamondLower", (0.0, 0.0, 0.19), 0.03, 0.24, 0.26, ruby_mat, verts=8)
    _add_cone("DiamondCrown", (0.0, 0.0, 0.43), 0.24, 0.12, 0.18, ruby_mat, verts=8)


def build_prop_item_poison() -> None:
    """Magenta alchemical Poison flask (#FF00FF, 0.60m)."""
    glass_mat = make_pbr_material("PoisonMagenta", (0.92, 0.14, 0.90, 1.0), metallic=0.12, roughness=0.20, emission=(0.88, 0.10, 0.86), emission_strength=0.9)
    cork_mat = make_pbr_material("FlaskCork", (0.46, 0.28, 0.14, 1.0), metallic=0.0, roughness=0.82)
    ring_mat = make_pbr_material("FlaskSilver", (0.76, 0.78, 0.82, 1.0), metallic=0.88, roughness=0.26)

    bulb = add_uv_sphere("PoisonFlaskBody", (0.0, 0.0, 0.21), 0.21, glass_mat, scale=(1.0, 1.0, 0.95))
    _set_smooth(bulb)
    add_cylinder("PoisonNeck", (0.0, 0.0, 0.44), 0.08, 0.16, glass_mat, verts=14)
    add_cylinder("PoisonCollar", (0.0, 0.0, 0.49), 0.105, 0.04, ring_mat, verts=14)
    add_cylinder("PoisonCork", (0.0, 0.0, 0.56), 0.068, 0.10, cork_mat, verts=12)


def build_prop_item_boot() -> None:
    """Emerald winged adventure Boot charm (#00FF00, 0.55m)."""
    boot_mat = make_pbr_material("EmeraldBoot", (0.14, 0.82, 0.24, 1.0), metallic=0.08, roughness=0.45, emission=(0.10, 0.68, 0.18), emission_strength=0.5)
    sole_mat = make_pbr_material("BootSole", (0.20, 0.16, 0.14, 1.0), metallic=0.10, roughness=0.72)
    wing_mat = make_pbr_material("BootGoldWing", (0.92, 0.80, 0.34, 1.0), metallic=0.82, roughness=0.28)

    add_beveled_box("BootSole", (0.0, -0.05, 0.04), (0.24, 0.44, 0.08), sole_mat, bevel_width=0.015)
    add_beveled_box("BootFoot", (0.0, -0.06, 0.14), (0.22, 0.40, 0.14), boot_mat, bevel_width=0.03)
    add_cylinder("BootShaft", (0.0, 0.07, 0.34), 0.115, 0.34, boot_mat, verts=14)
    add_cylinder("BootCuff", (0.0, 0.07, 0.51), 0.135, 0.07, wing_mat, verts=14)
    for sx in (-0.15, 0.15):
        add_beveled_box(f"BootWing_{sx:.2f}", (sx, 0.12, 0.38), (0.05, 0.18, 0.14), wing_mat, bevel_width=0.008)


def build_prop_item_chalice() -> None:
    """Cyan ornate stemmed Chalice (#00FFFF, 0.60m)."""
    cyan_mat = make_pbr_material("ChaliceCyan", (0.16, 0.88, 0.94, 1.0), metallic=0.75, roughness=0.22, emission=(0.12, 0.80, 0.88), emission_strength=0.6)
    gold_mat = make_pbr_material("ChaliceGold", (0.88, 0.70, 0.24, 1.0), metallic=0.88, roughness=0.24)

    _add_cone("ChaliceFoot", (0.0, 0.0, 0.06), 0.18, 0.06, 0.12, gold_mat, verts=16)
    add_cylinder("ChaliceStem", (0.0, 0.0, 0.20), 0.042, 0.18, gold_mat, verts=12)
    add_uv_sphere("ChaliceKnob", (0.0, 0.0, 0.21), 0.065, cyan_mat)
    cup = _add_cone("ChaliceBowl", (0.0, 0.0, 0.43), 0.07, 0.22, 0.30, cyan_mat, verts=18)
    _set_smooth(cup)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.215, minor_radius=0.022, location=(0.0, 0.0, 0.575))
    rim = bpy.context.active_object
    rim.name = "ChaliceRim"
    rim.data.materials.append(gold_mat)


def build_prop_item_cup() -> None:
    """Golden royal two-handled Goblet Cup (#FFFF00, 0.50m)."""
    gold_mat = make_pbr_material("RoyalCupGold", (0.96, 0.82, 0.16, 1.0), metallic=0.90, roughness=0.22, emission=(0.75, 0.62, 0.10), emission_strength=0.45)

    _add_cone("CupFoot", (0.0, 0.0, 0.05), 0.16, 0.07, 0.10, gold_mat, verts=16)
    add_cylinder("CupStem", (0.0, 0.0, 0.15), 0.048, 0.12, gold_mat, verts=12)
    bowl = _add_cone("CupBowl", (0.0, 0.0, 0.34), 0.10, 0.20, 0.28, gold_mat, verts=16)
    _set_smooth(bowl)
    for sx in (-0.21, 0.21):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.08, minor_radius=0.02, location=(sx, 0.0, 0.34), rotation=(math.pi * 0.5, 0.0, 0.0))
        h = bpy.context.active_object
        h.name = f"CupHandle_{sx:.2f}"
        h.data.materials.append(gold_mat)


def build_prop_item_bottle() -> None:
    """Pearlescent white Elixir Bottle (#FFFFFF, 0.60m)."""
    pearl_mat = make_pbr_material("ElixirPearl", (0.94, 0.95, 0.98, 1.0), metallic=0.18, roughness=0.22, emission=(0.75, 0.80, 0.90), emission_strength=0.55)
    silver_mat = make_pbr_material("ElixirSilver", (0.78, 0.82, 0.88, 1.0), metallic=0.88, roughness=0.24)

    add_cylinder("BottleBody", (0.0, 0.0, 0.19), 0.16, 0.36, pearl_mat, verts=16)
    _add_cone("BottleShoulder", (0.0, 0.0, 0.41), 0.16, 0.065, 0.10, pearl_mat, verts=16)
    add_cylinder("BottleNeck", (0.0, 0.0, 0.51), 0.055, 0.12, silver_mat, verts=14)
    add_uv_sphere("BottleStopper", (0.0, 0.0, 0.585), 0.065, silver_mat)


def build_prop_item_crystal_ball() -> None:
    """Glowing magical arcane Crystal Ball resting on a sculpted bronze pedestal (0.55m)."""
    bronze_dark = make_pbr_material("CrystalPedestalBronze", (0.34, 0.21, 0.11, 1.0), metallic=0.68, roughness=0.36)
    bronze_trim = make_pbr_material("CrystalPedestalBronzeTrim", (0.62, 0.42, 0.18, 1.0), metallic=0.78, roughness=0.26)
    core_heart = make_pbr_material(
        "CrystalCoreHeart",
        (1.0, 0.92, 1.0, 1.0),
        metallic=0.0,
        roughness=0.10,
        emission=(1.0, 0.85, 1.0),
        emission_strength=6.0,
    )
    core_aura = make_pbr_material(
        "CrystalCoreAura",
        (0.72, 0.22, 1.0, 0.65),
        metallic=0.0,
        roughness=0.12,
        emission=(0.68, 0.22, 1.0),
        emission_strength=2.8,
    )
    mote_mat = make_pbr_material(
        "CrystalStarMote",
        (0.55, 0.92, 1.0, 1.0),
        metallic=0.0,
        roughness=0.10,
        emission=(0.45, 0.88, 1.0),
        emission_strength=4.5,
    )
    outer_glass = make_pbr_material(
        "CrystalOuterGlass",
        (0.38, 0.12, 0.68, 0.34),
        metallic=0.06,
        roughness=0.06,
        emission=(0.48, 0.16, 0.88),
        emission_strength=0.75,
    )

    # Stepped fluted bronze pedestal (z = 0.00 .. 0.23)
    _add_cone("PedestalPlinth", (0.0, 0.0, 0.025), 0.23, 0.20, 0.05, bronze_dark, verts=16)
    _add_cone("PedestalBase", (0.0, 0.0, 0.085), 0.18, 0.10, 0.07, bronze_dark, verts=16)
    add_cylinder("PedestalStem", (0.0, 0.0, 0.15), 0.072, 0.06, bronze_dark, verts=14)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.088, minor_radius=0.016, major_segments=20, minor_segments=8, location=(0.0, 0.0, 0.155)
    )
    collar = bpy.context.active_object
    collar.name = "PedestalRing"
    collar.data.materials.append(bronze_trim)

    cup = _add_cone("PedestalCup", (0.0, 0.0, 0.205), 0.085, 0.165, 0.055, bronze_trim, verts=16)
    _set_smooth(cup)

    # 4 tapered bronze prongs cradling the lower hemisphere of the orb (z = 0.21 .. 0.31)
    for idx in range(4):
        ang = math.radians(idx * 90.0 + 45.0)
        ca, sa = math.cos(ang), math.sin(ang)
        prong = _add_cone(
            f"PedestalProng_{idx}",
            (0.152 * ca, 0.152 * sa, 0.255),
            0.026,
            0.012,
            0.10,
            bronze_trim,
            verts=8,
            rotation=(0.24 * sa, -0.24 * ca, 0.0),
        )
        _set_smooth(prong)

    # Glowing multi-layered magical orb centered at z = 0.375 (top = 0.55m)
    heart = add_uv_sphere("CrystalCoreHeart", (0.0, 0.0, 0.375), 0.055, core_heart)
    _set_smooth(heart)
    aura = add_uv_sphere("CrystalCoreAura", (0.0, 0.0, 0.375), 0.105, core_aura)
    _set_smooth(aura)

    for idx, (mx, my, mz) in enumerate([
        (0.082, 0.032, 0.405),
        (-0.074, 0.052, 0.345),
        (0.036, -0.078, 0.360),
        (-0.042, -0.055, 0.425),
    ]):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.016, location=(mx, my, mz))
        mote = bpy.context.active_object
        mote.name = f"CrystalMote_{idx}"
        mote.data.materials.append(mote_mat)

    shell = add_uv_sphere("CrystalOuterGlass", (0.0, 0.0, 0.375), 0.175, outer_glass)
    _set_smooth(shell)

    # Delicate tilted bronze-gold arcane ring orbiting the crystal orb
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.205,
        minor_radius=0.009,
        major_segments=28,
        minor_segments=8,
        location=(0.0, 0.0, 0.375),
        rotation=(math.radians(24.0), math.radians(-14.0), 0.0),
    )
    ring = bpy.context.active_object
    ring.name = "ArcaneRunicRing"
    ring.data.materials.append(bronze_trim)
    _set_smooth(ring)


def build_prop_item_extra_life() -> None:
    """Alabaster Sabreman hero idol statuette (#FFFFFF, 0.65m)."""
    idol_mat = make_pbr_material("ExtraLifeAlabaster", (0.95, 0.94, 0.90, 1.0), metallic=0.12, roughness=0.32, emission=(0.92, 0.88, 0.72), emission_strength=0.65)
    gold_mat = make_pbr_material("ExtraLifePlinth", (0.86, 0.68, 0.26, 1.0), metallic=0.85, roughness=0.28)

    add_cylinder("IdolPlinth", (0.0, 0.0, 0.05), 0.20, 0.10, gold_mat, verts=8)
    add_beveled_box("IdolTorso", (0.0, 0.0, 0.26), (0.24, 0.16, 0.30), idol_mat, bevel_width=0.03)
    add_uv_sphere("IdolHead", (0.0, 0.0, 0.47), 0.115, idol_mat)
    add_cylinder("IdolHelmetBrim", (0.0, 0.0, 0.56), 0.18, 0.04, idol_mat, verts=14)
    add_uv_sphere("IdolHelmetCrown", (0.0, 0.0, 0.59), 0.12, idol_mat, scale=(1.0, 1.0, 0.65))


def build_generic_sprite_sculpt(sprite_path: Path, target_height: float) -> None:
    """Converts any arbitrary 2D sprite PNG alpha silhouette into a smooth beveled 3D sculpt."""
    img = bpy.data.images.load(str(sprite_path))
    w, h = img.size[0], img.size[1]
    pixels = list(img.pixels)

    # Downsample to 16x16 occupancy grid for clean topology
    grid_n = 16
    cell_sz = target_height / float(grid_n)
    bm = bmesh.new()

    color_accum = [0.0, 0.0, 0.0]
    color_cnt = 0

    for gy in range(grid_n):
        for gx in range(grid_n):
            px = min(w - 1, int((gx + 0.5) * w / grid_n))
            py = min(h - 1, int((gy + 0.5) * h / grid_n))
            idx = (py * w + px) * 4
            if pixels[idx + 3] > 0.4:
                color_accum[0] += pixels[idx]
                color_accum[1] += pixels[idx + 1]
                color_accum[2] += pixels[idx + 2]
                color_cnt += 1
                cx = (gx - grid_n * 0.5 + 0.5) * cell_sz
                cz = (gy + 0.5) * cell_sz
                bmesh.ops.create_cube(
                    bm,
                    size=1.0,
                    matrix=(
                        Vector((cell_sz, 0, 0)).to_track_quat("X", "Z").to_matrix().to_4x4()
                    ),
                )
                # Shift the last 8 added verts
                for v in bm.verts[-8:]:
                    v.co = Vector((v.co.x * cell_sz * 1.02 + cx, v.co.y * (cell_sz * 2.2), v.co.z * cell_sz * 1.02 + cz))

    if len(bm.verts) == 0:
        bmesh.ops.create_cube(bm, size=target_height)

    mesh = bpy.data.meshes.new("SpriteSculptMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SpriteSculpt", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    c = (
        (color_accum[0] / color_cnt, color_accum[1] / color_cnt, color_accum[2] / color_cnt, 1.0)
        if color_cnt > 0
        else (0.55, 0.55, 0.65, 1.0)
    )
    mat = make_pbr_material("SpriteMaterial", c, metallic=0.25, roughness=0.55)
    obj.data.materials.append(mat)

    remesh = obj.modifiers.new(name="SmoothRemesh", type="REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = max(0.03, target_height / 24.0)
    bpy.ops.object.modifier_apply(modifier=remesh.name)


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--sprite", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--kind", required=True)
    parser.add_argument("--height", type=float, default=1.0)
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sprite_path = Path(args.sprite).resolve()
    palette = load_palette(sprite_path)

    # Note: prop builders use Blender Y-up or Z-up? Let's keep prop builders consistent in Blender Z-up
    #Wait: primitive_cube_add / cylinder_add are Z-up in Blender, and export_yup=True rotates Blender +Z -> glTF +Y!
    # So we fix build_prop_chest/cauldron/key/pillar/rigged to keep vertical axis along Blender +Z!
    if args.kind == "prop_chest":
        build_prop_chest_knightlore(palette)
    elif args.kind == "prop_cauldron":
        build_prop_cauldron_knightlore(palette)
    elif args.kind == "prop_key":
        c_gold = palette[0] if palette else (0.95, 0.78, 0.22)
        gold_mat = make_pbr_material("OrnateGold", (c_gold[0], c_gold[1], c_gold[2], 1.0), metallic=0.92, roughness=0.24, emission=(c_gold[0] * 0.35, c_gold[1] * 0.35, c_gold[2] * 0.2), emission_strength=0.6)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.035, location=(0.0, 0.0, 0.38), rotation=(math.pi * 0.5, 0.0, 0.0))
        bow = bpy.context.active_object
        bow.name = "KeyBow"
        bow.data.materials.append(gold_mat)
        add_cylinder("KeyShaft", (0.0, 0.0, 0.16), 0.032, 0.32, gold_mat, verts=14)
        add_beveled_box("KeyToothA", (0.06, 0.0, 0.08), (0.10, 0.04, 0.04), gold_mat, bevel_width=0.005)
        add_beveled_box("KeyToothB", (0.05, 0.0, 0.02), (0.08, 0.04, 0.04), gold_mat, bevel_width=0.005)
    elif args.kind == "prop_pillar":
        build_prop_pillar_knightlore()
    elif args.kind == "prop_arch_doorway":
        build_prop_arch_doorway()
    elif args.kind == "prop_door_trim_to_forest":
        build_prop_door_trim_to_forest()
    elif args.kind == "prop_door_trim_to_stone":
        build_prop_door_trim_to_stone()
    elif args.kind == "prop_wall_panel":
        build_prop_wall_panel()
    elif args.kind == "prop_wall_lintel_panel":
        build_prop_wall_lintel_panel()
    elif args.kind == "prop_portcullis":
        build_prop_portcullis()
    elif args.kind == "prop_stone_block":
        build_prop_stone_block()
    elif args.kind == "prop_moving_platform":
        build_prop_moving_platform()
    elif args.kind == "prop_collapsing_tile":
        build_prop_collapsing_tile()
    elif args.kind == "prop_pressure_plate":
        build_prop_pressure_plate()
    elif args.kind == "prop_tree_wall_panel":
        build_prop_tree_wall_panel()
    elif args.kind == "prop_tree_wall_lintel":
        build_prop_tree_lintel_panel()
    elif args.kind == "prop_low_wall_stone":
        build_prop_low_wall_stone()
    elif args.kind == "prop_low_wall_woodland":
        build_prop_low_wall_woodland()
    elif args.kind == "prop_tree_arch_doorway":
        build_prop_tree_arch_doorway()
    elif args.kind == "prop_table":
        build_prop_table()
    elif args.kind == "prop_rock":
        build_prop_rock()
    elif args.kind == "prop_dropping_block":
        build_prop_dropping_block()
    elif args.kind == "prop_gargoyle":
        build_prop_gargoyle()
    elif args.kind == "prop_spikes":
        build_prop_spikes()
    elif args.kind == "prop_spiked_ball":
        build_prop_spiked_ball()
    elif args.kind == "prop_ball":
        build_prop_ball()
    elif args.kind == "prop_fire":
        build_prop_fire()
    elif args.kind == "prop_ghost":
        build_prop_ghost()
    elif args.kind == "prop_item_diamond":
        build_prop_item_diamond()
    elif args.kind == "prop_item_poison":
        build_prop_item_poison()
    elif args.kind == "prop_item_boot":
        build_prop_item_boot()
    elif args.kind == "prop_item_chalice":
        build_prop_item_chalice()
    elif args.kind == "prop_item_cup":
        build_prop_item_cup()
    elif args.kind == "prop_item_bottle":
        build_prop_item_bottle()
    elif args.kind == "prop_item_crystal_ball":
        build_prop_item_crystal_ball()
    elif args.kind == "prop_item_extra_life":
        build_prop_item_extra_life()
    elif args.kind == "character_humanoid":
        build_rigged_character(args.kind, palette)
    elif args.kind == "character_sentinel":
        build_rigged_sentinel(palette)
    elif args.kind == "character_melkhior":
        build_rigged_melkhior(palette)
    elif args.kind == "character_explorer":
        build_rigged_explorer(palette, _load_proportions(sprite_path))
    elif args.kind == "character_werewolf":
        build_rigged_werewolf(palette, _load_proportions(sprite_path))
    else:
        build_generic_sprite_sculpt(sprite_path, args.height)

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=True,
        export_skins=True,
    )
    print(f"Generated raw GLB ({args.kind}) -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
