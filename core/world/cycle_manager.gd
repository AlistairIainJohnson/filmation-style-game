class_name CycleManagerNode
extends Node
## Manages Filmation day/night meta-loop phases, emitting lighting and gameplay
## transformation events (e.g. boosted night jump clearance).

enum Phase { DAY, NIGHT }

signal phase_changed(new_phase: int, day_count: int)
signal cycle_progress_updated(phase: int, normalized_t: float)

@export var auto_advance: bool = false
@export var day_duration_sec: float = 45.0
@export var night_duration_sec: float = 35.0
@export var night_jump_height_multiplier: float = 1.22

var current_phase: Phase = Phase.DAY
var day_count: int = 1
var phase_elapsed: float = 0.0


func configure(cfg: Dictionary) -> void:
	auto_advance = bool(cfg.get("enabled", false))
	day_duration_sec = maxf(0.1, float(cfg.get("day_duration_sec", 45.0)))
	night_duration_sec = maxf(0.1, float(cfg.get("night_duration_sec", 35.0)))
	night_jump_height_multiplier = maxf(0.5, float(cfg.get("night_jump_height_multiplier", 1.22)))


func reset_cycle() -> void:
	current_phase = Phase.DAY
	day_count = 1
	phase_elapsed = 0.0


func get_current_duration() -> float:
	return night_duration_sec if current_phase == Phase.NIGHT else day_duration_sec


func get_jump_height_multiplier() -> float:
	return night_jump_height_multiplier if current_phase == Phase.NIGHT else 1.0


func set_phase(next_phase: Phase) -> void:
	var changed: bool = (current_phase != next_phase)
	current_phase = next_phase
	phase_elapsed = 0.0
	if changed:
		phase_changed.emit(current_phase, day_count)


func advance_time(delta: float) -> void:
	if delta <= 0.0:
		return
	phase_elapsed += delta
	var dur: float = get_current_duration()
	while phase_elapsed >= dur:
		phase_elapsed -= dur
		if current_phase == Phase.DAY:
			current_phase = Phase.NIGHT
		else:
			current_phase = Phase.DAY
			day_count += 1
		phase_changed.emit(current_phase, day_count)
		dur = get_current_duration()
	cycle_progress_updated.emit(current_phase, clampf(phase_elapsed / dur, 0.0, 1.0))


func _process(delta: float) -> void:
	if auto_advance:
		advance_time(delta)


func serialize_state() -> Dictionary:
	return {
		"current_phase": int(current_phase),
		"day_count": day_count,
		"phase_elapsed": phase_elapsed,
		"auto_advance": auto_advance
	}


func hydrate_state(data: Dictionary) -> void:
	current_phase = int(data.get("current_phase", Phase.DAY)) as Phase
	day_count = int(data.get("day_count", 1))
	phase_elapsed = float(data.get("phase_elapsed", 0.0))
	auto_advance = bool(data.get("auto_advance", auto_advance))
	phase_changed.emit(current_phase, day_count)
