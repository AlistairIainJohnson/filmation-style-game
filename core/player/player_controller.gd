class_name PlayerController
extends CharacterBody3D
## Deterministic CharacterBody3D player controller with camera-relative 8-way / 4-way
## movement, analytically derived asymmetric jump curve, coyote time, jump buffering,
## height-tracked Decal drop shadow, and global player_world_pos shader sync.

enum MoveMode { SCREEN_8_WAY, ISO_AXIS_4_WAY }

const PLAYER_VISUAL_LAYER: int = 2
const PLAYER_COLLISION_LAYER: int = 2
const WORLD_COLLISION_MASK: int = 1 | 4

@export var move_speed: float = 4.2
@export var push_speed: float = 2.4
@export var push_normal_y_threshold: float = 0.25
@export var jump_height: float = 1.35
@export var time_to_apex: float = 0.28
@export var time_to_descent: float = 0.22
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.10
@export var move_mode: MoveMode = MoveMode.SCREEN_8_WAY
@export var enable_player_input: bool = true
@export var character_model_path: String = "res://assets/characters/hero_explorer.glb"
@export var night_character_model_path: String = "res://assets/characters/hero_werewolf.glb"

var jump_velocity: float = 0.0
var gravity_up: float = 0.0
var gravity_down: float = 0.0

var visual_root: Node3D
var anim_player: AnimationPlayer
var current_anim_state: StringName = &"idle"
var active_model_path: String = ""
var drop_shadow: DropShadowController
var collision_shape: CollisionShape3D

var _camera_rig: DioramaCameraRig
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0


func _init() -> void:
	recompute_jump_constants()
	_configure_physics_body()
	_build_default_nodes()


func _ready() -> void:
	recompute_jump_constants()
	_configure_physics_body()
	sync_shader_world_pos()
	if drop_shadow != null:
		drop_shadow.call_deferred("update_shadow")


func recompute_jump_constants() -> void:
	jump_velocity = (2.0 * jump_height) / time_to_apex
	gravity_up = (2.0 * jump_height) / (time_to_apex * time_to_apex)
	gravity_down = (2.0 * jump_height) / (time_to_descent * time_to_descent)


func _configure_physics_body() -> void:
	collision_layer = PLAYER_COLLISION_LAYER
	collision_mask = WORLD_COLLISION_MASK
	floor_stop_on_slope = true
	floor_block_on_wall = true
	floor_snap_length = 0.2
	max_slides = 8
	safe_margin = 0.005
	wall_min_slide_angle = deg_to_rad(15.0)


func _build_default_nodes() -> void:
	if collision_shape == null or not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "BodyCollider"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.28
		capsule.height = 1.36
		collision_shape.shape = capsule
		collision_shape.position = Vector3(0.0, 0.68, 0.0)
		add_child(collision_shape)

	if visual_root == null or not is_instance_valid(visual_root):
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)

		var loaded_model: bool = set_character_model(character_model_path)

		if not loaded_model:
			var armor_mat := StandardMaterial3D.new()
			armor_mat.albedo_color = Color(0.24, 0.44, 0.72, 1.0)
			armor_mat.metallic = 0.45
			armor_mat.roughness = 0.42

			var visor_mat := StandardMaterial3D.new()
			visor_mat.albedo_color = Color(0.92, 0.76, 0.34, 1.0)
			visor_mat.metallic = 0.85
			visor_mat.roughness = 0.28

			var torso := MeshInstance3D.new()
			torso.name = "TorsoMesh"
			torso.layers = PLAYER_VISUAL_LAYER
			torso.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			var torso_mesh := CapsuleMesh.new()
			torso_mesh.radius = 0.26
			torso_mesh.height = 0.96
			torso_mesh.material = armor_mat
			torso.mesh = torso_mesh
			torso.position = Vector3(0.0, 0.50, 0.0)
			visual_root.add_child(torso)

			var head := MeshInstance3D.new()
			head.name = "HeadMesh"
			head.layers = PLAYER_VISUAL_LAYER
			head.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			var head_mesh := SphereMesh.new()
			head_mesh.radius = 0.22
			head_mesh.height = 0.44
			head_mesh.material = armor_mat
			head.mesh = head_mesh
			head.position = Vector3(0.0, 1.14, 0.0)
			visual_root.add_child(head)

			var visor := MeshInstance3D.new()
			visor.name = "VisorMesh"
			visor.layers = PLAYER_VISUAL_LAYER
			visor.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			var visor_mesh := BoxMesh.new()
			visor_mesh.size = Vector3(0.26, 0.09, 0.14)
			visor_mesh.material = visor_mat
			visor.mesh = visor_mesh
			visor.position = Vector3(0.0, 1.16, -0.18)
			visual_root.add_child(visor)

	if drop_shadow == null or not is_instance_valid(drop_shadow):
		drop_shadow = DropShadowController.new()
		drop_shadow.name = "DropShadowController"
		add_child(drop_shadow)


