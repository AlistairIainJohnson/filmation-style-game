class_name WorldManagerNode
extends Node
## Manages the 16x16 Filmation world graph, cooperative threaded neighbor preloading,
## persistent room state hydration across flip-screen transitions, and world saves.

signal room_loaded(room_id: Vector2i, build_result: Dictionary)
signal room_transition_started(from_room: Vector2i, to_room: Vector2i, exit_dir: String)
signal item_collected(entity_id: String, item_kind: String)

const OPPOSITE_DIR: Dictionary = {
	"north": "south",
	"south": "north",
	"east": "west",
	"west": "east"
}

var manifest: Dictionary = {}
var world_config: Dictionary = {}
var room_states: Dictionary = {}
var player_inventory: Array[String] = []
var current_room_id: Vector2i = Vector2i(-1, -1)
var current_build: Dictionary = {}
var active_room_node: Node3D
var active_player: PlayerController
var room_container: Node3D
var base_player_jump_height: float = 1.35

var _pending_scene_loads: Dictionary = {}
var _cached_scenes: Dictionary = {}
var _cached_room_json: Dictionary = {}
var _transition_lock: bool = false
var _transition_cooldown: float = 0.0
var _cycle_connected: bool = false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	_ensure_cycle_connection()
	_ensure_fade_overlay()


func _ensure_cycle_connection() -> void:
	if _cycle_connected:
		return
	var cycle: Node = get_node_or_null("/root/CycleManager")
	if cycle != null and cycle.has_signal("phase_changed"):
		if not cycle.phase_changed.is_connected(_on_cycle_phase_changed):
			cycle.phase_changed.connect(_on_cycle_phase_changed)
		_cycle_connected = true


func _ensure_fade_overlay() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "WorldFadeLayer"
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


func _process(delta: float) -> void:
	if _transition_cooldown > 0.0:
		_transition_cooldown = maxf(0.0, _transition_cooldown - delta)
	poll_threaded_loads()


func load_world_manifest(graph_path: String = "res://data/world_graph.json") -> bool:
	_ensure_cycle_connection()
	var parsed: Dictionary = RoomBuilder.load_json_dict(graph_path)
	if parsed.is_empty():
		return false

	world_config = parsed
	manifest.clear()
	_cached_room_json.clear()

	for entry: Variant in (parsed.get("rooms", []) as Array):
		if not (entry is Dictionary):
			continue
		var rdict: Dictionary = entry as Dictionary
		var id_arr: Array = rdict.get("id", [0, 0]) as Array
		var rid := Vector2i(int(id_arr[0]), int(id_arr[1]))
		manifest[rid] = rdict

	var cycle: Node = get_node_or_null("/root/CycleManager")
	if cycle != null and parsed.has("cycle"):
		cycle.call("configure", parsed["cycle"] as Dictionary)

	return not manifest.is_empty()


func set_room_container(container: Node3D) -> void:
	room_container = container


func reset_world_state() -> void:
	room_states.clear()
	player_inventory.clear()
	current_room_id = Vector2i(-1, -1)
	current_build.clear()
	_transition_lock = false
	_transition_cooldown = 0.0
	_clear_active_room()


func _clear_active_room() -> void:
	active_player = null
	if active_room_node != null and is_instance_valid(active_room_node):
		if active_room_node.get_parent() != null:
			active_room_node.get_parent().remove_child(active_room_node)
		active_room_node.free()
	active_room_node = null


func preload_neighbors(room_id: Vector2i) -> void:
	if not manifest.has(room_id):
		return
	var rmeta: Dictionary = manifest[room_id] as Dictionary
	var exits: Dictionary = rmeta.get("exits", {}) as Dictionary
	for target_var: Variant in exits.values():
		if not (target_var is Array):
			continue
		var t_arr: Array = target_var as Array
		var neighbor_id := Vector2i(int(t_arr[0]), int(t_arr[1]))
		if not manifest.has(neighbor_id):
			continue
		var nmeta: Dictionary = manifest[neighbor_id] as Dictionary
		var json_path: String = str(nmeta.get("json_path", ""))
		if not json_path.is_empty() and not _cached_room_json.has(json_path):
			_cached_room_json[json_path] = RoomBuilder.load_json_dict(json_path)

		var scene_path: String = str(nmeta.get("scene_path", "res://core/world/chamber_shell.tscn"))
		if not scene_path.is_empty() and not _cached_scenes.has(scene_path) and not _pending_scene_loads.has(scene_path):
			var err: Error = ResourceLoader.load_threaded_request(scene_path)
			if err == OK:
				_pending_scene_loads[scene_path] = true
			else:
				push_warning("WorldManager: load_threaded_request failed for %s (%s)" % [scene_path, error_string(err)])


