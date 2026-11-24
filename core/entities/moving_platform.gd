class_name MovingPlatform
extends AnimatableBody3D
## Deterministic kinematic moving platform using AnimatableBody3D (sync_to_physics = true)
## so carried PlayerController and PushableBlock riders inherit velocity cleanly.

@export var entity_id: String = ""
@export var archetype: String = "moving_platform"
@export var persistent: bool = true
@export var waypoints: Array[Vector3] = []
@export var move_speed: float = 2.0
@export var pause_duration: float = 0.25

var _target_index: int = 1
var _direction: int = 1
var _pause_timer: float = 0.0
var _visual_mesh: MeshInstance3D
var _visual_node: Node3D


func _init() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(PuzzleEntity3D.GROUP_NAME)
	sync_to_physics = true
	if waypoints.is_empty():
		waypoints.append(position)


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var col := CollisionShape3D.new()
	col.name = "BodyCollider"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	mesh.layers = 1
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(mesh)
	_visual_mesh = mesh


func set_visual_model(model_scene: PackedScene) -> void:
	if model_scene == null:
		return
	if _visual_mesh != null and is_instance_valid(_visual_mesh):
		remove_child(_visual_mesh)
		_visual_mesh.free()
		_visual_mesh = null
	if _visual_node != null and is_instance_valid(_visual_node):
		remove_child(_visual_node)
		_visual_node.free()
		_visual_node = null

	var inst: Node3D = model_scene.instantiate() as Node3D
	inst.name = "ModelVisual"
	_set_layer_recursive(inst)
	add_child(inst)
	_visual_node = inst


static func _set_layer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_set_layer_recursive(child)


func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return

	if _pause_timer > 0.0:
		_pause_timer = maxf(0.0, _pause_timer - delta)
		return

	_target_index = clampi(_target_index, 0, waypoints.size() - 1)
	var target: Vector3 = waypoints[_target_index]
	var next_pos: Vector3 = position.move_toward(target, move_speed * delta)
	position = next_pos

	if position.distance_to(target) <= 0.002:
		position = target
		_pause_timer = pause_duration
		if _target_index == waypoints.size() - 1:
			_direction = -1
		elif _target_index == 0:
			_direction = 1
		_target_index += _direction


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"pos": [position.x, position.y, position.z],
		"target_index": _target_index,
		"direction": _direction
	}


func hydrate_state(data: Dictionary) -> void:
	if data.has("pos"):
		var p: Variant = data["pos"]
		if p is Array and p.size() >= 3:
			position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_target_index = int(data.get("target_index", _target_index))
	_direction = int(data.get("direction", _direction))
