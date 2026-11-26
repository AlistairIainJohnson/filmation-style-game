#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VISUAL=false
if [[ "${1:-}" == "--visual" ]]; then
  VISUAL=true
fi

echo "==> Tier 1: Godot class cache import & GDScript static parse check"
godot --headless --path . --import

while IFS= read -r -d '' gd_file; do
  rel_path="${gd_file#./}"
  echo "  Checking res://$rel_path"
  check_out="$(godot --headless --path . --check-only --script "res://$rel_path" 2>&1)"
  echo "$check_out"
  if echo "$check_out" | grep -qE "SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script"; then
    echo "ERROR: Static parse check failed for res://$rel_path" >&2
    exit 1
  fi
done < <(find core game tests tools -name '*.gd' -print0 2>/dev/null)

echo "==> Tier 1b: Python uv environment, JSON syntax & schema validation"
uv run --directory tools python -c "import PIL, jsonschema, trimesh, pygltflib, httpx; print('Python tooling imports OK')"
while IFS= read -r -d '' json_file; do
  uv run --directory tools python -c "import json, sys; json.load(open(sys.argv[1], 'r', encoding='utf-8'))" "$ROOT_DIR/${json_file#./}"
  echo "  JSON OK: ${json_file#./}"
done < <(find data schemas -name '*.json' -print0 2>/dev/null)
uv run --directory tools python validate_world.py
uv run --directory tools python validate_knight_lore.py
uv run --directory tools python asset_pipeline/validate_glb.py --manifest ../assets/asset_manifest.json
uv run --directory tools python -m unittest discover -s . -p "test_*.py" -v

echo "==> Tier 2: Headless GUT unit & physics test suite"
gut_out="$(godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1)"
echo "$gut_out"
if echo "$gut_out" | grep -qE "Nothing was run|SCRIPT ERROR:|Failed to load script"; then
  echo "ERROR: GUT test suite did not execute cleanly." >&2
  exit 1
fi

echo "==> Tier 2b: Audio preview & level validation"
uv run --directory tools python audio_pipeline/validate_audio.py
godot --headless --path . -s tools/render_audio_preview.gd

verify_png() {
  local png_path="$1"
  uv run --directory tools python - "$png_path" <<'PY'
import sys
from PIL import Image, ImageStat

img_path = sys.argv[1]
img = Image.open(img_path).convert("RGB")
w, h = img.size
assert (w, h) == (1280, 720), f"Unexpected screenshot resolution: {w}x{h}"
stat = ImageStat.Stat(img)
stddev_sum = sum(stat.stddev)
assert stddev_sum > 1.0, f"Screenshot appears blank/uniform (stddev_sum={stddev_sum:.3f})"
print(f"Visual QA image OK: {img_path} ({w}x{h}, stddev_sum={stddev_sum:.2f})")
PY
}

