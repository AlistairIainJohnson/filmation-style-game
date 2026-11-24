extends GutTest


func after_each() -> void:
	for action_name: String in ["move_up", "move_down", "move_left", "move_right", "jump"]:
		if Input.is_action_pressed(action_name):
			var ev := InputEventAction.new()
			ev.action = action_name
			ev.pressed = false
			Input.parse_input_event(ev)


func _create_floor_and_block_arena() -> Node3D:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24.0, 0.5, 24.0)
	floor_col.shape = floor_box
	floor_body.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)

	var block_body := StaticBody3D.new()
	var block_col := CollisionShape3D.new()
	var block_box := BoxShape3D.new()
	block_box.size = Vector3(2.0, 1.0, 2.0)
	block_col.shape = block_box
	block_body.position = Vector3(3.0, 0.5, 0.0)
	block_body.add_child(block_col)
	arena.add_child(block_body)

	return arena


func test_analytical_jump_constants() -> void:
	var player := PlayerController.new()
	add_child_autofree(player)
	assert_almost_eq(player.jump_velocity, 9.643, 0.01)
	assert_almost_eq(player.gravity_up, 34.439, 0.01)
	assert_almost_eq(player.gravity_down, 55.785, 0.01)


func test_player_clears_and_lands_on_1m_block() -> void:
	var arena: Node3D = _create_floor_and_block_arena()
	var player := PlayerController.new()
	player.enable_player_input = false
	player.move_mode = PlayerController.MoveMode.ISO_AXIS_4_WAY
	player.position = Vector3(0.8, 0.0, 0.0)
	arena.add_child(player)

	await wait_physics_frames(3)
	for _i: int in range(4):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)
	assert_true(player.is_on_floor(), "Player should start grounded on floor")

	var max_y: float = player.global_position.y
	for tick: int in range(45):
		var jump_now: bool = (tick == 0)
		player.step_movement(Vector2(1.0, 0.0), jump_now, 1.0 / 60.0)
		max_y = maxf(max_y, player.global_position.y)
		await wait_physics_frames(1)

	assert_gte(max_y, 1.20, "Player jump arc must cleanly clear a 1.0 m block")
	assert_gte(player.global_position.x, 2.0, "Player should advance onto the 1.0 m block")
	assert_true(player.is_on_floor(), "Player should land cleanly on top of the 1.0 m block")
	assert_almost_eq(player.global_position.y, 1.0, 0.05, "Player feet must rest at y=1.0 on block")


func test_input_event_jump_headless() -> void:
	var arena: Node3D = _create_floor_and_block_arena()
	var player := PlayerController.new()
	player.enable_player_input = true
	player.position = Vector3(-2.0, 0.0, 0.0)
	arena.add_child(player)

	await wait_physics_frames(4)
	assert_true(player.is_on_floor())

	var press_ev := InputEventAction.new()
	press_ev.action = "jump"
	press_ev.pressed = true
	Input.parse_input_event(press_ev)

	await wait_physics_frames(2)
	assert_gt(player.velocity.y, 5.0, "InputEventAction jump must launch player upward in headless mode")


func test_coyote_time_allows_late_jump() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var ledge := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.5, 2.0)
	col.shape = box
	ledge.position = Vector3(0.0, -0.25, 0.0)
	ledge.add_child(col)
	arena.add_child(ledge)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.move_mode = PlayerController.MoveMode.ISO_AXIS_4_WAY
	player.position = Vector3(0.95, 0.0, 0.0)
	arena.add_child(player)

	await wait_physics_frames(3)
	player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
	await wait_physics_frames(1)
	assert_true(player.is_on_floor())

	# Step forward until just off the ledge (capsule radius 0.28 clears x=1.0 around x=1.30)
	for _i: int in range(10):
		player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
		await wait_physics_frames(1)
		if not player.is_on_floor():
			break
	# Advance 2 more airborne frames (~0.033s < 0.10s coyote_time)
	for _j: int in range(2):
		player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
		await wait_physics_frames(1)
	assert_false(player.is_on_floor(), "Player should have walked off ledge")

	player.step_movement(Vector2(1.0, 0.0), true, 1.0 / 60.0)
	assert_gt(player.velocity.y, 5.0, "Coyote time must permit jump shortly after leaving ledge")


func test_jump_buffer_fires_upon_landing() -> void:
	var arena: Node3D = _create_floor_and_block_arena()
	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(-3.0, 0.25, 0.0)
	arena.add_child(player)

	await wait_physics_frames(2)
	# Press jump while still descending above floor; buffer should trigger upon touchdown
	var triggered_bounce: bool = false
	for tick: int in range(20):
		player.step_movement(Vector2.ZERO, tick == 0, 1.0 / 60.0)
		await wait_physics_frames(1)
		if tick > 0 and player.velocity.y > 5.0:
			triggered_bounce = true
			break

	assert_true(triggered_bounce, "Jump input buffer must fire jump when touching down within 100ms")


