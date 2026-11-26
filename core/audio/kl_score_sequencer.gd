class_name KlScoreSequencer
extends Node
## Config-driven orchestral score cue controller.
## Loads cue definitions (stream paths, loop behavior, crossfade durations, volume levels)
## from data/knight_lore/audio_score.json and drives ZxAudioManager's crossfading players.

signal cue_finished(cue_name: String)

var audio_manager: ZxAudioManager

var _score_cfg: Dictionary = {}
var _current_cue_name: String = ""
var _current_stream_path: String = ""
var _is_playing: bool = false


func _init(p_mgr: ZxAudioManager = null) -> void:
	name = "KlScoreSequencer"
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio_manager = p_mgr
	load_configs("res://data/knight_lore/audio_score.json")


func _ready() -> void:
	if audio_manager == null:
		audio_manager = get_parent() as ZxAudioManager
	if _score_cfg.is_empty():
		load_configs("res://data/knight_lore/audio_score.json")
	if audio_manager != null and not audio_manager.music_stream_finished.is_connected(_on_music_stream_finished):
		audio_manager.music_stream_finished.connect(_on_music_stream_finished)


func load_configs(score_path: String, _legacy_audio_path: String = "") -> void:
	if not FileAccess.file_exists(score_path):
		return
	var f := FileAccess.open(score_path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_score_cfg = parsed as Dictionary


func play_cue(cue_name: String, loop_override: Variant = null) -> void:
	var cues: Dictionary = _score_cfg.get("cues", {}) as Dictionary
	if not cues.has(cue_name):
		push_warning("KlScoreSequencer: Cue '%s' not found" % cue_name)
		return

	var cue_data: Dictionary = cues[cue_name] as Dictionary
	var stream_path: String = str(cue_data.get("stream", ""))
	var should_loop: bool = bool(loop_override) if loop_override != null else bool(cue_data.get("loop", false))
	var vol_db: float = float(cue_data.get("volume_db", -5.0))
	var fade_s: float = float(cue_data.get("fade_s", 0.8))

	# Avoid restarting the exact same looping cue unnecessarily
	if _is_playing and _current_cue_name == cue_name and should_loop and audio_manager != null and audio_manager.is_music_playing():
		return

	_current_cue_name = cue_name
	_current_stream_path = stream_path
	_is_playing = true

	if audio_manager != null:
		if not audio_manager.music_stream_finished.is_connected(_on_music_stream_finished):
			audio_manager.music_stream_finished.connect(_on_music_stream_finished)
		var ok: bool = audio_manager.play_music_stream(stream_path, should_loop, vol_db, fade_s)
		if not ok:
			_is_playing = false


func stop_cue(fade_s: float = 0.4) -> void:
	_is_playing = false
	_current_cue_name = ""
	_current_stream_path = ""
	if audio_manager != null:
		audio_manager.stop_music(fade_s)


func is_playing(cue_name: String = "") -> bool:
	if not _is_playing:
		return false
	if cue_name.is_empty():
		return true
	return _current_cue_name == cue_name


func get_current_cue() -> String:
	return _current_cue_name


func _on_music_stream_finished(stream_path: String) -> void:
	if _is_playing and stream_path == _current_stream_path:
		var finished_cue: String = _current_cue_name
		_is_playing = false
		_current_cue_name = ""
		_current_stream_path = ""
		cue_finished.emit(finished_cue)