if [[ "$VISUAL" == true ]]; then
  echo "==> Tier 3: Metal visual screenshot capture (non-headless)"
  mkdir -p _verify
  if [[ -n "${CAPTURE_SCENE:-}" ]]; then
    CAPTURE_OUT="${CAPTURE_OUT:-_verify/capture.png}"
    godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- "$CAPTURE_SCENE" "$CAPTURE_OUT" 20
    verify_png "$ROOT_DIR/$CAPTURE_OUT"
  else
    FILMATION_LIGHTING_PRESET=castle_stone_skylight godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/room_08_08_day.png 24
    verify_png "$ROOT_DIR/_verify/room_08_08_day.png"

    FILMATION_LIGHTING_PRESET=castle_moonlight_night godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/room_08_08_night.png 24
    verify_png "$ROOT_DIR/_verify/room_08_08_night.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=5.5,1.1,4.5 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage2_player_jump.png 24
    verify_png "$ROOT_DIR/_verify/stage2_player_jump.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=9.5,0.0,9.5 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage2_cutaway.png 24
    verify_png "$ROOT_DIR/_verify/stage2_cutaway.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=2.5,0.0,4.5 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage2_interior_pillar_cutaway.png 24
    verify_png "$ROOT_DIR/_verify/stage2_interior_pillar_cutaway.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=9.6,0.0,11.1 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage2_pillar_in_front_opaque.png 24
    verify_png "$ROOT_DIR/_verify/stage2_pillar_in_front_opaque.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_STAGE3_DEMO=1 FILMATION_PLAYER_POS=5.5,0.0,5.5 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage3_puzzle_stack.png 36
    verify_png "$ROOT_DIR/_verify/stage3_puzzle_stack.png"

    FILMATION_START_ROOM=9,8 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/main_game.tscn _verify/stage4_room_09_08.png 24
    verify_png "$ROOT_DIR/_verify/stage4_room_09_08.png"

    FILMATION_PREVIEW_ROOM=res://data/rooms/room_09_07.json FILMATION_PREVIEW_GRID=1 FILMATION_CAMERA_MODE=dimetric_2_1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/stage5_sanctum_preview.png 24
    verify_png "$ROOT_DIR/_verify/stage5_sanctum_preview.png"

    FILMATION_START_ROOM=8,8 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/main_game.tscn _verify/stage6_vertical_slice_day.png 24
    verify_png "$ROOT_DIR/_verify/stage6_vertical_slice_day.png"

    FILMATION_LIGHTING_PRESET=castle_moonlight_night godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage6_vertical_slice_night.png 24
    verify_png "$ROOT_DIR/_verify/stage6_vertical_slice_night.png"

    FILMATION_START_ROOM=9,8 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/main_game.tscn _verify/stage6_eastern_gallery.png 24
    verify_png "$ROOT_DIR/_verify/stage6_eastern_gallery.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=5.5,0.0,4.5 FILMATION_PLAYER_FREEZE=1 FILMATION_PLAYER_ANIM=walk FILMATION_PLAYER_ANIM_TIME=0.0 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage6_hero_walk.png 24
    verify_png "$ROOT_DIR/_verify/stage6_hero_walk.png"

    FILMATION_LIGHTING_PRESET=castle_stone_skylight FILMATION_PLAYER_POS=5.5,0.0,4.5 FILMATION_PLAYER_FREEZE=1 FILMATION_PLAYER_YAW_DEG=135 FILMATION_PLAYER_ANIM=idle FILMATION_PLAYER_ANIM_TIME=0.0 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/test_chamber.tscn _verify/stage6_explorer_front.png 24
    verify_png "$ROOT_DIR/_verify/stage6_explorer_front.png"

    FILMATION_KL_ROOM=136 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase1_room_136_cauldron.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase1_room_136_cauldron.png"

    FILMATION_KL_ROOM=8 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase1_room_008_forest.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase1_room_008_forest.png"

    FILMATION_KL_ROOM=16 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase1_room_016_high_arch.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase1_room_016_high_arch.png"

    FILMATION_KL_ROOM=47 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase1_room_047_start.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase1_room_047_start.png"

    FILMATION_KL_ROOM=109 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase2_props_charms.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase2_props_charms.png"

    FILMATION_KL_ROOM=109 FILMATION_PLAYER_POS=3.6,0.0,1.6 FILMATION_PLAYER_FREEZE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/tools/room_preview.tscn _verify/kl_phase2_room_109_cutaway.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase2_room_109_cutaway.png"

    FILMATION_KL_ROOM=47 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase3_gameplay_hud.png 24
    verify_png "$ROOT_DIR/_verify/kl_phase3_gameplay_hud.png"

    FILMATION_KL_ROOM=136 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase3_cauldron_hint.png 36
    verify_png "$ROOT_DIR/_verify/kl_phase3_cauldron_hint.png"

    FILMATION_KL_ROOM=136 FILMATION_KL_FORCE_NIGHT=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase4_room_136_night_wulf.png 48
    verify_png "$ROOT_DIR/_verify/kl_phase4_room_136_night_wulf.png"

    FILMATION_KL_ROOM=33 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase4_room_033_entities.png 40
    verify_png "$ROOT_DIR/_verify/kl_phase4_room_033_entities.png"

    # Phase 5: Title Screen & Pause Menu
    FILMATION_KL_NO_MENU=0 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase5_title_menu.png 18
    verify_png "$ROOT_DIR/_verify/kl_phase5_title_menu.png"

    FILMATION_CAPTURE_PAUSE=1 godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase5_pause_menu.png 25
    verify_png "$ROOT_DIR/_verify/kl_phase5_pause_menu.png"
  fi
fi

echo "==> All requested verification tiers PASSED"