func test_8way_and_4way_movement_directions() -> void:
	var rig := DioramaCameraRig.new()
	add_child_autofree(rig)
	rig.configure_for_room(Vector3(12.0, 6.0, 12.0), DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC, 0.10)

	var player := PlayerController.new()
	add_child_autofree(player)
	player.set_camera_rig(rig)

	player.set_move_mode(PlayerController.MoveMode.SCREEN_8_WAY)
	var dir_8way_up: Vector3 = player.compute_move_direction(Vector2(0.0, -1.0))
	assert_almost_eq(dir_8way_up.distance_to(rig.get_camera_forward_xz()), 0.0, 0.001)

	player.set_move_mode(PlayerController.MoveMode.ISO_AXIS_4_WAY)
	var dir_4way_up: Vector3 = player.compute_move_direction(Vector2(0.0, -1.0))
	var dir_4way_right: Vector3 = player.compute_move_direction(Vector2(1.0, 0.0))
	assert_almost_eq(dir_4way_up.distance_to(Vector3(0.0, 0.0, -1.0)), 0.0, 0.001)
	assert_almost_eq(dir_4way_right.distance_to(Vector3(1.0, 0.0, 0.0)), 0.0, 0.001)


func test_drop_shadow_tracks_height_and_hides_over_void() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var slab := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.5, 4.0)
	col.shape = box
	slab.position = Vector3(2.0, -0.25, 2.0)
	slab.add_child(col)
	arena.add_child(slab)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(2.0, 1.2, 2.0)
	arena.add_child(player)

	await wait_physics_frames(3)
	player.drop_shadow.update_shadow()
	assert_true(player.drop_shadow.decal.visible, "Drop shadow decal must be visible above floor")
	assert_eq(player.drop_shadow.decal.cull_mask, 1, "Drop shadow decal must exclude player visual layer 2")
	assert_almost_eq(player.drop_shadow.decal.global_position.y, 0.02, 0.03)
	assert_lt(player.drop_shadow.decal.modulate.a, player.drop_shadow.max_alpha)

	player.position = Vector3(12.0, 1.2, 12.0)
	await wait_physics_frames(1)
	player.drop_shadow.update_shadow()
	assert_false(player.drop_shadow.decal.visible, "Drop shadow decal must hide when over void")


func test_foreground_occluders_only_use_cutaway_shader() -> void:
	var room_paths: Array[String] = [
		"res://data/rooms/room_08_08.json",
		"res://data/rooms/room_09_08.json",
		"res://data/rooms/room_08_07.json",
		"res://data/rooms/room_09_07.json"
	]

	for room_path: String in room_paths:
		var host := Node3D.new()
		add_child_autofree(host)

		var builder := RoomBuilder.new()
		var result: Dictionary = builder.build_room_from_path(host, room_path)
		var fg_root: Node3D = result.get("foreground_root") as Node3D
		assert_gt(fg_root.get_child_count(), 0, room_path + " must have foreground occluders")

		for fg_child: Node in fg_root.get_children():
			var fg_mesh: MeshInstance3D = fg_child.get_node("Mesh") as MeshInstance3D
			var fg_box: BoxMesh = fg_mesh.mesh as BoxMesh
			assert_true(fg_box.material is ShaderMaterial, "%s %s must use cutaway ShaderMaterial" % [room_path, fg_child.name])
			var fg_shader_mat: ShaderMaterial = fg_box.material as ShaderMaterial
			var max_trans: float = float(fg_shader_mat.get_shader_parameter("max_cutaway_transparency"))
			assert_gt(max_trans, 0.0, "Cutaway transparency cap must allow dithering")
			assert_lt(max_trans, 1.0, "Cutaway transparency cap must leave foreground partially visible")
			assert_true(fg_child.is_in_group("foreground_occluders"), "%s %s must belong to foreground_occluders group" % [room_path, fg_child.name])
			_assert_cutaway_shadow_caster_valid(fg_child, "%s %s" % [room_path, fg_child.name])

		var arch_root: Node3D = result.get("architecture_root") as Node3D
		var pillar_count: int = 0
		for arch_child: Node in arch_root.get_children():
			if arch_child.name.contains("stone_pillar"):
				pillar_count += 1
				var p_mesh: MeshInstance3D = arch_child.get_node("Mesh") as MeshInstance3D
				var p_box: BoxMesh = p_mesh.mesh as BoxMesh
				assert_true(p_box.material is ShaderMaterial, "%s %s must use cutaway ShaderMaterial" % [room_path, arch_child.name])
				assert_true(arch_child.is_in_group("foreground_occluders"), "%s %s must belong to foreground_occluders group" % [room_path, arch_child.name])
				_assert_cutaway_shadow_caster_valid(arch_child, "%s %s" % [room_path, arch_child.name])

		assert_gt(pillar_count, 0, room_path + " must validate at least one interior stone_pillar")

		if room_path.ends_with("room_08_08.json"):
			for opaque_name: String in ["Block_00_stone_ledge", "Block_04_stone_plinth", "Wall_west"]:
				var opaque_node: Node = arch_root.get_node_or_null(opaque_name)
				assert_not_null(opaque_node, "Missing expected opaque node: " + opaque_name)
				var opaque_box: BoxMesh = (opaque_node.get_node("Mesh") as MeshInstance3D).mesh as BoxMesh
				assert_true(opaque_box.material is StandardMaterial3D, opaque_name + " must stay opaque StandardMaterial3D")
				assert_false(opaque_node.is_in_group("foreground_occluders"), opaque_name + " must NOT be in foreground_occluders")

		var tile: Node3D = arch_root.get_node("FloorTiles").get_child(0) as Node3D
		var tile_box: BoxMesh = (tile.get_node("Mesh") as MeshInstance3D).mesh as BoxMesh
		assert_true(tile_box.material is StandardMaterial3D, "Floor tiles must NOT use cutaway shader (protect Early-Z)")
		var floor_col: StaticBody3D = arch_root.get_node_or_null("FloorCollision") as StaticBody3D
		assert_not_null(floor_col, room_path + " must expose merged FloorCollision StaticBody3D")
		var merged_shapes: int = 0
		for fc: Node in floor_col.get_children():
			if fc is CollisionShape3D:
				merged_shapes += 1
		assert_gt(merged_shapes, 0)
		assert_lt(merged_shapes, 20, room_path + " floor colliders must be merged into few boxes")


