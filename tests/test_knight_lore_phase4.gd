extends GutTest


func _make_room_arena(room_dims: Vector3 = Vector3(8.0, 6.0, 8.0)) -> Dictionary:
	var root := Node3D.new()
	add_child_autofree(root)

	var arch := Node3D.new()
	arch.name = "Architecture"
	root.add_child(arch)

	var ent := Node3D.new()
	ent.name = "Entities"
	root.add_child(ent)

	var doorways := Node3D.new()
	doorways.name = "Doorways"
	root.add_child(doorways)

	# Floor
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.position = Vector3(room_dims.x * 0.5, -0.25, room_dims.z * 0.5)
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(room_dims.x, 0.5, room_dims.z)
	fcol.shape = fbox
	floor_body.add_child(fcol)
	arch.add_child(floor_body)

	# 4 walls
	var wall_specs: Array = [
		[Vector3(room_dims.x * 0.5, 3.0, -0.25), Vector3(room_dims.x, 6.0, 0.5)],
		[Vector3(room_dims.x * 0.5, 3.0, room_dims.z + 0.25), Vector3(room_dims.x, 6.0, 0.5)],
		[Vector3(-0.25, 3.0, room_dims.z * 0.5), Vector3(0.5, 6.0, room_dims.z)],
		[Vector3(room_dims.x + 0.25, 3.0, room_dims.z * 0.5), Vector3(0.5, 6.0, room_dims.z)]
	]
	for ws: Array in wall_specs:
		var wb := StaticBody3D.new()
		wb.collision_layer = 1
		wb.position = ws[0] as Vector3
		var wc := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = ws[1] as Vector3
		wc.shape = wbox
		wb.add_child(wc)
		arch.add_child(wb)

	return {"root": root, "arch": arch, "ent": ent, "doorways": doorways}


func test_pushables_chest_slides_while_table_and_moveable_block_stop() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var chest := KlPushableEntity.new()
	chest.configure("chest", fg_types["6"] as Dictionary, Vector3(1.125, 0.75, 0.75), Vector3(1.5, 0.0, 2.0))
	ent.add_child(chest)

	var table := KlPushableEntity.new()
	table.configure("table", fg_types["7"] as Dictionary, Vector3(0.75, 0.75, 1.25), Vector3(1.5, 0.0, 4.0))
	ent.add_child(table)

	var mblk := KlPushableEntity.new()
	mblk.configure("moveable_block", fg_types["16"] as Dictionary, Vector3(1.0, 0.75, 1.0), Vector3(1.5, 0.0, 6.0))
	ent.add_child(mblk)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 1, 46)
	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(46, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, null, kl.entities_cfg, 123)

	await wait_physics_frames(2)
	assert_true(chest.try_push(Vector3(0.08, 0.0, 0.0)))
	assert_true(table.try_push(Vector3(0.08, 0.0, 0.0)))
	assert_true(mblk.try_push(Vector3(0.08, 0.0, 0.0)))

	await wait_physics_frames(40)
	assert_gt(chest.position.x, 2.4, "chest (clears_velocity=false) must keep sliding until blocked")
	assert_almost_eq(table.position.x, 1.58, 0.03, "table (clears_velocity=true) must stop when push ends")
	assert_almost_eq(mblk.position.x, 1.58, 0.03, "moveable_block (clears_velocity=true) must stop when push ends")


