class_name KlPushableEntity
extends CharacterBody3D
## Config-driven Knight Lore pushable entity (chest: clears_velocity=false slides until blocked;
## table & moveable_block: clears_velocity=true stops on release). Supports stacked rider carry.

@export var entity_type_name: String = "chest"
@export var clears_velocity: bool = false
@export var gravity_accel: float = 28.0
@export var slide_speed: float = 2.6

var behavior: String = "pushable_sliding"
var params: Dictionary = {}
var entity_size: Vector3 = Vector3(1.125, 0.75, 0.75)
var simulation_active: bool = false
var director: KlRoomDirector = null

var collision_shape: CollisionShape3D
var proxy_mesh: MeshInstance3D
var rider_cast: ShapeCast3D

var _slide_dir: Vector3 = Vector3.ZERO


func _init() -> void:
	_configure_physics_body()


func _configure_physics_body() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	platform_floor_layers = 1
	floor_stop_on_slope = true
	floor_block_on_wall = true
	floor_snap_length = 0.15
	max_slides = 6
	safe_margin = 0.004


func configure(p_type_name: String, type_cfg: Dictionary, size: Vector3, start_pos: Vector3) -> void:
	entity_type_name = p_type_name
	behavior = str(type_cfg.get("behavior", "pushable_stop"))
	params = (type_cfg.get("params", {}) as Dictionary).duplicate(true)
	clears_velocity = bool(params.get("clears_velocity", behavior != "pushable_sliding"))
	entity_size = size
	position = start_pos
	set_meta("kl_type", p_type_name)
	set_meta("kl_behavior", behavior)

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = entity_size
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(collision_shape)

	proxy_mesh = MeshInstance3D.new()
	proxy_mesh.name = "Mesh"
	proxy_mesh.layers = 1
	proxy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box_mesh := BoxMesh.new()
	box_mesh.size = entity_size
	proxy_mesh.mesh = box_mesh
	proxy_mesh.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(proxy_mesh)

	rider_cast = ShapeCast3D.new()
	rider_cast.name = "RiderShapeCast"
	var cast_box := BoxShape3D.new()
	cast_box.size = Vector3(entity_size.x * 0.85, 0.08, entity_size.z * 0.85)
	rider_cast.shape = cast_box
	rider_cast.position = Vector3(0.0, entity_size.y + 0.04, 0.0)
	rider_cast.target_position = Vector3(0.0, 0.14, 0.0)
	rider_cast.collision_mask = 4
	rider_cast.exclude_parent = true
	rider_cast.enabled = true
	add_child(rider_cast)


func bind_director(p_director: KlRoomDirector) -> void:
	director = p_director


func get_stacked_riders() -> Array[Node3D]:
	var riders: Array[Node3D] = []
	if rider_cast == null or not is_inside_tree():
		return riders
	rider_cast.force_shapecast_update()
	if not rider_cast.is_colliding():
		return riders
	for i: int in range(rider_cast.get_collision_count()):
		var collider: Object = rider_cast.get_collider(i)
		if (collider is KlPushableEntity or collider is PushableBlock or collider is KlSpecialItem) and collider != self:
			var rider: Node3D = collider as Node3D
			if not riders.has(rider):
				riders.append(rider)
	return riders


func can_push(horiz_motion: Vector3, visited: Dictionary = {}) -> bool:
	var id_key: int = get_instance_id()
	if visited.has(id_key):
		return true
	visited[id_key] = true

	if test_move(global_transform, horiz_motion):
		return false

	if director != null:
		var next_pos: Vector3 = position + horiz_motion
		var margin_x: float = entity_size.x * 0.5 + 0.02
		var margin_z: float = entity_size.z * 0.5 + 0.02
		if not director.is_inside_room_xz(next_pos, margin_x, margin_z):
			return false

	for rider: Node3D in get_stacked_riders():
		if rider is KlPushableEntity:
			if not (rider as KlPushableEntity).can_push(horiz_motion, visited):
				return false
		elif rider is PhysicsBody3D:
			var pb: PhysicsBody3D = rider as PhysicsBody3D
			if pb.test_move(pb.global_transform, horiz_motion):
				return false
	return true


func try_push(motion: Vector3) -> bool:
	var horiz := Vector3(motion.x, 0.0, motion.z)
	if horiz.length_squared() < 1e-8:
		return false
	var cardinal: Vector3 = _to_cardinal(horiz)
	var step_dist: float = horiz.length()
	var step_vec: Vector3 = cardinal * step_dist
	if not can_push(step_vec, {}):
		return false
	_apply_push_recursive(step_vec, {})
	if not clears_velocity:
		_slide_dir = cardinal
	return true


func try_pull(motion: Vector3) -> bool:
	var horiz := Vector3(motion.x, 0.0, motion.z)
	if horiz.length_squared() < 1e-8:
		return false
	var cardinal: Vector3 = _to_cardinal(horiz)
	var step_vec: Vector3 = cardinal * horiz.length()
	if not can_push(step_vec, {}):
		return false
	_slide_dir = Vector3.ZERO
	_apply_push_recursive(step_vec, {})
	return true


static func _to_cardinal(v: Vector3) -> Vector3:
	if absf(v.x) >= absf(v.z):
		return Vector3(signf(v.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _apply_push_recursive(horiz: Vector3, visited: Dictionary) -> void:
	var id_key: int = get_instance_id()
	if visited.has(id_key):
		return
	visited[id_key] = true

	var riders: Array[Node3D] = get_stacked_riders()
	global_position += horiz
	for rider: Node3D in riders:
		if rider is KlPushableEntity:
			(rider as KlPushableEntity)._apply_push_recursive(horiz, visited)
		else:
			rider.global_position += horiz


func _physics_process(delta: float) -> void:
	if simulation_active and not clears_velocity and _slide_dir != Vector3.ZERO:
		var spd: float = slide_speed
		if director != null:
			var walk_u: float = float((director.entities_cfg.get("player", {}) as Dictionary).get("walk_speed", 3.0))
			spd = maxf(director.kl_speed_to_mps(walk_u), 2.2)
		var step: Vector3 = _slide_dir * spd * delta
		if can_push(step, {}):
			_apply_push_recursive(step, {})
		else:
			_slide_dir = Vector3.ZERO

	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity_accel * delta
	else:
		velocity.y = 0.0
	move_and_slide()