func test_pillar_cutaway_activates_only_when_player_is_behind_pillar() -> void:
	var host := Node3D.new()
	add_child_autofree(host)

	var builder := RoomBuilder.new()
	var result: Dictionary = builder.build_room_from_path(host, "res://data/rooms/room_08_08.json")
	var rig: DioramaCameraRig = result.get("camera_rig") as DioramaCameraRig
	var fg_root: Node3D = result.get("foreground_root") as Node3D
	var arch_root: Node3D = result.get("architecture_root") as Node3D

	var corner_pillar: Node3D = fg_root.get_node("Foreground_00_arch_column") as Node3D
	var interior_pillar: Node3D = arch_root.get_node("Block_02_stone_pillar") as Node3D
	assert_not_null(corner_pillar)
	assert_not_null(interior_pillar)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.set_camera_rig(rig)
	host.add_child(player)

	# 1. Beside / in front of SE corner pillar (user-reported position): neither pillar should cut away
	player.position = Vector3(9.6, 0.0, 11.1)
	player.sync_shader_world_pos()
	assert_false(bool(corner_pillar.get_meta("cutaway_active", true)), "Corner pillar must stay opaque when player stands beside/in front at (9.6, 0, 11.1)")
	assert_false(bool(interior_pillar.get_meta("cutaway_active", true)))

	# 2. Directly in front of SE corner pillar
	player.position = Vector3(10.5, 0.0, 11.35)
	player.sync_shader_world_pos()
	assert_false(bool(corner_pillar.get_meta("cutaway_active", true)), "Corner pillar must stay opaque when player stands directly in front")
	assert_false(bool(interior_pillar.get_meta("cutaway_active", true)))

	# 3. Behind SE corner pillar: only corner pillar becomes transparent
	player.position = Vector3(9.5, 0.0, 9.5)
	player.sync_shader_world_pos()
	assert_true(bool(corner_pillar.get_meta("cutaway_active", false)), "Corner pillar must cut away when player is behind it")
	assert_false(bool(interior_pillar.get_meta("cutaway_active", true)))

	# 4. Directly in front of interior pillar [3, 0, 5]
	player.position = Vector3(3.5, 0.0, 6.35)
	player.sync_shader_world_pos()
	assert_false(bool(interior_pillar.get_meta("cutaway_active", true)), "Interior pillar must stay opaque when player stands directly in front")
	assert_false(bool(corner_pillar.get_meta("cutaway_active", true)))

	# 5. Behind interior pillar [3, 0, 5]: only interior pillar becomes transparent
	player.position = Vector3(2.5, 0.0, 4.5)
	player.sync_shader_world_pos()
	assert_true(bool(interior_pillar.get_meta("cutaway_active", false)), "Interior pillar must cut away when player is behind it")
	assert_false(bool(corner_pillar.get_meta("cutaway_active", true)))


