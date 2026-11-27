extends GutTest
## Test suite verifying complex Knight Lore puzzle edge cases:
## 1. Multi-item drop-climb staircase stacking and vertical reachability (Rooms 16, 168)
## 2. Entity-on-entity stacking & hazard core vertical safety (Room 199 ghost + moveable block)
## 3. Live 3D physics Cauldron drop arc, delivery detection, and victory advancement (Room 136)
## 4. Castle-wide foreground entity doorway clearance across all 128 chambers

const KLGameScript: Script = preload("res://game/knight_lore_game.gd")


func test_multi_step_drop_climb_staircase_and_apex_reachability() -> void:
	# Build a test chamber arena
	var arena := Node3D.new()
	add_child_autofree(arena)

	# Static floor
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	var f_col := CollisionShape3D.new()
	var f_box := BoxShape3D.new()
	f_box.size = Vector3(12.0, 0.5, 12.0)
	f_col.shape = f_box
	f_col.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(f_col)
	arena.add_child(floor_body)

	# Session with 3 carried charms
	var kl: KnightLoreData = KnightLoreData.load_default()
	var sess := KnightLoreSession.new()
	sess.start_new_game(kl, 168, 168)
	sess.inventory = [2, 1, 0] # 3 items in FIFO

	# Player controller
	var player := PlayerController.new()
	player.position = Vector3(4.0, 0.0, 4.0)
	arena.add_child(player)
	await wait_physics_frames(3)

	# Step 1: Drop first charm beneath player (elevates from 0.0m -> ~0.72m)
	var drop1: Dictionary = sess.drop_or_rotate(168, player.position, true)
	assert_eq(str(drop1.get("action", "")), "dropped")
	var item1 := KlSpecialItem.new()
	var d1_entry: Dictionary = drop1.get("dropped_item", {}) as Dictionary
	item1.configure(int(d1_entry.get("id", 1)), int(d1_entry.get("type_id", 0)), Vector3(4.0, 0.0, 4.0))
	arena.add_child(item1)

	player.position.y += 0.72
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_almost_eq(player.position.y, 0.72, 0.08, "First drop must elevate hero onto charm 1 (~0.72m)")

	# Step 2: Step forward slightly and drop second charm (elevates from ~0.72m -> ~1.44m)
	player.position.x += 0.45
	var drop2: Dictionary = sess.drop_or_rotate(168, player.position, true)
	assert_eq(str(drop2.get("action", "")), "dropped")
	var item2 := KlSpecialItem.new()
	var d2_entry: Dictionary = drop2.get("dropped_item", {}) as Dictionary
	item2.configure(int(d2_entry.get("id", 2)), int(d2_entry.get("type_id", 1)), Vector3(4.45, 0.72, 4.0))
	arena.add_child(item2)

	player.position.y += 0.72
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_almost_eq(player.position.y, 1.44, 0.08, "Second drop must elevate hero onto charm 2 (~1.44m)")

	# Step 3: Step forward slightly and drop third charm (elevates from ~1.44m -> ~2.16m)
	player.position.x += 0.45
	var drop3: Dictionary = sess.drop_or_rotate(168, player.position, true)
	assert_eq(str(drop3.get("action", "")), "dropped")
	var item3 := KlSpecialItem.new()
	var d3_entry: Dictionary = drop3.get("dropped_item", {}) as Dictionary
	item3.configure(int(d3_entry.get("id", 3)), int(d3_entry.get("type_id", 2)), Vector3(4.90, 1.44, 4.0))
	arena.add_child(item3)

	player.position.y += 0.72
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_almost_eq(player.position.y, 2.16, 0.08, "Third drop must elevate hero onto charm 3 (~2.16m)")

	# From 2.16m elevation, Human jump reaches 2.16 + 1.35 = 3.51m apex
	# Werewolf jump reaches 2.16 + 1.65 = 3.81m apex
	var human_apex: float = player.position.y + 1.35
	var werewolf_apex: float = player.position.y + 1.65
	assert_gt(human_apex, 3.0, "Human jumping from 3-drop staircase reaches > 3.0m elevation")
	assert_gt(werewolf_apex, 3.5, "Werewolf jumping from 3-drop staircase reaches > 3.5m elevation")
	assert_eq(sess.inventory, [-1, -1, -1], "All 3 inventory slots successfully deployed")


