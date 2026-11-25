# Architecture & Development Memory — Modern 3D Filmation Foundation

**Repository**: `https://github.com/AlistairIainJohnson/filmation-style-game` (`main`)
**Engine & Tooling**: Godot `4.7.2` Standard (`Forward+`, `Jolt Physics 3D`, `physics/common/physics_interpolation=true`), macOS Apple Silicon (`Metal 4.0`), Blender `5.3.0`, Python `3.13+` (`uv` in `tools/`), LDtk `v1.5.3`, GUT `v9.6.1`.

---

## 1. Core Architectural Invariants & Rendering Rules

### Camera & Coordinate System
- **Right-handed Y-up**: `1.0 unit = 1.0 m`, walkable floor surface at `y = 0.0`, floor grid snap `1.0 m`, pushable half-snap `0.5 m`.
- **Orthographic Camera (`core/camera/diorama_camera_rig.gd`)**:
  - Default **True Isometric**: `yaw = 45.0°`, `pitch = -35.2644°`.
  - Toggleable **2:1 Dimetric**: `yaw = 45.0°`, `pitch = -30.0°`.
  - **NEVER** set 3D camera pitch to `-26.565°` (2D screen slope) and keep `Camera3D.far <= 80.0`.

### Orthographic Lighting & Foreground Cutaway Shaders
- **Lighting (`core/lighting/diorama_lighting.gd`)**:
  - `sdfgi_enabled = false` ALWAYS in `WorldEnvironment` (prevents orthographic striping).
  - Uses `VoxelGI` + `SSAO` + `SSIL` + `AgX` tonemapping (`Environment.TONE_MAPPER_AGX`) + `DirectionalLight3D.SHADOW_ORTHOGONAL`.
  - Presets in `data/lighting_presets.json`: `castle_stone_skylight` (Day) and `castle_moonlight_night` (Night).
- **Cutaway Dithering & Shadow Preservation (`core/shaders/foreground_cutaway.gdshader`, `core/world/room_builder.gd`, `core/player/player_controller.gd`)**:
  - Applied **ONLY** to tagged `foreground_occluders` / tall pillars (never floors or general rooms, protecting Early-Z).
  - `PlayerController.update_occluder_cutaways()` casts 5 orthographic camera-ray segments (ankle, mid, head, left/right shoulders) against each occluder's world `AABB`, setting `cutaway_active` (`1.0` vs `0.0`) recursively so pillars turn transparent **only when the character moves behind them**.
  - Peak cutaway discard is capped via `max_cutaway_transparency = 0.75`, leaving `25%` uniform Bayer halftone visibility so tall columns keep continuous structure instead of leaving floating capitals.
  - Because `discard` in `fragment()` executes in the directional shadow pass too, `RoomBuilder._attach_cutaway_shadow_caster()` sets `cast_shadow = SHADOW_CASTING_SETTING_OFF` on visual cutaway meshes and adds a sibling `ShadowCaster` node (`SHADOW_CASTING_SETTING_SHADOWS_ONLY`, opaque `StandardMaterial3D`, `GI_MODE_DISABLED`, no duplicate collision shapes) so pillars continue casting unbroken shadows onto the room and player even while partially transparent.

---

## 2. Player Movement, Physics Interpolation & Animation System

- **Physics Interpolation (`project.godot`, `core/world/world_manager.gd`)**:
  - `physics/common/physics_interpolation=true` eliminates 60 Hz physics vs. high-refresh display micro-stutter.
  - `WorldManager` calls `active_player.reset_physics_interpolation()` on room spawns (`_spawn_player_in_room`) and save hydration (`hydrate_world_save`).
- **Player Controller (`core/player/player_controller.gd`)**:
  - Kinematic `CharacterBody3D` (`layer = 2`, `mask = 1 | 4`, visual hierarchy on `PLAYER_VISUAL_LAYER = 2`).
  - Analytical asymmetric jump (`jump_height = 1.35 m`, `time_to_apex = 0.28 s`, `time_to_descent = 0.22 s`) with `coyote_time = 0.10 s` and `jump_buffer_time = 0.10 s`.
  - Smooth horizontal velocity ramp (`ground_accel = 56.0`, `ground_decel = 52.0` via `Vector2.move_toward`), exponential facing damping (`turn_speed = 18.0` via `lerp_angle`), and `diagonal_release_debounce = 0.045 s`.
  - Animation crossfading (`0.12 s` standard, `0.06 s` for `jump`/`land`), velocity-scaled `walk` `speed_scale`, and touchdown playback of `&"land"`.
  - `_process()` calls `sync_shader_world_pos(true)` using `get_global_transform_interpolated().origin` at display refresh rate, while zero-argument `sync_shader_world_pos()` uses immediate `global_position` for deterministic unit tests.