func _assert_cutaway_shadow_caster_valid(occ: Node, label: String) -> void:
	var caster: Node = occ.get_node_or_null("ShadowCaster")
	assert_not_null(caster, label + " must have dedicated opaque ShadowCaster child")
	var caster_meshes: int = 0
	for child: Node in caster.get_children():
		if child is MeshInstance3D:
			caster_meshes += 1
			var mi: MeshInstance3D = child as MeshInstance3D
			assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, label + " ShadowCaster mesh must be shadows-only")
			assert_true(mi.material_override is StandardMaterial3D, label + " ShadowCaster mesh must use opaque StandardMaterial3D")
	assert_gt(caster_meshes, 0, label + " ShadowCaster must contain at least one MeshInstance3D")

	var pillar_model: Node = occ.get_node_or_null("PillarModel")
	if pillar_model != null:
		var visual_meshes: Array[MeshInstance3D] = []
		RoomBuilder._collect_mesh_instances_recursive(pillar_model, visual_meshes)
		assert_gt(visual_meshes.size(), 0, label + " PillarModel must contain visual MeshInstance3D nodes")
		for mi: MeshInstance3D in visual_meshes:
			assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, label + " visual PillarModel must not cast shadow")


func test_smooth_movement_physics_interpolation_and_animation_blending() -> void:
	assert_true(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)), "3D physics interpolation must be enabled in project.godot")

	var arena: Node3D = _create_floor_and_block_arena()
	var player := PlayerController.new()
	player.enable_player_input = false
	player.move_mode = PlayerController.MoveMode.ISO_AXIS_4_WAY
	player.position = Vector3(-4.0, 0.0, 0.0)
	arena.add_child(player)

	await wait_physics_frames(3)
	player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
	await wait_physics_frames(1)

	# 1. Acceleration ramp: 1 tick produces partial speed, ~8 ticks reaches full speed
	player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
	var first_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_gt(first_speed, 0.1, "Acceleration ramp must start moving on first tick")
	assert_lt(first_speed, player.move_speed, "Acceleration ramp must not snap to full speed in 1 tick")

	for _i: int in range(8):
		player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
	var cruise_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_almost_eq(cruise_speed, player.move_speed, 0.05, "Player must reach move_speed within ~8 ticks")

	# 2. Smooth 180-degree facing turn (exponential damping rather than 1-tick snap)
	var yaw_before: float = player.visual_root.rotation.y
	player.step_movement(Vector2(-1.0, 0.0), false, 1.0 / 60.0)
	var yaw_after_1: float = player.visual_root.rotation.y
	var target_reverse_yaw: float = atan2(1.0, 0.0)
	assert_gt(absf(angle_difference(yaw_after_1, target_reverse_yaw)), 0.5, "180-degree turn must damp over multiple ticks instead of snapping")
	for _i: int in range(25):
		player.step_movement(Vector2(-1.0, 0.0), false, 1.0 / 60.0)
	assert_lt(absf(angle_difference(player.visual_root.rotation.y, target_reverse_yaw)), 0.05, "Facing yaw must converge smoothly")
	assert_ne(yaw_before, player.visual_root.rotation.y)

	# 3. Diagonal release debounce preserves diagonal heading across a 1-tick partial key release
	player.set_move_mode(PlayerController.MoveMode.SCREEN_8_WAY)
	var expected_diag_dir: Vector3 = player.compute_move_direction(Vector2(1.0, 1.0))
	var diag_target: float = atan2(-expected_diag_dir.x, -expected_diag_dir.z)
	for _i: int in range(25):
		player.step_movement(Vector2(1.0, 1.0), false, 1.0 / 60.0)
	var diag_yaw: float = player.visual_root.rotation.y
	player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
	assert_lt(absf(angle_difference(player.visual_root.rotation.y, diag_target)), 0.05, "Single-tick diagonal release must keep diagonal heading")
	assert_lt(absf(angle_difference(player.visual_root.rotation.y, diag_yaw)), 0.05)

	# 4. Touchdown triggers 'land' clip when horizontally settled
	player.velocity = Vector3.ZERO
	player.position = Vector3(-4.0, 0.5, 0.0)
	player.reset_physics_interpolation()
	await wait_physics_frames(2)
	var saw_land: bool = false
	for _i: int in range(25):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)
		if player.current_anim_state == &"land":
			saw_land = true
			break
	assert_true(saw_land, "Landing after airborne descent must play the 'land' animation state")
