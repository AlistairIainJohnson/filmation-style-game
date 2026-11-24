extends GutTest


func _create_floor_arena(width: float = 20.0) -> Node3D:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(width, 0.5, width)
	floor_col.shape = floor_box
	floor_body.position = Vector3(width * 0.5, -0.25, width * 0.5)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)
	return arena


func _make_push_block(eid: String, pos: Vector3) -> PushableBlock:
	var blk := PushableBlock.new()
	blk.entity_id = eid
	var mat := StandardMaterial3D.new()
	blk.setup_visual_and_collider(Vector3(0.98, 1.0, 0.98), mat)
	blk.position = pos
	return blk


func test_pushable_block_slides_and_snaps_to_half_grid() -> void:
	var arena: Node3D = _create_floor_arena()
	var blk: PushableBlock = _make_push_block("blk_1", Vector3(4.5, 0.0, 4.5))
	arena.add_child(blk)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.move_mode = PlayerController.MoveMode.ISO_AXIS_4_WAY
	player.position = Vector3(3.4, 0.0, 4.5)
	arena.add_child(player)

	await wait_physics_frames(4)
	for _i: int in range(18):
		player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
		await wait_physics_frames(1)

	assert_gt(blk.global_position.x, 4.7, "Player should push PushableBlock along +X")
	assert_almost_eq(blk.rotation_degrees.length(), 0.0, 0.01, "PushableBlock must never rotate")

	# Release input and let block snap smoothly to nearest 0.5m increment
	for _j: int in range(30):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)

	var snapped_x: float = snappedf(blk.global_position.x, 0.5)
	assert_lt(absf(blk.global_position.x - snapped_x), 0.02, "Released PushableBlock must snap to 0.5m half-grid")


func test_pushable_block_blocked_by_wall_no_clipping() -> void:
	var arena: Node3D = _create_floor_arena()
	var wall := StaticBody3D.new()
	var wall_col := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 3.0, 4.0)
	wall_col.shape = wall_box
	wall.position = Vector3(6.5, 1.5, 4.5)
	wall.add_child(wall_col)
	arena.add_child(wall)

	var blk: PushableBlock = _make_push_block("blk_wall", Vector3(5.5, 0.0, 4.5))
	arena.add_child(blk)
	await wait_physics_frames(4)

	var start_x: float = blk.global_position.x
	var pushed: bool = blk.try_push(Vector3(0.2, 0.0, 0.0))
	assert_false(pushed, "Blocked PushableBlock must refuse push into solid wall")
	assert_almost_eq(blk.global_position.x, start_x, 0.001)


func test_stacked_pushable_blocks_carry_together() -> void:
	var arena: Node3D = _create_floor_arena()
	var bottom: PushableBlock = _make_push_block("blk_bottom", Vector3(4.5, 0.0, 4.5))
	var top: PushableBlock = _make_push_block("blk_top", Vector3(4.5, 1.02, 4.5))
	arena.add_child(bottom)
	arena.add_child(top)

	await wait_physics_frames(8)
	assert_true(top.is_on_floor(), "Top PushableBlock must rest on bottom PushableBlock")
	assert_almost_eq(top.global_position.y, 1.0, 0.03)

	var top_start_x: float = top.global_position.x
	var bottom_start_x: float = bottom.global_position.x
	for _i: int in range(10):
		var ok: bool = bottom.try_push(Vector3(0.05, 0.0, 0.0))
		assert_true(ok, "Unobstructed stacked push should succeed")
		await wait_physics_frames(1)

	assert_gt(bottom.global_position.x, bottom_start_x + 0.4)
	assert_almost_eq(top.global_position.x, bottom.global_position.x, 0.05, "Top block must ride along with bottom block")
	assert_gt(top.global_position.x, top_start_x + 0.4)
	assert_almost_eq(top.global_position.y, 1.0, 0.04)


func test_player_climbs_two_block_staircase() -> void:
	var arena: Node3D = _create_floor_arena()
	var step1: PushableBlock = _make_push_block("step_1", Vector3(4.5, 0.0, 4.5))
	var step2_base: PushableBlock = _make_push_block("step_2a", Vector3(5.5, 0.0, 4.5))
	var step2_top: PushableBlock = _make_push_block("step_2b", Vector3(5.5, 1.02, 4.5))
	arena.add_child(step1)
	arena.add_child(step2_base)
	arena.add_child(step2_top)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.move_mode = PlayerController.MoveMode.ISO_AXIS_4_WAY
	player.position = Vector3(3.1, 0.0, 4.5)
	arena.add_child(player)

	await wait_physics_frames(8)
	# Jump onto step 1 (x=4.5, y=1.0)
	for tick: int in range(24):
		player.step_movement(Vector2(1.0, 0.0), tick == 0, 1.0 / 60.0)
		await wait_physics_frames(1)
	for _s: int in range(10):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, 1.0, 0.06, "Player should stand on 1-block step")

	# Jump onto step 2 (x=5.5, y=2.0)
	for tick: int in range(22):
		player.step_movement(Vector2(1.0, 0.0), tick == 0, 1.0 / 60.0)
		await wait_physics_frames(1)
	for _s: int in range(12):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, 2.0, 0.06, "Player should climb onto 2-block stack")


