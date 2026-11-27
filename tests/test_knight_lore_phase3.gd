extends GutTest


func test_session_new_game_initialization_and_rating_formulas() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 42)

	assert_eq(sess.lives, 5, "New game must start with 5 lives")
	assert_eq(sess.day_count, 1)
	assert_false(sess.is_night)
	assert_false(sess.is_wulf)
	assert_eq(sess.required_sequence.size(), 14, "Cauldron sequence must require 14 charms")
	assert_eq(sess.world_items.size(), 32, "32 special items must populate across castle")
	assert_true([47, 68, 143, 179].has(sess.current_room_id), "Start room must be one of the 4 canonical rooms")
	assert_eq(sess.inventory, [-1, -1, -1])

	# Quest percentage & rating formula
	assert_eq(sess.get_quest_percent(), 1, "1 visited room / 156 = 1%")
	assert_eq(sess.get_rating_label(), "POOR")
	for r_i: int in range(65):
		sess.visited_rooms[r_i] = true
	assert_eq(sess.get_rating_label(), "FAIR")
	sess.quest_completed = true
	sess.charms_collected = 14
	assert_eq(sess.get_rating_label(), "GOOD")


func test_three_slot_inventory_fifo_rotation_displacement_and_extra_life() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 7, 47)

	# Inject 4 carryables and 1 Extra Life into Room 47 for deterministic rules check
	var base_idx: int = sess.world_items.size()
	for tid: int in [0, 1, 2, 3]:
		sess.world_items.append({
			"id": 500 + tid,
			"type_id": tid,
			"room_id": 47,
			"pos": Vector3(2.0 + float(tid), 0.0, 4.0),
			"active": true
		})
	sess.world_items.append({"id": 510, "type_id": 7, "room_id": 47, "pos": Vector3(5.0, 0.0, 5.0), "active": true})

	# Pick up 3 items into FIFO slots [0, 1, 2]
	var p0: Dictionary = sess.pickup_item(500, Vector3(3.0, 0.0, 3.0))
	assert_true(bool(p0.get("ok", false)))
	assert_eq(sess.inventory, [0, -1, -1])

	sess.pickup_item(501, Vector3(3.0, 0.0, 3.0))
	assert_eq(sess.inventory, [1, 0, -1])

	sess.pickup_item(502, Vector3(3.0, 0.0, 3.0))
	assert_eq(sess.inventory, [2, 1, 0])

	# Picking 4th item displaces slot 2 (type 0) onto the floor
	var p3: Dictionary = sess.pickup_item(503, Vector3(4.5, 0.0, 4.5))
	assert_eq(sess.inventory, [3, 2, 1])
	var disp: Dictionary = p3.get("displaced_item", {}) as Dictionary
	assert_false(disp.is_empty(), "4th pickup must displace oldest carried charm")
	assert_eq(int(disp.get("type_id", -1)), 0)

	# Clear room so room capacity allows drops, test headroom block vs drop + empty slot rotation
	sess.world_items[base_idx + 4]["active"] = false
	for e: Dictionary in sess.get_room_items(47):
		e["active"] = false

	var blocked: Dictionary = sess.drop_or_rotate(47, Vector3(4.0, 0.0, 4.0), false)
	assert_eq(str(blocked.get("action", "")), "blocked_headroom")
	assert_eq(sess.inventory, [3, 2, 1])

	var drop1: Dictionary = sess.drop_or_rotate(47, Vector3(4.0, 0.0, 4.0), true)
	assert_eq(str(drop1.get("action", "")), "dropped")
	assert_eq(int((drop1.get("dropped_item", {}) as Dictionary).get("type_id", -1)), 1)
	assert_eq(sess.inventory, [-1, 3, 2])

	# Drop slot occupied by 2 -> drops 2
	sess.drop_or_rotate(47, Vector3(4.5, 0.0, 4.0), true)
	assert_eq(sess.inventory, [-1, -1, 3])
	# Drop third item (3) -> now 3 items in Room 47
	sess.drop_or_rotate(47, Vector3(4.8, 0.0, 4.0), true)
	assert_eq(sess.inventory, [-1, -1, -1])

	# Add 4th item to room to hit room limit (max 4 carryables in standard rooms)
	sess.inventory = [-1, -1, 5]
	sess.drop_or_rotate(47, Vector3(5.0, 0.0, 4.0), true)
	sess.inventory = [-1, -1, 4]
	var full_res: Dictionary = sess.drop_or_rotate(47, Vector3(5.2, 0.0, 4.0), true)
	assert_eq(str(full_res.get("action", "")), "room_full", "Room max 4 special objects must block 5th drop")

	# Clear room and drop remaining charm, then verify empty-slot rotation
	for e: Dictionary in sess.get_room_items(47):
		e["active"] = false
	sess.inventory = [-1, -1, -1]
	sess.inventory = [6, -1, -1]
	var rot_res: Dictionary = sess.drop_or_rotate(47, Vector3(4.0, 0.0, 4.0), true)
	assert_eq(str(rot_res.get("action", "")), "rotated")
	assert_eq(sess.inventory, [-1, 6, -1], "Dropping empty slot must rotate queue")

	# Extra Life idol
	sess.world_items.append({"id": 610, "type_id": 7, "room_id": 47, "pos": Vector3(5.0, 0.0, 5.0), "active": true})
	sess.disable_spike_ball_drop = true
	assert_true(sess.collect_extra_life(610))
	assert_eq(sess.lives, 6)
	assert_false(sess.disable_spike_ball_drop)


