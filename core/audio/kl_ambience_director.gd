class_name KlAmbienceDirector
extends Node
## Config-driven biome ambience & day/night soundscape director.
## Selects the appropriate pre-rendered stereo ambience stream (dungeon air/drips vs
## woodland day wind/birds vs woodland night breeze/crickets/owl) from audio_soundscapes.json
## and smoothly crossfades via ZxAudioManager without interrupting continuous loops.

var audio_manager: ZxAudioManager

var _soundscapes_cfg: Dictionary = {}
var _current_biome: String = "dungeon"
var _is_night: bool = false
var _active_stream_path: String = ""


func _init(p_mgr: ZxAudioManager = null) -> void:
	name = "KlAmbienceDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio_manager = p_mgr
	load_config("res://data/knight_lore/audio_soundscapes.json")


func _ready() -> void:
	if audio_manager == null:
		audio_manager = get_parent() as ZxAudioManager
	if _soundscapes_cfg.is_empty():
		load_config("res://data/knight_lore/audio_soundscapes.json")


func load_config(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_soundscapes_cfg = parsed as Dictionary


func set_biome(biome_id: String) -> void:
	_current_biome = biome_id
	_sync_ambience_stream()


func set_cycle(p_night: bool) -> void:
	_is_night = p_night
	_sync_ambience_stream()


func get_active_stream_path() -> String:
	return _active_stream_path


func _sync_ambience_stream() -> void:
	var biomes: Dictionary = _soundscapes_cfg.get("biomes", {}) as Dictionary
	if not biomes.has(_current_biome):
		return
	var b_data: Dictionary = biomes[_current_biome] as Dictionary
	var streams: Dictionary = b_data.get("ambience_streams", {}) as Dictionary
	var phase_key: String = "night" if _is_night else "day"
	var target_path: String = str(streams.get(phase_key, streams.get("day", "")))
	var vol_db: float = float(streams.get("volume_db", -5.0))
	if target_path.is_empty():
		return

	if target_path == _active_stream_path and audio_manager != null and audio_manager.is_ambience_playing():
		return

	_active_stream_path = target_path
	if audio_manager != null:
		audio_manager.play_ambience_stream(target_path, vol_db, 1.2)