func test_pushing_block_onto_pressure_plate_opens_portcullis() -> void:
	var host := Node3D.new()
	add_child_autofree(host)

	var builder := RoomBuilder.new()
	var result: Dictionary = builder.build_room_from_path(host, "res://data/rooms/room_08_08.json")
	var entity_map: Dictionary = result.get("entity_map", {}) as Dictionary

	var chest := entity_map.get("chest_01") as PushableBlock
	var plate := entity_map.get("plate_01") as TriggerSwitch
	var gate := entity_map.get("gate_01") as Portcullis
	assert_not_null(chest)
	assert_not_null(plate)
	assert_not_null(gate)
	assert_false(gate.is_open, "Portcullis should start closed")

	await wait_physics_frames(4)
	# Position chest right next to plate_01 (4.5, 0, 3.5) and push it onto the plate
	chest.global_position = Vector3(3.35, 0.0, 3.5)
	await wait_physics_frames(2)
	for _i: int in range(24):
		chest.try_push(Vector3(0.05, 0.0, 0.0))
		await wait_physics_frames(1)
	await wait_physics_frames(45)

	assert_true(plate.is_pressed, "Pressure plate must activate when PushableBlock rests on it")
	assert_true(gate.is_open, "Linked Portcullis must open when pressure plate activates")
	assert_gt(gate.position.y, 1.5, "Portcullis must rise physically to clear doorway")


func test_moving_platform_carries_player_and_pushable_block() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var plat := MovingPlatform.new()
	plat.entity_id = "plat_01"
	plat.waypoints = [Vector3(0.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)]
	plat.move_speed = 3.0
	plat.pause_duration = 0.0
	plat.setup_visual_and_collider(Vector3(2.4, 0.35, 2.4), StandardMaterial3D.new())
	plat.position = Vector3(0.0, 0.0, 0.0)
	arena.add_child(plat)

	var player := PlayerController.new()
	player.enable_player_input = true
	player.position = Vector3(-0.4, 0.36, 0.0)
	arena.add_child(player)

	var blk := _make_push_block("plat_blk", Vector3(0.5, 0.36, 0.0))
	arena.add_child(blk)

	await wait_physics_frames(6)
	var p_start_x: float = player.global_position.x
	var b_start_x: float = blk.global_position.x

	await wait_physics_frames(30)

	assert_gt(plat.position.x, 1.0, "MovingPlatform should advance along waypoints")
	assert_gt(player.global_position.x, p_start_x + 0.8, "Player must ride MovingPlatform cleanly")
	assert_gt(blk.global_position.x, b_start_x + 0.8, "PushableBlock must ride MovingPlatform cleanly")


func test_collapsing_tile_drops_when_stepped_on() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var tile := CollapsingTile.new()
	tile.entity_id = "crumble_01"
	tile.collapse_delay = 0.10
	tile.setup_visual_and_collider(Vector3(1.2, 0.25, 1.2), StandardMaterial3D.new())
	tile.position = Vector3(2.0, 0.0, 2.0)
	arena.add_child(tile)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(2.0, 0.26, 2.0)
	arena.add_child(player)

	await wait_physics_frames(20)
	assert_true(tile.collapsed, "CollapsingTile must collapse shortly after player steps on it")


func test_collectible_item_and_patrol_hazard() -> void:
	var arena: Node3D = _create_floor_arena()

	var key := CollectibleItem.new()
	key.entity_id = "key_01"
	key.item_kind = "gold_key"
	key.setup_visual_and_collider(Vector3(0.42, 0.42, 0.42), StandardMaterial3D.new())
	key.position = Vector3(3.0, 0.0, 3.0)
	arena.add_child(key)

	var haz := PatrolHazard.new()
	haz.entity_id = "haz_01"
	haz.waypoints = [Vector3(6.0, 0.0, 3.0), Vector3(7.0, 0.0, 3.0)]
	haz.patrol_speed = 1.5
	haz.setup_visual_and_collider(Vector3(0.68, 1.4, 0.68), StandardMaterial3D.new())
	haz.position = Vector3(6.0, 0.0, 3.0)
	arena.add_child(haz)

	var hit_ids: Array[String] = []
	haz.player_hit.connect(func(hid: String, _p: Node3D) -> void: hit_ids.append(hid))

	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(3.0, 0.0, 3.0)
	arena.add_child(player)

	await wait_physics_frames(5)
	assert_true(key.is_collected, "Player overlapping CollectibleItem must collect it")

	player.global_position = haz.global_position
	player.force_update_transform()
	await wait_physics_frames(6)
	assert_gt(hit_ids.size(), 0, "PatrolHazard must emit player_hit when overlapping player")


func test_entity_serialization_roundtrip() -> void:
	var arena: Node3D = _create_floor_arena()
	var blk := _make_push_block("ser_blk", Vector3(2.5, 0.0, 4.0))
	arena.add_child(blk)

	var gate := Portcullis.new()
	gate.entity_id = "ser_gate"
	gate.setup_visual_and_collider(Vector3(1.9, 2.6, 0.24), StandardMaterial3D.new())
	gate.position = Vector3(6.0, 0.0, 0.0)
	arena.add_child(gate)
	gate.on_trigger_changed(true)

	await wait_physics_frames(2)
	var saved_blk: Dictionary = blk.serialize_state()
	var saved_gate: Dictionary = gate.serialize_state()

	blk.global_position = Vector3(9.0, 0.0, 9.0)
	gate.on_trigger_changed(false)

	blk.hydrate_state(saved_blk)
	gate.hydrate_state(saved_gate)
	assert_almost_eq(blk.global_position.x, 2.5, 0.01)
	assert_true(gate.is_open)