func poll_threaded_loads() -> void:
	if _pending_scene_loads.is_empty():
		return
	var paths: Array = _pending_scene_loads.keys()
	for p_var: Variant in paths:
		var path: String = str(p_var)
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var res: Resource = ResourceLoader.load_threaded_get(path)
				if res is PackedScene:
					_cached_scenes[path] = res as PackedScene
				_pending_scene_loads.erase(path)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("WorldManager: Threaded load failed for " + path)
				_pending_scene_loads.erase(path)


func is_scene_preloaded(scene_path: String) -> bool:
	return _cached_scenes.has(scene_path)


func save_current_room_state() -> void:
	if active_room_node == null or not is_instance_valid(active_room_node):
		return
	if current_room_id.x < 0 or current_room_id.y < 0:
		return

	var saved_entities: Dictionary = {}
	var entity_map: Dictionary = current_build.get("entity_map", {}) as Dictionary
	for eid_var: Variant in entity_map.keys():
		var eid: String = str(eid_var)
		var node: Node = entity_map[eid] as Node
		if node == null or not is_instance_valid(node):
			continue
		var is_persistent: bool = bool(node.get("persistent")) if "persistent" in node else bool(node.get_meta("persistent", true))
		if not is_persistent:
			continue
		var state: Dictionary = PuzzleEntity3D.serialize_node(node)
		if not state.is_empty():
			saved_entities[eid] = state
	room_states[current_room_id] = saved_entities


func hydrate_room_state(room_id: Vector2i) -> void:
	if not room_states.has(room_id):
		return
	var saved_entities: Dictionary = room_states[room_id] as Dictionary
	var entity_map: Dictionary = current_build.get("entity_map", {}) as Dictionary
	for eid_var: Variant in saved_entities.keys():
		var eid: String = str(eid_var)
		if not entity_map.has(eid):
			continue
		var node: Node = entity_map[eid] as Node
		var state: Dictionary = saved_entities[eid] as Dictionary
		PuzzleEntity3D.hydrate_node(node, state)


func load_room(room_id: Vector2i, spawn_dir: String = "") -> bool:
	if not manifest.has(room_id):
		push_error("WorldManager: Unknown room_id " + str(room_id))
		return false
	if room_container == null or not is_instance_valid(room_container):
		push_error("WorldManager: room_container must be set before load_room()")
		return false

	save_current_room_state()
	_clear_active_room()

	var rmeta: Dictionary = manifest[room_id] as Dictionary
	var scene_path: String = str(rmeta.get("scene_path", "res://core/world/chamber_shell.tscn"))
	var packed: PackedScene
	if _cached_scenes.has(scene_path):
		packed = _cached_scenes[scene_path] as PackedScene
	else:
		packed = ResourceLoader.load(scene_path) as PackedScene
		if packed != null:
			_cached_scenes[scene_path] = packed
	if packed == null:
		push_error("WorldManager: Failed to load chamber shell scene: " + scene_path)
		return false

	var json_path: String = str(rmeta.get("json_path", ""))
	var room_data: Dictionary
	if _cached_room_json.has(json_path):
		room_data = _cached_room_json[json_path] as Dictionary
	else:
		room_data = RoomBuilder.load_json_dict(json_path)
		if not room_data.is_empty():
			_cached_room_json[json_path] = room_data
	if room_data.is_empty():
		return false

	active_room_node = packed.instantiate() as Node3D
	active_room_node.name = "Room_%02d_%02d" % [room_id.x, room_id.y]
	room_container.add_child(active_room_node)

	var lighting_preset: String = _get_lighting_preset_for_room(rmeta)
	var builder := RoomBuilder.new()
	current_build = builder.build_room_into(active_room_node, room_data, lighting_preset)
	current_room_id = room_id

	_wire_room_entities(current_build.get("entity_map", {}) as Dictionary)
	hydrate_room_state(room_id)
	_wire_doorways(current_build.get("doorways_root") as Node3D)
	_spawn_player_in_room(spawn_dir)

	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	var arch_root: Node = current_build.get("architecture_root") as Node
	if lighting != null and arch_root != null:
		lighting.call_deferred("bake_gi_if_supported", arch_root)

	preload_neighbors(room_id)
	room_loaded.emit(room_id, current_build)
	return true