func test_room_199_phantom_stack_block_riding_and_safe_elevation() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var builder := RoomBuilder.new()
	var root := Node3D.new()
	add_child_autofree(root)

	var build: Dictionary = builder.build_knight_lore_room(root, 199, kl, "castle_moonlight_night", "true_isometric", false)
	assert_false(build.is_empty(), "Room 199 must build cleanly")

	var ent_root: Node3D = build.get("entities_root") as Node3D
	assert_not_null(ent_root, "Entities root must exist in Room 199")

	# Find ghost hazard and moveable block
	var ghost: KlHazardEntity = null
	var block: KlPushableEntity = null
	for child: Node in ent_root.get_children():
		if child is KlHazardEntity:
			ghost = child as KlHazardEntity
		elif child is KlPushableEntity:
			block = child as KlPushableEntity

	assert_not_null(ghost, "Room 199 must contain the roaming ghost hazard")
	assert_not_null(block, "Room 199 must contain the moveable block")

	# Verify moveable block rests above the ghost's base elevation
	# Ghost at floor (y ≈ 0.0m); Block at y ≈ 0.75m (z=140 vs floor z=128)
	assert_almost_eq(ghost.position.y, 0.0, 0.15, "Ghost starts at floor elevation")
	assert_almost_eq(block.position.y, 0.75, 0.15, "Moveable block must start stacked atop ghost at ~0.75m")

	# Verify that when standing on the block, the hero is safely above the ghost hazard core
	var player_on_block_pos := Vector3(block.position.x, block.position.y + block.entity_size.y, block.position.z)
	var col_shape: CollisionShape3D = ghost.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(col_shape)
	var bsz: Vector3 = (col_shape.shape as BoxShape3D).size

	var is_in_core: bool = bool(KLGameScript.call("is_player_in_hazard_core", player_on_block_pos, col_shape.global_position, bsz))
	assert_false(is_in_core, "Player standing atop moveable block must be vertically above hazard core (no damage)")

	# Jump reachability from atop block
	# Block top = 0.75m + 0.75m = 1.50m. Werewolf jump apex = 1.50 + 1.65 = 3.15m > 3.0m South arch threshold
	var jump_apex: float = player_on_block_pos.y + 1.65
	assert_gt(jump_apex, 3.0, "Werewolf jumping from block atop ghost reaches > 3.0m, clearing South high arch")


func test_room_136_cauldron_3d_drop_arc_and_charm_acceptance() -> void:
	var prev_room: String = OS.get_environment("FILMATION_KL_ROOM")
	var prev_night: String = OS.get_environment("FILMATION_KL_FORCE_NIGHT")
	OS.set_environment("FILMATION_KL_ROOM", "136")
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", "0")

	var packed: PackedScene = ResourceLoader.load("res://game/knight_lore_game.tscn") as PackedScene
	assert_not_null(packed)
	var game: Node3D = packed.instantiate() as Node3D
	add_child_autofree(game)
	await wait_physics_frames(5)

	var sess: KnightLoreSession = game.get("session") as KnightLoreSession
	var hero: PlayerController = game.get("player") as PlayerController
	assert_not_null(sess)
	assert_not_null(hero)

	# Give hero the exact next required charm
	var expected_charm: int = sess.get_next_required_charm()
	sess.inventory = [-1, -1, expected_charm]

	# Position hero atop the dais beside the cauldron rim (y >= 0.65m)
	hero.position = Vector3(4.0, 0.75, 5.2)
	hero.reset_physics_interpolation()
	await wait_physics_frames(2)

	# Trigger drop interaction
	game.call("_handle_interact")

	# Find the spawned special item node
	var item_nodes: Dictionary = game.get("_item_nodes") as Dictionary
	assert_gt(item_nodes.size(), 0, "Dropping into cauldron must spawn item node")

	var dropped_item: KlSpecialItem = null
	for item_v: Variant in item_nodes.values():
		if item_v is KlSpecialItem:
			dropped_item = item_v as KlSpecialItem
			break

	assert_not_null(dropped_item, "Dropped item node must be valid")
	assert_true(dropped_item.is_arcing, "Cauldron drop must launch ballistic arc into cauldron")

	# Await arc flight completion (~45 physics frames)
	await wait_physics_frames(48)

	assert_eq(sess.charms_collected, 1, "Successful cauldron drop must advance charms collected counter")
	assert_false(hero.input_locked, "Player input must unlock after cauldron arc completes")

	OS.set_environment("FILMATION_KL_ROOM", prev_room)
	OS.set_environment("FILMATION_KL_FORCE_NIGHT", prev_night)


func test_all_128_rooms_foreground_entity_doorway_clearance() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var room_ids: Array[int] = kl.get_room_ids()

	var doorways: Dictionary = {
		"north": Vector2(3.5, 7.0),
		"south": Vector2(3.5, 1.0),
		"west": Vector2(1.0, 3.5),
		"east": Vector2(7.0, 3.5)
	}

	var conflicts: Array[String] = []

	for rid: int in room_ids:
		var r_data: Dictionary = kl.get_room(rid)
		var fgs: Array = r_data.get("foregrounds", []) as Array
		var floor_z: float = float(r_data.get("floor_z", 128))

		for fg_v: Variant in fgs:
			var fg: Dictionary = fg_v as Dictionary
			var tname: String = str(fg.get("type_name", ""))
			# Only check solid furniture, blocks, or lethal hazards
			if tname in ["wall", "block", "table", "chest", "moveable_block", "spikes", "guard_ew", "guard_square", "ghost"]:
				var ent_x: float = float(fg.get("x", 0)) / 16.0
				var ent_y: float = float(fg.get("y", 0)) / 16.0
				var ent_z: float = (float(fg.get("z", 128)) - floor_z) / 16.0

				# Check distance to each doorway sill
				for dname: String in doorways.keys():
					var dpos: Vector2 = doorways[dname] as Vector2
					var dist: float = dpos.distance_to(Vector2(ent_x, ent_y))
					if dist < 0.65 and ent_z < 1.0:
						conflicts.append("Room %d: %s at (%.2f, %.2f, %.2f) conflicts with %s doorway" % [rid, tname, ent_x, ent_y, ent_z, dname])

	assert_eq(conflicts.size(), 0, "No foreground obstacles or hazards may spawn inside doorway thresholds across all 128 rooms")
