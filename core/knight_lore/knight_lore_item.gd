class_name KlSpecialItem
extends CharacterBody3D
## Interactive Knight Lore special object (charms 0..6 & Extra Life idol 7).
## Carryable charms behave as climbable, gently pushable solid props under gravity;
## dropped charms in Room 136 can launch an arc into Melkhior's cauldron.

signal extra_life_touched(item_id: int)

const GRAVITY_ACCEL: float = 30.0

var item_id: int = -1
var type_id: int = 0
var is_extra_life: bool = false
var is_arcing: bool = false

var collision_shape: CollisionShape3D
var pickup_area: Area3D
var visual_node: Node3D
var _spin_phase: float = 0.0


func configure(id: int, charm_type: int, start_pos: Vector3) -> void:
	item_id = id
	type_id = charm_type
	is_extra_life = (charm_type == 7)
	name = "KlItem_%d_%s" % [id, KnightLoreSession.get_charm_name(charm_type).replace(" ", "_")]
	position = start_pos

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	if is_extra_life:
		collision_layer = 0
		collision_mask = 0
		pickup_area = Area3D.new()
		pickup_area.name = "ExtraLifeArea"
		pickup_area.collision_layer = 8
		pickup_area.collision_mask = 2
		pickup_area.monitoring = true
		var a_col := CollisionShape3D.new()
		var a_box := BoxShape3D.new()
		a_box.size = Vector3(0.75, 0.90, 0.75)
		a_col.shape = a_box
		a_col.position = Vector3(0.0, 0.45, 0.0)
		pickup_area.add_child(a_col)
		pickup_area.body_entered.connect(_on_pickup_area_entered)
		add_child(pickup_area)
	else:
		collision_layer = 4
		collision_mask = 1 | 4
		floor_stop_on_slope = true
		floor_snap_length = 0.12
		max_slides = 4
		safe_margin = 0.004

		collision_shape = CollisionShape3D.new()
		collision_shape.name = "BodyCollider"
		var box := BoxShape3D.new()
		box.size = Vector3(0.58, 0.72, 0.58)
		collision_shape.shape = box
		collision_shape.position = Vector3(0.0, 0.36, 0.0)
		add_child(collision_shape)

	var glb_path: String = KnightLoreSession.get_charm_glb_path(charm_type)
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			inst.name = "ModelVisual"
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


func _on_pickup_area_entered(body: Node3D) -> void:
	if is_extra_life and body is PlayerController:
		extra_life_touched.emit(item_id)


func try_push(motion: Vector3) -> bool:
	if is_extra_life or is_arcing:
		return false
	var horiz := Vector3(motion.x, 0.0, motion.z)
	if horiz.length_squared() < 1e-8:
		return false
	if test_move(global_transform, horiz):
		return false
	global_position += horiz
	return true


func launch_cauldron_arc(target_pos: Vector3, on_finished: Callable) -> void:
	is_arcing = true
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	var start_pos: Vector3 = global_position
	var peak_pos := Vector3(
		lerpf(start_pos.x, target_pos.x, 0.5),
		maxf(start_pos.y, target_pos.y) + 0.95,
		lerpf(start_pos.z, target_pos.z, 0.5)
	)
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", peak_pos, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target_pos, 0.33).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(on_finished)


func _physics_process(delta: float) -> void:
	if visual_node != null and (is_extra_life or is_arcing):
		_spin_phase += delta
		visual_node.rotation.y = _spin_phase * 2.2
	if is_extra_life or is_arcing:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY_ACCEL * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
