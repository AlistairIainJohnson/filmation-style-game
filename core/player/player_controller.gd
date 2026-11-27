class_name PlayerController
extends CharacterBody3D
## Deterministic CharacterBody3D player controller with camera-relative 8-way / 4-way
## movement, analytically derived asymmetric jump curve, coyote time, jump buffering,
## height-tracked Decal drop shadow, and global player_world_pos shader sync.

signal stepped(step_pos: Vector3)
signal jumped()
signal landed()
signal pushed()

enum MoveMode { SCREEN_8_WAY, ISO_AXIS_4_WAY, ROTATIONAL_4_WAY }

const PLAYER_VISUAL_LAYER: int = 2
const PLAYER_COLLISION_LAYER: int = 2
const WORLD_COLLISION_MASK: int = 1 | 4

@export var move_speed: float = 4.2
@export var push_speed: float = 2.4
@export var pull_speed: float = 2.2
@export var ground_accel: float = 56.0
@export var ground_decel: float = 52.0
@export var turn_speed: float = 18.0
@export var rotational_turn_cooldown: float = 0.16
@export var diagonal_release_debounce: float = 0.045
@export var push_normal_y_threshold: float = 0.25
@export var jump_height: float = 1.35
@export var jump_boost: bool = false
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
var input_locked: bool = false
var facing_cardinal: int = 3 # 0=West (-X), 1=East (+X), 2=North (-Z), 3=South (+Z)
var is_pulling: bool = false

var _camera_rig: DioramaCameraRig
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _rot_turn_timer: float = 0.0
var _target_yaw: float = 0.0
var allow_mode_toggle_hotkey: bool = true
var _has_facing_target: bool = false
var _prev_input_was_diagonal: bool = false
var _diag_debounce_timer: float = 0.0
var _last_diag_yaw: float = 0.0
var _was_on_floor: bool = true
var _land_timer: float = 0.0
var _step_distance_accumulator: float = 0.0


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
		capsule.radius = 0.24
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


func set_rotational_mode(enabled: bool) -> void:
	move_mode = MoveMode.ROTATIONAL_4_WAY if enabled else MoveMode.SCREEN_8_WAY
	_rot_turn_timer = 0.0
	if enabled:
		var fv: Vector3 = get_facing_vector()
		_target_yaw = atan2(-fv.x, -fv.z)
		_has_facing_target = true


func toggle_control_scheme() -> void:
	set_rotational_mode(move_mode != MoveMode.ROTATIONAL_4_WAY)


func get_facing_vector() -> Vector3:
	match facing_cardinal:
		0:
			return Vector3(-1.0, 0.0, 0.0)
		1:
			return Vector3(1.0, 0.0, 0.0)
		2:
			return Vector3(0.0, 0.0, -1.0)
		_:
			return Vector3(0.0, 0.0, 1.0)


func check_headroom_clear(lift_height: float = 0.76) -> bool:
	return not test_move(global_transform, Vector3(0.0, lift_height, 0.0))


func compute_move_direction(input_vec: Vector2) -> Vector3:
	if move_mode == MoveMode.ROTATIONAL_4_WAY:
		if input_vec.y < -0.5:
			return get_facing_vector()
		return Vector3.ZERO

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
		if allow_mode_toggle_hotkey and Input.is_action_just_pressed("toggle_move_mode"):
			toggle_move_mode()
		var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var jump_pressed: bool = Input.is_action_just_pressed("jump")
		var jump_held: bool = Input.is_action_pressed("jump")
		var pull_held: bool = Input.is_action_pressed("grab_pull")
		step_movement(input_vec, jump_pressed, delta, jump_held, pull_held)
	else:
		sync_shader_world_pos()


func _process(_delta: float) -> void:
	if is_inside_tree():
		sync_shader_world_pos(true)


