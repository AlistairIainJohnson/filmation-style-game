class_name CollapsingTile
extends AnimatableBody3D
## Classic Filmation crumbling floor tile that drops away shortly after being stepped on.

signal collapsed_triggered(entity_id: String)

@export var entity_id: String = ""
@export var archetype: String = "collapsing_tile"
@export var persistent: bool = true
@export var collapse_delay: float = 0.35
@export var drop_distance: float = 4.0

var triggered: bool = false
var collapsed: bool = false

var _timer: float = 0.0
var _start_y: float = 0.0
var _collider: CollisionShape3D
var _sensor: Area3D
var _visual_mesh: MeshInstance3D
var _visual_node: Node3D


func _init() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(PuzzleEntity3D.GROUP_NAME)
	_start_y = position.y


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_collider = CollisionShape3D.new()
	_collider.name = "BodyCollider"
	var shape := BoxShape3D.new()
	shape.size = size
	_collider.shape = shape
	_collider.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(_collider)

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

	_sensor = Area3D.new()
	_sensor.name = "StepSensor"
	_sensor.collision_layer = 8
	_sensor.collision_mask = 2 | 4
	_sensor.monitoring = true
	var sensor_col := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(size.x * 0.85, 0.25, size.z * 0.85)
	sensor_col.shape = sensor_box
	sensor_col.position = Vector3(0.0, size.y + 0.12, 0.0)
	_sensor.add_child(sensor_col)
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
	if collapsed:
		position.y = move_toward(position.y, _start_y - drop_distance, 10.0 * delta)
		return

	if not triggered and _sensor != null:
		if not _sensor.get_overlapping_bodies().is_empty():
			triggered = true
			_timer = collapse_delay

	if triggered and not collapsed:
		_timer -= delta
		if _timer <= 0.0:
			collapsed = true
			if _collider != null:
				_collider.disabled = true
			if _sensor != null:
				_sensor.monitoring = false
			collapsed_triggered.emit(entity_id)


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"collapsed": collapsed
	}


func hydrate_state(data: Dictionary) -> void:
	collapsed = bool(data.get("collapsed", false))
	triggered = collapsed
	if collapsed:
		if _collider != null:
			_collider.disabled = true
		if _sensor != null:
			_sensor.monitoring = false
		position.y = _start_y - drop_distance
