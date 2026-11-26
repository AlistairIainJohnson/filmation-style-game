extends GutTest
## Test suite for genuine orchestral scoring, audio bus routing, dungeon hard echo, and woodland soundscapes.

var _audio_mgr: ZxAudioManager
var _score_seq: KlScoreSequencer
var _ambience_dir: KlAmbienceDirector


func before_each() -> void:
	_audio_mgr = ZxAudioManager.new()
	add_child_autofree(_audio_mgr)
	_score_seq = KlScoreSequencer.new(_audio_mgr)
	add_child_autofree(_score_seq)
	_ambience_dir = KlAmbienceDirector.new(_audio_mgr)
	add_child_autofree(_ambience_dir)


func test_audio_configs_exist_and_reference_valid_streams() -> void:
	assert_true(FileAccess.file_exists("res://data/knight_lore/audio_score.json"), "audio_score.json must exist")
	assert_true(FileAccess.file_exists("res://data/knight_lore/audio_soundscapes.json"), "audio_soundscapes.json must exist")

	var cues: Dictionary = _score_seq._score_cfg.get("cues", {}) as Dictionary
	assert_eq(cues.size(), 6, "Should define all 6 orchestral cues")
	for cname: Variant in cues.keys():
		var path: String = str((cues[cname] as Dictionary).get("stream", ""))
		assert_true(ResourceLoader.exists(path), "Missing cue stream: " + path)
		var st: AudioStream = ResourceLoader.load(path) as AudioStream
		assert_not_null(st, "Should load AudioStream for cue " + str(cname))
		assert_gt(st.get_length(), 2.0, "Cue should have meaningful duration: " + str(cname))

	var biomes: Dictionary = _ambience_dir._soundscapes_cfg.get("biomes", {}) as Dictionary
	assert_true(biomes.has("dungeon") and biomes.has("woodland"), "Should define dungeon & woodland biomes")


func test_dynamic_buses_configured() -> void:
	assert_gt(AudioServer.get_bus_index(&"Master"), -1, "Master bus must exist")
	assert_gt(AudioServer.get_bus_index(&"Music"), -1, "Music bus must exist")
	assert_gt(AudioServer.get_bus_index(&"SFX"), -1, "SFX bus must exist")
	assert_gt(AudioServer.get_bus_index(&"RoomFX"), -1, "RoomFX bus must exist")
	assert_gt(AudioServer.get_bus_index(&"SFX_Dry"), -1, "SFX_Dry bus must exist")
	assert_gt(AudioServer.get_bus_index(&"Ambience"), -1, "Ambience bus must exist")


func test_dungeon_and_woodland_biome_acoustics() -> void:
	_audio_mgr.apply_biome("dungeon", false)
	assert_eq(_audio_mgr.get_current_biome(), "dungeon")
	assert_not_null(_audio_mgr._reverb_effect, "Reverb effect must be allocated")
	assert_not_null(_audio_mgr._delay_effect, "Delay effect must be allocated")
	assert_gt(_audio_mgr._reverb_effect.room_size, 0.70, "Dungeon must have large room_size for stone hall reverb")
	assert_gt(_audio_mgr._reverb_effect.wet, 0.30, "Dungeon must have substantial wet reverb level")
	assert_true(_audio_mgr._delay_effect.tap1_active, "Dungeon must enable hard echo tap1")
	assert_gt(_audio_mgr._delay_effect.tap1_delay_ms, 80.0, "Dungeon slapback delay should be >= 80ms")

	_audio_mgr.apply_biome("woodland", false)
	assert_eq(_audio_mgr.get_current_biome(), "woodland")
	assert_lt(_audio_mgr._reverb_effect.room_size, 0.25, "Woodland must have small open-air room_size")
	assert_lt(_audio_mgr._reverb_effect.wet, 0.12, "Woodland must have minimal wet reverb")
	assert_false(_audio_mgr._delay_effect.tap1_active, "Woodland must disable hard stone slapback echo")


func test_orchestral_score_sequencer_plays_and_crossfades_cues() -> void:
	_score_seq.play_cue("menu", true)
	assert_true(_score_seq.is_playing("menu"), "Menu cue should be active")
	assert_true(_audio_mgr.is_music_playing(), "Music player should be playing menu cue")

	_score_seq.play_cue("gameplay_day", true)
	assert_true(_score_seq.is_playing("gameplay_day"), "Should switch to gameplay_day cue")

	_score_seq.stop_cue(0.0)
	assert_false(_score_seq.is_playing(), "Score sequencer should stop cleanly")
	assert_false(_audio_mgr.is_music_playing(), "Music player should stop when fade=0")


func test_ambience_director_swaps_biome_and_day_night_streams() -> void:
	_ambience_dir.set_biome("woodland")
	_ambience_dir.set_cycle(false)
	assert_true(_ambience_dir.get_active_stream_path().ends_with("ambience_woodland_day.ogg"))
	assert_true(_audio_mgr.is_ambience_playing())

	_ambience_dir.set_cycle(true)
	assert_true(_ambience_dir.get_active_stream_path().ends_with("ambience_woodland_night.ogg"))

	_ambience_dir.set_biome("dungeon")
	assert_true(_ambience_dir.get_active_stream_path().ends_with("ambience_dungeon.ogg"))


func test_room_fx_vs_dry_sfx_routing_and_biome_footstep_variants() -> void:
	_audio_mgr.apply_biome("dungeon", false)
	_audio_mgr.play_sfx("sfx_step_player", 1.0)
	var played_stone: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _audio_mgr._room_sfx_players:
		if p.playing and p.stream != null and p.stream.resource_path.contains("step_stone"):
			played_stone = p
			break
	assert_not_null(played_stone, "Dungeon player step should play step_stone_* on RoomFX pool")
	assert_lte(played_stone.volume_db, -14.0, "Dungeon player footsteps should be quiet and unobtrusive")

	_audio_mgr.apply_biome("woodland", false)
	_audio_mgr.play_sfx("sfx_step_player", 1.0)
	var played_wood: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _audio_mgr._room_sfx_players:
		if p.playing and p.stream != null and p.stream.resource_path.contains("step_woodland"):
			played_wood = p
			break
	assert_not_null(played_wood, "Woodland player step should play step_woodland_* on RoomFX pool")

	_audio_mgr.play_sfx("sfx_menu_select")
	var played_dry: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _audio_mgr._dry_sfx_players:
		if p.playing and p.stream != null and p.stream.resource_path.contains("menu_select"):
			played_dry = p
			break
	assert_not_null(played_dry, "UI menu select should route to SFX_Dry pool without dungeon echo")