func step_movement(input_vec: Vector2, jump_just_pressed: bool, delta: float, jump_held: bool = true, pull_held: bool = false) -> void:
	if input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor() or velocity.y > 0.0:
			velocity.y -= gravity_down * delta
		move_and_slide()
		_update_anim_state(Vector3.ZERO, false)
		sync_shader_world_pos()
		if drop_shadow != null:
			drop_shadow.update_shadow()
		return

	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	if jump_just_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	if _rot_turn_timer > 0.0:
		_rot_turn_timer = maxf(0.0, _rot_turn_timer - delta)

	if move_mode == MoveMode.ROTATIONAL_4_WAY and is_on_floor() and _rot_turn_timer <= 0.0 and absf(input_vec.x) > 0.5:
		const CW_ORDER: Array[int] = [0, 2, 1, 3]
		var cur_idx: int = CW_ORDER.find(facing_cardinal)
		if cur_idx == -1:
			cur_idx = 3
		var step_turn: int = 1 if input_vec.x > 0.0 else -1
		facing_cardinal = CW_ORDER[posmod(cur_idx + step_turn, 4)]
		_rot_turn_timer = rotational_turn_cooldown
		var rot_fv: Vector3 = get_facing_vector()
		_target_yaw = atan2(-rot_fv.x, -rot_fv.z)
		_has_facing_target = true

	var dir: Vector3 = compute_move_direction(input_vec)
	var pull_target: Node3D = null
	var pull_dir := Vector3.ZERO
	is_pulling = false
	if pull_held and is_on_floor() and dir.length_squared() > 0.001 and is_inside_tree():
		pull_target = _find_pull_target(dir)
		if pull_target != null:
			pull_dir = Vector3(signf(dir.x), 0.0, 0.0) if absf(dir.x) >= absf(dir.z) else Vector3(0.0, 0.0, signf(dir.z))

	var horiz_vel := Vector2(velocity.x, velocity.z)
	var eff_speed: float = move_speed * (1.35 if (jump_boost and not is_on_floor()) else 1.0)
	var target_vel := Vector2.ZERO if pull_target != null else (Vector2(dir.x, dir.z) * eff_speed)
	var accel_rate: float = ground_accel if (dir.length_squared() > 0.001 and pull_target == null) else ground_decel
	horiz_vel = horiz_vel.move_toward(target_vel, accel_rate * delta)
	if pull_target != null:
		horiz_vel = Vector2.ZERO
	velocity.x = horiz_vel.x
	velocity.z = horiz_vel.y

	if pull_target != null:
		var to_blk := Vector2(pull_target.global_position.x - global_position.x, pull_target.global_position.z - global_position.z)
		if to_blk.length_squared() > 0.0001:
			_target_yaw = atan2(-to_blk.x, -to_blk.y)
			_has_facing_target = true
		_prev_input_was_diagonal = false
		_diag_debounce_timer = 0.0
	elif dir.length_squared() > 0.001:
		var is_diag: bool = (move_mode != MoveMode.ROTATIONAL_4_WAY) and absf(input_vec.x) > 0.2 and absf(input_vec.y) > 0.2
		var desired_yaw: float = atan2(-dir.x, -dir.z)
		if is_diag:
			_prev_input_was_diagonal = true
			_diag_debounce_timer = diagonal_release_debounce
			_last_diag_yaw = desired_yaw
			_target_yaw = desired_yaw
			_has_facing_target = true
		elif _prev_input_was_diagonal and _diag_debounce_timer > 0.0:
			_diag_debounce_timer = maxf(0.0, _diag_debounce_timer - delta)
			_target_yaw = _last_diag_yaw
			_has_facing_target = true
		else:
			_prev_input_was_diagonal = false
			_diag_debounce_timer = 0.0
			_target_yaw = desired_yaw
			_has_facing_target = true
		if move_mode != MoveMode.ROTATIONAL_4_WAY:
			if absf(dir.x) >= absf(dir.z):
				facing_cardinal = 1 if dir.x >= 0.0 else 0
			else:
				facing_cardinal = 3 if dir.z >= 0.0 else 2
	else:
		_prev_input_was_diagonal = false
		_diag_debounce_timer = 0.0

	if visual_root != null and _has_facing_target:
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _target_yaw, 1.0 - exp(-turn_speed * delta))

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		jumped.emit()

	if not is_on_floor() or velocity.y > 0.0:
		var g: float = gravity_up if (velocity.y > 0.0 and jump_held) else gravity_down
		velocity.y -= g * delta

	move_and_slide()

	var grounded_now: bool = is_on_floor()
	if grounded_now and not _was_on_floor:
		_land_timer = 0.14
		landed.emit()
	elif _land_timer > 0.0:
		_land_timer = maxf(0.0, _land_timer - delta)
	_was_on_floor = grounded_now

	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if grounded_now and (dir.length_squared() > 0.001 or h_speed > 0.35):
		_step_distance_accumulator += h_speed * delta
		if _step_distance_accumulator >= 0.72:
			_step_distance_accumulator -= 0.72
			stepped.emit(global_position)
	else:
		_step_distance_accumulator = 0.0

	var is_pushing: bool = false
	if pull_target != null and pull_dir != Vector3.ZERO:
		var pull_motion: Vector3 = pull_dir * pull_speed * delta
		if not test_move(global_transform, pull_motion):
			global_position += pull_motion
			force_update_transform()
			var pulled_ok: bool = false
			if pull_target.has_method("try_pull"):
				pulled_ok = bool(pull_target.call("try_pull", pull_motion))
			elif pull_target.has_method("try_push"):
				pulled_ok = bool(pull_target.call("try_push", pull_motion))
			if pulled_ok:
				is_pulling = true
			else:
				global_position -= pull_motion
				force_update_transform()
	elif dir.length_squared() > 0.001:
		for i: int in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var collider: Object = col.get_collider()
			var normal: Vector3 = col.get_normal()
			if collider != null and (collider is PushableBlock or collider.has_method("try_push")) and absf(normal.y) < push_normal_y_threshold:
				var push_dir := Vector3(-normal.x, 0.0, -normal.z)
				if push_dir.length_squared() > 0.001:
					push_dir = push_dir.normalized()
					if dir.dot(push_dir) > 0.35:
						is_pushing = true
						pushed.emit()
						var push_motion: Vector3 = push_dir * push_speed * delta
						if collider.call("try_push", push_motion):
							move_and_collide(push_motion)
						break

	_update_anim_state(dir, is_pushing or is_pulling)
	sync_shader_world_pos()
	if drop_shadow != null:
		drop_shadow.update_shadow()


