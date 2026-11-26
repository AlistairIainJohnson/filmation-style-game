class_name KlHazardEntity
extends CharacterBody3D
## Config-driven Knight Lore dynamic hazard & enemy CharacterBody3D covering:
## falling_spike_ball, patrol_ew, patrol_ns, patrol_square_cw,
## vertical_bouncer, bouncing_ball_ai, random_diagonal, chase_player.

enum SpikeState { SUSPENDED, FALLING, LANDED }

signal stepped(pos: Vector3)

@export var entity_type_name: String = "guard_ew"
@export var simulation_active: bool = false
@export var ignore_walls: bool = false

var behavior: String = "patrol_ew"
var params: Dictionary = {}
var entity_size: Vector3 = Vector3(0.75, 1.5, 0.75)
var init_pos: Vector3 = Vector3.ZERO
var director: KlRoomDirector = null

var collision_shape: CollisionShape3D
var proxy_mesh: MeshInstance3D
var model_visual: Node3D = null
var anim_player: AnimationPlayer = null

var _floating: bool = false
var _patrol_sign: float = 1.0
var _patrol_dirs: Array[Vector3] = [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]
var _dir_idx: int = 0
var _turn_cooldown: float = 0.0
var _spike_state: SpikeState = SpikeState.SUSPENDED
var _bounce_rising: bool = true
var _diag_vel_xz: Vector2 = Vector2.ZERO
var _anim_phase: float = 0.0
var _target_yaw: float = 0.0
var _step_dist_acc: float = 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	floor_stop_on_slope = true
	floor_block_on_wall = true
	floor_snap_length = 0.12
	max_slides = 6
	safe_margin = 0.004


