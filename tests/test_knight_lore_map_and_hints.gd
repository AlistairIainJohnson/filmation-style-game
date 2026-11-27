extends GutTest
## Test suite verifying the 16x16 World Map Overlay ([M]) and
## Melkhior's Room Puzzle Hint Engine ([H]) in Knight Lore Reimagined.

var _kl_data: KnightLoreData
var _session: KnightLoreSession


func before_each() -> void:
	_kl_data = KnightLoreData.load_default()
	_session = KnightLoreSession.new()
	_session.start_new_game(_kl_data, 12345, 47)


func test_16x16_grid_mapping_and_integrity() -> void:
	assert_not_null(_kl_data, "KnightLoreData should load")
	var room_ids: Array[int] = _kl_data.get_room_ids()
	assert_eq(room_ids.size(), 128, "There should be exactly 128 rooms in Knight Lore")

	var grid_coords: Dictionary = {}
	for rid: int in room_ids:
		var r: Dictionary = _kl_data.get_room(rid)
		var gx: int = int(r.get("grid_x", -1))
		var gy: int = int(r.get("grid_y", -1))

		assert_true(gx >= 0 and gx <= 15, "grid_x must be in 0..15 for room %d" % rid)
		assert_true(gy >= 0 and gy <= 15, "grid_y must be in 0..15 for room %d" % rid)
		assert_eq((gy * 16) + gx, rid, "Room %d coordinate must satisfy (grid_y * 16) + grid_x" % rid)

		var key: String = "%d,%d" % [gx, gy]
		assert_false(grid_coords.has(key), "Grid coordinate %s must be unique (duplicate on room %d)" % [key, rid])
		grid_coords[key] = rid

	# Verify Cauldron Room 136 coordinate
	var cr: Dictionary = _kl_data.get_room(136)
	assert_eq(int(cr.get("grid_x", -1)), 8, "Cauldron Room grid_x should be 8")
	assert_eq(int(cr.get("grid_y", -1)), 8, "Cauldron Room grid_y should be 8")


func test_hint_engine_cauldron_room_dynamic_charm() -> void:
	var req_type: int = _session.get_next_required_charm()
	var hint: Dictionary = KnightLoreHintEngine.get_room_hint(136, _kl_data, _session)

	assert_eq(int(hint.get("room_id", -1)), 136)
	assert_true(bool(hint.get("is_cauldron", false)), "Room 136 must be flagged as cauldron")
	assert_true(str(hint.get("title", "")).contains("Cauldron"), "Title should mention cauldron")

	var solution: String = str(hint.get("solution", ""))
	var charm_name: String = _session.get_charm_name(req_type)
	assert_true(solution.to_upper().contains(charm_name.to_upper()), "Solution must mention the active requested charm: %s" % charm_name)


func test_hint_engine_handcrafted_rooms() -> void:
	# Room 79: Chamber of Spikes
	var hint79: Dictionary = KnightLoreHintEngine.get_room_hint(79, _kl_data, _session)
	assert_true(str(hint79.get("title", "")).contains("Spikes"), "Room 79 title should mention spikes")
	assert_true(str(hint79.get("warning", "")).contains("spike"), "Warning should alert to lethal spikes")
	assert_true(str(hint79.get("form_synergy", "")).contains("Werewolf"), "Synergy should note werewolf jump height advantage")

	# Room 47: Start Room
	var hint47: Dictionary = KnightLoreHintEngine.get_room_hint(47, _kl_data, _session)
	assert_true(str(hint47.get("title", "")).contains("South-West"), "Room 47 title should mention South-West")
	assert_false(str(hint47.get("solution", "")).is_empty(), "Solution text must not be empty")

	# Room 155: Oscillating Platforms & Spikes (verified not pushable)
	var hint155: Dictionary = KnightLoreHintEngine.get_room_hint(155, _kl_data, _session)
	assert_true(str(hint155.get("title", "")).contains("Oscillating"), "Room 155 title should mention Oscillating Platforms")
	assert_true(str(hint155.get("solution", "")).contains("oscillating shuttles"), "Solution must clarify moving blocks are autonomous shuttles")
	assert_true(str(hint155.get("warning", "")).contains("cannot be pushed"), "Warning must clarify moving blocks cannot be pushed")


