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
	assert_true(str(hint47.get("title", "")).contains("Archway"), "Room 47 title should be resolved")
	assert_false(str(hint47.get("solution", "")).is_empty(), "Solution text must not be empty")


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
