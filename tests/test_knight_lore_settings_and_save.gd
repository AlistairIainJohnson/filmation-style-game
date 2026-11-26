extends GutTest
## Test suite verifying Knight Lore Settings (lives modes, invulnerability, jump boost, volume)
## and State Serialization / Disk Save & Load workflows.

var _kl_data: KnightLoreData
var _session: KnightLoreSession
var _game: Node


func before_each() -> void:
	_kl_data = KnightLoreData.load_default()
	_session = KnightLoreSession.new()
	_session.start_new_game(_kl_data, 12345, 47)


func after_each() -> void:
	if FileAccess.file_exists("user://settings.json"):
		DirAccess.remove_absolute("user://settings.json")


func test_lives_modes() -> void:
	# Normal mode: 5 lives, decrements on death
	assert_eq(_session.lives, 5, "Normal lives should be 5")
	assert_false(_session.infinite_lives, "infinite_lives should be false")
	var res: Dictionary = _session.apply_player_death()
	assert_eq(_session.lives, 4, "Lives should decrement to 4")
	assert_false(bool(res.get("game_over", false)))

	# 99 Lives mode
	_session.lives = 99
	_session.infinite_lives = false
	res = _session.apply_player_death()
	assert_eq(_session.lives, 98, "99 lives should decrement to 98 on death")

	# Infinite Lives mode
	_session.lives = KnightLoreSession.INFINITE_LIVES
	_session.infinite_lives = true
	res = _session.apply_player_death()
	assert_eq(_session.lives, KnightLoreSession.INFINITE_LIVES, "Infinite lives must never decrement")
	assert_false(bool(res.get("game_over", false)))


func test_invulnerability_mode() -> void:
	_session.lives = 5
	_session.invulnerable = true
	var res: Dictionary = _session.apply_player_death()
	assert_eq(_session.lives, 5, "Invulnerable player must not lose lives")
	assert_false(bool(res.get("game_over", false)), "Invulnerable player must not suffer game over")


func test_jump_boost_on_player_controller() -> void:
	var player := PlayerController.new()
	add_child_autofree(player)

	player.jump_boost = false
	player.jump_height = 1.35
	player.recompute_jump_constants()
	var base_jump_vel: float = player.jump_velocity

	# Turn on jump boost
	player.jump_boost = true
	player.jump_height = 1.35 * 1.45
	player.recompute_jump_constants()
	assert_gt(player.jump_velocity, base_jump_vel, "Boosted jump height must yield higher jump velocity")
	assert_true(player.jump_boost, "jump_boost flag must be true")


func test_session_state_serialization_and_hydration() -> void:
	_session.current_room_id = 136
	_session.day_count = 14
	_session.is_night = true
	_session.is_wulf = true
	_session.half_day_progress = 0.65
	_session.charms_collected = 7
	_session.lives = 99
	_session.infinite_lives = false
	_session.invulnerable = true
	_session.inventory = [1, 3, -1]
	_session.visited_rooms[47] = true
	_session.visited_rooms[136] = true

	var serialized: Dictionary = _session.serialize_state()
	assert_true(serialized.has("version"))
	assert_eq(int(serialized.get("current_room_id", 0)), 136)
	assert_eq(int(serialized.get("day_count", 0)), 14)
	assert_eq(int(serialized.get("charms_collected", 0)), 7)
	assert_eq(int(serialized.get("lives", 0)), 99)
	assert_true(bool(serialized.get("invulnerable", false)))

	# Hydrate into brand-new session
	var fresh_session := KnightLoreSession.new()
	var ok: bool = fresh_session.hydrate_state(serialized)
	assert_true(ok, "Hydration must return true")
	assert_eq(fresh_session.current_room_id, 136)
	assert_eq(fresh_session.day_count, 14)
	assert_true(fresh_session.is_night)
	assert_true(fresh_session.is_wulf)
	assert_almost_eq(fresh_session.half_day_progress, 0.65, 0.01)
	assert_eq(fresh_session.charms_collected, 7)
	assert_eq(fresh_session.lives, 99)
	assert_false(fresh_session.infinite_lives)
	assert_true(fresh_session.invulnerable)
	assert_eq(fresh_session.inventory, [1, 3, -1])
	assert_true(fresh_session.visited_rooms.has(47))
	assert_true(fresh_session.visited_rooms.has(136))


func test_settings_dialog_ui_and_signals() -> void:
	var dialog := KnightLoreSettingsDialog.new()
	add_child_autofree(dialog)

	var signal_emitted: Array = []
	dialog.settings_saved.connect(func(s: Dictionary) -> void: signal_emitted.append(s))

	dialog.open({
		"lives_mode": "normal",
		"music_volume": 0.5,
		"sfx_volume": 0.6,
		"invulnerable": false,
		"jump_boost": false
	})

	assert_true(dialog.visible)
	var current: Dictionary = dialog.get_settings()
	assert_eq(current.get("lives_mode"), "normal")
	assert_almost_eq(float(current.get("music_volume")), 0.5, 0.01)

	# Cycle lives
	dialog._on_lives_cycle_pressed()
	assert_eq(dialog.get_settings().get("lives_mode"), "99")

	# Toggle invulnerability and jump boost
	dialog._on_invuln_toggled()
	assert_true(bool(dialog.get_settings().get("invulnerable")))

	dialog._on_jump_toggled()
	assert_true(bool(dialog.get_settings().get("jump_boost")))

	assert_gt(signal_emitted.size(), 0, "settings_saved signal should have fired on changes")
	dialog.close()
	assert_false(dialog.visible)


func test_game_save_and_load_from_slot() -> void:
	var packed: PackedScene = load("res://game/knight_lore_game.tscn") as PackedScene
	_game = packed.instantiate()
	add_child_autofree(_game)

	# Start game
	_game._start_session()
	_game.session.current_room_id = 68
	_game.session.charms_collected = 3
	_game.session.day_count = 5
	_game._current_settings["lives_mode"] = "99"
	_game._current_settings["invulnerable"] = true
	_game._current_settings["jump_boost"] = true

	var test_path: String = "user://saves/test_save_slot_99.json"
	var err: Error = _game.save_game_to_slot(99, test_path)
	assert_eq(err, OK, "Saving game to slot must return OK")
	assert_true(FileAccess.file_exists(test_path), "Save file must exist on disk")

	# Modify in-memory state
	_game.session.current_room_id = 143
	_game.session.charms_collected = 0
	_game.session.day_count = 1
	_game._current_settings["lives_mode"] = "normal"
	_game._current_settings["invulnerable"] = false

	# Reload from file
	err = _game.load_game_from_slot(99, test_path)
	assert_eq(err, OK, "Loading game from slot must return OK")
	assert_eq(_game.session.current_room_id, 68, "Room ID must be restored to 68")
	assert_eq(_game.session.charms_collected, 3, "Charms must be restored to 3")
	assert_eq(_game.session.day_count, 5, "Day count must be restored to 5")
	assert_eq(_game._current_settings.get("lives_mode"), "99", "Settings must be restored")
	assert_true(bool(_game._current_settings.get("invulnerable")), "Invulnerable must be restored")

	# Clean up test save file
	DirAccess.remove_absolute(test_path)
