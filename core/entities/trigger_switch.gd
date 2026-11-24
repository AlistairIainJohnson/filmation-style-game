class_name TriggerSwitch
extends PuzzleEntity3D
## Floor pressure plate triggered by PlayerController or PushableBlock overlap.

signal state_changed(switch_id: String, is_pressed: bool)

@export var trigger_targets: Array[String] = []

var is_pressed: bool = false

var _linked_nodes: Array[Node] = []
var _visual_mesh: MeshInstance3D
var _visual_node: Node3D
var _sensor: Area3D
var _rest_y: float = 0.05


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_rest_y = size.y * 0.5
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "Visual"
	_visual_mesh.layers = 1
	_visual_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	_visual_mesh.mesh = box
	_visual_mesh.position = Vector3(0.0, _rest_y, 0.0)
	add_child(_visual_mesh)

	_sensor = Area3D.new()
	_sensor.name = "PlateSensor"
	_sensor.collision_layer = 8
	_sensor.collision_mask = 2 | 4
	_sensor.monitoring = true
	var col := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(size.x, 0.5, size.z)
	col.shape = sensor_box
	col.position = Vector3(0.0, 0.25, 0.0)
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
	_set_layer_recursive(inst)
	inst.position.y = -0.04 if is_pressed else 0.0
	add_child(inst)
	_visual_node = inst


static func _set_layer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_set_layer_recursive(child)


func bind_targets(nodes: Array[Node]) -> void:
	_linked_nodes = nodes.duplicate()
	_notify_targets()


func _physics_process(_delta: float) -> void:
	evaluate_overlap()


func evaluate_overlap() -> void:
	if _sensor == null or not is_inside_tree():
		return
	var bodies: Array[Node3D] = _sensor.get_overlapping_bodies()
	var next_pressed: bool = false
	for b: Node3D in bodies:
		if b is PlayerController or b is PushableBlock:
			next_pressed = true
			break
	if next_pressed != is_pressed:
		_set_pressed(next_pressed)


func _set_pressed(pressed: bool) -> void:
	is_pressed = pressed
	if _visual_mesh != null:
		_visual_mesh.position.y = _rest_y - (0.04 if is_pressed else 0.0)
	if _visual_node != null:
		_visual_node.position.y = -0.04 if is_pressed else 0.0
	state_changed.emit(entity_id, is_pressed)
	_notify_targets()


func _notify_targets() -> void:
	for target: Node in _linked_nodes:
		if is_instance_valid(target) and target.has_method("on_trigger_changed"):
			target.call("on_trigger_changed", is_pressed)


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"is_pressed": is_pressed
	}


func hydrate_state(data: Dictionary) -> void:
	_set_pressed(bool(data.get("is_pressed", false)))
