class_name KlDynamicBlock
extends AnimatableBody3D
## Config-driven Knight Lore dynamic blocks using AnimatableBody3D (sync_to_physics = true):
## - moving_platform_ew / moving_platform_ns (triangle-wave shuttle carrying player & moveables)
## - dropping_block (falls steadily while stood upon)
## - collapsing_block (vanishes with sparkle VFX immediately on step)

@export var entity_type_name: String = "block_ew"
@export var simulation_active: bool = false

var behavior: String = "moving_platform_ew"
var params: Dictionary = {}
var entity_size: Vector3 = Vector3(1.0, 0.75, 1.0)
var director: KlRoomDirector = null

var collision_shape: CollisionShape3D
var proxy_mesh: MeshInstance3D
var step_sensor: Area3D
var down_cast: ShapeCast3D

var _origin_pos: Vector3 = Vector3.ZERO
var _phase_time: float = 0.0
var _collapsed: bool = false
var _amplitude_m: float = 1.0
var _speed_mps: float = 0.875


func _init() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0


func configure(p_type_name: String, type_cfg: Dictionary, size: Vector3, start_pos: Vector3, phase_idx: int = 0) -> void:
	entity_type_name = p_type_name
	behavior = str(type_cfg.get("behavior", "moving_platform_ew"))
	params = (type_cfg.get("params", {}) as Dictionary).duplicate(true)
	entity_size = size
	_origin_pos = start_pos
	_phase_time = float(phase_idx) * 0.45
	_collapsed = false
	position = start_pos
	set_meta("kl_type", p_type_name)
	set_meta("kl_behavior", behavior)

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = entity_size
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(collision_shape)

	proxy_mesh = MeshInstance3D.new()
	proxy_mesh.name = "Mesh"
	proxy_mesh.layers = 1
	proxy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box := BoxMesh.new()
	box.size = entity_size
	proxy_mesh.mesh = box
	proxy_mesh.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(proxy_mesh)

	if behavior == "dropping_block" or behavior == "collapsing_block":
		step_sensor = Area3D.new()
		step_sensor.name = "StepSensor"
		step_sensor.collision_layer = 8
		step_sensor.collision_mask = 2 | 4
		step_sensor.monitoring = true
		var s_col := CollisionShape3D.new()
		var s_box := BoxShape3D.new()
		s_box.size = Vector3(entity_size.x * 0.85, 0.22, entity_size.z * 0.85)
		s_col.shape = s_box
		s_col.position = Vector3(0.0, entity_size.y + 0.11, 0.0)
		step_sensor.add_child(s_col)
		add_child(step_sensor)

	if behavior == "dropping_block":
		down_cast = ShapeCast3D.new()
		down_cast.name = "DownCast"
		var d_box := BoxShape3D.new()
		d_box.size = Vector3(entity_size.x * 0.78, 0.04, entity_size.z * 0.78)
		down_cast.shape = d_box
		down_cast.position = Vector3(0.0, 0.04, 0.0)
		down_cast.target_position = Vector3(0.0, -0.09, 0.0)
		down_cast.collision_mask = 1 | 4
		down_cast.exclude_parent = true
		down_cast.enabled = true
		add_child(down_cast)


func bind_director(p_director: KlRoomDirector) -> void:
	director = p_director
	if director != null:
		var amp_u: float = float(params.get("amplitude", 16.0))
		var spd_u: float = float(params.get("speed", 1.0))
		_amplitude_m = director.kl_units_to_meters(amp_u)
		_speed_mps = director.kl_speed_to_mps(spd_u)


func _physics_process(delta: float) -> void:
	if not simulation_active or _collapsed:
		return

	match behavior:
		"moving_platform_ew":
			_step_moving_platform(delta, Vector3.RIGHT)
		"moving_platform_ns":
			_step_moving_platform(delta, Vector3(0.0, 0.0, -1.0))
		"dropping_block":
			_step_dropping_block(delta)
		"collapsing_block":
			_step_collapsing_block()


func _step_moving_platform(delta: float, axis: Vector3) -> void:
	if _amplitude_m <= 0.001:
		return
	_phase_time += delta * _speed_mps
	var frac: float = pingpong(_phase_time, _amplitude_m)
	var next_pos: Vector3 = _origin_pos + axis * frac
	if director != null:
		var mx: float = entity_size.x * 0.5
		var mz: float = entity_size.z * 0.5
		next_pos.x = clampf(next_pos.x, mx, maxf(mx, director.room_dims.x - mx))
		next_pos.z = clampf(next_pos.z, mz, maxf(mz, director.room_dims.z - mz))
	position = next_pos


func _has_standing_rider() -> bool:
	if step_sensor == null or not is_inside_tree():
		return false
	for body: Node3D in step_sensor.get_overlapping_bodies():
		if body is PlayerController or body is KlPushableEntity or body is PushableBlock or body is KlSpecialItem:
			return true
	return false


func _step_dropping_block(delta: float) -> void:
	if position.y <= 0.005:
		position.y = 0.0
		return
	if not _has_standing_rider():
		return
	if down_cast != null:
		down_cast.force_shapecast_update()
		if down_cast.is_colliding():
			return
	var fall_speed: float = director.kl_speed_to_mps(1.5) if director != null else 1.3125
	position.y = maxf(0.0, position.y - fall_speed * delta)


func _step_collapsing_block() -> void:
	if _collapsed:
		return
	if _has_standing_rider():
		_collapsed = true
		if collision_shape != null:
			collision_shape.disabled = true
		if step_sensor != null:
			step_sensor.monitoring = false
		visible = false
		var vfx_parent: Node3D = get_parent() as Node3D
		if vfx_parent != null:
			KlSparkleVfx.spawn_burst(vfx_parent, global_position + Vector3(0.0, entity_size.y * 0.5, 0.0), &"collapse")
		queue_free()