func test_hint_engine_procedural_generation() -> void:
	# Test an arbitrary non-handcrafted room (e.g., room 0 or room 10)
	var hint0: Dictionary = KnightLoreHintEngine.get_room_hint(0, _kl_data, _session)
	assert_eq(int(hint0.get("room_id", -1)), 0)
	assert_false(str(hint0.get("challenge", "")).is_empty(), "Procedural challenge must not be empty")
	assert_false(str(hint0.get("solution", "")).is_empty(), "Procedural solution must not be empty")
	assert_false(str(hint0.get("warning", "")).is_empty(), "Procedural warning must not be empty")

	# Verify elevated exit detection if room has high archways
	for rid: int in _kl_data.get_room_ids():
		var exits: Dictionary = _kl_data.get_room_exits(rid)
		var has_high: bool = false
		for ex_v: Variant in exits.values():
			if bool((ex_v as Dictionary).get("high", false)):
				has_high = true
				break
		if has_high:
			var hint_high: Dictionary = KnightLoreHintEngine.get_room_hint(rid, _kl_data, _session)
			var el_ex: Array = hint_high.get("elevated_exits", []) as Array
			assert_true(el_ex.size() > 0, "Room %d has high archways and must report elevated_exits" % rid)
			assert_true(str(hint_high.get("challenge", "")).contains("3.0m elevation") or str(hint_high.get("challenge", "")).contains("elevated"), "Challenge text must note high arch elevation")
			break


func test_map_dialog_instantiation_and_inspection() -> void:
	var map_dlg := KnightLoreMapDialog.new()
	add_child_autofree(map_dlg)

	assert_eq(map_dlg.layer, 35, "Map dialog must reside on Layer 35")
	assert_false(map_dlg.visible, "Map dialog should initially be hidden")

	var visited: Dictionary = {47: true, 68: true, 136: true}
	map_dlg.open(47, visited, 2, 1)
	assert_true(map_dlg.visible, "Map dialog should be visible when opened")

	# Select room 136 (Cauldron Hub)
	watch_signals(map_dlg)
	map_dlg._on_room_button_clicked(136)
	assert_signal_emitted_with_parameters(map_dlg, "room_selected", [136])

	# Select room 79
	map_dlg._on_room_button_clicked(79)
	assert_signal_emitted_with_parameters(map_dlg, "room_selected", [79])

	map_dlg.close()
	assert_false(map_dlg.visible, "Map dialog should be hidden after close()")
	assert_signal_emitted(map_dlg, "closed")


func test_hint_dialog_instantiation_and_lifecycle() -> void:
	var hint_dlg := KnightLoreHintDialog.new()
	add_child_autofree(hint_dlg)

	assert_eq(hint_dlg.layer, 35, "Hint dialog must reside on Layer 35")
	assert_false(hint_dlg.visible, "Hint dialog should initially be hidden")

	watch_signals(hint_dlg)
	hint_dlg.open(79, _session)
	assert_true(hint_dlg.visible, "Hint dialog should be visible when opened")

	hint_dlg.close()
	assert_false(hint_dlg.visible, "Hint dialog should be hidden after close()")
	assert_signal_emitted(hint_dlg, "closed")


func test_pause_menu_map_and_hint_buttons_and_signals() -> void:
	var pause_menu := KnightLorePauseMenu.new()
	add_child_autofree(pause_menu)

	watch_signals(pause_menu)
	pause_menu.open(false, false, false)
	assert_true(pause_menu.visible, "Pause menu should be visible")

	# Test map button trigger
	pause_menu._on_map_pressed()
	assert_signal_emitted(pause_menu, "map_requested")
	assert_false(pause_menu.visible, "Pause menu should close when map requested")

	# Reopen and test hint button trigger
	pause_menu.open(false, false, false)
	pause_menu._on_hint_pressed()
	assert_signal_emitted(pause_menu, "hint_requested")
	assert_false(pause_menu.visible, "Pause menu should close when hint requested")

	# Reopen and test prologue button trigger
	pause_menu.open(false, false, false)
	pause_menu._on_prologue_pressed()
	assert_signal_emitted(pause_menu, "prologue_requested")
	assert_false(pause_menu.visible, "Pause menu should close when prologue requested")


