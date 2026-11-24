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
    ("LeftUpperArm", "Chest", (0.24, 0.0, 0.82), (0.38, 0.0, 0.67)),
    ("LeftLowerArm", "LeftUpperArm", (0.38, 0.0, 0.67), (0.47, 0.0, 0.53)),
    ("LeftHand", "LeftLowerArm", (0.47, 0.0, 0.53), (0.51, 0.0, 0.46)),
    ("RightUpperArm", "Chest", (-0.24, 0.0, 0.82), (-0.38, 0.0, 0.67)),
    ("RightLowerArm", "RightUpperArm", (-0.38, 0.0, 0.67), (-0.47, 0.0, 0.53)),
    ("RightHand", "RightLowerArm", (-0.47, 0.0, 0.53), (-0.51, 0.0, 0.46)),
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
    ("LeftUpperArm", "Chest", (0.28, 0.0, 0.92), (0.42, 0.0, 0.74)),
    ("LeftLowerArm", "LeftUpperArm", (0.42, 0.0, 0.74), (0.50, -0.02, 0.57)),
    ("LeftHand", "LeftLowerArm", (0.50, -0.02, 0.57), (0.54, -0.05, 0.48)),
    ("RightUpperArm", "Chest", (-0.28, 0.0, 0.92), (-0.42, 0.0, 0.74)),
    ("RightLowerArm", "RightUpperArm", (-0.42, 0.0, 0.74), (-0.50, -0.02, 0.57)),
    ("RightHand", "RightLowerArm", (-0.50, -0.02, 0.57), (-0.54, -0.05, 0.48)),
    ("LeftUpperLeg", "Hips", (0.13, 0.0, 0.48), (0.13, 0.0, 0.27)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.13, 0.0, 0.27), (0.13, 0.0, 0.10)),
    ("LeftFoot", "LeftLowerLeg", (0.13, 0.0, 0.10), (0.13, -0.11, 0.0)),
    ("RightUpperLeg", "Hips", (-0.13, 0.0, 0.48), (-0.13, 0.0, 0.27)),
    ("RightLowerLeg", "RightUpperLeg", (-0.13, 0.0, 0.27), (-0.13, 0.0, 0.10)),
    ("RightFoot", "RightLowerLeg", (-0.13, 0.0, 0.10), (-0.13, -0.11, 0.0)),
]


