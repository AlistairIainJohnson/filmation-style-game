class_name Portcullis
extends AnimatableBody3D
## Rising/lowering security gate controlled by TriggerSwitch or puzzle state.

@export var entity_id: String = ""
@export var archetype: String = "portcullis"
@export var persistent: bool = true
@export var starts_closed: bool = true
@export var open_lift_height: float = 2.6
@export var slide_speed: float = 4.5
@export var latch_open: bool = false

var is_open: bool = false
var _closed_y: float = 0.0
var _visual_mesh: MeshInstance3D
var _visual_node: Node3D


func _init() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(PuzzleEntity3D.GROUP_NAME)
	sync_to_physics = true
	_closed_y = position.y
	if not starts_closed:
		is_open = true
		position.y = _closed_y + open_lift_height


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


func on_trigger_changed(active: bool) -> void:
	if active:
		is_open = true
	elif not latch_open:
		is_open = false


func _physics_process(delta: float) -> void:
	var target_y: float = _closed_y + (open_lift_height if is_open else 0.0)
	position.y = move_toward(position.y, target_y, slide_speed * delta)


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"is_open": is_open,
		"pos": [position.x, position.y, position.z]
	}


func hydrate_state(data: Dictionary) -> void:
	is_open = bool(data.get("is_open", not starts_closed))
	if data.has("pos"):
		var p: Variant = data["pos"]
		if p is Array and p.size() >= 3:
			position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	else:
		position.y = _closed_y + (open_lift_height if is_open else 0.0)
