# Filmation 3D Foundation (Godot 4.7.2)

A reusable, data-driven modern 3D interpretation of classic ZX Spectrum **Filmation** isometric adventures (*Knight Lore* / *Alien 8* / *Head Over Heels*) built for **Godot 4.7.2 Standard (`Forward+` / `Jolt Physics 3D`)** on macOS Apple Silicon (`Metal 4.0`) and cross-platform desktops.

---

## Core Architecture & Features

- **Authentic Orthographic Camera Rig (`core/camera/diorama_camera_rig.gd`)**:
  - Default **True Isometric** (`yaw = 45°`, `pitch = -35.2644°`) with live toggle to **2:1 Dimetric** (`pitch = -30.0°`), auto-framed per chamber.
- **Modern PBR Diorama Lighting (`core/lighting/diorama_lighting.gd`)**:
  - `VoxelGI` + `SSAO` + `SSIL` + `AgX` tonemapping + `DirectionalLight3D` orthogonal shadows (`SDFGI` explicitly disabled to prevent orthographic striping).
  - Switchable Day (`castle_stone_skylight`) and Moonlight Night (`castle_moonlight_night`) presets.
- **Deterministic Player Controller & Readability Aids (`core/player/`)**:
  - Kinematic `CharacterBody3D` (`physics_interpolation=true`) supporting camera-relative 8-way and isometric grid-aligned 4-way movement with smooth ground acceleration/deceleration ramps, exponential facing damping + diagonal-release debounce, animation crossfades, and `INTERPOLATION_CUBIC` humanoid motion (`core/characters/humanoid_animation_library.gd`).
  - Analytical asymmetric jump curve (`jump_height = 1.35 m`, `time_to_apex = 0.28 s`, `time_to_descent = 0.22 s`) with coyote time & jump input buffering.
  - Height-reactive `ShapeCast3D` + interpolated `Decal` drop shadow (`cull_mask = 1`, isolated from player visual layer `2`).
  - Camera-ray AABB gated 8×8 Bayer cutaway dithering (`core/shaders/foreground_cutaway.gdshader`) capped to preserve partial foreground visibility (`25%` halftone silhouette) paired with opaque `ShadowCaster` siblings so pillars keep casting solid shadows while transparent.
- **Hybrid Kinematic Puzzle Entities (`core/entities/`)**:
  - `PushableBlock` (`CharacterBody3D` + 0.5 m half-grid snap + multi-block stack carry), `Portcullis` (`AnimatableBody3D`), `MovingPlatform` (`sync_to_physics`), `CollapsingTile`, `TriggerSwitch`, `CollectibleItem`, and `PatrolHazard`.
- **Multi-Room World Graph & Day/Night Meta-Loop (`core/world/`)**:
  - Cooperative `WorldManager` (`ResourceLoader.load_threaded_request`) seamlessly loading LDtk-compiled room JSONs across a 4-room interconnected loop with persistent room state hydration and JSON save/load.
  - `CycleManager` driving Day → Night atmospheric shifts, jump height boost (`1.22×`), and Explorer → Werewolf morphing.
- **100% Local Sprite-to-3D Pipeline (`tools/asset_pipeline/`)**:
  - `extract_spritesheet.py` pairs 1-bit ink & mask passes from `concept-art/knight-lore-sprites.jpg` into clean transparent `RGBA` sprites (`187` extracted cells across 12 rows + `28` full-body Explorer/Werewolf composites).
  - Headless **Blender 5.3.0** (`blender_sculpt_generator.py` + `normalize_glb.py`) generates & normalizes 16 PBR `.glb` props, gothic architecture (including continuous doorway lintel masonry), and 17-bone `SkeletonProfileHumanoid` characters validated by `validate_glb.py`.
- **Architecture & Development Memory (`memory/ARCHITECTURE_AND_DEVELOPMENT_MEMORY.md`)**:
  - Captures verified rendering/cutaway invariants, physics smoothing & animation architecture, the 16-asset manifest, git milestone history, and test baseline.

---

## Controls

| Action | Default Keys |
|---|---|
| Move (8-way / 4-way toggle) | `WASD` / Arrow Keys |
| Jump | `Space` |
| Toggle Camera Projection (Isometric / 2:1 Dimetric) | `Tab` / `C` |
| Toggle Movement Mode (8-way / 4-way) | `M` |

---

## Verification & Local Tooling

All scripts, JSON schemas, LDtk compilation, 16 `.glb` assets, GUT unit/physics tests, and Metal screenshots are validated by:

```bash
./scripts/verify.sh --visual
```

Prerequisites on macOS Apple Silicon:
- **Godot 4.7.2+** on `PATH`
- **Blender 5.3.0+** on `PATH`
- **Python 3.13+** with `uv` (`uv sync` inside `tools/`)
- **LDtk v1.5.3+** (optional, for editing `levels/filmation_world.ldtk`)
