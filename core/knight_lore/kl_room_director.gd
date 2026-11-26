class_name KlRoomDirector
extends Node
## Room-level coordinator for Knight Lore entities: converts 14 Hz ZX units/tick
## into metric speeds & accelerations, enforces room-wide mutexes (falling spike
## ball, moving portcullis), and answers player-form / near-arch queries.

var room_id: int = 47
var room_dims: Vector3 = Vector3(8.0, 6.0, 8.0)
var is_odd_room: bool = true
var session: KnightLoreSession
var player: PlayerController
var entities_cfg: Dictionary = {}
var tick_rate_hz: float = 14.0
var rng := RandomNumberGenerator.new()

var active_falling_spike_ball: Node3D = null
var active_moving_portcullis: Node3D = null
var portcullis_fast_drops_remaining: int = 4

var _arch_root: Node3D
var _entities_root: Node3D
var _doorways_root: Node3D


func activate_room(
	p_room_id: int,
	p_room_dims: Vector3,
	arch_root: Node3D,
	entities_root: Node3D,
	doorways_root: Node3D,
	p_session: KnightLoreSession,
	p_player: PlayerController,
	p_entities_cfg: Dictionary,
	rng_seed: int = -1
) -> void:
	room_id = p_room_id
	room_dims = p_room_dims
	is_odd_room = ((p_room_id & 1) == 1)
	_arch_root = arch_root
	_entities_root = entities_root
	_doorways_root = doorways_root
	session = p_session
	player = p_player
	entities_cfg = p_entities_cfg

	var sim: Dictionary = entities_cfg.get("simulation_constants", {}) as Dictionary
	tick_rate_hz = float(sim.get("tick_rate_hz", 14.0))

	var fg_types: Dictionary = entities_cfg.get("foreground_types", {}) as Dictionary
	var gate_cfg: Dictionary = fg_types.get("26", {}) as Dictionary
	var gate_params: Dictionary = gate_cfg.get("params", {}) as Dictionary
	portcullis_fast_drops_remaining = int(gate_params.get("initial_fast_drops", 4))

	active_falling_spike_ball = null
	active_moving_portcullis = null

	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	_bind_subtree(arch_root)
	_bind_subtree(entities_root)


func _bind_subtree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	for child: Node in root.get_children():
		if child.has_method("bind_director"):
			child.call("bind_director", self)
		if child is KlPortcullisGate:
			var g: KlPortcullisGate = child as KlPortcullisGate
			if not g.slammed.is_connected(_on_gate_slammed):
				g.slammed.connect(_on_gate_slammed)
		elif child is KlHazardEntity:
			var h: KlHazardEntity = child as KlHazardEntity
			if not h.stepped.is_connected(_on_hazard_stepped):
				h.stepped.connect(_on_hazard_stepped)
		if "simulation_active" in child:
			child.set("simulation_active", true)


signal portcullis_slammed()
signal entity_stepped(pos: Vector3)


func _on_gate_slammed() -> void:
	portcullis_slammed.emit()


func _on_hazard_stepped(pos: Vector3) -> void:
	entity_stepped.emit(pos)


func deactivate_hazards() -> void:
	_deactivate_subtree(_arch_root)
	_deactivate_subtree(_entities_root)


func _deactivate_subtree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	for child: Node in root.get_children():
		if child is KlHazardEntity or child is KlPortcullisGate:
			child.set("simulation_active", false)
			if child.is_in_group("kl_lethal_hazards"):
				child.remove_from_group("kl_lethal_hazards")


func kl_units_to_meters(units: float) -> float:
	return units / KnightLoreData.UNITS_PER_METER


func kl_speed_to_mps(units_per_tick: float) -> float:
	return units_per_tick * tick_rate_hz / KnightLoreData.UNITS_PER_METER


func kl_accel_to_mps2(units_per_tick2: float) -> float:
	return units_per_tick2 * tick_rate_hz * tick_rate_hz / KnightLoreData.UNITS_PER_METER


func should_trigger_per_tick(prob_per_tick: float, delta: float) -> bool:
	if prob_per_tick <= 0.0 or delta <= 0.0:
		return false
	if prob_per_tick >= 1.0:
		return true
	var ticks: float = maxf(delta * tick_rate_hz, 0.0)
	var frame_p: float = 1.0 - pow(1.0 - clampf(prob_per_tick, 0.0, 1.0), ticks)
	return rng.randf() < frame_p


func is_player_wulf() -> bool:
	return session != null and session.is_wulf


func is_spike_ball_drop_disabled() -> bool:
	return session != null and session.disable_spike_ball_drop


func is_player_near_arch() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var p: Vector3 = player.global_position
	if p.x < 0.65 or p.x > room_dims.x - 0.65 or p.z < 0.65 or p.z > room_dims.z - 0.65:
		return true
	if _doorways_root != null and is_instance_valid(_doorways_root):
		for child: Node in _doorways_root.get_children():
			if child is Area3D and child.name.begins_with("Exit_"):
				var exit_pos: Vector3 = (child as Area3D).global_position
				if Vector2(p.x - exit_pos.x, p.z - exit_pos.z).length() <= 1.35:
					return true
	return false


func is_inside_room_xz(pos: Vector3, margin_x: float, margin_z: float) -> bool:
	return (
		pos.x >= margin_x
		and pos.x <= room_dims.x - margin_x
		and pos.z >= margin_z
		and pos.z <= room_dims.z - margin_z
	)
