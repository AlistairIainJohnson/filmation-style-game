class_name PatrolHazard
extends PuzzleEntity3D
## Deterministic patrolling hazard moving along room waypoints.

signal player_hit(hazard_id: String, player: Node3D)

@export var waypoints: Array[Vector3] = []
@export var patrol_speed: float = 2.2

var _target_index: int = 1
var _direction: int = 1
var _sensor: Area3D
var _visual_mesh: MeshInstance3D
var _visual_node: Node3D
var _anim_player: AnimationPlayer


func _ready() -> void:
	super._ready()
	if waypoints.is_empty():
		waypoints.append(position)


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	mesh.layers = 1
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var cyl := CylinderMesh.new()
	cyl.top_radius = size.x * 0.42
	cyl.bottom_radius = size.x * 0.5
	cyl.height = size.y
	cyl.material = mat
	mesh.mesh = cyl
	mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(mesh)
	_visual_mesh = mesh

	_sensor = Area3D.new()
	_sensor.name = "HazardSensor"
	_sensor.collision_layer = 8
	_sensor.collision_mask = 2
	_sensor.monitoring = true
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = size.x * 0.48
	shape.height = size.y
	col.shape = shape
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	_sensor.add_child(col)
	add_child(_sensor)


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
	inst.rotation_degrees.y = 180.0
	_set_layer_recursive(inst)
	add_child(inst)
	_visual_node = inst
	_anim_player = HumanoidAnimationLibrary.attach_to_character(inst)
	if _anim_player != null and _anim_player.has_animation(&"walk"):
		_anim_player.play(&"walk")


static func _set_layer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_set_layer_recursive(child)


func _physics_process(delta: float) -> void:
	if waypoints.size() >= 2:
		_target_index = clampi(_target_index, 0, waypoints.size() - 1)
		var target: Vector3 = waypoints[_target_index]
		position = position.move_toward(target, patrol_speed * delta)
		if position.distance_to(target) <= 0.005:
			position = target
			if _target_index == waypoints.size() - 1:
				_direction = -1
			elif _target_index == 0:
				_direction = 1
			_target_index += _direction

	if _sensor != null and is_inside_tree():
		for body: Node3D in _sensor.get_overlapping_bodies():
			if body is PlayerController:
				player_hit.emit(entity_id, body)
				break


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"pos": [position.x, position.y, position.z],
		"target_index": _target_index,
		"direction": _direction
	}


func hydrate_state(data: Dictionary) -> void:
	super.hydrate_state(data)
	_target_index = int(data.get("target_index", _target_index))
	_direction = int(data.get("direction", _direction))