func test_dynamic_blocks_moving_dropping_and_collapsing() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var blk_ew := KlDynamicBlock.new()
	blk_ew.configure("block_ew", fg_types["14"] as Dictionary, Vector3(1.0, 0.75, 1.0), Vector3(2.0, 1.0, 2.0), 0)
	ent.add_child(blk_ew)

	var blk_ns := KlDynamicBlock.new()
	blk_ns.configure("block_ns", fg_types["15"] as Dictionary, Vector3(1.0, 0.75, 1.0), Vector3(5.0, 1.0, 5.0), 0)
	ent.add_child(blk_ns)

	var drop_blk := KlDynamicBlock.new()
	drop_blk.configure("dropping_block", fg_types["21"] as Dictionary, Vector3(1.0, 0.75, 1.0), Vector3(4.0, 2.0, 2.0), 0)
	ent.add_child(drop_blk)

	var col_blk := KlDynamicBlock.new()
	col_blk.configure("collapsing_block", fg_types["22"] as Dictionary, Vector3(1.0, 0.75, 1.0), Vector3(6.0, 1.0, 2.0), 0)
	ent.add_child(col_blk)

	var hero := PlayerController.new()
	hero.enable_player_input = true
	hero.input_locked = true
	hero.position = Vector3(2.0, 1.75, 2.0)
	root.add_child(hero)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 2, 46)
	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(46, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, hero, kl.entities_cfg, 10)

	await wait_physics_frames(22)
	assert_gt(blk_ew.position.x, 2.15, "block_ew must oscillate East along X")
	assert_lt(blk_ns.position.z, 4.85, "block_ns must oscillate North along -Z")
	assert_gt(hero.position.x, 2.10, "block_ew AnimatableBody3D must carry standing player")
	assert_almost_eq(drop_blk.position.y, 2.0, 0.02, "dropping_block must remain fixed until stood upon")

	# Step onto dropping_block
	hero.position = Vector3(4.0, 2.75, 2.0)
	hero.velocity = Vector3.ZERO
	await wait_physics_frames(20)
	assert_lt(drop_blk.position.y, 1.85, "dropping_block must descend while player stands on it")

	# Step onto collapsing_block -> must trigger KlSparkleVfx and vanish
	hero.position = Vector3(6.0, 1.75, 2.0)
	hero.velocity = Vector3.ZERO
	await wait_physics_frames(6)
	var found_sparkle: bool = false
	for ch: Node in ent.get_children():
		if ch is KlSparkleVfx:
			found_sparkle = true
			break
	assert_true(found_sparkle, "collapsing_block must spawn collapse KlSparkleVfx on trigger")
	assert_true(not is_instance_valid(col_blk) or col_blk.is_queued_for_deletion(), "collapsing_block must vanish after trigger")


func test_falling_spike_ball_odd_room_latch_and_mutex() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var high_cfg: Dictionary = (fg_types["19"] as Dictionary).duplicate(true)
	(high_cfg["params"] as Dictionary)["trigger_chance"] = 1.0

	var sb1 := KlHazardEntity.new()
	sb1.configure("spike_ball_high_fall", high_cfg, Vector3(0.75, 0.75, 0.75), Vector3(2.5, 2.5, 2.5))
	ent.add_child(sb1)

	var sb2 := KlHazardEntity.new()
	sb2.configure("spike_ball_high_fall", high_cfg, Vector3(0.75, 0.75, 0.75), Vector3(5.5, 2.5, 2.5))
	ent.add_child(sb2)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 3, 79)
	assert_false(sess.disable_spike_ball_drop, "Odd rooms such as Room 79 must not block falling spike balls")

	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(79, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, null, kl.entities_cfg, 55)

	# One falling spike ball at a time (mutex)
	await wait_physics_frames(5)
	assert_not_null(director.active_falling_spike_ball, "Room 79 must allow first spike ball to drop immediately")
	assert_lt(sb1.position.y, 2.49, "First spike ball must begin falling")
	assert_almost_eq(sb2.position.y, 2.5, 0.01, "Second spike ball must wait while first is falling")

	await wait_physics_frames(45)
	assert_almost_eq(sb1.position.y, 0.0, 0.08, "First spike ball must land on floor")
	assert_lt(sb2.position.y, 2.49, "Second spike ball may fall once first has landed")


