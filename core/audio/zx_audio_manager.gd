class_name ZxAudioManager
extends Node
## Native stream-based orchestral & environmental audio manager.
## Manages:
## 1. Dynamic AudioServer bus routing (Master <- Music, Ambience, RoomFX <- SFX, SFX_Dry).
## 2. Dual A/B AudioStreamPlayers with smooth Tween crossfades for orchestral music and biome ambience.
## 3. Polyphonic SFX player pools with variant cycling, pitch jitter, and RoomFX reverb/echo routing.
## 4. Config-driven acoustic presets loaded from audio_score.json and audio_soundscapes.json.

signal tune_finished(tune_name: String)
signal music_stream_finished(stream_path: String)

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_ROOM_FX: StringName = &"RoomFX"
const BUS_SFX_DRY: StringName = &"SFX_Dry"
const BUS_AMBIENCE: StringName = &"Ambience"

const ROOM_SFX_POOL_SIZE: int = 6
const DRY_SFX_POOL_SIZE: int = 4

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music_idx: int = 0
var _music_tween: Tween
var _current_music_path: String = ""
var _current_music_loop: bool = false

var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _active_amb_idx: int = 0
var _amb_tween: Tween
var _current_amb_path: String = ""

var _room_sfx_players: Array[AudioStreamPlayer] = []
var _dry_sfx_players: Array[AudioStreamPlayer] = []
var _room_sfx_cursor: int = 0
var _dry_sfx_cursor: int = 0
var _variant_cursors: Dictionary = {}
var _stream_cache: Dictionary = {}

var _audio_cfg: Dictionary = {}
var _score_cfg: Dictionary = {}
var _soundscapes_cfg: Dictionary = {}

var _current_biome: String = "dungeon"
var _reverb_effect: AudioEffectReverb
var _delay_effect: AudioEffectDelay
var _biome_tween: Tween

var master_volume: float = 0.90
var music_volume: float = 0.85
var sfx_volume: float = 0.90
var ambience_volume: float = 0.85
var muted: bool = false


func _init() -> void:
	name = "ZxAudioManager"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_init_players()
	load_audio_config("res://data/knight_lore/audio.json")
	load_score_config("res://data/knight_lore/audio_score.json")
	load_soundscapes_config("res://data/knight_lore/audio_soundscapes.json")


func _ready() -> void:
	_apply_bus_volumes()
	apply_biome(_current_biome, false)


# -----------------------------------------------------------------------------
# Dynamic AudioServer Bus Architecture
# -----------------------------------------------------------------------------

func _setup_audio_buses() -> void:
	_ensure_bus_exists(BUS_MUSIC, BUS_MASTER)
	_ensure_bus_exists(BUS_AMBIENCE, BUS_MASTER)
	_ensure_bus_exists(BUS_ROOM_FX, BUS_MASTER)
	_ensure_bus_exists(BUS_SFX, BUS_ROOM_FX)
	_ensure_bus_exists(BUS_SFX_DRY, BUS_MASTER)

	var room_bus_idx: int = AudioServer.get_bus_index(BUS_ROOM_FX)
	if room_bus_idx >= 0:
		for i: int in range(AudioServer.get_bus_effect_count(room_bus_idx)):
			var eff: AudioEffect = AudioServer.get_bus_effect(room_bus_idx, i)
			if eff is AudioEffectReverb:
				_reverb_effect = eff as AudioEffectReverb
			elif eff is AudioEffectDelay:
				_delay_effect = eff as AudioEffectDelay

		if _reverb_effect == null:
			_reverb_effect = AudioEffectReverb.new()
			AudioServer.add_bus_effect(room_bus_idx, _reverb_effect)

		if _delay_effect == null:
			_delay_effect = AudioEffectDelay.new()
			AudioServer.add_bus_effect(room_bus_idx, _delay_effect)


func _ensure_bus_exists(bus_name: StringName, send_to: StringName) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	return idx