- **Drop Shadow (`core/player/drop_shadow_controller.gd`)**:
  - `ShapeCast3D` + `Decal` (`cull_mask = 1`, `PHYSICS_INTERPOLATION_MODE_OFF`) tracking `get_global_transform_interpolated().origin` in `_process()`.
- **Shared Rigged Animation Library (`core/characters/humanoid_animation_library.gd`, `assets/animations/humanoid_core.res`)**:
  - `LIBRARY_FORMAT_VERSION = 4`, targeting `SkeletonProfileHumanoid` 17-bone armatures.
  - Conjugates model-space delta quaternions onto `Skeleton3D` rest poses (`parent_global_rest_q^-1 * delta_q * parent_global_rest_q * local_rest_q`) + hemisphere continuity and `TYPE_POSITION_3D` rest-origin offsets.
  - Uses `INTERPOLATION_CUBIC` with loop wrap: 4-phase passing `walk` keyframes (knee lift + `±0.025 m` `Hips` bounce), `idle` look-left/look-right head turns, `push`, `jump`, `fall`, and `land` (`-0.04 m` crouch dip).
- **Day/Night Transformation**: `CycleManager` toggles `PlayerController.set_night_form()` between `hero_explorer.glb` (Day Explorer) and `hero_werewolf.glb` (Night Werewolf) plus `1.22×` jump height multiplier.

---

## 3. World Architecture, Merged Floor Colliders & Puzzle Entities

- **Modular Room Construction (`core/world/room_builder.gd`)**:
  - Consumes `data/rooms/room_{08_08,09_08,08_07,09_07}.json` (`schemas/room.schema.json`).
  - `FloorTiles` keeps `1×1 m` checkerboard visual `Node3D`/`MeshInstance3D` nodes (`layers = 1`, `GI_MODE_STATIC`, opaque `StandardMaterial3D`), while `FloorCollision` (`StaticBody3D`) greedily merges contiguous non-void cells into maximal `BoxShape3D` colliders to eliminate tile-seam snags.
  - North/West masonry walls tile `wall_stone_panel.glb` (`2.0×6.0 m`), bridge tall arched doorway/portcullis lintels (`y = 3.0..6.0 m`) with `wall_stone_lintel.glb`, frame openings with `arch_stone_doorway.glb`, and render carved `stone_pillar.glb` / `stone_block.glb`. All architectural `.glb.import` files enforce `meshes/generate_lods=false`.
- **Hybrid Kinematic Entities (`core/entities/`)**:
  - `PushableBlock` (`CharacterBody3D`, `0.5 m` half-grid snap, vertical stack carry), `Portcullis` (`AnimatableBody3D`), `MovingPlatform` (`sync_to_physics`), `CollapsingTile`, `TriggerSwitch`, `CollectibleItem`, `PatrolHazard`, instantiated via `EntityFactory` & `data/entities.json`.
- **World Graph & Level Tooling**:
  - `WorldManager` (`core/world/world_manager.gd`) handles `ResourceLoader.load_threaded_request` neighbor preloading, persistent entity state serialization/hydration, room transitions, and JSON save/load.
  - `levels/filmation_world.ldtk` compiles via `tools/import_ldtk.py`, validated by `tools/validate_world.py`, previewed interactively in `game/tools/room_preview.tscn`.

---

## 4. Local 2D-to-3D Asset Pipeline & Manifest (`tools/asset_pipeline/`, `assets/asset_manifest.json`)