func test_patrol_bouncer_ghost_and_repel_spell_behaviors() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var bg_specs: Dictionary = kl.entities_cfg.get("special_background_entities", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var hero := PlayerController.new()
	hero.enable_player_input = false
	hero.input_locked = true
	hero.position = Vector3(6.5, 0.0, 4.0)
	root.add_child(hero)

	var guard := KlHazardEntity.new()
	guard.configure("guard_square", fg_types["13"] as Dictionary, Vector3(0.75, 1.5, 0.75), Vector3(0.85, 0.0, 6.0))
	ent.add_child(guard)

	var wizard := KlHazardEntity.new()
	wizard.configure("wizard", bg_specs["wizard"] as Dictionary, Vector3(0.625, 1.5, 0.625), Vector3(0.80, 0.0, 2.0))
	(arena["arch"] as Node3D).add_child(wizard)

	var ball_ud := KlHazardEntity.new()
	ball_ud.configure("ball_ud", fg_types["24"] as Dictionary, Vector3(0.875, 0.75, 0.875), Vector3(4.0, 0.0, 1.5))
	ent.add_child(ball_ud)

	var ghost := KlHazardEntity.new()
	ghost.configure("ghost", fg_types["9"] as Dictionary, Vector3(0.75, 0.75, 0.75), Vector3(4.0, 0.0, 4.0))
	ent.add_child(ghost)

	var repel := KlHazardEntity.new()
	repel.configure("repel_spell", fg_types["25"] as Dictionary, Vector3(0.625, 0.75, 0.625), Vector3(4.0, 0.4, 4.0), true)
	ent.add_child(repel)

	var ball_ai := KlHazardEntity.new()
	ball_ai.configure("ball_bounce", fg_types["23"] as Dictionary, Vector3(0.875, 0.75, 0.875), Vector3(4.0, 0.02, 5.5))
	ent.add_child(ball_ai)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 5, 46)
	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(46, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, hero, kl.entities_cfg, 77)

	# Steer check for bouncing_ball_ai: away from Human, toward Wulf
	sess.is_wulf = false
	var steer_human: Vector3 = ball_ai.call("_compute_ball_steer_dir") as Vector3
	assert_lt(steer_human.x, 0.0, "ball_bounce must steer away from Human player")
	sess.is_wulf = true
	var steer_wulf: Vector3 = ball_ai.call("_compute_ball_steer_dir") as Vector3
	assert_gt(steer_wulf.x, 0.0, "ball_bounce must steer toward Wulf player")

	await wait_physics_frames(20)
	assert_gt(ball_ud.position.y, 0.5, "vertical_bouncer must rise upward toward init_y + 2.0m")
	assert_ne(ghost.velocity.x, 0.0, "ghost must pick non-zero diagonal X speed")
	assert_ne(ghost.velocity.z, 0.0, "ghost must pick non-zero diagonal Z speed")

	# Near West wall: guard_square and wizard walk West then rotate CW to North (-Z)
	await wait_physics_frames(20)
	assert_lt(guard.position.z, 5.95, "guard_square hitting West boundary must turn CW to North (-Z)")
	assert_lt(wizard.position.z, 1.95, "wizard hitting West boundary must turn CW to North (-Z)")

	# Repel spell speed slows near arch outside room 136
	hero.position = Vector3(4.0, 0.0, 4.0)
	assert_false(director.is_player_near_arch())
	hero.position = Vector3(0.2, 0.0, 4.0)
	assert_true(director.is_player_near_arch())


func test_portcullis_mutex_fast_drops_and_dropping_only_lethality() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var g1 := KlPortcullisGate.new()
	g1.configure("gate_ud_1", fg_types["26"] as Dictionary, Vector3(1.5, 2.0, 0.125), Vector3(2.5, 2.0, 3.0))
	ent.add_child(g1)

	var g2 := KlPortcullisGate.new()
	g2.configure("gate_ud_1", fg_types["26"] as Dictionary, Vector3(1.5, 2.0, 0.125), Vector3(5.5, 2.0, 3.0))
	ent.add_child(g2)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 8, 63)
	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(63, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, null, kl.entities_cfg, 9)

	await wait_physics_frames(3)
	assert_eq(g1.gate_state, KlPortcullisGate.GateState.DROPPING, "First portcullis must immediately perform initial fast drop")
	assert_true(g1.is_in_group("kl_lethal_hazards"), "Dropping portcullis must be lethal")
	assert_eq(g2.gate_state, KlPortcullisGate.GateState.RAISED, "Second portcullis must wait (one moves at a time)")
	assert_false(g2.is_in_group("kl_lethal_hazards"), "Stationary raised portcullis must not be lethal")

	await wait_physics_frames(55)
	assert_eq(g1.gate_state, KlPortcullisGate.GateState.LOWERED, "First portcullis must finish dropping to floor")
	assert_false(g1.is_in_group("kl_lethal_hazards"), "Lowered portcullis must cease being lethal")
	assert_ne(g2.gate_state, KlPortcullisGate.GateState.RAISED, "Second portcullis must perform fast drop once first lands")