func _find_pull_target(move_dir: Vector3) -> Node3D:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return null
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.72
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.40, 0.0))
	query.collision_mask = 4
	query.exclude = [get_rid()]
	var hits: Array[Dictionary] = space_state.intersect_shape(query, 8)
	var best_body: Node3D = null
	var best_dist: float = INF
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		if not (collider is Node3D):
			continue
		if not (collider is PushableBlock or collider.has_method("try_pull") or collider.has_method("try_push")):
			continue
		var body: Node3D = collider as Node3D
		if absf(body.global_position.y - global_position.y) >= 0.65:
			continue
		var to_body_xz := Vector3(body.global_position.x - global_position.x, 0.0, body.global_position.z - global_position.z)
		var d_len: float = to_body_xz.length()
		if d_len < 0.05:
			continue
		if move_dir.dot(to_body_xz / d_len) < -0.25 and d_len < best_dist:
			best_dist = d_len
			best_body = body
	return best_body


func _update_anim_state(dir: Vector3, is_pushing: bool) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	var next_anim: StringName = &"idle"
	if not is_on_floor():
		next_anim = &"jump" if velocity.y > 0.0 else &"fall"
	elif is_pushing:
		next_anim = &"push"
	elif dir.length_squared() > 0.001 or horiz_speed > 0.35:
		next_anim = &"walk"
	elif _land_timer > 0.0:
		next_anim = &"land"

	if next_anim != current_anim_state:
		current_anim_state = next_anim
		if anim_player != null and anim_player.has_animation(next_anim):
			var blend_sec: float = 0.06 if (next_anim == &"jump" or next_anim == &"land") else 0.12
			anim_player.play(next_anim, blend_sec)

	if anim_player != null:
		if current_anim_state == &"walk":
			anim_player.speed_scale = clampf(horiz_speed / maxf(move_speed, 0.01), 0.35, 1.35)
		else:
			anim_player.speed_scale = 1.0


static func _apply_visual_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = layer_mask
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_apply_visual_layer_recursive(child, layer_mask)


func sync_shader_world_pos(use_interpolated: bool = false) -> void:
	var origin: Vector3 = get_global_transform_interpolated().origin if (use_interpolated and is_inside_tree()) else global_position
	RenderingServer.global_shader_parameter_set(&"player_world_pos", origin + Vector3(0.0, 0.75, 0.0))
	update_occluder_cutaways(origin)