- **Sprite Extraction (`extract_spritesheet.py`)**: Pairs ink + mask passes from `concept-art/knight-lore-sprites.jpg`, compositing `28` full-body Explorer/Werewolf frames and cataloging all `187` monochrome sprites across 12 rows (`all_sprites_catalog.json`, `character_proportions.json`).
- **Blender `5.3.0` Generation & Normalization**: `preprocess_sprite.py` → `generate_3d.py` / `blender_sculpt_generator.py` → `normalize_glb.py` (`(0,0,0)` bottom-center pivot, exact metric height, `-convcol` collision suffix support, clamped PBR roughness/metallic) → `validate_glb.py`.
- **Validated 16-Asset Manifest (`assets/asset_manifest.json`)**:
  - **Architecture & Props (12)**: `pushable_chest.glb` (`1.0 m`, `3156` tris), `cauldron.glb` (`0.95 m`, `5994` tris), `collectible_key.glb` (`0.45 m`, `1420` tris), `stone_pillar.glb` (`3.5 m`, `784` tris, `-convcol`), `arch_stone_doorway.glb` (`3.2 m`, `2484` tris), `wall_stone_panel.glb` (`6.0 m`, `1836` tris), `wall_stone_lintel.glb` (`3.0 m`, `756` tris), `portcullis_gate.glb` (`2.6 m`, `2588` tris), `stone_block.glb` (`1.0 m`, `432` tris), `moving_platform.glb` (`0.35 m`, `648` tris), `collapsing_tile.glb` (`0.25 m`, `540` tris), `pressure_plate.glb` (`0.10 m`, `328` tris).
  - **Rigged 17-Bone Characters (4)**: `hero_knight.glb` (`1.55 m`, `1836` tris), `patrol_sentinel.glb` (`1.45 m`, `3244` tris), `hero_explorer.glb` (`1.40 m`, `7112` tris), `hero_werewolf.glb` (`1.52 m`, `3828` tris).

---

## 5. Development Log (Git Milestones to Date)

1. `af0244e` — Built Stages 0–6 Modern 3D Filmation Foundation + Knight Lore local Blender sprite-to-3D pipeline, rest-conjugated humanoid animation library, Explorer/Werewolf Day/Night swap, and camera-ray gated pillar cutaways.
2. `22b3847` — Added `wall_stone_lintel.glb` (`build_prop_wall_lintel_panel()`) and `RoomBuilder._attach_wall_lintel_masonry()` so stone courses and `TopCoping` continue seamlessly across doorway and portcullis lintels.
3. `01a7c3c` — Added `max_cutaway_transparency = 0.75` to `foreground_cutaway.gdshader` so cut-away pillars remain 25% halftone visible instead of disappearing completely.
4. `150b0ae` — Added `RoomBuilder._attach_cutaway_shadow_caster()` (`ShadowCaster` `SHADOW_CASTING_SETTING_SHADOWS_ONLY` siblings) so cut-away pillars keep casting full solid shadows on the room and hero.
5. `27240f1` — Enabled `physics/common/physics_interpolation=true`, `reset_physics_interpolation()` on room transitions, interpolated shadow/shader updates in `_process()`, exponential yaw damping + diagonal-release debounce, ground accel/decel ramps, animation crossfading + `INTERPOLATION_CUBIC` 4-phase walk with `Hips` bounce (`humanoid_core.res` v4), and merged `FloorCollision` rectangles.
6. *Uncommitted (Knight Lore Phases 1–3)*:
   - **Phase 1**: Ingested 128-room `data/knight_lore/` JSON pack, added `tools/validate_knight_lore.py`, `core/knight_lore/knight_lore_data.gd`, and `RoomBuilder.build_knight_lore_room()` with Option 2A subtle room tints.
   - **Phase 2**: Fixed doorway sill/backstop physics & transitions, raised foreground South/East wall colliders to `6.0 m` (splitting `high_arch` clearance at `3.0 m`), extended `0.80 m` visible `SillFloorMesh` into portals, moved `Exit_*` triggers outward (`±0.60 m`), tuned cutaway opacity (`0.58`), added `forest_floor.gdshader`, and expanded asset manifest from `16` to **`41`** normalized `.glb` assets (`meshes/generate_lods=false` on architectural meshes).
   - **Phase 3**: Added `KnightLoreSession`, `KlSpecialItem`, `KnightLoreHud`, `game/knight_lore_game.tscn`, Rotational + Directional controls + variable jump in `PlayerController`, Room 136 Cauldron hint bubbles / Repel Spells, 40-day cycle, and `tests/test_knight_lore_phase3.gd` (**51/51 GUT tests**, **9/9 Python tests**).
   - **Pre-baked `VoxelGIData` & Instant Room Transitions**: Added [tools/bake_voxel_gi.gd](tools/bake_voxel_gi.gd) to bake all **132** compressed `VoxelGIData` `.res` files offline (`128` Knight Lore rooms in `data/knight_lore/voxel_gi/` = `22M`, `4` declarative JSON rooms in `data/rooms/voxel_gi/` = `644K`). `DioramaLighting.apply_prebaked_gi()` caches and assigns `voxel_gi.data` at runtime without calling `VoxelGI.bake()`, while `knight_lore_game.gd`, `world_manager.gd`, and `room_preview.gd` persist a single `RoomBuilder` (and `knight_lore_game.gd` reuses `PlayerController`) for instant room swaps.

