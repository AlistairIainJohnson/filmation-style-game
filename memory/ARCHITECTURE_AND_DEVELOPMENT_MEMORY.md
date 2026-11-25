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
6. `59d7a30` — *Knight Lore Phases 1–3 + visual polish + sculpted werewolf + pre-baked VoxelGI* (pushed to `origin/main`; see Sections 8–9 for the 6-phase plan, decisions, and resume instructions):
   - **Phase 1**: Ingested 128-room `data/knight_lore/` JSON pack, added `tools/validate_knight_lore.py`, `core/knight_lore/knight_lore_data.gd`, and `RoomBuilder.build_knight_lore_room()` with Option 2A subtle room tints.
   - **Phase 2**: Fixed doorway sill/backstop physics & transitions, raised foreground South/East wall colliders to `6.0 m` (splitting `high_arch` clearance at `3.0 m`), extended `0.80 m` visible `SillFloorMesh` into portals, moved `Exit_*` triggers outward (`±0.60 m`), tuned cutaway opacity (`0.58`), added `forest_floor.gdshader`, and expanded asset manifest from `16` to **`41`** normalized `.glb` assets (`meshes/generate_lods=false` on architectural meshes).
   - **Phase 3**: Added `KnightLoreSession`, `KlSpecialItem`, `KnightLoreHud`, `game/knight_lore_game.tscn`, Rotational + Directional controls + variable jump in `PlayerController`, Room 136 Cauldron hint bubbles / Repel Spells, 40-day cycle, and `tests/test_knight_lore_phase3.gd` (**51/51 GUT tests**, **9/9 Python tests**).
   - **Pre-baked `VoxelGIData` & Instant Room Transitions**: Added [tools/bake_voxel_gi.gd](tools/bake_voxel_gi.gd) to bake all **132** compressed `VoxelGIData` `.res` files offline (`128` Knight Lore rooms in `data/knight_lore/voxel_gi/` = `22M`, `4` declarative JSON rooms in `data/rooms/voxel_gi/` = `644K`). `DioramaLighting.apply_prebaked_gi()` caches and assigns `voxel_gi.data` at runtime without calling `VoxelGI.bake()`, while `knight_lore_game.gd`, `world_manager.gd`, and `room_preview.gd` persist a single `RoomBuilder` (and `knight_lore_game.gd` reuses `PlayerController`) for instant room swaps.

---

## 6. Verification Baseline & Known Pitfalls

- **Mandatory Verification (`./scripts/verify.sh --visual`)**:
  - **Tier 1**: `godot --headless --path . --import` & `--check-only` across all `.gd` files.
  - **Tier 1b**: JSON schema validation (`4` rooms, `2` lighting presets, `4` world nodes), `validate_knight_lore.py` (`128` rooms, `24` backgrounds, `29` entity types, `32` spawns, `286` exits), `validate_glb.py --manifest` (**`41`** `.glb` assets), and Python `unittest` (`9/9` tests).
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


---

## 8. Knight Lore 6-Phase Development Plan (Status & Resume Point)

**Goal**: Turn the Modern 3D Filmation Foundation into the complete 128-room *Knight Lore* (1984) 3D game, driven by the pre-decoded data pack (`data/knight_lore/*.json`, originals + specs in `concept-game-logic/`). **Mandatory phase gating**: stop after each phase for manual user review and prompt what to check before starting the next.

| Phase | Scope | Status |
|---|---|---|
| **1** | Data pack ingestion (`data/knight_lore/{rooms,backgrounds,entities,audio,strings_and_ui}.json`), `tools/validate_knight_lore.py`, `core/knight_lore/knight_lore_data.gd` (coordinate mapper, 3 room sizes `8×8`/`4×8`/`8×4 m`, neighbor exits, high-arch elevations), `RoomBuilder.build_knight_lore_room()` | **DONE** |
| **2** | Asset pack: manifest grew `16 → 41` normalized `.glb` (woodland wall/lintel/arch, low walls, door trims, table/rock/dropping block, Melkhior, gargoyle/spikes/balls/fire/ghost, 7 charms + Extra Life) | **DONE** |
| **3** | Core gameplay loop: `KnightLoreSession` (lives, 14-charm sequence, 32 spawns, 3-slot FIFO inventory, drop-lift, 40-day Sun/Moon cycle, quest %/rating), `KlSpecialItem`, `KnightLoreHud`, playable `game/knight_lore_game.tscn`, Rotational/Directional controls, variable jump, Room 136 hint bubbles / homing Repel Spells | **DONE (awaiting user manual review)** |
| **4** | All 29 entity behaviors from `entities.json` + Cauldron Hub & Sparkle VFX (see below) | **NOT STARTED — next** |
| **5** | Modern filtered procedural audio engine (`core/audio/zx_audio_manager.gd`, `AudioStreamGenerator`, inspired by `audio.json`: 4 tunes + 16 SFX) and full UI flow (`game/ui/{main_menu,hud,end_screen}`, pause, control/camera toggles, exact menu/Game Over/Victory strings) | NOT STARTED |
| **6** | Full automated verification & docs: new GUT suites (`test_knight_lore_data.gd`, `test_knight_lore_gameplay.gd`, `test_knight_lore_audio_ui.gd`), Metal captures (Room 136 Day/Night, forest room, high-arch room, Title/HUD/Victory/Game Over), memory update, push | NOT STARTED |

