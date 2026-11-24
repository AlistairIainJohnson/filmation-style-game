class_name PushableBlock
extends CharacterBody3D
## Deterministic kinematic pushable and stackable puzzle block.
## Never uses unconstrained RigidBody3D dynamics.

@export var entity_id: String = ""
@export var archetype: String = "pushable_chest"
@export var persistent: bool = true
@export var block_size: Vector3 = Vector3(0.98, 1.0, 0.98)
@export var gravity_accel: float = 35.0
@export var snap_increment: float = 0.5
@export var snap_speed: float = 6.0
@export var snap_release_delay: float = 0.08

var collision_shape: CollisionShape3D
var visual_mesh: MeshInstance3D
var visual_node: Node3D
var rider_cast: ShapeCast3D

var _pushed_this_tick: bool = false
var _needs_release_snap: bool = false
var _snap_cooldown: float = 0.0


func _init() -> void:
	_configure_physics_body()


func _ready() -> void:
	add_to_group(PuzzleEntity3D.GROUP_NAME)
	_configure_physics_body()


func _configure_physics_body() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	# Ride MovingPlatform / AnimatableBody3D on layer 1; stacked PushableBlocks on layer 4
	# are carried deterministically by _apply_push_recursive without double-carrying.
	platform_floor_layers = 1
	floor_stop_on_slope = true
	floor_block_on_wall = true
	floor_snap_length = 0.15
	max_slides = 6
	safe_margin = 0.004


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	block_size = size
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "BodyCollider"
	var box_shape := BoxShape3D.new()
	box_shape.size = block_size
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, block_size.y * 0.5, 0.0)
	add_child(collision_shape)

	visual_mesh = MeshInstance3D.new()
	visual_mesh.name = "Visual"
	visual_mesh.layers = 1
	visual_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box_mesh := BoxMesh.new()
	box_mesh.size = block_size
	box_mesh.material = mat
	visual_mesh.mesh = box_mesh
	visual_mesh.position = Vector3(0.0, block_size.y * 0.5, 0.0)
	add_child(visual_mesh)

	rider_cast = ShapeCast3D.new()
	rider_cast.name = "RiderShapeCast"
	var cast_box := BoxShape3D.new()
	cast_box.size = Vector3(block_size.x * 0.88, 0.08, block_size.z * 0.88)
	rider_cast.shape = cast_box
	rider_cast.position = Vector3(0.0, block_size.y + 0.04, 0.0)
	rider_cast.target_position = Vector3(0.0, 0.14, 0.0)
	rider_cast.collision_mask = 4
	rider_cast.exclude_parent = true
	rider_cast.enabled = true
	add_child(rider_cast)


func set_visual_model(model_scene: PackedScene) -> void:
	if model_scene == null:
		return
	if visual_mesh != null and is_instance_valid(visual_mesh):
		remove_child(visual_mesh)
		visual_mesh.free()
		visual_mesh = null
	if visual_node != null and is_instance_valid(visual_node):
		remove_child(visual_node)
		visual_node.free()
		visual_node = null

	var inst: Node3D = model_scene.instantiate() as Node3D
	inst.name = "ModelVisual"
	inst.position = Vector3.ZERO
	_set_layer_recursive(inst)
	add_child(inst)
	visual_node = inst


static func _set_layer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_set_layer_recursive(child)


func get_stacked_riders() -> Array[PushableBlock]:
	var riders: Array[PushableBlock] = []
	if rider_cast == null or not is_inside_tree():
		return riders
	rider_cast.force_shapecast_update()
	if not rider_cast.is_colliding():
		return riders
	for i: int in range(rider_cast.get_collision_count()):
		var collider: Object = rider_cast.get_collider(i)
		if collider is PushableBlock and collider != self:
			var rider: PushableBlock = collider as PushableBlock
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

	for rider: PushableBlock in get_stacked_riders():
		if not rider.can_push(horiz_motion, visited):
			return false
	return true


func try_push(motion: Vector3) -> bool:
	var horiz := Vector3(motion.x, 0.0, motion.z)
	if horiz.length_squared() < 1e-8:
		return false
	if not can_push(horiz, {}):
		return false
	_apply_push_recursive(horiz, {}, true)
	return true


func _apply_push_recursive(horiz: Vector3, visited: Dictionary, mark_pushed: bool) -> void:
	var id_key: int = get_instance_id()
	if visited.has(id_key):
		return
	visited[id_key] = true

	var riders: Array[PushableBlock] = get_stacked_riders()
	global_position += horiz
	if mark_pushed:
		_pushed_this_tick = true
		_needs_release_snap = true
		_snap_cooldown = snap_release_delay

	for rider: PushableBlock in riders:
		rider._apply_push_recursive(horiz, visited, mark_pushed)


func _physics_process(delta: float) -> void:
	if _pushed_this_tick:
		_pushed_this_tick = false
	elif _snap_cooldown > 0.0:
		_snap_cooldown = maxf(0.0, _snap_cooldown - delta)
	elif _needs_release_snap and is_on_floor() and snap_increment > 0.0:
		var target_x: float = snappedf(global_position.x, snap_increment)
		var target_z: float = snappedf(global_position.z, snap_increment)
		var delta_xz := Vector3(target_x - global_position.x, 0.0, target_z - global_position.z)
		if delta_xz.length() <= 0.005:
			if not test_move(global_transform, delta_xz):
				_apply_push_recursive(delta_xz, {}, false)
			_needs_release_snap = false
		else:
			var step_len: float = minf(delta_xz.length(), snap_speed * delta)
			var step: Vector3 = delta_xz.normalized() * step_len
			if can_push(step, {}):
				_apply_push_recursive(step, {}, false)
			else:
				_needs_release_snap = false

	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity_accel * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"pos": [global_position.x, global_position.y, global_position.z]
	}


func hydrate_state(data: Dictionary) -> void:
	if data.has("pos"):
		var p: Variant = data["pos"]
		if p is Array and p.size() >= 3:
			global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_pushed_this_tick = false
	_needs_release_snap = false