---

## 6. Verification Baseline & Known Pitfalls

- **Mandatory Verification (`./scripts/verify.sh --visual`)**:
  - **Tier 1**: `godot --headless --path . --import` & `--check-only` across all `.gd` files.
  - **Tier 1b**: JSON schema validation (`4` rooms, `2` lighting presets, `4` world nodes), `validate_glb.py --manifest` (`16` `.glb` assets), and Python `unittest` (`8/8` tests).
  - **Tier 2**: GUT `9.6.1` headless suite (`51/51` tests, `3,089` assertions across 9 test files).
  - **Tier 3**: Non-headless Metal `4.0` visual captures (`22` `1280×720` PNGs in `_verify/`).
- **Offline GI Pre-bake Command** (re-run only when room geometry/layout changes):
  `godot --path . --resolution 640x360 -s tools/bake_voxel_gi.gd` (NEVER `--headless`).
- **Critical Gotchas**:
  - Never run `tools/capture_frame.gd` with `--headless` on macOS Metal.
  - Always commit `.uid` and `.import` sidecars; keep `meshes/generate_lods=false` on architectural `.glb.import` files.
  - Never call `_attach_cutaway_shadow_caster()` by duplicating an entire `-convcol` `.glb` scene (clone only lightweight `MeshInstance3D` nodes) and always skip `"ShadowCaster"` in cutaway parameter recursion.
  - Bump `HumanoidAnimationLibrary.LIBRARY_FORMAT_VERSION` whenever procedural animation tracks change so `res://assets/animations/humanoid_core.res` regenerates cleanly.

---

## 7. Potential Future Improvements (Backlog)

*(Captured from movement & visual polish review; note that the core smoothing stack — 3D `physics_interpolation`, `lerp_angle` yaw damping + diagonal-release debounce, ground accel/decel ramps, animation crossfading + `INTERPOLATION_CUBIC` 4-phase walk with `Hips` bounce + `&"land"`, and merged `FloorCollision` rectangles — was already implemented in commit `27240f1`; see Sections 2, 3, and 5.)*

1. **Block-Pushing Contact Transition (`core/player/player_controller.gd`)**: Smooth the speed transition between `move_and_slide()` at `move_speed` (`4.2 m/s`) and `move_and_collide()` at `push_speed` (`2.4 m/s`) on initial push contact/release, and pause or scale the `push` leg cycle when a `PushableBlock` is blocked by a wall.
2. **Movement Feel Playtest Tuning (`core/player/player_controller.gd`)**: Tune `ground_accel`, `ground_decel`, `turn_speed`, `diagonal_release_debounce`, and `walk` `speed_scale` curves based on hands-on playtesting across tight platforming rooms.
3. **Footstep & Landing Feedback (`core/characters/humanoid_animation_library.gd`, `core/player/player_controller.gd`)**: Sync subtle footstep audio cues or dust puffs to `walk` contact keyframes (`0.0s` / `0.3s`) and `&"land"` touchdowns.
4. **Moving Platform Momentum Handoff (`core/entities/moving_platform.gd`, `core/player/player_controller.gd`)**: Verify and polish smooth velocity handoff and interpolation continuity when stepping onto or jumping off `MovingPlatform`.
5. **Cutaway Uniform Fade (`core/shaders/foreground_cutaway.gdshader`, `core/player/player_controller.gd`)**: Smooth `cutaway_active` transitions over ~`0.10–0.15 s` per occluder (instead of a binary `0.0`/`1.0` step) so foreground pillars fade smoothly into and out of `25%` Bayer translucency as the player walks behind them.