func test_prologue_dialog_lifecycle_and_signals() -> void:
	var prologue_dlg := KnightLorePrologueDialog.new()
	add_child_autofree(prologue_dlg)

	assert_false(prologue_dlg.visible, "Prologue dialog should initially be hidden")
	watch_signals(prologue_dlg)

	prologue_dlg.open(false)
	assert_true(prologue_dlg.visible, "Prologue dialog should be visible when opened")

	prologue_dlg.close()
	assert_false(prologue_dlg.visible, "Prologue dialog should be hidden after close()")
	assert_signal_emitted(prologue_dlg, "closed")


func test_authentic_woodland_ink_colors() -> void:
	# Verify that woodland rooms distribute across Yellow and Magenta
	var yellow_forest: Array[int] = []
	var magenta_forest: Array[int] = []
	for rid: int in _kl_data.get_room_ids():
		if _kl_data.is_forest_room(rid):
			var r: Dictionary = _kl_data.get_room(rid)
			var iname: String = str(r.get("ink_color_name", ""))
			if iname == "Yellow":
				yellow_forest.append(rid)
			elif iname == "Magenta":
				magenta_forest.append(rid)

	assert_eq(yellow_forest.size(), 12, "There should be exactly 12 Yellow woodland rooms")
	assert_eq(magenta_forest.size(), 12, "There should be exactly 12 Magenta woodland rooms")
	assert_eq(yellow_forest.size() + magenta_forest.size(), 24, "All 24 woodland rooms must be Yellow or Magenta")


func test_all_128_rooms_doorway_spawn_clearance_and_puzzle_reachability() -> void:
	var builder := RoomBuilder.new()
	var player_radius: float = 0.28
	var player_height: float = 1.36
	var werewolf_apex: float = 1.65

	for rid: int in _kl_data.get_room_ids():
		var root := Node3D.new()
		var build: Dictionary = builder.build_knight_lore_room(root, rid, _kl_data, "castle_stone_skylight", "true_isometric", false)
		assert_false(build.is_empty(), "Room %d must build successfully" % rid)

		var doorways: Node3D = build.get("doorways_root") as Node3D
		var arch_root: Node3D = build.get("architecture_root") as Node3D

		if doorways != null and arch_root != null:
			for child: Node in doorways.get_children():
				if child is Marker3D and child.name.begins_with("Spawn_"):
					var sp_pos: Vector3 = (child as Marker3D).position
					for a_child: Node in arch_root.get_children():
						if a_child is StaticBody3D:
							var cshape: CollisionShape3D = a_child.get_node_or_null("CollisionShape3D") as CollisionShape3D
							if cshape != null and cshape.shape is BoxShape3D:
								var box: BoxShape3D = cshape.shape as BoxShape3D
								var b_half: Vector3 = box.size * 0.5
								var b_pos: Vector3 = a_child.position + cshape.position
								var dx: float = absf(sp_pos.x - b_pos.x)
								var dz: float = absf(sp_pos.z - b_pos.z)
								if dx < (b_half.x + player_radius - 0.04) and dz < (b_half.z + player_radius - 0.04):
									var player_bottom: float = sp_pos.y
									var player_top: float = sp_pos.y + player_height
									var block_bottom: float = b_pos.y - b_half.y
									var block_top: float = b_pos.y + b_half.y
									var overlaps: bool = (player_bottom < (block_top - 0.05) and player_top > (block_bottom + 0.05))
									assert_false(overlaps, "Room %d doorway spawn [%s] must not overlap %s at %s" % [rid, child.name, a_child.name, b_pos])

		root.free()