func _get_lighting_preset_for_room(rmeta: Dictionary) -> String:
	var cycle: Node = get_node_or_null("/root/CycleManager")
	if cycle != null and int(cycle.get("current_phase")) == CycleManagerNode.Phase.NIGHT:
		return str(rmeta.get("lighting_preset_night", "castle_moonlight_night"))
	return str(rmeta.get("lighting_preset_day", "castle_stone_skylight"))


func _wire_room_entities(entity_map: Dictionary) -> void:
	for node_var: Variant in entity_map.values():
		if node_var is CollectibleItem:
			var item: CollectibleItem = node_var as CollectibleItem
			if not item.collected.is_connected(_on_collectible_collected):
				item.collected.connect(_on_collectible_collected)


func _on_collectible_collected(eid: String, kind: String) -> void:
	if not player_inventory.has(eid):
		player_inventory.append(eid)
	item_collected.emit(eid, kind)


func _wire_doorways(doorways_root: Node3D) -> void:
	if doorways_root == null:
		return
	for child: Node in doorways_root.get_children():
		if child is Area3D and child.name.begins_with("Exit_"):
			var area: Area3D = child as Area3D
			var dir_name: String = str(area.get_meta("direction", ""))
			var target_room: Vector2i = area.get_meta("target_room", Vector2i(-1, -1))
			area.body_entered.connect(_on_doorway_body_entered.bind(dir_name, target_room))


func _on_doorway_body_entered(body: Node3D, dir_name: String, target_room: Vector2i) -> void:
	if not (body is PlayerController):
		return
	if _transition_lock or _transition_cooldown > 0.0:
		return
	call_deferred("transition_to_room", dir_name, target_room, false)


func _spawn_player_in_room(spawn_dir: String) -> void:
	active_player = PlayerController.new()
	active_player.name = "Player"

	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		active_player.set_camera_rig(cam_rig)

	var cycle: Node = get_node_or_null("/root/CycleManager")
	var mult: float = float(cycle.call("get_jump_height_multiplier")) if cycle != null else 1.0
	var is_night: bool = cycle != null and int(cycle.get("current_phase")) == CycleManagerNode.Phase.NIGHT
	active_player.set_night_form(is_night)
	active_player.jump_height = base_player_jump_height * mult
	active_player.recompute_jump_constants()

	var spawn_pos: Vector3 = _resolve_spawn_position(spawn_dir)
	active_player.position = spawn_pos
	active_room_node.add_child(active_player)
	active_player.reset_physics_interpolation()
	active_player.sync_shader_world_pos()
	if active_player.drop_shadow != null:
		active_player.drop_shadow.call_deferred("update_shadow")


func _resolve_spawn_position(spawn_dir: String) -> Vector3:
	var doorways: Node3D = current_build.get("doorways_root") as Node3D
	if doorways != null:
		if not spawn_dir.is_empty():
			var marker: Marker3D = doorways.get_node_or_null("Spawn_" + spawn_dir) as Marker3D
			if marker != null:
				return marker.position
		for child: Node in doorways.get_children():
			if child is Marker3D:
				return (child as Marker3D).position
	var dims: Vector3 = current_build.get("room_dims", Vector3(12.0, 6.0, 12.0))
	return Vector3(dims.x * 0.5, 0.0, dims.z * 0.5)


func transition_to_room(exit_dir: String, target_room: Vector2i, instant: bool = false) -> void:
	if _transition_lock or not manifest.has(target_room):
		return
	_transition_lock = true
	room_transition_started.emit(current_room_id, target_room, exit_dir)

	var incoming_spawn: String = str(OPPOSITE_DIR.get(exit_dir, ""))
	if instant or DisplayServer.get_name() == "headless" or _fade_rect == null:
		load_room(target_room, incoming_spawn)
		_transition_cooldown = 0.35
		_transition_lock = false
		return

	var tween_out: Tween = create_tween()
	tween_out.tween_property(_fade_rect, "color:a", 1.0, 0.14)
	await tween_out.finished

	load_room(target_room, incoming_spawn)
	_transition_cooldown = 0.35

	var tween_in: Tween = create_tween()
	tween_in.tween_property(_fade_rect, "color:a", 0.0, 0.16)
	await tween_in.finished
	_transition_lock = false


