class_name KlPortcullisGate
extends AnimatableBody3D
## Config-driven Knight Lore portcullis gate (gate_ud_1, gate_ud_2, gate_*):
## only one gate moves per room at a time; 4 initial immediate drops then
## 1-in-32 chance/tick; accelerates downward and is lethal only while dropping.

enum GateState { RAISED, DROPPING, LOWERED, RISING }

signal slammed()

@export var entity_type_name: String = "gate_ud_1"
@export var simulation_active: bool = false

var behavior: String = "portcullis"
var params: Dictionary = {}
var entity_size: Vector3 = Vector3(1.5, 2.0, 0.125)
var director: KlRoomDirector = null
var gate_state: GateState = GateState.RAISED

var collision_shape: CollisionShape3D
var proxy_mesh: MeshInstance3D

var _low_y: float = 0.0
var _high_y: float = 2.0
var _vel_y: float = 0.0
var _rise_speed_mps: float = 0.875
var _drop_accel_mps2: float = -24.5
var _trigger_chance: float = 0.03125


func _init() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0


func configure(p_type_name: String, type_cfg: Dictionary, size: Vector3, start_pos: Vector3) -> void:
	entity_type_name = p_type_name
	behavior = str(type_cfg.get("behavior", "portcullis"))
	params = (type_cfg.get("params", {}) as Dictionary).duplicate(true)
	entity_size = size
	position = start_pos
	set_meta("kl_type", p_type_name)
	set_meta("kl_behavior", behavior)

	var raised_offset_m: float = float(params.get("raised_z_offset", 32.0)) / KnightLoreData.UNITS_PER_METER
	_low_y = 0.0
	_high_y = maxf(_low_y + raised_offset_m, start_pos.y)
	_trigger_chance = float(params.get("trigger_chance", 0.03125))
	gate_state = GateState.RAISED if start_pos.y >= (_high_y - 0.1) else GateState.LOWERED
	_vel_y = 0.0

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = entity_size
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(collision_shape)

	proxy_mesh = MeshInstance3D.new()
	proxy_mesh.name = "Mesh"
	proxy_mesh.layers = 1
	proxy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var box := BoxMesh.new()
	box.size = entity_size
	proxy_mesh.mesh = box
	proxy_mesh.position = Vector3(0.0, entity_size.y * 0.5, 0.0)
	add_child(proxy_mesh)


func bind_director(p_director: KlRoomDirector) -> void:
	director = p_director
	if director != null:
		_rise_speed_mps = director.kl_speed_to_mps(float(params.get("rise_net_dz", 1.0)))
		_drop_accel_mps2 = director.kl_accel_to_mps2(float(params.get("drop_accel_dz", -2.0)))


func is_lethal_now() -> bool:
	return gate_state == GateState.DROPPING


func _physics_process(delta: float) -> void:
	if not simulation_active or director == null:
		return

	match gate_state:
		GateState.RAISED:
			if director.active_moving_portcullis == null:
				var should_drop: bool = false
				if director.portcullis_fast_drops_remaining > 0:
					director.portcullis_fast_drops_remaining -= 1
					should_drop = true
				elif director.should_trigger_per_tick(_trigger_chance, delta):
					should_drop = true
				if should_drop:
					director.active_moving_portcullis = self
					gate_state = GateState.DROPPING
					_vel_y = 0.0
					if not is_in_group("kl_lethal_hazards"):
						add_to_group("kl_lethal_hazards")
		GateState.DROPPING:
			_vel_y = maxf(-9.0, _vel_y + _drop_accel_mps2 * delta)
			position.y += _vel_y * delta
			if position.y <= _low_y:
				position.y = _low_y
				_vel_y = 0.0
				gate_state = GateState.LOWERED
				if is_in_group("kl_lethal_hazards"):
					remove_from_group("kl_lethal_hazards")
				if director.active_moving_portcullis == self:
					director.active_moving_portcullis = null
				slammed.emit()
		GateState.LOWERED:
			if director.active_moving_portcullis == null and director.should_trigger_per_tick(_trigger_chance, delta):
				director.active_moving_portcullis = self
				gate_state = GateState.RISING
		GateState.RISING:
			position.y += _rise_speed_mps * delta
			if position.y >= _high_y:
				position.y = _high_y
				gate_state = GateState.RAISED
				if director.active_moving_portcullis == self:
					director.active_moving_portcullis = null
				slammed.emit()