func _init_players() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_a.name = "MusicPlayerA"
	_music_a.bus = BUS_MUSIC
	_music_a.finished.connect(_on_music_player_finished.bind(0))
	add_child(_music_a)

	_music_b = AudioStreamPlayer.new()
	_music_b.name = "MusicPlayerB"
	_music_b.bus = BUS_MUSIC
	_music_b.finished.connect(_on_music_player_finished.bind(1))
	add_child(_music_b)

	_amb_a = AudioStreamPlayer.new()
	_amb_a.name = "AmbiencePlayerA"
	_amb_a.bus = BUS_AMBIENCE
	add_child(_amb_a)

	_amb_b = AudioStreamPlayer.new()
	_amb_b.name = "AmbiencePlayerB"
	_amb_b.bus = BUS_AMBIENCE
	add_child(_amb_b)

	for i: int in range(ROOM_SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "RoomSfxPlayer_%d" % i
		p.bus = BUS_ROOM_FX
		add_child(p)
		_room_sfx_players.append(p)

	for i: int in range(DRY_SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "DrySfxPlayer_%d" % i
		p.bus = BUS_SFX_DRY
		add_child(p)
		_dry_sfx_players.append(p)


# -----------------------------------------------------------------------------
# Config & Resource Loading
# -----------------------------------------------------------------------------

func load_audio_config(path: String) -> void:
	_audio_cfg = _load_json_dict(path)


func load_score_config(path: String) -> void:
	_score_cfg = _load_json_dict(path)


func load_soundscapes_config(path: String) -> void:
	_soundscapes_cfg = _load_json_dict(path)


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = ResourceLoader.load(path) as AudioStream
	if st != null:
		_stream_cache[path] = st
	return st


# -----------------------------------------------------------------------------
# Biome Environmental Acoustics (Reverb + Hard Stone Echo)
# -----------------------------------------------------------------------------

func apply_biome(biome_id: String, smooth: bool = true) -> void:
	_current_biome = biome_id
	var biomes: Dictionary = _soundscapes_cfg.get("biomes", {}) as Dictionary
	if not biomes.has(biome_id):
		return
	var b_data: Dictionary = biomes[biome_id] as Dictionary

	var rev_cfg: Dictionary = b_data.get("reverb", {}) as Dictionary
	var target_room: float = float(rev_cfg.get("room_size", 0.5))
	var target_damp: float = float(rev_cfg.get("damping", 0.5))
	var target_wet: float = float(rev_cfg.get("wet", 0.3))
	var target_dry: float = float(rev_cfg.get("dry", 0.85))
	var target_spread: float = float(rev_cfg.get("spread", 0.8))

	var echo_cfg: Dictionary = b_data.get("echo", {}) as Dictionary
	var echo_enabled: bool = bool(echo_cfg.get("enabled", float(echo_cfg.get("delay_ms", 0.0)) > 10.0))

	if _delay_effect != null:
		if echo_enabled:
			var delay_ms: float = maxf(15.0, float(echo_cfg.get("delay_ms", 125.0)))
			var tap2_ms: float = maxf(delay_ms + 20.0, float(echo_cfg.get("tap2_ms", delay_ms * 2.04)))
			var fb_ms: float = maxf(20.0, float(echo_cfg.get("feedback_ms", delay_ms * 1.48)))
			_delay_effect.tap1_active = true
			_delay_effect.tap1_delay_ms = delay_ms
			_delay_effect.tap2_active = true
			_delay_effect.tap2_delay_ms = tap2_ms
			_delay_effect.feedback_active = true
			_delay_effect.feedback_delay_ms = fb_ms
		else:
			_delay_effect.tap1_active = false
			_delay_effect.tap2_active = false
			_delay_effect.feedback_active = false

	var target_tap1_db: float = float(echo_cfg.get("tap1_db", -8.0)) if echo_enabled else -60.0
	var target_tap2_db: float = float(echo_cfg.get("tap2_db", -14.0)) if echo_enabled else -60.0
	var target_fb_db: float = float(echo_cfg.get("feedback_db", -13.0)) if echo_enabled else -60.0
	var target_echo_dry: float = float(echo_cfg.get("dry", 0.90)) if echo_enabled else 1.0

	if not smooth or not is_inside_tree():
		if _reverb_effect != null:
			_reverb_effect.room_size = target_room
			_reverb_effect.damping = target_damp
			_reverb_effect.wet = target_wet
			_reverb_effect.dry = target_dry
			_reverb_effect.spread = target_spread
		if _delay_effect != null:
			_delay_effect.tap1_level_db = target_tap1_db
			_delay_effect.tap2_level_db = target_tap2_db
			_delay_effect.feedback_level_db = target_fb_db
			_delay_effect.dry = target_echo_dry
		return

	if _biome_tween != null and _biome_tween.is_valid():
		_biome_tween.kill()
	_biome_tween = create_tween()
	_biome_tween.set_parallel(true)
	if _reverb_effect != null:
		_reverb_effect.room_size = target_room
		_reverb_effect.damping = target_damp
		_reverb_effect.spread = target_spread
		_biome_tween.tween_property(_reverb_effect, "wet", target_wet, 0.40)
		_biome_tween.tween_property(_reverb_effect, "dry", target_dry, 0.40)
	if _delay_effect != null:
		_biome_tween.tween_property(_delay_effect, "tap1_level_db", target_tap1_db, 0.35)
		_biome_tween.tween_property(_delay_effect, "tap2_level_db", target_tap2_db, 0.35)
		_biome_tween.tween_property(_delay_effect, "feedback_level_db", target_fb_db, 0.35)
		_biome_tween.tween_property(_delay_effect, "dry", target_echo_dry, 0.35)


func get_current_biome() -> String:
	return _current_biome


# -----------------------------------------------------------------------------
# Music & Ambience Crossfading Players
# -----------------------------------------------------------------------------

func play_music_stream(stream_path: String, loop: bool = true, volume_db: float = -4.0, fade_s: float = 0.8) -> bool:
	var base_st: AudioStream = _get_stream(stream_path)
	if base_st == null:
		return false

	var st: AudioStream = base_st
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = loop
	elif st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED

	var old_player: AudioStreamPlayer = _music_a if _active_music_idx == 0 else _music_b
	_active_music_idx = 1 - _active_music_idx
	var new_player: AudioStreamPlayer = _music_a if _active_music_idx == 0 else _music_b

	_current_music_path = stream_path
	_current_music_loop = loop

	new_player.stop()
	new_player.stream = st
	if fade_s <= 0.05 or not is_inside_tree():
		old_player.stop()
		new_player.volume_db = volume_db
		if new_player.is_inside_tree():
			new_player.play()
		return true

	new_player.volume_db = -42.0
	if new_player.is_inside_tree():
		new_player.play()

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(new_player, "volume_db", volume_db, fade_s).set_trans(Tween.TRANS_SINE)
	if old_player.playing:
		_music_tween.tween_property(old_player, "volume_db", -48.0, fade_s).set_trans(Tween.TRANS_SINE)
		_music_tween.chain().tween_callback(old_player.stop)
	return true


func stop_music(fade_s: float = 0.4) -> void:
	_current_music_path = ""
	if fade_s <= 0.05 or not is_inside_tree():
		if _music_a != null:
			_music_a.stop()
		if _music_b != null:
			_music_b.stop()
		return

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	if _music_a != null and _music_a.playing:
		_music_tween.tween_property(_music_a, "volume_db", -48.0, fade_s)
	if _music_b != null and _music_b.playing:
		_music_tween.tween_property(_music_b, "volume_db", -48.0, fade_s)
	_music_tween.chain().tween_callback(func() -> void:
		if _music_a != null:
			_music_a.stop()
		if _music_b != null:
			_music_b.stop()
	)


func is_music_playing() -> bool:
	return (_music_a != null and _music_a.playing) or (_music_b != null and _music_b.playing)


func _on_music_player_finished(idx: int) -> void:
	if idx == _active_music_idx and not _current_music_loop and not _current_music_path.is_empty():
		var finished_path: String = _current_music_path
		_current_music_path = ""
		music_stream_finished.emit(finished_path)


func play_ambience_stream(stream_path: String, volume_db: float = -4.0, fade_s: float = 1.2) -> bool:
	if stream_path == _current_amb_path and is_ambience_playing():
		return true
	var base_st: AudioStream = _get_stream(stream_path)
	if base_st == null:
		return false

	if base_st is AudioStreamOggVorbis:
		(base_st as AudioStreamOggVorbis).loop = true
	elif base_st is AudioStreamWAV:
		(base_st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	var old_player: AudioStreamPlayer = _amb_a if _active_amb_idx == 0 else _amb_b
	_active_amb_idx = 1 - _active_amb_idx
	var new_player: AudioStreamPlayer = _amb_a if _active_amb_idx == 0 else _amb_b
	_current_amb_path = stream_path

	new_player.stop()
	new_player.stream = base_st
	if fade_s <= 0.05 or not is_inside_tree():
		old_player.stop()
		new_player.volume_db = volume_db
		if new_player.is_inside_tree():
			new_player.play()
		return true

	new_player.volume_db = -44.0
	if new_player.is_inside_tree():
		new_player.play()
	if _amb_tween != null and _amb_tween.is_valid():
		_amb_tween.kill()
	_amb_tween = create_tween()
	_amb_tween.set_parallel(true)
	_amb_tween.tween_property(new_player, "volume_db", volume_db, fade_s).set_trans(Tween.TRANS_SINE)
	if old_player.playing:
		_amb_tween.tween_property(old_player, "volume_db", -48.0, fade_s).set_trans(Tween.TRANS_SINE)
		_amb_tween.chain().tween_callback(old_player.stop)
	return true


func stop_ambience(fade_s: float = 0.6) -> void:
	_current_amb_path = ""
	if fade_s <= 0.05 or not is_inside_tree():
		if _amb_a != null:
			_amb_a.stop()
		if _amb_b != null:
			_amb_b.stop()
		return
	if _amb_tween != null and _amb_tween.is_valid():
		_amb_tween.kill()
	_amb_tween = create_tween()
	_amb_tween.set_parallel(true)
	if _amb_a != null and _amb_a.playing:
		_amb_tween.tween_property(_amb_a, "volume_db", -48.0, fade_s)
	if _amb_b != null and _amb_b.playing:
		_amb_tween.tween_property(_amb_b, "volume_db", -48.0, fade_s)
	_amb_tween.chain().tween_callback(func() -> void:
		if _amb_a != null:
			_amb_a.stop()
		if _amb_b != null:
			_amb_b.stop()
	)


func is_ambience_playing() -> bool:
	return (_amb_a != null and _amb_a.playing) or (_amb_b != null and _amb_b.playing)


# -----------------------------------------------------------------------------
# Config-Driven SFX Dispatcher
# -----------------------------------------------------------------------------

func play_sfx(event_name: String, _pitch_param: float = 0.0) -> void:
	if muted:
		return
	var events: Dictionary = _soundscapes_cfg.get("sfx_events", {}) as Dictionary
	var cfg: Dictionary = events.get(event_name, {}) as Dictionary
	if cfg.is_empty():
		return

	var candidates: Array = []
	var biome_map: Dictionary = cfg.get("biome_streams", {}) as Dictionary
	if not biome_map.is_empty() and biome_map.has(_current_biome):
		candidates = biome_map[_current_biome] as Array
	if candidates.is_empty():
		candidates = cfg.get("streams", []) as Array
	if candidates.is_empty():
		return

	var cursor: int = int(_variant_cursors.get(event_name, 0))
	var chosen_path: String = str(candidates[cursor % candidates.size()])
	_variant_cursors[event_name] = (cursor + 1) % candidates.size()

	var st: AudioStream = _get_stream(chosen_path)
	if st == null:
		return

	var bus_name: String = str(cfg.get("bus", "RoomFX"))
	var use_room_fx: bool = (bus_name == "RoomFX")
	var player: AudioStreamPlayer = _alloc_sfx_player(use_room_fx)
	if player == null:
		return

	var p_min: float = float(cfg.get("pitch_min", 1.0))
	var p_max: float = float(cfg.get("pitch_max", 1.0))
	var vol_db: float = float(cfg.get("volume_db", -5.0))
	var biome_vols: Dictionary = cfg.get("biome_volume_db", {}) as Dictionary
	if not biome_vols.is_empty() and biome_vols.has(_current_biome):
		vol_db = float(biome_vols[_current_biome])
	player.stream = st
	player.volume_db = vol_db
	player.pitch_scale = randf_range(p_min, p_max) if p_max > p_min else p_min
	if player.is_inside_tree():
		player.play()


func _alloc_sfx_player(use_room_fx: bool) -> AudioStreamPlayer:
	if use_room_fx:
		if _room_sfx_players.is_empty():
			return null
		for p: AudioStreamPlayer in _room_sfx_players:
			if not p.playing:
				return p
		var p: AudioStreamPlayer = _room_sfx_players[_room_sfx_cursor % _room_sfx_players.size()]
		_room_sfx_cursor += 1
		return p
	else:
		if _dry_sfx_players.is_empty():
			return null
		for p: AudioStreamPlayer in _dry_sfx_players:
			if not p.playing:
				return p
		var p: AudioStreamPlayer = _dry_sfx_players[_dry_sfx_cursor % _dry_sfx_players.size()]
		_dry_sfx_cursor += 1
		return p


# -----------------------------------------------------------------------------
# Legacy / Backward-Compatible Helpers
# -----------------------------------------------------------------------------

func play_tune(tune_key: String, loop: bool = false) -> void:
	var cues: Dictionary = _score_cfg.get("cues", {}) as Dictionary
	if cues.has(tune_key):
		var c: Dictionary = cues[tune_key] as Dictionary
		play_music_stream(str(c.get("stream", "")), loop, float(c.get("volume_db", -4.0)), float(c.get("fade_s", 0.5)))


func stop_tune() -> void:
	stop_music(0.2)


func is_tune_playing(tune_key: String = "") -> bool:
	if not is_music_playing():
		return false
	if tune_key.is_empty():
		return true
	var cues: Dictionary = _score_cfg.get("cues", {}) as Dictionary
	if cues.has(tune_key):
		var c: Dictionary = cues[tune_key] as Dictionary
		return _current_music_path == str(c.get("stream", ""))
	return true


# -----------------------------------------------------------------------------
# Volume & Mute Bus Controls
# -----------------------------------------------------------------------------

func _apply_bus_volumes() -> void:
	_set_bus_linear(BUS_MASTER, master_volume)
	_set_bus_linear(BUS_MUSIC, music_volume)
	_set_bus_linear(BUS_AMBIENCE, ambience_volume)
	_set_bus_linear(BUS_ROOM_FX, sfx_volume)
	_set_bus_linear(BUS_SFX_DRY, sfx_volume)
	var m_idx: int = AudioServer.get_bus_index(BUS_MASTER)
	if m_idx >= 0:
		AudioServer.set_bus_mute(m_idx, muted)


func _set_bus_linear(bus_name: StringName, lin: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var clamped: float = clampf(lin, 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, -80.0 if clamped <= 0.001 else linear_to_db(clamped))


func set_mute(p_muted: bool) -> void:
	muted = p_muted
	var m_idx: int = AudioServer.get_bus_index(BUS_MASTER)
	if m_idx >= 0:
		AudioServer.set_bus_mute(m_idx, muted)


func toggle_mute() -> bool:
	set_mute(not muted)
	return muted


func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear(BUS_MASTER, master_volume)


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear(BUS_MUSIC, music_volume)


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear(BUS_ROOM_FX, sfx_volume)
	_set_bus_linear(BUS_SFX_DRY, sfx_volume)


func set_ambience_volume(vol: float) -> void:
	ambience_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear(BUS_AMBIENCE, ambience_volume)