func test_sparkle_vfx_and_room_136_victory_convergence() -> void:
	var prev_room: String = OS.get_environment("FILMATION_KL_ROOM")
	var prev_night: String = OS.get_environment("FILMATION_KL_FORCE_NIGHT")
	OS.set_environment("FILMATION_KL_ROOM", "136")
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", "0")

	var packed: PackedScene = ResourceLoader.load("res://game/knight_lore_game.tscn") as PackedScene
	assert_not_null(packed)
	var game: Node3D = packed.instantiate() as Node3D
	add_child_autofree(game)
	await wait_physics_frames(4)

	var director: KlRoomDirector = game.get("room_director") as KlRoomDirector
	assert_not_null(director, "KnightLoreGame must activate KlRoomDirector on room load")
	var build: Dictionary = game.get("current_build") as Dictionary
	var wiz: KlHazardEntity = (build.get("architecture_root") as Node3D).get_node_or_null("MelkhiorWizard") as KlHazardEntity
	assert_not_null(wiz, "MelkhiorWizard must use KlHazardEntity")
	assert_true(wiz.simulation_active, "MelkhiorWizard must be active in KnightLoreGame")

	var sess: KnightLoreSession = game.get("session") as KnightLoreSession
	sess.charms_collected = 13
	var last_charm: int = sess.get_next_required_charm()
	var res: Dictionary = sess.resolve_cauldron_item(last_charm)
	assert_true(bool(res.get("victory", false)))
	assert_true(bool(game.get("_victory_sequence_active")), "14/14 charms in Room 136 must initiate victory sparkle convergence")
	var v_sparkles: Array = game.get("_victory_sparkles") as Array
	assert_gt(v_sparkles.size(), 0, "Victory sequence must spawn rising convergence sparkles")

	# Wait for sparkles to converge on hero and open Victory end screen (max 190 frames ~ 3.1s)
	for _i: int in range(190):
		await wait_physics_frames(1)
		if not bool(game.get("_victory_sequence_active")):
			break
	assert_false(bool(game.get("_victory_sequence_active")), "Victory sparkles must converge cleanly and finish victory sequence")
	var hud: KnightLoreHud = game.get("hud") as KnightLoreHud
	var end_panel: Control = hud.get("_end_overlay") as Control
	assert_true(end_panel != null and end_panel.visible, "HUD Victory screen must be visible after sparkle convergence")

	OS.set_environment("FILMATION_KL_ROOM", prev_room)
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", prev_night)


func test_player_pull_moves_pushables_backwards_without_sliding_away() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var fg_types: Dictionary = kl.entities_cfg.get("foreground_types", {}) as Dictionary
	var arena: Dictionary = _make_room_arena()
	var root: Node3D = arena["root"] as Node3D
	var ent: Node3D = arena["ent"] as Node3D

	var table := KlPushableEntity.new()
	table.configure("table", fg_types["7"] as Dictionary, Vector3(0.75, 0.75, 1.25), Vector3(3.0, 0.0, 2.5))
	ent.add_child(table)

	var chest := KlPushableEntity.new()
	chest.configure("chest", fg_types["6"] as Dictionary, Vector3(1.125, 0.75, 0.75), Vector3(3.0, 0.0, 5.5))
	ent.add_child(chest)

	var hero := PlayerController.new()
	hero.enable_player_input = false
	hero.set_move_mode(PlayerController.MoveMode.ISO_AXIS_4_WAY)
	hero.position = Vector3(3.70, 0.0, 2.5)
	root.add_child(hero)

	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 11, 46)
	var director := KlRoomDirector.new()
	root.add_child(director)
	director.activate_room(46, Vector3(8, 6, 8), arena["arch"] as Node3D, ent, arena["doorways"] as Node3D, sess, hero, kl.entities_cfg, 33)

	await wait_physics_frames(3)
	var tbl_start_x: float = table.position.x
	for _i: int in range(12):
		hero.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0, false, true)
		await wait_physics_frames(1)
	assert_gt(table.position.x, tbl_start_x + 0.18, "Shift+Move away from table must pull table along with player")

	# Pull sliding chest and verify releasing stops it without launching forward
	hero.position = Vector3(3.85, 0.0, 5.5)
	hero.velocity = Vector3.ZERO
	await wait_physics_frames(2)
	var ch_start_x: float = chest.position.x
	for _i: int in range(10):
		hero.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0, false, true)
		await wait_physics_frames(1)
	var ch_after_pull_x: float = chest.position.x
	assert_gt(ch_after_pull_x, ch_start_x + 0.15, "Pulling chest must drag chest with player")
	await wait_physics_frames(10)
	assert_almost_eq(chest.position.x, ch_after_pull_x, 0.02, "Pulled chest must stop cleanly on release instead of sliding away")


func test_tight_cylindrical_hazard_core_prevents_diagonal_corner_deaths() -> void:
	const KLGameScript: Script = preload("res://game/knight_lore_game.gd")
	var haz_center := Vector3(4.0, 0.33, 4.0)
	var haz_box_size := Vector3(0.57, 0.66, 0.57) # Scaled static spike collider (0.76 * 0.75)

	# Diagonal corner graze outside core cylinder should be safe
	var diag_graze := Vector3(4.36, 0.0, 4.36)
	assert_false(bool(KLGameScript.call("is_player_in_hazard_core", diag_graze, haz_center, haz_box_size)), "Diagonal corner graze must not falsely trigger lethal trap")

	# Direct overlap inside core must kill
	var direct_hit := Vector3(4.20, 0.0, 4.0)
	assert_true(bool(KLGameScript.call("is_player_in_hazard_core", direct_hit, haz_center, haz_box_size)), "Stepping into trap core must trigger lethal hit")

	# Jumping cleanly over trap must be safe
	var jumped_over := Vector3(4.0, 0.72, 4.0)
	assert_false(bool(KLGameScript.call("is_player_in_hazard_core", jumped_over, haz_center, haz_box_size)), "Jumping over low trap must clear vertical lethal span")