func configure(p_type_name: String, type_cfg: Dictionary, size: Vector3, start_pos: Vector3, p_ignore_walls: bool = false) -> void:
	entity_type_name = p_type_name
	behavior = str(type_cfg.get("behavior", "patrol_ew"))
	params = (type_cfg.get("params", {}) as Dictionary).duplicate(true)
	entity_size = size
	init_pos = start_pos
	position = start_pos
	ignore_walls = p_ignore_walls
	_floating = bool(params.get("floating", false))
	if behavior == "falling_spike_ball" or behavior == "random_diagonal" or behavior == "chase_player" or behavior == "vertical_bouncer":
		_floating = true
	if ignore_walls:
		collision_mask = 0
	else:
		collision_mask = 1 | 4

	set_meta("kl_type", p_type_name)
	set_meta("kl_behavior", behavior)
	set_meta("kl_lethal", true)
	if not is_in_group("kl_lethal_hazards"):
		add_to_group("kl_lethal_hazards")

	_spike_state = SpikeState.SUSPENDED
	_bounce_rising = true
	_patrol_sign = -1.0 if behavior == "patrol_ew" else 1.0
	_diag_vel_xz = Vector2.ZERO
	_dir_idx = 0
	_turn_cooldown = 0.0

	var dir_list: Array = params.get("directions", ["W", "N", "E", "S"]) as Array
	_patrol_dirs.clear()
	for d_v: Variant in dir_list:
		match str(d_v):
			"W":
				_patrol_dirs.append(Vector3(-1.0, 0.0, 0.0))
			"N":
				_patrol_dirs.append(Vector3(0.0, 0.0, -1.0))
			"E":
				_patrol_dirs.append(Vector3(1.0, 0.0, 0.0))
			"S":
				_patrol_dirs.append(Vector3(0.0, 0.0, 1.0))
	if _patrol_dirs.is_empty():
		_patrol_dirs = [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var cbox := BoxShape3D.new()
	cbox.size = entity_size
	collision_shape.shape = cbox
	collision_shape.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(collision_shape)

	proxy_mesh = MeshInstance3D.new()
	proxy_mesh.name = "Mesh"
	proxy_mesh.layers = 1
	proxy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	proxy_mesh.visible = false
	proxy_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pbox := BoxMesh.new()
	pbox.size = entity_size
	proxy_mesh.mesh = pbox
	proxy_mesh.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(proxy_mesh)


func attach_visual_support() -> void:
	model_visual = get_node_or_null("ModelVisual") as Node3D


func set_animation_player(ap: AnimationPlayer) -> void:
	anim_player = ap
	if anim_player != null and anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


func bind_director(p_director: KlRoomDirector) -> void:
	director = p_director
	attach_visual_support()
	if behavior == "random_diagonal" and _diag_vel_xz.length_squared() < 0.001:
		_pick_diagonal_velocity()


func _physics_process(delta: float) -> void:
	if not simulation_active or director == null:
		return

	_anim_phase += delta
	if _turn_cooldown > 0.0:
		_turn_cooldown = maxf(0.0, _turn_cooldown - delta)

	match behavior:
		"falling_spike_ball":
			_step_falling_spike_ball(delta)
		"patrol_ew":
			_step_linear_patrol(delta, Vector3.RIGHT)
		"patrol_ns":
			_step_linear_patrol(delta, Vector3(0.0, 0.0, -1.0))
		"patrol_square_cw":
			_step_square_patrol(delta)
		"vertical_bouncer":
			_step_vertical_bouncer(delta)
		"bouncing_ball_ai":
			_step_bouncing_ball_ai(delta)
		"random_diagonal":
			_step_random_diagonal(delta)
		"chase_player":
			_step_chase_player(delta)

	_update_visuals(delta)


func _gravity_mps2() -> float:
	var grav_u: float = absf(float((director.entities_cfg.get("simulation_constants", {}) as Dictionary).get("gravity_default", -1.0)))
	return director.kl_accel_to_mps2(grav_u)


func _step_falling_spike_ball(delta: float) -> void:
	match _spike_state:
		SpikeState.SUSPENDED:
			if director.is_spike_ball_drop_disabled():
				return
			if director.active_falling_spike_ball != null:
				return
			var prob: float = float(params.get("trigger_chance", 0.0625))
			if director.should_trigger_per_tick(prob, delta):
				director.active_falling_spike_ball = self
				_spike_state = SpikeState.FALLING
				velocity = Vector3.ZERO
		SpikeState.FALLING:
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y -= _gravity_mps2() * delta
			move_and_slide()
			if is_on_floor() or position.y <= 0.01:
				if position.y < 0.0:
					position.y = 0.0
				_spike_state = SpikeState.LANDED
				velocity = Vector3.ZERO
				if director.active_falling_spike_ball == self:
					director.active_falling_spike_ball = null
		SpikeState.LANDED:
			velocity = Vector3.ZERO


func _step_linear_patrol(delta: float, axis: Vector3) -> void:
	var spd: float = director.kl_speed_to_mps(float(params.get("speed", 2.0)))
	var move_vec: Vector3 = axis * (_patrol_sign * spd)
	velocity.x = move_vec.x
	velocity.z = move_vec.z
	if _floating:
		velocity.y = 0.0
	else:
		if not is_on_floor():
			velocity.y -= _gravity_mps2() * delta
		else:
			velocity.y = 0.0

	move_and_slide()
	var blocked: bool = _hit_horizontal_obstacle() or _out_of_room_x_or_z()
	if blocked and _turn_cooldown <= 0.0:
		_patrol_sign *= -1.0
		_turn_cooldown = 0.08
		_clamp_inside_room()


func _step_square_patrol(delta: float) -> void:
	var spd: float = director.kl_speed_to_mps(float(params.get("speed", 2.0)))
	var cur_dir: Vector3 = _patrol_dirs[_dir_idx % _patrol_dirs.size()]
	velocity.x = cur_dir.x * spd
	velocity.z = cur_dir.z * spd
	if not is_on_floor():
		velocity.y -= _gravity_mps2() * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	if (_hit_horizontal_obstacle() or _out_of_room_x_or_z()) and _turn_cooldown <= 0.0:
		_dir_idx = (_dir_idx + 1) % _patrol_dirs.size()
		_turn_cooldown = 0.08
		_clamp_inside_room()


func _step_vertical_bouncer(delta: float) -> void:
	var rise_dz_u: float = float(params.get("rise_dz", 3.0))
	var apex_off_m: float = director.kl_units_to_meters(float(params.get("apex_offset_z", 32.0)))
	var apex_y: float = init_pos.y + apex_off_m
	velocity.x = 0.0
	velocity.z = 0.0

	if _bounce_rising:
		velocity.y = director.kl_speed_to_mps(rise_dz_u)
		move_and_slide()
		if position.y >= apex_y or is_on_ceiling():
			position.y = minf(position.y, apex_y)
			_bounce_rising = false
			velocity.y = 0.0
	else:
		velocity.y -= _gravity_mps2() * delta
		move_and_slide()
		if is_on_floor() or position.y <= 0.01:
			if position.y < 0.0:
				position.y = 0.0
			_bounce_rising = true


func _step_bouncing_ball_ai(delta: float) -> void:
	velocity.y -= _gravity_mps2() * delta
	move_and_slide()

	for i: int in range(get_slide_collision_count()):
		var n: Vector3 = get_slide_collision(i).get_normal()
		if absf(n.y) < 0.35:
			if absf(n.x) >= absf(n.z):
				velocity.x = absf(velocity.x) * signf(n.x)
			else:
				velocity.z = absf(velocity.z) * signf(n.z)
	var mx: float = entity_size.x * 0.5 + 0.02
	var mz: float = entity_size.z * 0.5 + 0.02
	if position.x <= mx and velocity.x < 0.0:
		velocity.x = -velocity.x
	elif position.x >= director.room_dims.x - mx and velocity.x > 0.0:
		velocity.x = -velocity.x
	if position.z <= mz and velocity.z < 0.0:
		velocity.z = -velocity.z
	elif position.z >= director.room_dims.z - mz and velocity.z > 0.0:
		velocity.z = -velocity.z

	if is_on_floor() or (position.y <= 0.01 and velocity.y <= 0.0):
		if position.y < 0.0:
			position.y = 0.0
		var base_dz: int = int(params.get("base_bounce_dz", 4))
		var odd_extra: int = int(params.get("odd_room_extra_dz_max", 3))
		var dz_u: int = base_dz + (director.rng.randi_range(0, odd_extra) if director.is_odd_room else 0)
		velocity.y = director.kl_speed_to_mps(float(dz_u))

		var horiz_spd: float = director.kl_speed_to_mps(float(params.get("speed", 2.0)))
		var steer_dir: Vector3 = _compute_ball_steer_dir()
		if director.rng.randi() % 2 == 0:
			var sx: float = signf(steer_dir.x)
			if is_zero_approx(sx):
				sx = 1.0 if director.rng.randf() >= 0.5 else -1.0
			velocity.x = sx * horiz_spd
			velocity.z = 0.0
		else:
			var sz_sign: float = signf(steer_dir.z)
			if is_zero_approx(sz_sign):
				sz_sign = 1.0 if director.rng.randf() >= 0.5 else -1.0
			velocity.z = sz_sign * horiz_spd
			velocity.x = 0.0


func _compute_ball_steer_dir() -> Vector3:
	if director.player == null or not is_instance_valid(director.player):
		return Vector3.ZERO
	var diff: Vector3 = director.player.global_position - global_position
	diff.y = 0.0
	if not director.is_player_wulf():
		diff = -diff
	return diff


func _pick_diagonal_velocity() -> void:
	if director == null:
		return
	var choices: Array = params.get("speed_choices", [-4, -3, 3, 4]) as Array
	if choices.is_empty():
		choices = [-4, -3, 3, 4]
	var vx_u: float = float(choices[director.rng.randi_range(0, choices.size() - 1)])
	var vz_u: float = float(choices[director.rng.randi_range(0, choices.size() - 1)])
	_diag_vel_xz = Vector2(director.kl_speed_to_mps(vx_u), director.kl_speed_to_mps(vz_u))


func _step_random_diagonal(_delta: float) -> void:
	if _diag_vel_xz.length_squared() < 0.001:
		_pick_diagonal_velocity()
	velocity = Vector3(_diag_vel_xz.x, 0.0, _diag_vel_xz.y)
	move_and_slide()
	if (_hit_horizontal_obstacle() or _out_of_room_x_or_z()) and _turn_cooldown <= 0.0:
		_clamp_inside_room()
		_pick_diagonal_velocity()
		_turn_cooldown = 0.10


func _step_chase_player(delta: float) -> void:
	if director.player == null or not is_instance_valid(director.player):
		return
	var use_slow: bool = director.is_player_near_arch() and director.room_id != KnightLoreSession.CAULDRON_ROOM_ID
	var spd_u: float = float(params.get("near_arch_speed", 1.0)) if use_slow else float(params.get("speed", 4.0))
	var spd: float = director.kl_speed_to_mps(spd_u)
	var target: Vector3 = director.player.global_position
	var vx: float = 0.0
	var vz: float = 0.0
	if absf(target.x - position.x) > 0.06:
		vx = signf(target.x - position.x) * spd
	if absf(target.z - position.z) > 0.06:
		vz = signf(target.z - position.z) * spd
	velocity = Vector3(vx, 0.0, vz)
	if ignore_walls:
		global_position += velocity * delta
	else:
		move_and_slide()


func _hit_horizontal_obstacle() -> bool:
	for i: int in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var n: Vector3 = col.get_normal()
		if absf(n.y) < 0.35:
			return true
	return false


func _out_of_room_x_or_z() -> bool:
	var mx: float = entity_size.x * 0.5 + 0.03
	var mz: float = entity_size.z * 0.5 + 0.03
	return not director.is_inside_room_xz(position, mx, mz)


func _clamp_inside_room() -> void:
	var mx: float = entity_size.x * 0.5 + 0.04
	var mz: float = entity_size.z * 0.5 + 0.04
	position.x = clampf(position.x, mx, maxf(mx, director.room_dims.x - mx))
	position.z = clampf(position.z, mz, maxf(mz, director.room_dims.z - mz))


func _update_visuals(delta: float) -> void:
	var horiz := Vector2(velocity.x, velocity.z)
	var is_moving: bool = horiz.length() > 0.15
	if model_visual != null and is_instance_valid(model_visual):
		if is_moving:
			_target_yaw = atan2(velocity.x, velocity.z)
			model_visual.rotation.y = lerp_angle(model_visual.rotation.y, _target_yaw, 1.0 - exp(-14.0 * delta))
		if behavior == "patrol_ew" or behavior == "patrol_ns":
			if entity_type_name.begins_with("fire"):
				var f: float = 1.0 + 0.09 * sin(_anim_phase * 14.0)
				model_visual.scale.y = (entity_size.y / 0.80) * f
		elif behavior == "random_diagonal":
			model_visual.position.y = 0.06 * sin(_anim_phase * 5.0)
		elif behavior == "chase_player":
			model_visual.rotation.y += 4.5 * delta

	if anim_player != null:
		var want_anim: StringName = &"walk" if is_moving else &"idle"
		if anim_player.current_animation != want_anim and anim_player.has_animation(want_anim):
			anim_player.play(want_anim, 0.10)
		if is_moving:
			_step_dist_acc += horiz.length() * delta
			if _step_dist_acc >= 0.95:
				_step_dist_acc -= 0.95
				stepped.emit(global_position)
		else:
			_step_dist_acc = 0.0