func update_occluder_cutaways(world_origin: Vector3 = Vector3.INF) -> void:
	if not is_inside_tree():
		return

	var base_origin: Vector3 = global_position if world_origin == Vector3.INF else world_origin
	var cam_dir: Vector3 = Vector3(1.0, 1.0, 1.0).normalized()
	var cam_right: Vector3 = Vector3(0.70710678, 0.0, -0.70710678)
	if _camera_rig != null and is_instance_valid(_camera_rig):
		if _camera_rig.camera != null and is_instance_valid(_camera_rig.camera):
			cam_dir = _camera_rig.camera.global_transform.basis.z.normalized()
		cam_right = _camera_rig.get_camera_right_xz()

	var sample_origins: Array[Vector3] = [
		base_origin + Vector3(0.0, 0.30, 0.0),
		base_origin + Vector3(0.0, 0.75, 0.0),
		base_origin + Vector3(0.0, 1.20, 0.0),
		base_origin + Vector3(0.0, 0.75, 0.0) + cam_right * 0.20,
		base_origin + Vector3(0.0, 0.75, 0.0) - cam_right * 0.20
	]

	for occ: Node in get_tree().get_nodes_in_group("foreground_occluders"):
		if not (occ is Node3D) or not bool(occ.get_meta("cutaway", true)):
			continue
		var world_aabb: AABB = AABB()
		var has_aabb: bool = false
		var mesh_inst: MeshInstance3D = occ.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null:
			world_aabb = (mesh_inst.global_transform * mesh_inst.get_aabb()).grow(-0.01)
			has_aabb = true
		else:
			var col_node: CollisionShape3D = occ.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col_node != null and col_node.shape is BoxShape3D:
				var b_sz: Vector3 = (col_node.shape as BoxShape3D).size
				world_aabb = (col_node.global_transform * AABB(-b_sz * 0.5, b_sz)).grow(-0.01)
				has_aabb = true
		if not has_aabb:
			continue
		var occluded: bool = false
		for orig: Vector3 in sample_origins:
			if world_aabb.intersects_segment(orig, orig + cam_dir * 40.0) != null:
				occluded = true
				break
		var active_val: float = 1.0 if occluded else 0.0
		_set_cutaway_active_recursive(occ, active_val)
		occ.set_meta("cutaway_active", occluded)


const CUTAWAY_SHADER_PATH: String = "res://core/shaders/foreground_cutaway.gdshader"


static func _is_cutaway_material(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.resource_path == CUTAWAY_SHADER_PATH


## Returns a per-body private copy of a shared cutaway material (created lazily once) and applies the value.
static func _resolve_cutaway_material(mat: Material, active_val: float, mat_map: Dictionary) -> ShaderMaterial:
	if not _is_cutaway_material(mat):
		return null
	var target: ShaderMaterial = mat as ShaderMaterial
	if not target.has_meta(&"cutaway_private"):
		if mat_map.has(target):
			target = mat_map[target] as ShaderMaterial
		else:
			var dup: ShaderMaterial = target.duplicate() as ShaderMaterial
			dup.set_meta(&"cutaway_private", true)
			mat_map[target] = dup
			target = dup
	target.set_shader_parameter(&"cutaway_active", active_val)
	return target


static func _set_cutaway_active_recursive(node: Node, active_val: float, mat_map: Dictionary = {}) -> void:
	if node.name == "ShadowCaster":
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		var ov: ShaderMaterial = _resolve_cutaway_material(mi.material_override, active_val, mat_map)
		if ov != null:
			mi.material_override = ov
		if mi.mesh != null:
			if mi.mesh is BoxMesh:
				var bm: BoxMesh = mi.mesh as BoxMesh
				var bm_mat: ShaderMaterial = _resolve_cutaway_material(bm.material, active_val, mat_map)
				if bm_mat != null:
					bm.material = bm_mat
			for s_idx: int in range(mi.mesh.get_surface_count()):
				var sm: ShaderMaterial = _resolve_cutaway_material(mi.get_surface_override_material(s_idx), active_val, mat_map)
				if sm != null:
					mi.set_surface_override_material(s_idx, sm)
	for child: Node in node.get_children():
		_set_cutaway_active_recursive(child, active_val, mat_map)
