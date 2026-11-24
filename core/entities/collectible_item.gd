class_name CollectibleItem
extends PuzzleEntity3D
## Pickup entity collected on overlap with PlayerController.

signal collected(entity_id: String, item_kind: String)

@export var item_kind: String = "key"

var is_collected: bool = false

var _visual_mesh: MeshInstance3D
var _visual_node: Node3D
var _sensor: Area3D


func setup_visual_and_collider(size: Vector3, mat: Material) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "Visual"
	_visual_mesh.layers = 1
	_visual_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	_visual_mesh.mesh = box
	_visual_mesh.position = Vector3(0.0, size.y * 0.5 + 0.15, 0.0)
	add_child(_visual_mesh)

	_sensor = Area3D.new()
	_sensor.name = "PickupSensor"
	_sensor.collision_layer = 8
	_sensor.collision_mask = 2
	_sensor.monitoring = true
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(maxf(size.x, 0.5), maxf(size.y + 0.4, 0.7), maxf(size.z, 0.5))
	col.shape = box_shape
	col.position = Vector3(0.0, 0.35, 0.0)
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
	inst.position = Vector3(0.0, 0.15, 0.0)
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
	if is_collected:
		return
	var rot_target: Node3D = _visual_node if _visual_node != null else _visual_mesh
	if rot_target != null:
		rot_target.rotation.y += 1.6 * delta
	if _sensor != null and is_inside_tree():
		for body: Node3D in _sensor.get_overlapping_bodies():
			if body is PlayerController:
				_mark_collected()
				break


func _mark_collected() -> void:
	if is_collected:
		return
	is_collected = true
	if _visual_mesh != null:
		_visual_mesh.visible = false
	if _visual_node != null:
		_visual_node.visible = false
	if _sensor != null:
		_sensor.set_deferred("monitoring", false)
	collected.emit(entity_id, item_kind)


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"is_collected": is_collected
	}


func hydrate_state(data: Dictionary) -> void:
	is_collected = bool(data.get("is_collected", false))
	if _visual_mesh != null:
		_visual_mesh.visible = not is_collected
	if _visual_node != null:
		_visual_node.visible = not is_collected
	if _sensor != null:
		_sensor.monitoring = not is_collected
