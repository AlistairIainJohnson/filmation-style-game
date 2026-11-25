# AGENTS.md — Knight Lore 3D (Godot 4) Architecture & Coding Contract

This document defines the architecture, coordinate mapping, and implementation rules for the Godot 4 reimplementation of *Knight Lore* (1984).

---

## 1. Project & Data Files

All game data is pre-decoded into JSON under `res://data/`:
- `res://data/rooms.json` — All 128 rooms, grid coordinates, room sizes, colors, background template IDs, unpacked foreground objects, and 32 special object spawn locations.
- `res://data/backgrounds.json` — All 24 background templates (`arch_*`, `wall_size_*`, `tree_*`, `gate_*`, `wizard`, `cauldron`) and `room_sizes`.
- `res://data/entities.json` — Simulation constants, player parameters, special objects, and all 29 foreground entity behaviors/hitboxes.
- `res://data/audio.json` — Decoded ZX Spectrum tunes (`menu`, `start_game`, `game_over`, `game_complete`) in Hz/ms and all 16 SFX event triggers.
- `res://data/strings_and_ui.json` — Exact menu/HUD/Game Over/Victory strings, ZX Spectrum color palette, and rating thresholds.

---

## 2. Core Architectural Rule: Decoupled Integer Simulation

**Do NOT use Godot's `CharacterBody3D`, `RigidBody3D`, or `Area3D` for gameplay physics.**

1. Run the original discrete integer simulation (`SimulationEngine`) in pure GDScript at a fixed tick rate of **14 Hz** (accumulated inside `_physics_process`).
2. Keep all coordinates, hitboxes, and velocities in the original unsigned/signed integer space (`X, Y, Z ∈ [0..255]`, `room_center = (128, 128)`, `floor_z = 128`).
3. Resolve collisions strictly axis-by-axis in order **Z → X → Y**, matching the exact Knight Lore specification (pushing `moveable` blocks, riding moving platforms, lifting the player `+12` Z when dropping an item, `chest` sliding indefinitely vs. `table`/`moveable_block` stopping immediately).
4. **Ignore 2D depth sorting (`calc_display_order_and_render`)** — Godot's 3D Z-buffer handles occlusion automatically.
5. `RoomView3D` observes `SimulationEngine` signals and smoothly interpolates `Node3D.position` between `prev_pos` and `curr_pos` using the tick accumulator fraction `alpha`.

---

## 3. 3D Coordinate, Scale & Camera Contract

Knight Lore is **Z-up** (`+X = East`, `+Y = North`, `+Z = Up`). Godot 3D is **Y-up** (`+X = East`, `-Z = North`, `+Y = Up`).

```gdscript
const UNITS_PER_METER: float = 16.0 # 1 standard block (w=8, d=8 -> 16x16) = 1.0m x 1.0m

static func kl_to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(
		(x - 128.0) / UNITS_PER_METER,
		(z - 128.0) / UNITS_PER_METER,
		-(y - 128.0) / UNITS_PER_METER
	)
```

- **Model Pivot:** All 3D models (`.glb` / `.tscn`) must have their origin at **bottom-center** `(x_center, z_bottom, y_center)` to match Knight Lore's object origin.
- **Merged Characters:** Player, Guards, and Melkhior are rendered as **single 3D models** driven by Slot 0's state (`height = 23` or `24`). Slot 1 (top half) is omitted visually.
- **Camera3D:** Use `PROJECTION_ORTHOGONAL`, positioned on the South-East isometric diagonal looking at `(0, 1.5, 0)`:
  - Rotation: `rotation_degrees = Vector3(-35.264, 45.0, 0.0)` (true isometric) or `Vector3(-30.0, 45.0, 0.0)` (classic 2:1 dimetric).
  - Zoom via `Camera3D.size` (approx. `12.0`–`14.0` meters to frame a 64×64 room).

---

## 4. Recommended Folder & Scene Structure

```text
res://
├── data/
│   ├── rooms.json
│   ├── backgrounds.json
│   ├── entities.json
│   ├── audio.json
│   └── strings_and_ui.json
├── src/
│   ├── sim/
│   │   ├── sim_entity.gd          # RefCounted data class for any room entity
│   │   ├── sim_engine.gd          # Core 14Hz loop, AABB physics, AI, quest state
│   │   └── data_loader.gd         # Loads & validates JSON tables
│   ├── view/
│   │   ├── room_view_3d.gd        # Spawns/syncs 3D models from SimEngine
│   │   ├── asset_registry.gd      # Maps Sprite_* names -> .glb / .tscn paths
│   │   └── audio_manager.gd       # Plays square-wave tunes & SFX hooks
│   └── ui/
│       ├── hud.gd                 # Inventory (3 slots), Day, Sun/Moon, Lives
│       ├── main_menu.gd           # Control mode toggle & Start
│       └── end_screen.gd          # Game Over / Victory stats & rating
├── scenes/
│   ├── Main.tscn
│   └── HUD.tscn
└── tests/
    └── test_simulation.gd         # Headless verification script
```

---

## 5. GDScript Coding Standards (Godot 4)

- Use **strict static typing** (`var x: int = 0`, `func step(dt: float) -> void:`) on all variables, parameters, and return types.
- Use typed `signal` declarations on `SimEngine` (`room_changed(room_id: int)`, `sfx_triggered(event_name: String, pos: Vector3i)`, `inventory_changed(items: Array[int])`, `player_transformed(is_wulf: bool)`, `game_over(won: bool)`).
- Use `%UniqueName` node references in UI/View scripts rather than fragile relative paths.
- Keep `src/sim/` **100% headless-compatible** (zero references to `Node3D`, `Camera3D`, or rendering APIs) so `tests/test_simulation.gd` can run via `godot --headless -s tests/test_simulation.gd`.