func test_cauldron_sequence_victory_cycle_and_day_40_game_over() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 12, 136)

	var expected_first: int = sess.get_next_required_charm()
	var wrong_type: int = (expected_first + 1) % 7
	var rej: Dictionary = sess.resolve_cauldron_item(wrong_type)
	assert_false(bool(rej.get("accepted", true)))
	assert_eq(sess.charms_collected, 0)

	# Deliver all 14 in exact required order
	for i: int in range(14):
		var ctype: int = sess.get_next_required_charm()
		var acc: Dictionary = sess.resolve_cauldron_item(ctype)
		assert_true(bool(acc.get("accepted", false)))
		if i < 13:
			assert_false(sess.quest_completed)
		else:
			assert_true(sess.quest_completed, "14th correct charm must win the quest")

	# Sun/Moon transformation & Day 40 Game Over
	var sess2 := KnightLoreSession.new()
	sess2.start_new_game(kl, 99, 47)
	sess2.half_day_duration_sec = 10.0
	sess2.advance_cycle(10.5)
	assert_true(sess2.is_night)
	assert_true(sess2.pending_transform)
	assert_true(sess2.complete_transformation())
	assert_true(sess2.is_wulf)

	# Advance 39 full days -> reaches Day 40 -> Game Over
	for _d: int in range(39):
		sess2.advance_cycle(20.0)
	assert_eq(sess2.day_count, 40)
	assert_true(sess2.game_over, "Reaching Day 40 must trigger Game Over")


func test_player_rotational_mode_and_drop_climb_in_knight_lore_game() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(12, 0.5, 12)
	fc.shape = fb
	floor_body.position = Vector3(6, -0.25, 6)
	floor_body.add_child(fc)
	arena.add_child(floor_body)

	var p := PlayerController.new()
	p.enable_player_input = false
	p.set_rotational_mode(true)
	p.facing_cardinal = 3 # South (+Z)
	p.position = Vector3(6.0, 0.0, 6.0)
	arena.add_child(p)
	await wait_physics_frames(2)
	# Step once so Jolt settles is_on_floor() = true before testing grounded Rotational turning
	p.step_movement(Vector2.ZERO, false, 1.0 / 60.0)

	# Left rotates CCW from South (+Z) to East (+X)
	p.step_movement(Vector2(-1.0, 0.0), false, 1.0 / 60.0)
	assert_eq(p.facing_cardinal, 1, "Left turn from South must face East")
	# Hold Up walks forward along East (+X)
	var x_before: float = p.position.x
	for _f: int in range(6):
		p.step_movement(Vector2(0.0, -1.0), false, 1.0 / 60.0)
	assert_gt(p.position.x, x_before + 0.15, "Up in Rotational mode must walk forward in facing direction")
	p.queue_free()

	# Live KnightLoreGame drop-climb & Room 136 Human hint vs Wulf repel spell
	var prev_room: String = OS.get_environment("FILMATION_KL_ROOM")
	var prev_night: String = OS.get_environment("FILMATION_KL_FORCE_NIGHT")
	OS.set_environment("FILMATION_KL_ROOM", "136")
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", "0")

	var packed: PackedScene = ResourceLoader.load("res://game/knight_lore_game.tscn") as PackedScene
	assert_not_null(packed)
	var game: Node3D = packed.instantiate() as Node3D
	add_child_autofree(game)
	await wait_physics_frames(4)

	var sess: KnightLoreSession = game.get("session") as KnightLoreSession
	var hero: PlayerController = game.get("player") as PlayerController
	assert_not_null(sess)
	assert_not_null(hero)

	# Drop-climb puts item beneath hero and lifts hero onto it
	sess.inventory = [0, 1, 2]
	hero.position = Vector3(2.2, 0.0, 2.2)
	hero.force_update_transform()
	game.call("_handle_interact")
	await wait_physics_frames(4)
	assert_gte(hero.position.y, 0.60, "Drop-climb must lift hero onto dropped KlSpecialItem")

	# Human bubble hint in Room 136
	var fx_root: Node3D = game.get("_cauldron_fx_root") as Node3D
	game.call("_spawn_cauldron_hint_bubble")
	assert_gt(fx_root.get_child_count(), 0, "Human in Room 136 must spawn cauldron charm hint bubble")

	# Wulf spawns Repel Spell
	sess.is_wulf = true
	game.call("_spawn_repel_spell")
	var orbs: Array = game.get("_repel_orbs") as Array
	assert_eq(orbs.size(), 1, "Wulf in Room 136 must spawn Repel Spell")

	# Death decrements lives & triggers Game Over when exhausted
	sess.lives = 1
	var d1: Dictionary = sess.apply_player_death()
	assert_false(bool(d1.get("game_over", true)))
	assert_eq(sess.lives, 0)
	var d2: Dictionary = sess.apply_player_death()
	assert_true(bool(d2.get("game_over", false)))

	OS.set_environment("FILMATION_KL_ROOM", prev_room)
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", prev_night)