def build_rigged_explorer(palette: list[tuple[float, float, float]], prop_data: dict) -> None:
    """Chibi 1984 Sabreman-inspired explorer with pith helmet & safari tunic matching
    concept-art/knight-lore-sprites.jpg Rows 2-3 and concept-art/inspiration.png."""
    exp_pal = prop_data.get("explorer", {}).get("palette", {})
    c_helmet = tuple(exp_pal.get("helmet", palette[0] if len(palette) > 0 else (0.784, 0.663, 0.431)))
    c_tunic = tuple(exp_pal.get("tunic", (0.788, 0.643, 0.361)))
    c_skin = tuple(exp_pal.get("skin", (0.839, 0.624, 0.494)))
    c_boots = tuple(exp_pal.get("boots", (0.278, 0.180, 0.106)))
    c_brass = tuple(exp_pal.get("brass", (0.851, 0.659, 0.259)))

    helmet_mat = make_pbr_material("ExplorerHelmet", (*c_helmet, 1.0), metallic=0.04, roughness=0.76)
    tunic_mat = make_pbr_material("ExplorerTunic", (*c_tunic, 1.0), metallic=0.03, roughness=0.80)
    skin_mat = make_pbr_material("ExplorerSkin", (*c_skin, 1.0), metallic=0.0, roughness=0.62)
    nose_mat = make_pbr_material("ExplorerNose", (0.86, 0.60, 0.47, 1.0), metallic=0.0, roughness=0.58)
    leather_mat = make_pbr_material("ExplorerLeather", (*c_boots, 1.0), metallic=0.08, roughness=0.52)
    brass_mat = make_pbr_material("ExplorerBrass", (*c_brass, 1.0), metallic=0.88, roughness=0.28)
    eye_white_mat = make_pbr_material("ExplorerEyeWhite", (0.96, 0.95, 0.92, 1.0), metallic=0.0, roughness=0.28)
    eye_mat = make_pbr_material("ExplorerEyes", (0.06, 0.05, 0.05, 1.0), metallic=0.1, roughness=0.22)
    hair_mat = make_pbr_material("ExplorerHair", (0.26, 0.16, 0.09, 1.0), metallic=0.02, roughness=0.72)

    arm_obj = _create_armature_from_bones(EXPLORER_BONES)

    def _sphere(name: str, bone: str, loc: tuple[float, float, float], r: float, scl: tuple[float, float, float], mat: bpy.types.Material, rot: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> None:
        obj = add_uv_sphere(name, loc, r, mat, scale=scl, rotation=rot)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    def _cyl(name: str, bone: str, loc: tuple[float, float, float], r: float, depth: float, mat: bpy.types.Material, rot: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> None:
        obj = add_cylinder(name, loc, r, depth, mat, verts=16, rotation=rot)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    def _box(name: str, bone: str, loc: tuple[float, float, float], sz: tuple[float, float, float], mat: bpy.types.Material, bevel: float = 0.015) -> None:
        obj = add_beveled_box(name, loc, sz, mat, bevel_width=bevel, segments=2)
        _set_smooth(obj)
        _assign_bone_weight(obj, bone, arm_obj)

    # Head & clearly visible face under a raised, tilted-back pith helmet
    _sphere("HeadBase", "Head", (0.0, -0.02, 1.03), 0.21, (1.0, 0.96, 0.98), skin_mat)
    _sphere("Nose", "Head", (0.0, -0.228, 1.000), 0.036, (1.1, 1.15, 0.90), nose_mat)
    _sphere("Mustache", "Head", (0.0, -0.205, 0.955), 1.0, (0.088, 0.034, 0.024), hair_mat)
    for side_tag, sx in (("L", 0.072), ("R", -0.072)):
        _sphere(f"EyeWhite_{side_tag}", "Head", (sx, -0.195, 1.035), 0.036, (1.0, 0.55, 1.15), eye_white_mat)
        _sphere(f"EyePupil_{side_tag}", "Head", (sx, -0.212, 1.032), 0.020, (1.0, 0.55, 1.15), eye_mat)
        _box(f"Brow_{side_tag}", "Head", (sx, -0.196, 1.078), (0.068, 0.024, 0.018), hair_mat, bevel=0.005)

    rot_helmet = (-math.radians(18.0), 0.0, 0.0)
    _sphere("HelmetBrim", "Head", (0.0, 0.03, 1.215), 1.0, (0.295, 0.305, 0.042), helmet_mat, rot=rot_helmet)
    _sphere("HelmetCrown", "Head", (0.0, 0.05, 1.275), 1.0, (0.225, 0.235, 0.165), helmet_mat, rot=rot_helmet)
    _cyl("HelmetBand", "Head", (0.0, 0.038, 1.235), 0.215, 0.036, leather_mat, rot=rot_helmet)
    _sphere("HelmetButton", "Head", (0.0, 0.095, 1.430), 0.030, (1.0, 1.0, 0.7), helmet_mat, rot=rot_helmet)

    # Torso: rounded safari tunic, waist belt & brass buckle
    _sphere("ChestTunic", "Chest", (0.0, 0.0, 0.78), 1.0, (0.255, 0.215, 0.175), tunic_mat)
    _box("Collar", "Chest", (0.0, -0.11, 0.875), (0.16, 0.12, 0.055), tunic_mat, bevel=0.015)
    _sphere("SpineTunic", "Spine", (0.0, 0.0, 0.635), 1.0, (0.245, 0.21, 0.145), tunic_mat)
    _cyl("WaistBelt", "Spine", (0.0, 0.0, 0.565), 0.235, 0.055, leather_mat)
    _box("BeltBuckle", "Spine", (0.0, -0.23, 0.565), (0.085, 0.035, 0.065), brass_mat, bevel=0.008)
    _sphere("PelvisTunic", "Hips", (0.0, 0.0, 0.495), 1.0, (0.225, 0.195, 0.12), leather_mat)

    # Puffed safari sleeves, forearms & rounded hands
    for side_tag, sign_x in (("L", 1.0), ("R", -1.0)):
        _sphere(f"Sleeve_{side_tag}", f"{'Left' if sign_x > 0 else 'Right'}UpperArm", (sign_x * 0.275, 0.0, 0.775), 1.0, (0.11, 0.105, 0.105), tunic_mat)
        _cyl(f"Forearm_{side_tag}", f"{'Left' if sign_x > 0 else 'Right'}LowerArm", (sign_x * 0.425, 0.0, 0.60), 0.056, 0.18, skin_mat, rot=(0.0, -sign_x * math.radians(32.0), 0.0))
        _sphere(f"Hand_{side_tag}", f"{'Left' if sign_x > 0 else 'Right'}Hand", (sign_x * 0.49, 0.0, 0.495), 0.065, (1.0, 1.0, 1.05), skin_mat)

    # Short legs & sturdy boots grounded at z = 0.0
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        _cyl(f"ThighShorts_{side_tag}", f"{bone_prefix}UpperLeg", (sign_x * 0.11, 0.0, 0.35), 0.088, 0.20, leather_mat)
        _cyl(f"Shin_{side_tag}", f"{bone_prefix}LowerLeg", (sign_x * 0.11, 0.0, 0.18), 0.066, 0.16, skin_mat)
        _box(f"Boot_{side_tag}", f"{bone_prefix}Foot", (sign_x * 0.11, -0.04, 0.06), (0.14, 0.23, 0.12), leather_mat, bevel=0.03)


def build_rigged_werewolf(palette: list[tuple[float, float, float]], prop_data: dict) -> None:
    """Night-form Werewolf character driven by concept-art/knight-lore-sprites.jpg Rows 4-5."""
    wolf_pal = prop_data.get("werewolf", {}).get("palette", {})
    c_fur = tuple(wolf_pal.get("fur", palette[0] if len(palette) > 0 else (0.294, 0.208, 0.153)))
    c_ruff = tuple(wolf_pal.get("ruff", (0.431, 0.325, 0.251)))
    c_tunic = tuple(wolf_pal.get("tattered_tunic", (0.722, 0.588, 0.333)))
    c_eye = tuple(wolf_pal.get("amber_eye", (0.961, 0.706, 0.153)))
    c_claw = tuple(wolf_pal.get("claws", (0.140, 0.115, 0.105)))

    fur_mat = make_pbr_material("WolfFur", (*c_fur, 1.0), metallic=0.02, roughness=0.88)
    ruff_mat = make_pbr_material("WolfRuff", (*c_ruff, 1.0), metallic=0.02, roughness=0.84)
    shorts_mat = make_pbr_material("TatteredShorts", (*c_tunic, 1.0), metallic=0.02, roughness=0.86)
    eye_mat = make_pbr_material("WolfAmberEye", (*c_eye, 1.0), metallic=0.1, roughness=0.20, emission=c_eye, emission_strength=1.6)
    claw_mat = make_pbr_material("WolfClaws", (*c_claw, 1.0), metallic=0.22, roughness=0.45)

    arm_obj = _create_armature_from_bones(WEREWOLF_BONES)

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

    # Wolf skull, elongated snout, pointed ears & glowing amber eyes
    _sphere("WolfHead", "Head", (0.0, 0.0, 1.22), 1.0, (0.215, 0.23, 0.20), fur_mat)
    _sphere("WolfSnout", "Head", (0.0, -0.22, 1.175), 1.0, (0.11, 0.145, 0.085), ruff_mat)
    _sphere("WolfNose", "Head", (0.0, -0.355, 1.195), 0.036, (1.1, 0.9, 0.8), claw_mat)
    for side_tag, sign_x in (("L", 1.0), ("R", -1.0)):
        _sphere(f"WolfEye_{side_tag}", "Head", (sign_x * 0.082, -0.20, 1.255), 0.028, (1.0, 0.7, 0.9), eye_mat)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.065, radius2=0.008, depth=0.18, location=(sign_x * 0.125, 0.02, 1.43), rotation=(math.radians(-10.0), sign_x * math.radians(16.0), 0.0))
        ear = bpy.context.active_object
        ear.name = f"WolfEar_{side_tag}"
        ear.data.materials.append(fur_mat)
        _set_smooth(ear)
        _assign_bone_weight(ear, "Head", arm_obj)

    # Broad hunched chest with lighter chest ruff + tattered explorer shorts
    _sphere("WolfChest", "Chest", (0.0, 0.0, 0.88), 1.0, (0.295, 0.24, 0.20), fur_mat)
    _sphere("WolfRuff", "Chest", (0.0, -0.10, 0.885), 1.0, (0.20, 0.175, 0.16), ruff_mat)
    _sphere("WolfTorso", "Spine", (0.0, 0.0, 0.70), 1.0, (0.245, 0.205, 0.16), fur_mat)
    _box("WolfShorts", "Hips", (0.0, 0.0, 0.545), (0.44, 0.35, 0.16), shorts_mat, bevel=0.03)

    # Muscular fur arms & clawed hands
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        _cyl(f"WolfArmUp_{side_tag}", f"{bone_prefix}UpperArm", (sign_x * 0.35, 0.0, 0.83), 0.082, 0.22, fur_mat, rot=(0.0, -sign_x * math.radians(38.0), 0.0))
        _cyl(f"WolfArmLo_{side_tag}", f"{bone_prefix}LowerArm", (sign_x * 0.46, -0.01, 0.655), 0.068, 0.19, fur_mat, rot=(0.0, -sign_x * math.radians(24.0), 0.0))
        _box(f"WolfPaw_{side_tag}", f"{bone_prefix}Hand", (sign_x * 0.52, -0.04, 0.525), (0.11, 0.13, 0.11), claw_mat, bevel=0.025)

    # Beast legs & clawed feet grounded cleanly at z = 0.0
    for side_tag, bone_prefix, sign_x in (("L", "Left", 1.0), ("R", "Right", -1.0)):
        _cyl(f"WolfThigh_{side_tag}", f"{bone_prefix}UpperLeg", (sign_x * 0.13, 0.0, 0.375), 0.095, 0.21, shorts_mat if side_tag else fur_mat)
        _cyl(f"WolfShin_{side_tag}", f"{bone_prefix}LowerLeg", (sign_x * 0.13, 0.0, 0.185), 0.072, 0.18, fur_mat)
        _box(f"WolfFoot_{side_tag}", f"{bone_prefix}Foot", (sign_x * 0.13, -0.05, 0.055), (0.15, 0.25, 0.11), claw_mat, bevel=0.03)


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
    elif args.kind == "prop_wall_panel":
        build_prop_wall_panel()
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
    elif args.kind == "character_humanoid":
        build_rigged_character(args.kind, palette)
    elif args.kind == "character_sentinel":
        build_rigged_sentinel(palette)
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