func set_camera_rig(rig: DioramaCameraRig) -> void:
	_camera_rig = rig


func set_character_model(model_path: String) -> bool:
	if visual_root == null or not is_instance_valid(visual_root):
		return false
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return false
	if active_model_path == model_path and visual_root.get_node_or_null("HeroModel") != null:
		return true

	var packed: PackedScene = ResourceLoader.load(model_path) as PackedScene
	if packed == null:
		return false

	var existing: Node = visual_root.get_node_or_null("HeroModel")
	if existing != null and is_instance_valid(existing):
		visual_root.remove_child(existing)
		existing.free()
	anim_player = null

	var model_inst: Node3D = packed.instantiate() as Node3D
	model_inst.name = "HeroModel"
	model_inst.rotation_degrees.y = 180.0
	_apply_visual_layer_recursive(model_inst, PLAYER_VISUAL_LAYER)
	visual_root.add_child(model_inst)
	anim_player = HumanoidAnimationLibrary.attach_to_character(model_inst)
	active_model_path = model_path
	if anim_player != null:
		if anim_player.has_animation(current_anim_state):
			anim_player.play(current_anim_state)
		elif anim_player.has_animation(&"idle"):
			anim_player.play(&"idle")
	return true


func set_night_form(is_night: bool) -> void:
	var target_path: String = night_character_model_path if is_night else character_model_path
	set_character_model(target_path)


func set_move_mode(mode: MoveMode) -> void:
	move_mode = mode


func toggle_move_mode() -> void:
	if move_mode == MoveMode.SCREEN_8_WAY:
		move_mode = MoveMode.ISO_AXIS_4_WAY
	else:
		move_mode = MoveMode.SCREEN_8_WAY


func compute_move_direction(input_vec: Vector2) -> Vector3:
	if input_vec.length_squared() < 0.0001:
		return Vector3.ZERO

	if move_mode == MoveMode.ISO_AXIS_4_WAY:
		if absf(input_vec.x) > absf(input_vec.y):
			return Vector3(signf(input_vec.x), 0.0, 0.0)
		return Vector3(0.0, 0.0, signf(input_vec.y))

	var cam_right: Vector3 = Vector3(0.70710678, 0.0, -0.70710678)
	var cam_forward: Vector3 = Vector3(-0.70710678, 0.0, -0.70710678)
	if _camera_rig != null and is_instance_valid(_camera_rig):
		cam_right = _camera_rig.get_camera_right_xz()
		cam_forward = _camera_rig.get_camera_forward_xz()

	return (cam_right * input_vec.x + cam_forward * (-input_vec.y)).normalized()


func _physics_process(delta: float) -> void:
	if enable_player_input:
		if Input.is_action_just_pressed("toggle_move_mode"):
			toggle_move_mode()
		var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var jump_pressed: bool = Input.is_action_just_pressed("jump")
		step_movement(input_vec, jump_pressed, delta)
	else:
		sync_shader_world_pos()


