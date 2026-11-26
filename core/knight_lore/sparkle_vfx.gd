class_name KlSparkleVfx
extends Node3D
## Lightweight procedural 3D sparkle particle clusters for Knight Lore state transitions
## (room appear, death, Human/Wulf transform, collapsing block, cauldron accept/reject, and 14/14 victory convergence).

signal converged(sparkle: KlSparkleVfx)

enum Mode { BURST, VICTORY }

const PRESETS: Dictionary = {
	&"appear": {
		"color": Color(0.55, 0.92, 1.0, 1.0),
		"accent": Color(0.95, 0.98, 1.0, 1.0),
		"duration": 0.45,
		"radius": 0.48,
		"inward": true,
		"count": 8
	},
	&"death": {
		"color": Color(1.0, 0.28, 0.22, 1.0),
		"accent": Color(1.0, 0.82, 0.25, 1.0),
		"duration": 0.65,
		"radius": 0.85,
		"inward": false,
		"count": 10
	},
	&"transform": {
		"color": Color(0.76, 0.42, 1.0, 1.0),
		"accent": Color(1.0, 0.78, 0.30, 1.0),
		"duration": 1.35,
		"radius": 0.62,
		"inward": false,
		"count": 10
	},
	&"collapse": {
		"color": Color(0.88, 0.72, 0.46, 1.0),
		"accent": Color(1.0, 0.90, 0.68, 1.0),
		"duration": 0.45,
		"radius": 0.65,
		"inward": false,
		"count": 8
	},
	&"cauldron_accept": {
		"color": Color(0.28, 1.0, 0.62, 1.0),
		"accent": Color(1.0, 0.92, 0.35, 1.0),
		"duration": 0.70,
		"radius": 0.78,
		"inward": false,
		"count": 10
	},
	&"cauldron_reject": {
		"color": Color(0.95, 0.25, 0.85, 1.0),
		"accent": Color(1.0, 0.50, 0.65, 1.0),
		"duration": 0.50,
		"radius": 0.55,
		"inward": false,
		"count": 8
	}
}

var mode: Mode = Mode.BURST
var preset_name: StringName = &"appear"
var follow_target: Node3D = null
var victory_target: Node3D = null
var rise_target_y: float = 2.25

var _elapsed: float = 0.0
var _duration: float = 0.45
var _radius: float = 0.55
var _inward: bool = false
var _rising_phase: bool = true
var _emitted_converged: bool = false
var _motes: Array[Dictionary] = []


static func spawn_burst(
	parent: Node3D,
	world_pos: Vector3,
	preset: StringName = &"appear",
	target: Node3D = null
) -> KlSparkleVfx:
	if parent == null or not is_instance_valid(parent):
		return null
	var vfx := KlSparkleVfx.new()
	vfx.name = "Sparkle_%s" % String(preset)
	vfx.mode = Mode.BURST
	vfx.preset_name = preset
	vfx.follow_target = target
	parent.add_child(vfx)
	vfx.global_position = world_pos
	vfx._setup_burst(preset)
	return vfx


static func spawn_victory_sparkle(
	parent: Node3D,
	start_pos: Vector3,
	target: Node3D,
	rise_y: float = 2.25
) -> KlSparkleVfx:
	if parent == null or not is_instance_valid(parent):
		return null
	var vfx := KlSparkleVfx.new()
	vfx.name = "VictorySparkle"
	vfx.mode = Mode.VICTORY
	vfx.victory_target = target
	vfx.rise_target_y = rise_y
	parent.add_child(vfx)
	vfx.global_position = start_pos
	vfx._setup_victory_motes()
	return vfx


func _setup_burst(preset: StringName) -> void:
	var cfg: Dictionary = PRESETS.get(preset, PRESETS[&"appear"]) as Dictionary
	_duration = float(cfg.get("duration", 0.5))
	_radius = float(cfg.get("radius", 0.55))
	_inward = bool(cfg.get("inward", false))
	var col_a: Color = cfg.get("color", Color.CYAN) as Color
	var col_b: Color = cfg.get("accent", Color.WHITE) as Color
	var count: int = int(cfg.get("count", 8))
	_create_motes(count, col_a, col_b)


