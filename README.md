# Knight Lore Reimagined — Modern 3D Filmation Engine (Godot 4.7.2)

A modern 3D reimagining of Ultimate Play the Game's 1984 ZX Spectrum isometric classic ***Knight Lore***, built on a reusable, data-driven **Filmation 3D Foundation** for **Godot 4.7.2 Standard (`Forward+` / `Jolt Physics 3D`)** on macOS Apple Silicon (`Metal 4.0`) and cross-platform desktops.

Launching the project boots directly into **Knight Lore Reimagined** (`game/knight_lore_game.tscn`), featuring all 128 interconnected chambers, a 40-day Sun/Moon Sabreman/Werewolf transformation cycle, 14-charm cauldron quest, 29 config-driven entity behaviors, genuine offline-rendered orchestral music & biome soundscapes, and a dynamic parchment-scroll HUD.

*(The original 4-room foundation tech demo remains preserved at `game/main_game.tscn`.)*

---

## Core Architecture & Features

- **128-Room World & Cauldron Hub (`core/knight_lore/`)**:
  - Pre-decoded 128-room layout (`data/knight_lore/rooms.json`) with 3 chamber sizes (`8×8 m`, `4×8 m`, `8×4 m`), elevated high-arch doorways, forest & dungeon biomes, and biome-transition door trims.
  - **40-Day Day/Night Meta-Loop (`KnightLoreSession`)**: Smooth Sun/Moon cycle (`DayNightDial` sky-arch HUD) transforming Sabreman between Explorer (human) and Werewolf (night jump boost, tracked by Room 136 Melkhior's homing Repel Spells).
  - **3-Slot Rotating Inventory & Quest Progression**: Collect and drop charms (`E` / `Enter`) into Melkhior's Cauldron (Room 136) in the sequence revealed by rising cauldron hint bubbles.
  - **29 Config-Driven Entity Behaviors (`KlRoomDirector`)**: Pushable/pullable blocks & tables, dropping blocks, collapsing spikes, portcullis gates, patrolling guards, bouncing/falling spiked balls, gargoyles, fire, and ghosts driven by `data/knight_lore/entities.json`.
- **Authentic Orthographic Camera & Diorama Lighting (`core/camera/`, `core/lighting/`)**:
  - Default **True Isometric** (`yaw = 45°`, `pitch = -35.2644°`) with live toggle (`F1`) to **2:1 Dimetric** (`pitch = -30.0°`), auto-framed per chamber.
  - Pre-baked `VoxelGI` (`data/knight_lore/voxel_gi/*.res`) + `SSAO` + `SSIL` + `AgX` tonemapping + `DirectionalLight3D` orthogonal shadows (`SDFGI` disabled).
  - Camera-ray AABB gated 8×8 Bayer cutaway dithering (`core/shaders/foreground_cutaway.gdshader`) on foreground arches and tall props with opaque `ShadowCaster` siblings, plus procedural running-bond flagstones (`dungeon_floor.gdshader`) and organic woodland floors (`forest_floor.gdshader`).
- **Genuine Offline-Rendered Orchestral Score & Natural Soundscapes (`core/audio/`, `tools/audio_pipeline/`)**:
  - De-interleaved Knight Lore motifs arranged for symphony orchestra, rendered offline via **FluidSynth** + `GeneralUser GS` into normalized `.ogg` cues (`assets/audio/music/`).
  - Synthesized 30 s woodland & dungeon ambience loops (`KlAmbienceDirector`) and 24 `.wav` SFX routed through biome-aware `RoomFX` dungeon slapback/reverb buses (`data/knight_lore/audio_score.json`, `audio_soundscapes.json`).
- **100% Local 3D Asset Pipeline (`tools/asset_pipeline/`)**:
  - Headless **Blender 5.3.0** (`blender_sculpt_generator.py` + `normalize_glb.py`) generates & normalizes **41** PBR `.glb` assets (characters, woodland/dungeon walls, arches, trims, props, charms, glowing Crystal Ball) validated by `validate_glb.py`.
- **Architecture & Development Memory (`memory/ARCHITECTURE_AND_DEVELOPMENT_MEMORY.md`)**:
  - Captures verified rendering/cutaway invariants, physics smoothing & animation architecture, the 41-asset manifest, audio pipeline, git milestone history, and test baseline.

---

## Controls

| Action | Keys |
|---|---|
| Move (Directional 8-way / Classic Rotational) | `WASD` / Arrow Keys |
| Jump | `Space` |
| Drop / Pick Up Item (or Restart on End Screen) | `E` / `Enter` |
| Grab & Pull Pushable Blocks |Hold `Shift` + Move |
| Toggle Control Mode (Directional / Rotational) | `Tab` |
| Toggle Camera Projection (Isometric / 2:1 Dimetric) | `F1` |
| Pause Menu | `Esc` / `P` |
| Mute / Unmute Audio | `M` |
| Quick Restart Session | `R` |

### Developer & Debug Launch Options

Run from the project root with environment variables to jump straight into a specific room or state (bypassing the title screen):

```bash
# Boot directly into Room 136 (Cauldron Hub) at Night as Werewolf
FILMATION_KL_ROOM=136 FILMATION_KL_FORCE_NIGHT=1 godot --path .

# Boot into the room browser (step rooms with F4 / F5)
FILMATION_KL_ROOM=47 godot --path . res://game/tools/room_preview.tscn

# Capture Victory / Game Over screens
FILMATION_KL_ROOM=136 FILMATION_CAPTURE_END=victory godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/knight_lore_game.tscn _verify/kl_phase6_victory.png 25
```

---

## Verification & Local Tooling

All GDScript static checks, JSON/data schemas, 41 `.glb` assets, audio assets, GUT unit/physics tests, and Metal screenshots are validated by:

```bash
./scripts/verify.sh --visual
```

Offline regeneration commands (run only when modifying assets, audio, or room geometry):

```bash
# Re-bake offline VoxelGI light probes (never pass --headless)
godot --path . --resolution 640x360 -s tools/bake_voxel_gi.gd

# Re-render orchestral score & soundscapes
uv run --directory tools python audio_pipeline/compose_score.py
uv run --directory tools python audio_pipeline/render_soundscapes.py
```

Prerequisites on macOS Apple Silicon:
- **Godot 4.7.2+** on `PATH`
- **Blender 5.3.0+** on `PATH`
- **Python 3.13+** with `uv` (`uv sync` inside `tools/`)
- **FluidSynth** (optional, for regenerating `.ogg` orchestral stems)

---

## Attributions & Licenses

A complete, machine-readable inventory of all code, audio, 3D assets, fonts, and intellectual property is maintained in [`attributions.json`](attributions.json).

### Original Game Concept & Intellectual Property
- ***Knight Lore* (1984)**: Created and programmed by **Tim Stamper and Chris Stamper**, published by **Ultimate Play the Game** (Ashby Computers & Graphics Ltd) for the Sinclair ZX Spectrum 48K. Rights currently held by Microsoft / Rare Ltd. This project is an educational, non-commercial technical modernization and tribute celebrating the pioneering Filmation engine.
- **Reverse Engineering & Disassembly**: Room topologies, Z80 coordinate conversions, and sprite index mappings reference the authoritative *Knight Lore Disassembly & RAM Map* by **Richard Dymond (SkoolKit)**.

### Engine, Frameworks & Plugins
- **Godot Engine**: Version 4.7.2 Standard (`Forward+`). Copyright © 2014–present Godot Engine contributors; Copyright © 2007–2014 Juan Linietsky, Ariel Manzur. Released under the [MIT License](https://godotengine.org/license).
- **Godot Jolt (Jolt Physics 3D)**: Godot 4 3D physics integration. Copyright © 2023–present Jorrit Rouwe, Godot Jolt contributors. Released under the [MIT License](https://github.com/godot-jolt/godot-jolt/blob/master/LICENSE.txt).
- **GUT (Godot Unit Test)**: Headless unit & integration test framework (v9.6.1). Copyright © 2018 Tom "Butch" Wesley. Released under the [MIT License](addons/gut/LICENSE.md).

### Typography
- **Metamorphous Regular**: UI and HUD parchment typeface (`assets/ui/Metamorphous-Regular.ttf`). Designed by **James Grieshaber**, published by **Sorkin Type Co**. Licensed under the [SIL Open Font License, Version 1.1 (OFL-1.1)](http://scripts.sil.org/OFL).

### Music & Sound Design
- **Original Melodic Themes**: The 4 core 1-bit beeper motifs (Title Tune, Game Start Fanfare, Transformation Shimmer, Game Over / Epilogue) are © 1984 Ultimate Play the Game.
- **Symphonic Orchestral Arrangements**: Multi-part contrapuntal orchestral arrangements generated via `tools/audio_pipeline/compose_score.py` and rendered using FluidSynth.
- **GeneralUser GS SoundFont (v1.471)**: General MIDI orchestral sample bank by **S. Christian Collins** (1997–2015, [schristiancollins.com](http://www.schristiancollins.com)). Permissively free for musical production and software use.
- **Procedural Soundscapes & Foley**: Synthesized offline via custom Python DSP scripts (`tools/audio_pipeline/render_soundscapes.py`) using Voss-McCartney 1/f pink noise and Butterworth filter banks (30-second seamless woodland/dungeon ambience loops and 24 acoustic SFX). 

### 3D Models & 2D Art
- **41 Normalized PBR 3D Models (`.glb`)**: Procedurally generated, sculpted, and rigged locally via headless Blender 5.3.0 pipelines (`tools/asset_pipeline/`) based on original ZX Spectrum monochrome pixel silhouettes. 
- **UI Art & Textures**: Aged parchment background (`assets/ui/background.webp`) and illuminated title logo (`assets/ui/knight_lore_reimagined_logo.png`). 

### Python Tooling Dependencies
- [`mido`](https://mido.readthedocs.io/) (MIT License), [`numpy`](https://numpy.org/) (BSD 3-Clause), [`scipy`](https://scipy.org/) (BSD 3-Clause), [`pillow`](https://python-pillow.org/) (HPND / MIT-like), [`trimesh`](https://trimesh.org/) (MIT License), [`pygltflib`](https://gitlab.com/dodgybits/pygltflib) (MIT License), [`jsonschema`](https://python-jsonschema.readthedocs.io/) (MIT License), [`httpx`](https://www.python-httpx.org/) (BSD 3-Clause).