func _on_cycle_phase_changed(_new_phase: int, _day_count: int) -> void:
	if active_room_node == null or not is_instance_valid(active_room_node):
		return
	if not manifest.has(current_room_id):
		return

	var rmeta: Dictionary = manifest[current_room_id] as Dictionary
	var preset_name: String = _get_lighting_preset_for_room(rmeta)
	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	var room_dims: Vector3 = current_build.get("room_dims", Vector3(12.0, 6.0, 12.0))
	if lighting != null:
		var preset: Dictionary = DioramaLighting.load_preset_by_name(preset_name)
		lighting.apply_preset(preset, room_dims)
		var arch_root: Node = current_build.get("architecture_root") as Node
		if arch_root != null:
			lighting.call_deferred("bake_gi_if_supported", arch_root)

	if active_player != null and is_instance_valid(active_player):
		var cycle: Node = get_node_or_null("/root/CycleManager")
		var mult: float = float(cycle.call("get_jump_height_multiplier")) if cycle != null else 1.0
		var is_night: bool = cycle != null and int(cycle.get("current_phase")) == CycleManagerNode.Phase.NIGHT
		active_player.set_night_form(is_night)
		active_player.jump_height = base_player_jump_height * mult
		active_player.recompute_jump_constants()


func serialize_world_save() -> Dictionary:
	save_current_room_state()
	var serialized_rooms: Dictionary = {}
	for rid_var: Variant in room_states.keys():
		var rid: Vector2i = rid_var as Vector2i
		serialized_rooms["%d,%d" % [rid.x, rid.y]] = (room_states[rid] as Dictionary).duplicate(true)

	var cycle: Node = get_node_or_null("/root/CycleManager")
	var cycle_state: Dictionary = cycle.call("serialize_state") as Dictionary if cycle != null else {}
	var p_pos: Array = [0.0, 0.0, 0.0]
	if active_player != null and is_instance_valid(active_player):
		p_pos = [active_player.global_position.x, active_player.global_position.y, active_player.global_position.z]

	return {
		"current_room": [current_room_id.x, current_room_id.y],
		"player_pos": p_pos,
		"player_inventory": player_inventory.duplicate(),
		"room_states": serialized_rooms,
		"cycle": cycle_state
	}


func hydrate_world_save(save_data: Dictionary) -> bool:
	if save_data.is_empty():
		return false

	room_states.clear()
	var saved_rooms: Dictionary = save_data.get("room_states", {}) as Dictionary
	for key_var: Variant in saved_rooms.keys():
		var parts: PackedStringArray = str(key_var).split(",")
		if parts.size() == 2:
			var rid := Vector2i(int(parts[0]), int(parts[1]))
			room_states[rid] = (saved_rooms[key_var] as Dictionary).duplicate(true)

	player_inventory.clear()
	for item_var: Variant in (save_data.get("player_inventory", []) as Array):
		player_inventory.append(str(item_var))

	var cycle: Node = get_node_or_null("/root/CycleManager")
	if cycle != null and save_data.has("cycle"):
		cycle.call("hydrate_state", save_data["cycle"] as Dictionary)

	var cur_arr: Array = save_data.get("current_room", [8, 8]) as Array
	var target_rid := Vector2i(int(cur_arr[0]), int(cur_arr[1]))
	if not load_room(target_rid, ""):
		return false

	if active_player != null and save_data.has("player_pos"):
		var p_arr: Array = save_data["player_pos"] as Array
		if p_arr.size() >= 3:
			active_player.global_position = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
			active_player.reset_physics_interpolation()
			active_player.sync_shader_world_pos()
	return true


func save_to_file(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(serialize_world_save(), "\t"))
	return OK


func load_from_file(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return ERR_PARSE_ERROR
	return OK if hydrate_world_save(parsed as Dictionary) else ERR_CANT_RESOLVE
