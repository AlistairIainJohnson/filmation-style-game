#!/usr/bin/env python3
"""Compiles an LDtk v1.5.3 GridVania world file into canonical Filmation JSON room files
and data/world_graph.json."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ENTITY_MAP = {
    "PushableChest": "pushable_chest",
    "PressurePlate": "pressure_plate",
    "Portcullis": "portcullis",
    "Cauldron": "cauldron",
    "MovingPlatform": "moving_platform",
    "CollapsingTile": "collapsing_tile",
    "CollectibleKey": "collectible_key",
    "PatrolSentinel": "patrol_sentinel",
}


def _fields_dict(entity_inst: dict) -> dict:
    out: dict = {}
    for f in entity_inst.get("fieldInstances", []):
        out[f["__identifier"]] = f.get("__value")
    return out


def _level_fields(level: dict) -> dict:
    out: dict = {}
    for f in level.get("fieldInstances", []):
        out[f["__identifier"]] = f.get("__value")
    return out


def compile_ldtk(ldtk_path: Path, out_dir: Path) -> tuple[Path, list[Path]]:
    with ldtk_path.open("r", encoding="utf-8") as fh:
        ldtk = json.load(fh)

    grid_w_px = int(ldtk.get("worldGridWidth", 192))
    grid_h_px = int(ldtk.get("worldGridHeight", 192))
    cell_px = int(ldtk.get("defaultGridSize", 16))

    rooms_out_dir = out_dir / "rooms"
    rooms_out_dir.mkdir(parents=True, exist_ok=True)

    written_rooms: list[Path] = []
    world_rooms: list[dict] = []

    for level in ldtk.get("levels", []):
        lfields = _level_fields(level)
        rx = int(level.get("worldX", 0)) // grid_w_px
        ry = int(level.get("worldY", 0)) // grid_h_px
        width = int(level.get("pxWid", grid_w_px)) // cell_px
        depth = int(level.get("pxHei", grid_h_px)) // cell_px
        height = int(lfields.get("height", 6))

        room_name = str(lfields.get("room_name") or level.get("identifier", f"Room_{rx}_{ry}"))
        lighting_day = str(lfields.get("lighting_preset") or "castle_stone_skylight")
        lighting_night = str(lfields.get("lighting_preset_night") or "castle_moonlight_night")
        cam_mode = str(lfields.get("camera_mode") or "true_isometric")

        void_cells: list[list[int]] = []
        blocks: list[dict] = []
        foreground_occluders: list[dict] = []
        exits: dict[str, dict] = {}
        world_exits: dict[str, list[int]] = {}
        entities: list[dict] = []

        for layer in level.get("layerInstances", []):
            lid = layer.get("__identifier", "")
            c_wid = int(layer.get("__cWid", width))
            csv = layer.get("intGridCsv", [])

            if lid == "Floor_Y0" and csv:
                for idx, val in enumerate(csv):
                    if int(val) == 0:
                        void_cells.append([idx % c_wid, idx // c_wid])
            elif lid == "Blocks_Y0" and csv:
                for idx, val in enumerate(csv):
                    v = int(val)
                    if v == 0:
                        continue
                    x, z = idx % c_wid, idx // c_wid
                    if v == 1:
                        blocks.append({"type": "stone_ledge", "material": "stone_ledge", "pos": [x, 0, z], "size": [1, 1, 1]})
                    elif v == 2:
                        blocks.append({"type": "stone_pillar", "material": "stone_pillar", "pos": [x, 0, z], "size": [1, 3.5, 1], "cutaway": True})
                    elif v == 3:
                        blocks.append({"type": "stone_plinth", "material": "stone_pillar", "pos": [x, 0, z], "size": [1, 1, 1]})
                    elif v == 4:
                        foreground_occluders.append({"type": "arch_column", "material": "stone_pillar", "pos": [x, 0, z], "size": [1, 4, 1], "cutaway": True})
            elif lid == "Blocks_Y1" and csv:
                for idx, val in enumerate(csv):
                    if int(val) == 1:
                        x, z = idx % c_wid, idx // c_wid
                        blocks.append({"type": "stone_ledge", "material": "stone_ledge", "pos": [x, 1, z], "size": [1, 1, 1], "cutaway": True})
            elif lid == "Entities":
                for ent in layer.get("entityInstances", []):
                    e_type = ent.get("__identifier", "")
                    gx, gz = ent.get("__grid", [0, 0])
                    ef = _fields_dict(ent)
                    if e_type == "Doorway":
                        d_name = str(ef.get("direction", "north"))
                        target = [int(ef.get("target_rx", rx)), int(ef.get("target_ry", ry))]
                        door_pos = [int(gx), int(gz)]
                        exit_obj: dict = {
                            "target_room": target,
                            "door_pos": door_pos,
                            "width": int(ef.get("width", 2)),
                            "height": float(ef.get("height", 3.0)),
                        }
                        if ef.get("locked_by"):
                            exit_obj["locked_by"] = str(ef["locked_by"])
                        exits[d_name] = exit_obj
                        world_exits[d_name] = target
                    elif e_type in ENTITY_MAP:
                        eid = str(ef.get("id") or f"{ENTITY_MAP[e_type]}_{gx}_{gz}")
                        elev = float(ef.get("elevation", 0.0))
                        pos_x = float(ef.get("exact_x", float(gx) + 0.5))
                        pos_z = float(ef.get("exact_z", float(gz) + 0.5))
                        ent_obj: dict = {
                            "id": eid,
                            "archetype": ENTITY_MAP[e_type],
                            "pos": [pos_x, elev, pos_z],
                            "persistent": bool(ef.get("persistent", True)),
                        }
                        if ef.get("triggers"):
                            ent_obj["triggers"] = list(ef["triggers"])
                        if "starts_closed" in ef and ef["starts_closed"] is not None:
                            ent_obj["starts_closed"] = bool(ef["starts_closed"])
                        if "rotation_y" in ef and ef["rotation_y"] is not None:
                            ent_obj["rotation_y"] = float(ef["rotation_y"])
                        if ef.get("item_kind"):
                            ent_obj["item_kind"] = str(ef["item_kind"])
                        if ef.get("waypoints"):
                            ent_obj["waypoints"] = list(ef["waypoints"])
                        if "move_speed" in ef and ef["move_speed"] is not None:
                            ent_obj["move_speed"] = float(ef["move_speed"])
                        if "patrol_speed" in ef and ef["patrol_speed"] is not None:
                            ent_obj["patrol_speed"] = float(ef["patrol_speed"])
                        entities.append(ent_obj)

        room_obj = {
            "room_id": [rx, ry],
            "name": room_name,
            "dimensions": {"width": width, "depth": depth, "height": height},
            "camera": {"mode": cam_mode, "margin": 0.10},
            "lighting_preset": lighting_day,
            "floor": {
                "material": "stone_floor",
                "checker_material": "stone_floor_alt",
                "thickness": 0.5,
                "void_cells": void_cells,
            },
            "walls": {
                "material": "stone_wall",
                "curb_material": "foreground_curb",
                "trim_material": "doorway_trim",
                "thickness": 0.5,
                "curb_height": 0.4,
            },
            "exits": exits,
            "blocks": blocks,
            "foreground_occluders": foreground_occluders,
            "entities": entities,
        }

        room_filename = f"room_{rx:02d}_{ry:02d}.json"
        room_out = rooms_out_dir / room_filename
        with room_out.open("w", encoding="utf-8") as fh:
            json.dump(room_obj, fh, indent=2)
            fh.write("\n")
        written_rooms.append(room_out)

        world_rooms.append({
            "id": [rx, ry],
            "json_path": f"res://data/rooms/{room_filename}",
            "scene_path": "res://core/world/chamber_shell.tscn",
            "lighting_preset_day": lighting_day,
            "lighting_preset_night": lighting_night,
            "exits": world_exits,
        })

    world_graph = {
        "world_name": str(ldtk.get("worldName") or "Filmation Citadel"),
        "grid_size": [16, 16],
        "start_room": [8, 8],
        "start_spawn": "north",
        "cycle": {
            "enabled": False,
            "day_duration_sec": 45.0,
            "night_duration_sec": 35.0,
            "night_jump_height_multiplier": 1.22,
        },
        "rooms": world_rooms,
    }
    wg_out = out_dir / "world_graph.json"
    with wg_out.open("w", encoding="utf-8") as fh:
        json.dump(world_graph, fh, indent=2)
        fh.write("\n")

    return wg_out, written_rooms


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Compile LDtk v1.5.3 world into canonical Filmation JSON")
    parser.add_argument("--in", dest="inp", default=str(root / "levels" / "filmation_world.ldtk"))
    parser.add_argument("--out-dir", dest="out_dir", default=str(root / "data"))
    args = parser.parse_args(argv)

    wg_out, written = compile_ldtk(Path(args.inp).resolve(), Path(args.out_dir).resolve())
    print(f"Compiled {len(written)} room(s) and {wg_out.name} from {Path(args.inp).name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