func test_day_night_dial_updates_in_hud() -> void:
	var hud := KnightLoreHud.new()
	add_child_autofree(hud)
	var dial: Control = hud.get("_day_night_dial") as Control
	assert_not_null(dial, "KnightLoreHud must construct visible DayNightDial widget")
	hud.update_status(136, false, 3, true, true, 0.85, 5, 4, false)
	assert_true(bool(dial.get("is_night")), "DayNightDial must reflect Night phase")
	assert_almost_eq(float(dial.get("progress")), 0.85, 0.001, "DayNightDial must track cycle progress")


func test_static_spikes_are_non_solid_and_kill_when_landed_on() -> void:
	const KLGameScript: Script = preload("res://game/knight_lore_game.gd")
	var env := Node3D.new()
	add_child_autofree(env)

	var rb := RoomBuilder.new()
	rb._build_kl_floor(env, 8, 8, 0.5, rb.get_material("stone_floor"))
	var sz := Vector3(0.75, 0.75, 0.75)
	var spike: StaticBody3D = rb._spawn_kl_hazard_prop(env, "TestSpikes", "spike", Vector3(4.0, 0.0, 4.0), sz)
	assert_eq(spike.collision_layer, 0, "Static spikes must be non-solid so player cannot stand on top of them")
	assert_true(spike.is_in_group("kl_lethal_hazards"), "Static spikes must belong to kl_lethal_hazards")

	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(4.0, 1.0, 4.0)
	env.add_child(player)

	for _f: int in range(45):
		player.step_movement(Vector2.ZERO, false, 1.0 / 60.0)
		await wait_physics_frames(1)

	assert_lt(player.position.y, 0.20, "Player falling onto spikes must drop through to the floor instead of standing atop collider")
	var col_shape: CollisionShape3D = spike.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(col_shape)
	var bsz: Vector3 = (col_shape.shape as BoxShape3D).size
	assert_true(bool(KLGameScript.call("is_player_in_hazard_core", player.global_position, col_shape.global_position, bsz)), "Landing on static spikes must overlap lethal hazard core")


func test_hud_scrolls_align_to_projected_room_and_scale() -> void:
	var scene := Node3D.new()
	add_child_autofree(scene)
	var rig := DioramaCameraRig.new()
	scene.add_child(rig)
	rig.configure_for_room(Vector3(8.0, 6.0, 8.0), DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC, 0.12)

	var hud := KnightLoreHud.new()
	scene.add_child(hud)
	hud.bind_room_camera(rig.camera, Vector3(8.0, 6.0, 8.0), 0.5)
	hud.refresh_scroll_layout()

	var left_host: Control = hud.get("_left_scroll_host") as Control
	var right_host: Control = hud.get("_right_scroll_host") as Control
	var left_wing: Control = hud.get("_left_wing") as Control
	var left_content: Control = hud.get("_left_content") as Control
	assert_not_null(left_host)
	assert_not_null(right_host)
	assert_lt(left_host.position.x + left_host.size.x, right_host.position.x, "Left and right scrolls must leave center notch clear")

	var vp_sz: Vector2 = hud.get_viewport().get_visible_rect().size
	var p_left: Vector2 = KnightLoreHud.project_ortho_point(rig.camera, vp_sz, Vector3(-0.5, 0.0, 8.5))
	var p_bot: Vector2 = KnightLoreHud.project_ortho_point(rig.camera, vp_sz, Vector3(8.5, 0.0, 8.5))
	var expected_slope: float = (p_bot.y - p_left.y) / maxf(p_bot.x - p_left.x, 1.0)
	var wing_dx: float = (left_host.size.x - float(left_wing.get("inner_margin"))) - float(left_wing.get("roller_w"))
	var wing_dy: float = float(left_wing.get("inner_top_y")) - float(left_wing.get("outer_top_y"))
	var actual_slope: float = wing_dy / maxf(wing_dx, 1.0)
	assert_almost_eq(actual_slope, expected_slope, 0.03, "Left scroll top slope must align parallel to projected room edge")
	assert_gt(left_content.scale.x, 0.4, "Scroll content must apply positive scale factor")