func step_movement(input_vec: Vector2, jump_just_pressed: bool, delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	if jump_just_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	var dir: Vector3 = compute_move_direction(input_vec)
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

	if dir.length_squared() > 0.001 and visual_root != null:
		visual_root.rotation.y = atan2(-dir.x, -dir.z)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0

	if not is_on_floor() or velocity.y > 0.0:
		var g: float = gravity_up if velocity.y > 0.0 else gravity_down
		velocity.y -= g * delta

	move_and_slide()

	var is_pushing: bool = false
	if dir.length_squared() > 0.001:
		for i: int in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var collider: Object = col.get_collider()
			var normal: Vector3 = col.get_normal()
			if collider is PushableBlock and absf(normal.y) < push_normal_y_threshold:
				var push_dir := Vector3(-normal.x, 0.0, -normal.z)
				if push_dir.length_squared() > 0.001:
					push_dir = push_dir.normalized()
					if dir.dot(push_dir) > 0.35:
						is_pushing = true
						var push_motion: Vector3 = push_dir * push_speed * delta
						if (collider as PushableBlock).try_push(push_motion):
							move_and_collide(push_motion)
						break

	_update_anim_state(dir, is_pushing)
	sync_shader_world_pos()
	if drop_shadow != null:
		drop_shadow.update_shadow()


func _update_anim_state(dir: Vector3, is_pushing: bool) -> void:
	var next_anim: StringName = &"idle"
	if not is_on_floor():
		next_anim = &"jump" if velocity.y > 0.0 else &"fall"
	elif is_pushing:
		next_anim = &"push"
	elif dir.length_squared() > 0.001:
		next_anim = &"walk"

	if next_anim != current_anim_state:
		current_anim_state = next_anim
		if anim_player != null and anim_player.has_animation(next_anim):
			anim_player.play(next_anim)


static func _apply_visual_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = layer_mask
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_apply_visual_layer_recursive(child, layer_mask)


func sync_shader_world_pos() -> void:
	RenderingServer.global_shader_parameter_set(&"player_world_pos", global_position + Vector3(0.0, 0.75, 0.0))
	update_occluder_cutaways()


func update_occluder_cutaways() -> void:
	if not is_inside_tree():
		return

	var cam_dir: Vector3 = Vector3(1.0, 1.0, 1.0).normalized()
	var cam_right: Vector3 = Vector3(0.70710678, 0.0, -0.70710678)
	if _camera_rig != null and is_instance_valid(_camera_rig):
		if _camera_rig.camera != null and is_instance_valid(_camera_rig.camera):
			cam_dir = _camera_rig.camera.global_transform.basis.z.normalized()
		cam_right = _camera_rig.get_camera_right_xz()

	var sample_origins: Array[Vector3] = [
		global_position + Vector3(0.0, 0.30, 0.0),
		global_position + Vector3(0.0, 0.75, 0.0),
		global_position + Vector3(0.0, 1.20, 0.0),
		global_position + Vector3(0.0, 0.75, 0.0) + cam_right * 0.20,
		global_position + Vector3(0.0, 0.75, 0.0) - cam_right * 0.20
	]

	for occ: Node in get_tree().get_nodes_in_group("foreground_occluders"):
		if not (occ is Node3D) or not bool(occ.get_meta("cutaway", true)):
			continue
		var mesh_inst: MeshInstance3D = occ.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_inst == null:
			continue
		var world_aabb: AABB = (mesh_inst.global_transform * mesh_inst.get_aabb()).grow(-0.01)
		var occluded: bool = false
		for orig: Vector3 in sample_origins:
			if world_aabb.intersects_segment(orig, orig + cam_dir * 40.0) != null:
				occluded = true
				break
		var active_val: float = 1.0 if occluded else 0.0
		_set_cutaway_active_recursive(occ, active_val)
		occ.set_meta("cutaway_active", occluded)


static func _set_cutaway_active_recursive(node: Node, active_val: float) -> void:
	if node.name == "ShadowCaster":
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).set_instance_shader_parameter(&"cutaway_active", active_val)
	for child: Node in node.get_children():
		_set_cutaway_active_recursive(child, active_val)
