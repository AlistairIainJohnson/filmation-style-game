# AGENTS.md — Modern 3D Filmation Game Foundation (Godot 4.7.2)

## Mandatory Project Memory Review
- Read [memory/ARCHITECTURE_AND_DEVELOPMENT_MEMORY.md](memory/ARCHITECTURE_AND_DEVELOPMENT_MEMORY.md) at the start of every session before designing or implementing changes, and keep it updated when major architecture or milestones land.

## Stack & Engine Invariants
- **Engine**: Godot 4.7.2 Standard (`Forward+` renderer, `Jolt Physics 3D` default).
- **Primary Runtime Language**: Strictly typed **GDScript 2.0**.
- **Offline Tooling Language**: Python 3.13+ managed with `uv` in `tools/`, plus headless **Blender 5.3.0** (`bpy`) for 3D asset normalization.
- **Coordinate System**: Right-handed Y-up (`1.0 unit = 1.0 meter`). Floor grid snap = `1.0 m` (pushable half-snap = `0.5 m`).
- **Camera Invariant**: Fixed orthographic `Camera3D` per room (`projection = Camera3D.PROJECTION_ORTHOGONAL`).
  - Default projection: **True Isometric** (`yaw = 45.0°`, `pitch = -35.2644°`).
  - Toggleable projection: **2:1 Dimetric** (`yaw = 45.0°`, `pitch = -30.0°`).
  - **NEVER** set 3D camera pitch to `-26.565°` (that is the 2D screen edge slope, not the 3D camera pitch).
  - Keep `Camera3D.far <= 80.0` (target `~65.0` for `12×12×6 m` rooms).
- **Orthographic Lighting Invariants**:
  - **NEVER** enable `SDFGI` (`sdfgi_enabled = false`) in `WorldEnvironment` (causes striped artifacts in orthographic mode).
  - Use `VoxelGI`, `SSIL`, `SSAO`, `AreaLight3D`, `AgX` tonemapping (`tonemap_mode = 4`), and `DirectionalLight3D.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL` (`0`).
  - Update `player_world_pos` global shader uniform every tick via `RenderingServer.global_shader_parameter_set(&"player_world_pos", pos)`.
  - Apply foreground cutaway dither shaders **ONLY** to tagged foreground occluder walls/columns (never whole rooms, to protect Early-Z).

## 2D Background Compositor & UI Layer Hierarchy
- **SubViewport 2D Backdrop Compositing**:
  - In Godot 4, `CanvasLayer` always renders *after* the root 3D scene. To place 2D backdrops behind 3D rooms, encapsulate the 3D world in a `SubViewport(transparent_bg=true, own_world_3d=true)` within a `SubViewportContainer` on `CanvasLayer(layer = -3)`, with background `TextureRect` on `CanvasLayer(layer = -5)`.
  - **Menu Transition Cleanup**: Always toggle `_world_viewport_container.visible = false` when returning to 2D menus (e.g. Main Menu / Title Screen) to prevent 3D rooms bleeding through menu overlays.
- **Strict CanvasLayer Ordering**:
  - `layer = -5`: Background backdrop texture
  - `layer = -3`: 3D SubViewportContainer diorama
  - `layer = 0..10`: In-game HUD, Day/Night dial, corner scrolls, toast badges
  - `layer = 30`: Pause Menu overlay
  - `layer = 35`: Modal Dialogs (Settings, Save / Load screens)

## Strict Godot 4 API Guardrails (Reject Godot 3 Syntax)
- Use `Node3D` (not `Spatial`), `CharacterBody3D` (not `KinematicBody3D`), `await` (not `yield`), `@export` / `@onready` (not `export` / `onready`), `create_tween()` (not `Tween` node), `Callable` (not `funcref`).
- All pushable puzzle blocks MUST use kinematic `CharacterBody3D` / `AnimatableBody3D` contracts—never unconstrained dynamic `RigidBody3D`.
- **ThemeDB Invariant**: `ThemeDB.set_project_theme()` and `ThemeDB.project_theme` property do NOT exist in Godot 4.7.2. Always fetch `ThemeDB.get_project_theme()` and mutate the returned `Theme` in-place (e.g., via autoload `GameTheme`).
- **Parchment UI Styling**: Default UI text uses `#2B1108` (deep burnt umber) with a 1px–2px `#E89B3C` (warm amber at 35% alpha) shadow for embossed parchment ink; modal dialogs and toasts must include opaque/pill backing panels (`StyleBoxFlat`) for legibility over modulated backgrounds.

## File, Asset & Scene Safety Boundaries
- **Commit all `*.uid` files.** When moving or renaming `.gd` or `.gdshader` files, ALWAYS `git mv` the matching `.uid` sidecar together while Godot is closed.
- **Do NOT hand-edit complex `.tscn` files.** Express room layouts in LDtk / `data/rooms/*.json` consumed by `RoomBuilder.gd`, and validate with `tools/validate_world.py`.
- All imported 3D models (`assets/**/*.glb`) must pass headless Blender normalization (`tools/asset_pipeline/normalize_glb.py`) and `validate_glb.py` (bottom-center origin `(0, 0, 0)`, exact metric height, triangle budget, no Generate LODs on architectural meshes).

## Verification Commands (Mandatory Before Reporting Completion)
Run the unified script:
```bash
./scripts/verify.sh --visual
```
Or run tiers individually:
1. Refresh class cache (if new `class_name` added):
   `godot --headless --path . --import`
2. Syntax check modified scripts:
   `godot --headless --path . --check-only --script <res://path/to/script.gd>`
3. Run headless unit & physics test suite:
   `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
4. Visual check on macOS Metal (when changing lighting, camera, shaders, or room layouts — **NEVER** pass `--headless`):
   `godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/smoke_scene.tscn _verify/smoke.png`

## Handoff Format
Report: (1) modified file paths, (2) exact verification commands executed and observed exit codes/results, (3) screenshot findings if visual check applied, and (4) remaining risks or unverified edge cases.
