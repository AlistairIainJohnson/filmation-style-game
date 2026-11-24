#!/usr/bin/env python3
"""Static validator and playability linter for Filmation world graphs and room JSONs."""

from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path
from jsonschema import Draft202012Validator

OPPOSITE_EXIT = {
    "north": "south",
    "south": "north",
    "east": "west",
    "west": "east",
}


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def res_to_path(root: Path, data_dir: Path, res_path: str) -> Path:
    if res_path.startswith("res://data/"):
        return data_dir / res_path[len("res://data/") :]
    if res_path.startswith("res://"):
        return root / res_path[len("res://") :]
    return root / res_path


def _spawn_cell_for_exit(dir_name: str, exit_cfg: dict, width: int, depth: int) -> tuple[int, int]:
    door_pos = exit_cfg.get("door_pos", [0, 0])
    door_w = int(exit_cfg.get("width", 2))
    if dir_name == "north":
        return (int(door_pos[0]) + door_w // 2, 1)
    if dir_name == "south":
        return (int(door_pos[0]) + door_w // 2, depth - 2)
    if dir_name == "west":
        return (1, int(door_pos[1]) + door_w // 2)
    return (width - 2, int(door_pos[1]) + door_w // 2)


def validate_data_dir(data_dir: Path, root: Path | None = None) -> tuple[list[str], list[str], dict]:
    if root is None:
        root = Path(__file__).resolve().parent.parent
    schemas_dir = root / "schemas"

    room_schema = load_json(schemas_dir / "room.schema.json")
    lighting_schema = load_json(schemas_dir / "lighting_presets.schema.json")
    world_schema = load_json(schemas_dir / "world_graph.schema.json")

    room_validator = Draft202012Validator(room_schema)
    lighting_validator = Draft202012Validator(lighting_schema)
    world_validator = Draft202012Validator(world_schema)

    materials = load_json(data_dir / "materials.json")
    entities_catalog = load_json(data_dir / "entities.json")
    lighting_presets = load_json(data_dir / "lighting_presets.json")

    errors: list[str] = []
    warnings: list[str] = []

    for err in lighting_validator.iter_errors(lighting_presets):
        errors.append(f"lighting_presets.json: {err.message} at {list(err.path)}")

    room_files = sorted((data_dir / "rooms").glob("*.json"))
    if not room_files:
        errors.append("No room JSON files found in rooms/")

    rooms_data_by_id: dict[tuple[int, int], tuple[str, dict]] = {}

    for room_path in room_files:
        room = load_json(room_path)
        rel = room_path.name
        for err in room_validator.iter_errors(room):
            errors.append(f"{rel}: {err.message} at {list(err.path)}")

        rid = (int(room["room_id"][0]), int(room["room_id"][1]))
        rooms_data_by_id[rid] = (rel, room)

        dims = room.get("dimensions", {})
        w = int(dims.get("width", 12))
        d = int(dims.get("depth", 12))
        h = int(dims.get("height", 6))

        preset = room.get("lighting_preset")
        if preset not in lighting_presets:
            errors.append(f"{rel}: unknown lighting_preset '{preset}'")

        floor_cfg = room.get("floor", {})
        for mat_key in ["material", "checker_material"]:
            mat_val = floor_cfg.get(mat_key)
            if mat_val and mat_val not in materials:
                errors.append(f"{rel}: unknown floor.{mat_key} '{mat_val}'")

        wall_cfg = room.get("walls", {})
        for mat_key in ["material", "curb_material", "trim_material"]:
            mat_val = wall_cfg.get(mat_key)
            if mat_val and mat_val not in materials:
                errors.append(f"{rel}: unknown walls.{mat_key} '{mat_val}'")

        void_set: set[tuple[int, int]] = set()
        for cell in floor_cfg.get("void_cells", []):
            cx, cz = int(cell[0]), int(cell[1])
            if not (0 <= cx < w and 0 <= cz < d):
                errors.append(f"{rel}: void_cell {[cx, cz]} out of room bounds {w}x{d}")
            void_set.add((cx, cz))

        ground_blocked: set[tuple[int, int]] = set()
        has_pushable_or_platform = any(
            entities_catalog.get(e.get("archetype", ""), {}).get("kinematic_kind") in ("pushable_block", "moving_platform")
            for e in room.get("entities", [])
        )
        walkable_tops: list[float] = [0.0]

        for idx, blk in enumerate(room.get("blocks", [])):
            mat_val = blk.get("material")
            if mat_val not in materials:
                errors.append(f"{rel}: blocks[{idx}] unknown material '{mat_val}'")
            bx, by, bz = [float(v) for v in blk.get("pos", [0, 0, 0])]
            sx, sy, sz = [float(v) for v in blk.get("size", [1, 1, 1])]
            if bx < 0.0 or bz < 0.0 or bx + sx > w + 0.01 or bz + sz > d + 0.01 or by < 0.0 or by + sy > h + 0.01:
                errors.append(f"{rel}: blocks[{idx}] out of room bounds")
            if by < 0.5:
                for gx in range(int(bx), min(w, int(bx + sx + 0.99))):
                    for gz in range(int(bz), min(d, int(bz + sz + 0.99))):
                        ground_blocked.add((gx, gz))
            if sy < 2.5:
                walkable_tops.append(by + sy)

        for top_y in walkable_tops:
            if top_y > 1.25 and not has_pushable_or_platform:
                lower_step_exists = any(0.0 < prev < top_y and (top_y - prev) <= 1.25 for prev in walkable_tops)
                if not lower_step_exists:
                    warnings.append(f"{rel}: elevated ledge at y={top_y:.2f}m exceeds 1.25m single-jump clearance without step/block")

        for idx, occ in enumerate(room.get("foreground_occluders", [])):
            mat_val = occ.get("material")
            if mat_val not in materials:
                errors.append(f"{rel}: foreground_occluders[{idx}] unknown material '{mat_val}'")

        seen_ids: set[str] = set()
        for idx, ent in enumerate(room.get("entities", [])):
            eid = ent.get("id", "")
            if eid in seen_ids:
                errors.append(f"{rel}: duplicate entity id '{eid}'")
            seen_ids.add(eid)
            arch = ent.get("archetype")
            if arch not in entities_catalog:
                errors.append(f"{rel}: entities[{idx}] unknown archetype '{arch}'")
            ex, ey, ez = [float(v) for v in ent.get("pos", [0, 0, 0])]
            if ex < -0.5 or ez < -0.5 or ex > w + 0.5 or ez > d + 0.5 or ey < 0.0:
                errors.append(f"{rel}: entity '{eid}' pos {[ex, ey, ez]} out of bounds")

        for ent in room.get("entities", []):
            for tid in ent.get("triggers", []):
                if tid not in seen_ids:
                    errors.append(f"{rel}: entity '{ent.get('id')}' triggers unknown entity '{tid}'")

        for d_name, exit_cfg in room.get("exits", {}).items():
            sx, sz = _spawn_cell_for_exit(d_name, exit_cfg, w, d)
            if (sx, sz) in void_set:
                errors.append(f"{rel}: exit '{d_name}' spawn cell {(sx, sz)} is a void_cell")
            if (sx, sz) in ground_blocked:
                errors.append(f"{rel}: exit '{d_name}' spawn cell {(sx, sz)} is blocked by a floor-level block")

    world_path = data_dir / "world_graph.json"
    wg_count = 0
    if world_path.exists():
        wg = load_json(world_path)
        for err in world_validator.iter_errors(wg):
            errors.append(f"world_graph.json: {err.message} at {list(err.path)}")

        rooms_by_id: dict[tuple[int, int], dict] = {}
        for r in wg.get("rooms", []):
            rid = (int(r["id"][0]), int(r["id"][1]))
            if rid in rooms_by_id:
                errors.append(f"world_graph.json: duplicate room id {rid}")
            rooms_by_id[rid] = r

            r_json = res_to_path(root, data_dir, r["json_path"])
            if not r_json.exists():
                errors.append(f"world_graph.json: missing room json_path {r['json_path']}")
            if r.get("scene_path") and not res_to_path(root, data_dir, r["scene_path"]).exists():
                errors.append(f"world_graph.json: missing scene_path {r['scene_path']}")
            for pk in ["lighting_preset_day", "lighting_preset_night"]:
                pval = r.get(pk)
                if pval not in lighting_presets:
                    errors.append(f"world_graph.json: room {rid} unknown {pk} '{pval}'")

        wg_count = len(rooms_by_id)
        start_id = (int(wg["start_room"][0]), int(wg["start_room"][1]))
        if start_id not in rooms_by_id:
            errors.append(f"world_graph.json: start_room {start_id} not in rooms")

        for rid, r in rooms_by_id.items():
            # Verify world_graph exits match the room JSON exits
            if rid in rooms_data_by_id:
                rel_name, room_json = rooms_data_by_id[rid]
                room_exits = {k: tuple(int(v) for v in val["target_room"]) for k, val in room_json.get("exits", {}).items()}
                wg_exits = {k: tuple(int(v) for v in val) for k, val in r.get("exits", {}).items()}
                if room_exits != wg_exits:
                    errors.append(f"world_graph.json: room {rid} exits {wg_exits} differ from {rel_name} exits {room_exits}")

            for d_name, target_arr in r.get("exits", {}).items():
                tid = (int(target_arr[0]), int(target_arr[1]))
                if tid not in rooms_by_id:
                    errors.append(f"world_graph.json: room {rid} exit '{d_name}' targets missing room {tid}")
                    continue
                opp = OPPOSITE_EXIT[d_name]
                rev_target = rooms_by_id[tid].get("exits", {}).get(opp)
                if rev_target is None or (int(rev_target[0]), int(rev_target[1])) != rid:
                    errors.append(f"world_graph.json: exit reciprocity broken {rid} --{d_name}--> {tid} (missing {opp} back)")

        # BFS reachability from start_room
        if start_id in rooms_by_id:
            visited: set[tuple[int, int]] = {start_id}
            queue: deque[tuple[int, int]] = deque([start_id])
            while queue:
                cur = queue.popleft()
                for target_arr in rooms_by_id[cur].get("exits", {}).values():
                    tid = (int(target_arr[0]), int(target_arr[1]))
                    if tid in rooms_by_id and tid not in visited:
                        visited.add(tid)
                        queue.append(tid)
            unreachable = set(rooms_by_id.keys()) - visited
            if unreachable:
                errors.append(f"world_graph.json: unreachable room(s) from start_room {start_id}: {sorted(unreachable)}")

    summary = {"rooms": len(room_files), "presets": len(lighting_presets), "world_rooms": wg_count}
    return errors, warnings, summary


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Validate Filmation world graph and room layouts")
    parser.add_argument("--data-dir", default=str(root / "data"))
    args = parser.parse_args(argv)

    errors, warnings, summary = validate_data_dir(Path(args.data_dir).resolve(), root)
    for w in warnings:
        print(f"WARN: {w}")
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print(
        f"Validated {summary['rooms']} room(s), {summary['presets']} lighting preset(s), "
        f"and {summary['world_rooms']} world_graph node(s) cleanly."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
