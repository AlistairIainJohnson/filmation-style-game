#!/usr/bin/env python3
"""Validator for pre-decoded Knight Lore data pack under data/knight_lore/."""

from __future__ import annotations

import json
import sys
from pathlib import Path

EXPECTED_START_ROOMS = {47, 68, 143, 179}


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def neighbor_room_id(room_id: int, dir_name: str) -> int:
    if dir_name == "west":
        return (room_id & 0xF0) | ((room_id - 1) & 0x0F)
    if dir_name == "east":
        return (room_id & 0xF0) | ((room_id + 1) & 0x0F)
    if dir_name == "north":
        return (room_id + 16) & 0xFF
    if dir_name == "south":
        return (room_id - 16) & 0xFF
    raise ValueError(f"Unknown direction: {dir_name}")


def _exit_dir_from_bg(bg_name: str) -> str | None:
    if bg_name.startswith(("arch_", "tree_arch_", "high_arch_")) and not bg_name.endswith("_base"):
        suffix = bg_name.rsplit("_", 1)[-1]
        return {"n": "north", "s": "south", "e": "east", "w": "west"}.get(suffix)
    return None


def validate_knight_lore_dir(kl_dir: Path) -> tuple[list[str], dict]:
    errors: list[str] = []
    required_files = ["rooms.json", "backgrounds.json", "entities.json", "audio.json", "strings_and_ui.json"]
    for fname in required_files:
        if not (kl_dir / fname).is_file():
            errors.append(f"Missing required file: {kl_dir / fname}")
    if errors:
        return errors, {}

    rooms_doc = load_json(kl_dir / "rooms.json")
    bgs_doc = load_json(kl_dir / "backgrounds.json")
    entities_doc = load_json(kl_dir / "entities.json")
    audio_doc = load_json(kl_dir / "audio.json")
    ui_doc = load_json(kl_dir / "strings_and_ui.json")

    metadata = rooms_doc.get("metadata", {})
    rooms = rooms_doc.get("rooms", {})
    spawns = rooms_doc.get("special_object_spawns", [])

    if len(rooms) != 128:
        errors.append(f"Expected 128 rooms in rooms.json, found {len(rooms)}")
    if set(metadata.get("start_rooms", [])) != EXPECTED_START_ROOMS:
        errors.append(f"Unexpected start_rooms: {metadata.get('start_rooms')}")
    for sr in EXPECTED_START_ROOMS:
        if str(sr) not in rooms:
            errors.append(f"Start room {sr} missing from rooms.json")
    if int(metadata.get("cauldron_room", -1)) != 136 or "136" not in rooms:
        errors.append("Cauldron room 136 missing from metadata or rooms")
    if len(spawns) != 32:
        errors.append(f"Expected 32 special_object_spawns, found {len(spawns)}")
    for idx, sp in enumerate(spawns):
        if str(sp.get("room_id", -1)) not in rooms:
            errors.append(f"Special spawn {idx} references missing room {sp.get('room_id')}")

    room_sizes = bgs_doc.get("room_sizes", {})
    backgrounds = bgs_doc.get("backgrounds", {})
    for sz_key in ("0", "1", "2"):
        if sz_key not in room_sizes:
            errors.append(f"backgrounds.json missing room_sizes['{sz_key}']")
    if len(backgrounds) != 24:
        errors.append(f"Expected 24 backgrounds, found {len(backgrounds)}")
    for bid in range(24):
        if str(bid) not in backgrounds:
            errors.append(f"backgrounds.json missing background ID {bid}")

    fg_types = entities_doc.get("foreground_types", {})
    for tid in range(29):
        if str(tid) not in fg_types:
            errors.append(f"entities.json missing foreground_types['{tid}']")
    special_types = entities_doc.get("special_objects", {}).get("types", [])
    if len(special_types) != 8:
        errors.append(f"Expected 8 special_objects types, found {len(special_types)}")

    exit_count = 0
    fg_count = 0
    for rid_str, r in rooms.items():
        rid = int(rid_str)
        if str(r.get("size_type", -1)) not in room_sizes:
            errors.append(f"Room {rid} has invalid size_type {r.get('size_type')}")
        for bg_id in r.get("background_ids", []):
            if str(bg_id) not in backgrounds:
                errors.append(f"Room {rid} references unknown background_id {bg_id}")
        for bg_name in r.get("background_names", []):
            exit_dir = _exit_dir_from_bg(str(bg_name))
            if exit_dir is not None:
                exit_count += 1
                target_rid = neighbor_room_id(rid, exit_dir)
                if str(target_rid) not in rooms:
                    errors.append(f"Room {rid} exit '{bg_name}' points to missing room {target_rid}")
        for fg in r.get("foregrounds", []):
            fg_count += 1
            if str(fg.get("type_id", -1)) not in fg_types:
                errors.append(f"Room {rid} foreground references unknown type_id {fg.get('type_id')}")

    tunes = audio_doc.get("tunes", {})
    sfx = audio_doc.get("sfx_events", {})
    for tune_name in ("menu", "start_game", "game_over", "game_complete"):
        if not tunes.get(tune_name):
            errors.append(f"audio.json missing or empty tune '{tune_name}'")
    if len(sfx) != 16:
        errors.append(f"Expected 16 sfx_events in audio.json, found {len(sfx)}")

    for ui_key in ("zx_palette", "special_object_colors", "menu_screen", "hud", "game_complete_screen", "game_over_screen"):
        if ui_key not in ui_doc:
            errors.append(f"strings_and_ui.json missing '{ui_key}'")
    ratings = ui_doc.get("game_over_screen", {}).get("ratings", [])
    if len(ratings) != 8:
        errors.append(f"Expected 8 game_over ratings, found {len(ratings)}")

    summary = {
        "rooms": len(rooms),
        "backgrounds": len(backgrounds),
        "foreground_types": len(fg_types),
        "special_spawns": len(spawns),
        "exits": exit_count,
        "foregrounds": fg_count,
        "tunes": len(tunes),
        "sfx_events": len(sfx),
    }
    return errors, summary


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    kl_dir = root / "data" / "knight_lore"
    errors, summary = validate_knight_lore_dir(kl_dir)
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(
        "Validated Knight Lore data pack: "
        f"{summary['rooms']} rooms, {summary['backgrounds']} backgrounds, "
        f"{summary['foreground_types']} entity types, {summary['special_spawns']} spawns, "
        f"{summary['exits']} exits cleanly."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
