extends GutTest
## Phase 5 test suite verifying ZxAudioManager stream playback, full UI flow (MainMenu, PauseMenu),
## HUD integration, and audio/UI signal dispatch.

var _audio_mgr: ZxAudioManager
var _main_menu: KnightLoreMainMenu
var _pause_menu: KnightLorePauseMenu


func before_each() -> void:
	_audio_mgr = ZxAudioManager.new()
	add_child_autofree(_audio_mgr)


func test_audio_config_loaded_and_tunes_present() -> void:
	assert_true(_audio_mgr._audio_cfg.has("tunes"), "audio_cfg should have 'tunes'")
	assert_true(_audio_mgr._score_cfg.has("cues"), "score_cfg should have 'cues'")
	assert_true(_audio_mgr._soundscapes_cfg.has("sfx_events"), "soundscapes_cfg should have 'sfx_events'")
	var tunes: Dictionary = _audio_mgr._audio_cfg.get("tunes", {}) as Dictionary
	assert_true(tunes.has("menu"), "Must contain menu tune")
	assert_true(tunes.has("start_game"), "Must contain start_game tune")
	assert_true(tunes.has("game_over"), "Must contain game_over tune")
	assert_true(tunes.has("game_complete"), "Must contain game_complete tune")
	assert_gt((tunes["menu"] as Array).size(), 50, "Menu tune should have 98 notes")


func test_play_and_stop_tune() -> void:
	_audio_mgr.play_tune("start_game", false)
	assert_true(_audio_mgr.is_tune_playing("start_game"), "start_game should be playing")

	_audio_mgr.stop_music(0.0)
	assert_false(_audio_mgr.is_tune_playing(), "No tune should be playing after stop")


func test_sfx_dispatcher_allocates_voices() -> void:
	_audio_mgr.play_sfx("sfx_jump")
	_audio_mgr.play_sfx("sfx_portcullis_slam")
	_audio_mgr.play_sfx("sfx_transform")
	_audio_mgr.play_sfx("sfx_step_player", 4.0)

	var active_count: int = 0
	for p: AudioStreamPlayer in _audio_mgr._room_sfx_players:
		if p.playing:
			active_count += 1
	assert_gt(active_count, 1, "Multiple SFX players should be active simultaneously")


func test_audio_mute_toggle() -> void:
	assert_false(_audio_mgr.muted, "Default should not be muted")
	var res: bool = _audio_mgr.toggle_mute()
	assert_true(res, "toggle_mute should return true (muted)")
	assert_true(_audio_mgr.muted, "AudioManager muted should be true")

	res = _audio_mgr.toggle_mute()
	assert_false(res, "toggle_mute should return false (unmuted)")
	assert_false(_audio_mgr.muted, "AudioManager muted should be false")


func test_main_menu_initialization_and_strings() -> void:
	_main_menu = KnightLoreMainMenu.new()
	add_child_autofree(_main_menu)
	assert_not_null(_main_menu._title_label, "Title label should be constructed")
	assert_eq(_main_menu._title_label.text, "KNIGHT LORE REIMAGINED", "Title screen must read KNIGHT LORE REIMAGINED")
	assert_true(_main_menu._menu_labels.is_empty(), "Menu must not display legacy 1-0 option lines")
	assert_eq(_main_menu._selected_control_mode, "directional", "Default control should be directional")
	assert_eq(_main_menu._selected_camera_mode, "true_isometric", "Default camera should be true_isometric")

	# Toggle control mode
	_main_menu._on_toggle_control()
	assert_eq(_main_menu._selected_control_mode, "rotational", "Toggling control should set rotational")
	_main_menu._on_toggle_control()
	assert_eq(_main_menu._selected_control_mode, "directional", "Toggling control again should set directional")

	# Toggle camera mode
	_main_menu._on_toggle_camera()
	assert_eq(_main_menu._selected_camera_mode, "dimetric_2_1", "Toggling camera should set dimetric_2_1")
	_main_menu._on_toggle_camera()
	assert_eq(_main_menu._selected_camera_mode, "true_isometric", "Toggling camera again should set true_isometric")


func test_main_menu_start_signal() -> void:
	_main_menu = KnightLoreMainMenu.new()
	add_child_autofree(_main_menu)
	watch_signals(_main_menu)

	_main_menu._on_start_pressed()
	assert_signal_emitted(_main_menu, "start_game_requested", "Start button should emit start_game_requested")


func test_main_menu_exit_signal() -> void:
	_main_menu = KnightLoreMainMenu.new()
	add_child_autofree(_main_menu)
	assert_not_null(_main_menu._exit_btn, "Main menu must build an Exit Game button")
	watch_signals(_main_menu)

	_main_menu._on_exit_pressed()
	assert_signal_emitted(_main_menu, "exit_game_requested", "Exit button should emit exit_game_requested")


func test_pause_menu_flow() -> void:
	_pause_menu = KnightLorePauseMenu.new()
	add_child_autofree(_pause_menu)
	watch_signals(_pause_menu)

	assert_false(_pause_menu.visible, "Pause menu should be hidden initially")
	_pause_menu.open(false, false, false)
	assert_true(_pause_menu.visible, "Pause menu should be visible after open()")
	assert_true(get_tree().paused, "Tree should be paused when pause menu is open")

	_pause_menu.close()
	assert_false(_pause_menu.visible, "Pause menu should be hidden after close()")
	assert_false(get_tree().paused, "Tree should be unpaused after close()")

	# Toggle controls inside pause menu
	_pause_menu.open(false, false, false)
	_pause_menu._on_control_pressed()
	assert_signal_emitted(_pause_menu, "control_mode_toggled", "Pause menu should emit control_mode_toggled")
	_pause_menu.close()


func test_gameplay_scene_audio_and_menu_wiring() -> void:
	var game_scene: Node = load("res://game/knight_lore_game.tscn").instantiate()
	add_child_autofree(game_scene)

	var kl_game: Object = game_scene
	assert_not_null(kl_game.get("audio_manager"), "Game should instantiate audio_manager")
	assert_not_null(kl_game.get("score_sequencer"), "Game should instantiate score_sequencer")
	assert_not_null(kl_game.get("ambience_director"), "Game should instantiate ambience_director")
	assert_not_null(kl_game.get("pause_menu"), "Game should instantiate pause_menu")
	assert_not_null(kl_game.get("main_menu"), "Game should instantiate main_menu")
	assert_not_null(kl_game.get("hud"), "Game should instantiate hud")