*(Note: Phase 3 tests currently live in `tests/test_knight_lore_phase1.gd` and `tests/test_knight_lore_phase3.gd`; the plan's Phase 6 suite names are the intended consolidation targets.)*

### Phase 4 scope (next to implement)
- **Pushables**: `chest` (`clears_velocity=false`, slides until blocked) vs `table` / `moveable_block` (`clears_velocity=true`, stops on release).
- **Dynamic blocks**: `block_ew`/`block_ns` (triangle-wave amplitude `16`, carry player & moveables), `dropping_block` (falls while stood on), `collapsing_block` (vanishes with sparkle on step).
- **Hazards/enemies**: `gargoyle`, `spike`, `spike_high`, `spike_ball_fall`/`spike_ball_high_fall` (1/16 drop chance, one at a time, odd-room `disable_spike_ball_drop` latch), `fire_ew`/`fire_ns`, `ball_ud*` (bounce to `init_Z+32`), `ball_bounce` (steers toward Wulf / away from Human), `guard_ew`, `guard_square`, `wizard` (clockwise W→N→E→S patrol), `ghost` (random diagonal `{-4,-3,3,4}`), `repel_spell` (chases at `±4`, `±1` near arch), `portcullis` (`gate_*`, one moves at a time, 4 initial fast drops then 1/32 chance, lethal while dropping).
- **Cauldron Hub (Room 136) & `core/knight_lore/sparkle_vfx.gd`**: bubbles flash the next required charm to Human, become lethal Repel Spells for Wulf; dropped charm arcs to cauldron (credit on match, destroyed on mismatch); at `14/14` room blocks become rising victory sparkles converging on player → Victory. Also appear/death/transformation/collapse sparkles.
- Exact behavior source of truth: `data/knight_lore/entities.json` + `concept-game-logic/knight-lore-core-architecture-and-gameplay-logic-specification`.
- Phase 3 already wired a subset (lethal hazard collision via `kl_lethal_hazards` group, Room 136 hint bubbles / homing Repel Spells); verify against the spec before re-implementing.

---

## 9. Locked-In Architectural & Aesthetic Decisions (Knight Lore)

### User-approved decisions
1. **Simulation engine = Option A (Hybrid)**: keep the 60 Hz Jolt `CharacterBody3D`/`AnimatableBody3D` stack (`physics_interpolation=true`) and calibrate Knight Lore rules onto it. We did **NOT** adopt `concept-game-logic/AGENTS.md`'s 14 Hz integer `SimulationEngine`, its `src/` folder layout, or its "no CharacterBody3D" rule. Keep `core/`, `game/`, `data/`, `assets/`, `tests/`, `tools/` layout. Adopted from it: pre-decoded JSON data, `UNITS_PER_METER = 16.0`, Z-up→Y-up mapping, bottom-center pivots, strict static typing, typed signals, `%UniqueName` UI refs.
2. **Room colors = Option 2A**: subtle modern PBR tint per ZX `ink_color` (`KnightLoreData.get_subtle_room_tint()`), not the classic ZX palette. Forest rooms use a fixed mossy tint (`backdrop (0.32,0.44,0.26)`, `floor (0.76,0.86,0.70)`).
3. **Default controls = Directional** (camera-relative 8-way), with classic **Rotational** (Left/Right 90°, Up walks) toggleable via `[Tab]` (menu toggle planned in Phase 5).
4. **Audio (Phase 5)** = modern filtered procedural synth inspired by `audio.json`, not raw square waves.
5. Foundation 4-room demo (`data/world_graph.json`, `game/main_game.tscn`) and its tests stay intact; Knight Lore boots from `game/knight_lore_game.tscn` (env `FILMATION_KL_ROOM=<id>`, `FILMATION_KL_FORCE_NIGHT=1`; room browser `FILMATION_KL_ROOM` + `[F4]`/`[F5]` in `room_preview`).

### Geometry / scale conventions
- Room sizes: Type 0 `8×8 m`, Type 1 `4×8 m`, Type 2 `8×4 m`; wall thickness `0.5 m`; walls `6.0 m` tall; doorway `2.0 m` wide × `3.0 m` high; high arches at `Z=176` → `3.0 m` elevation on South/East with `HighArchBase` ledges.
- North/West = tall back walls (masonry panels + lintel + arch); South/East = foreground (low `0.4 m` curb visuals `low_wall_stone`/`low_wall_woodland` but **full-height `6.0 m` colliders** so the hero can never climb them; collider split below `3.0 m` at high-arch openings).
- Foreground arches (S/E) use cutaway (`max_cutaway_transparency = 0.58`) + opaque `ShadowCaster`; tall props over hero height (`1.40 m`) also cut away.

### Doorway / transition decisions
- **Walk-through transitions**: `Exit_*` `Area3D` triggers sit `±0.60 m` outside the room boundary (`0.36 m` thick) so the hero must walk fully into the portal.
- **Sill floor**: `DoorwaySill_*` has a visible `SillFloorMesh` sized exactly `door_w × wall_thickness` (`2.0 × 0.5 m`, **flush with the wall's outer face — do not overhang**) plus unchanged `SillFloor` (`1.4 m`) and `SillBackstop` physics colliders. Material matches the room floor (tile or `forest_floor.gdshader`).
- **Biome transitions** (stone↔forest): doors get subtle indicators — `door_trim_to_forest.glb` (mossy/ivy on stone doors leading to forest) and `door_trim_to_stone.glb` (broken stone ruin on forest arches leading to stone). Driven by `exits[*].biome_transition` / `target_is_forest`.
- **Woodland doorways**: `arch_tree_doorway.glb` projects `0.18 m` into the room so walls never clip it. The lintel above (`tree_wall_lintel.glb`) must **match the density of the neighboring `tree_wall_panel.glb`**: it is the upper half (`z-3.0`) of the panel — 3 slender vertical trunks (`x=-0.69/-0.03/0.71`), forked upper twigs, 7 upper-canopy leaf sprays (`z=1.70..2.82`), `LintelBack` plate — mounted at `fixed_coord = 0.02` (same plane as `WallMasonry_*`). Earlier versions (crossed logs, hanging vines, 10 sprays, `fixed_coord = 0.14`) were rejected as "too much".

### Aesthetic decisions
- Modern, non-retro low-poly sculpted PBR look; organic continuous lofts (`_loft_rings` with `subsurf_levels=1`, `_build_organic_tube`) instead of primitive boxes/spheres for characters.
- `hero_explorer.glb`: pith helmet, safari tunic, tucked arms, sculpted hands (palm, thumb, 4 fingers). `hero_werewolf.glb`: same organic style (lupine muzzle/fangs, amber eyes, cupped ears, chest ruff, tattered shorts, clawed hands, digitigrade legs, bushy tail). `melkhior_wizard.glb` 17-bone rig; `hazard_gargoyle.glb` crouched.
- Forest rooms: `tree_wall_panel.glb` walls, organic `forest_floor.gdshader` floor (no flat polka-dot cylinders), `low_wall_woodland.glb` borders (roots, moss, shrubs); dungeon rooms: `wall_stone_panel.glb` masonry + `low_wall_stone.glb` parapet.
- Room 136 Cauldron Hub: Human sees rising translucent charm-hint bubbles; Wulf sees homing emerald Repel Spells. Day↔Night swap = shimmer freeze + lighting preset swap (`castle_stone_skylight` ↔ `castle_moonlight_night`).

### Performance decision: pre-baked VoxelGI
- Runtime `VoxelGI.bake()` caused a ~1.6 s room-transition stall. All GI is now **baked offline** into `VoxelGIData` `.res` (`data/knight_lore/voxel_gi/room_XXX.res` ×128 = `22M`, `data/rooms/voxel_gi/*.res` ×4) by `tools/bake_voxel_gi.gd`; `DioramaLighting.apply_prebaked_gi()` caches/assigns at runtime. A single `RoomBuilder` (and `PlayerController` in `knight_lore_game.gd`) is reused across transitions.
- **Re-bake whenever room geometry, wall/arch/sill/lintel GLBs, or layout change**: `godot --path . --resolution 640x360 -s tools/bake_voxel_gi.gd` (never `--headless`; options `--kl-only`, `--rooms-only`, `--room=<id_or_stem>`, `--skip-existing`; ~209 s for all 132). Note: the lintel/sill polish was made before the bake finished in the side thread — if GI looks stale near doorways, re-bake.
- Legacy Stage 4 `world_manager.gd` still uses a `0.14 s + 0.16 s` fade tween unless `instant = true`; `knight_lore_game.gd` transitions in one frame.

### Process rules
- Follow `AGENTS.md` and the user rule: **no hardcoded business/domain field names, endpoints, or workflows in core engine code; prefer config-driven primitives** (data in `data/knight_lore/*.json`, `data/materials.json`, etc.).
- Run `./scripts/verify.sh --visual` (must exit `0`) before reporting; handoff = (1) modified files, (2) commands & exit codes, (3) screenshot findings, (4) remaining risks.
- Latest verified baseline (before commit `59d7a30`): GUT `51/51` tests across 9 scripts, Python `9/9`, `41/41` GLBs, `22` Metal captures.

### How to resume
1. Read this file, then `data/knight_lore/entities.json` and `concept-game-logic/knight-lore-core-architecture-and-gameplay-logic-specification`.
2. Confirm the user has reviewed Phase 3 (playable via `godot --path . res://game/knight_lore_game.tscn`; try `FILMATION_KL_ROOM=47`, `FILMATION_KL_FORCE_NIGHT=1`).
3. Start **Phase 4** (Section 8), re-bake GI if any room geometry changes, run `./scripts/verify.sh --visual`, then stop for review before Phase 5.