func _setup_victory_motes() -> void:
	_duration = 5.0
	_rising_phase = true
	_create_motes(5, Color(1.0, 0.92, 0.35, 1.0), Color(0.45, 1.0, 0.90, 1.0))


func _create_motes(count: int, col_a: Color, col_b: Color) -> void:
	for i: int in range(count):
		var mi := MeshInstance3D.new()
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := BoxMesh.new()
		box.size = Vector3(0.11, 0.11, 0.11)
		var mat := StandardMaterial3D.new()
		var c: Color = col_a if (i % 2 == 0) else col_b
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 2.6
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = mat
		mi.mesh = box
		add_child(mi)

		var angle: float = TAU * float(i) / float(maxi(count, 1))
		var elev: float = ((float(i % 3) - 1.0) * 0.35)
		var dir := Vector3(cos(angle), elev, sin(angle)).normalized()
		_motes.append({
			"mesh": mi,
			"mat": mat,
			"dir": dir,
			"angle": angle,
			"spin": 3.5 + float(i % 3) * 1.4
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if mode == Mode.BURST:
		_process_burst(delta)
	else:
		_process_victory(delta)


func _process_burst(_delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position + Vector3(0.0, 0.65, 0.0)

	var t: float = clampf(_elapsed / maxf(_duration, 0.01), 0.0, 1.0)
	for entry: Dictionary in _motes:
		var mi: MeshInstance3D = entry["mesh"] as MeshInstance3D
		var mat: StandardMaterial3D = entry["mat"] as StandardMaterial3D
		var dir: Vector3 = entry["dir"] as Vector3
		var base_angle: float = float(entry["angle"])
		var spin: float = float(entry["spin"])
		var r: float = lerpf(_radius, 0.06, t) if _inward else lerpf(0.08, _radius, t)
		var swirl: float = base_angle + _elapsed * spin
		var horiz := Vector3(cos(swirl), 0.0, sin(swirl)) * r
		var vert_offset: float = dir.y * r + (0.28 * t if preset_name == &"transform" else 0.0)
		mi.position = Vector3(horiz.x, vert_offset, horiz.z)
		mi.rotation.y = swirl * 1.5
		mi.rotation.x = _elapsed * 4.0
		var s: float = sin(t * PI) * 1.15
		mi.scale = Vector3(maxf(s, 0.05), maxf(s, 0.05), maxf(s, 0.05))
		mat.albedo_color.a = clampf(1.0 - t * 0.85, 0.0, 1.0)

	if _elapsed >= _duration:
		queue_free()


func _process_victory(delta: float) -> void:
	for i: int in range(_motes.size()):
		var entry: Dictionary = _motes[i]
		var mi: MeshInstance3D = entry["mesh"] as MeshInstance3D
		var swirl: float = float(entry["angle"]) + _elapsed * 5.0
		var r: float = 0.16 + 0.05 * sin(_elapsed * 6.0 + float(i))
		mi.position = Vector3(cos(swirl) * r, 0.12 * sin(_elapsed * 5.0 + float(i)), sin(swirl) * r)
		mi.rotation.y = swirl
		mi.rotation.z = _elapsed * 4.0

	if _rising_phase:
		global_position.y += 2.4 * delta
		if global_position.y >= rise_target_y:
			global_position.y = rise_target_y
			_rising_phase = false
		return

	if victory_target == null or not is_instance_valid(victory_target):
		if not _emitted_converged:
			_emitted_converged = true
			converged.emit(self)
		queue_free()
		return

	var target_pos: Vector3 = victory_target.global_position + Vector3(0.0, 0.65, 0.0)
	var to_target: Vector3 = target_pos - global_position
	var dist_xz: float = Vector2(to_target.x, to_target.z).length()
	if dist_xz <= 0.375:
		if not _emitted_converged:
			_emitted_converged = true
			converged.emit(self)
		queue_free()
		return

	var step_dir: Vector3 = to_target.normalized()
	global_position += step_dir * 3.2 * delta
