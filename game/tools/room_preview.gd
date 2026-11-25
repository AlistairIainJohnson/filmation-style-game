extends Node3D
## Live hot-reloading room previewer for rapid Filmation level design iteration.
## Hotkeys: F1 = True Iso / 2:1 Dimetric, F2 = Day / Night, F3 = 1m Grid + Jump Ruler, F4 = Next Room.

@export var room_json_path: String = "res://data/rooms/room_08_08.json"
@export var hot_reload_interval: float = 0.5

var preview_root: Node3D
var grid_overlay: MeshInstance3D
var player: PlayerController
var current_build: Dictionary = {}

const PREVIEW_OPPOSITE_DIR: Dictionary = {
	"north": "south",
	"south": "north",
	"east": "west",
	"west": "east"
}

var _camera_mode: DioramaCameraRig.ProjectionMode = DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
var _lighting_preset: String = "castle_stone_skylight"
var _grid_visible: bool = false
var _last_mtime: int = 0
var _poll_timer: float = 0.0
var _world_rooms: Array[String] = []
var _world_rooms_by_id: Dictionary = {}
var _room_idx: int = 0
var _kl_mode: bool = false
var _kl_room_ids: Array[int] = []
var _kl_idx: int = 0
var _kl_data: KnightLoreData
var _hud_label: Label
var _transition_lock: bool = false
var _transition_cooldown: float = 0.0
var _last_safe_spawn: Vector3 = Vector3(4.0, 0.0, 4.0)
var _room_builder: RoomBuilder = RoomBuilder.new()


func _ready() -> void:
	var env_kl: String = OS.get_environment("FILMATION_KL_ROOM")
	if not env_kl.is_empty():
		_kl_mode = true
	var env_room: String = OS.get_environment("FILMATION_PREVIEW_ROOM")
	if not env_room.is_empty():
		room_json_path = env_room
	var env_cam: String = OS.get_environment("FILMATION_CAMERA_MODE")
	if not env_cam.is_empty():
		_camera_mode = DioramaCameraRig.mode_from_string(env_cam)
	var env_lit: String = OS.get_environment("FILMATION_LIGHTING_PRESET")
	if not env_lit.is_empty():
		_lighting_preset = env_lit
	if OS.get_environment("FILMATION_PREVIEW_GRID") == "1":
		_grid_visible = true

	_load_world_room_list()
	_load_knight_lore_list(env_kl)
	_ensure_hud()
	reload_room()


func _load_knight_lore_list(initial_room_str: String) -> void:
	_kl_data = KnightLoreData.load_default()
	if _kl_data == null:
		return
	_kl_room_ids = _kl_data.get_room_ids()
	var target_id: int = 136 if initial_room_str.is_empty() else int(initial_room_str)
	if _kl_room_ids.has(target_id):
		_kl_idx = _kl_room_ids.find(target_id)
	elif not _kl_room_ids.is_empty():
		_kl_idx = 0


func _load_world_room_list() -> void:
	_world_rooms.clear()
	_world_rooms_by_id.clear()
	var wg: Dictionary = RoomBuilder.load_json_dict("res://data/world_graph.json")
	for entry: Variant in (wg.get("rooms", []) as Array):
		if entry is Dictionary:
			var rdict: Dictionary = entry as Dictionary
			var p: String = str(rdict.get("json_path", ""))
			if not p.is_empty():
				var idx: int = _world_rooms.size()
				_world_rooms.append(p)
				var id_arr: Array = rdict.get("id", []) as Array
				if id_arr.size() >= 2:
					_world_rooms_by_id[Vector2i(int(id_arr[0]), int(id_arr[1]))] = idx
	if _world_rooms.has(room_json_path):
		_room_idx = _world_rooms.find(room_json_path)


func _ensure_hud() -> void:
	if get_node_or_null("PreviewHUD") != null:
		return
	var canvas := CanvasLayer.new()
	canvas.name = "PreviewHUD"
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_hud_label = Label.new()
	_hud_label.name = "HudLabel"
	margin.add_child(_hud_label)
	panel.add_child(margin)
	canvas.add_child(panel)
	add_child(canvas)


func reload_room(spawn_dir: String = "") -> void:
	if preview_root != null and is_instance_valid(preview_root):
		remove_child(preview_root)
		preview_root.free()
	preview_root = Node3D.new()
	preview_root.name = "PreviewRoot"
	add_child(preview_root)

	var cam_mode_str: String = "dimetric_2_1" if _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 else "true_isometric"
	if _kl_mode and _kl_data != null and not _kl_room_ids.is_empty():
		current_build = _room_builder.build_knight_lore_room(preview_root, _kl_room_ids[_kl_idx], _kl_data, _lighting_preset, cam_mode_str)
	else:
		current_build = _room_builder.build_room_from_path(preview_root, room_json_path, _lighting_preset, cam_mode_str)
	if current_build.is_empty():
		return

	_last_mtime = FileAccess.get_modified_time(room_json_path)

	player = PlayerController.new()
	player.name = "PreviewPlayer"
	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		player.set_camera_rig(cam_rig)

	var room_dims: Vector3 = current_build.get("room_dims", Vector3(12.0, 6.0, 12.0))
	var doorways: Node3D = current_build.get("doorways_root") as Node3D
	var spawn_pos: Vector3 = _resolve_preview_spawn(doorways, spawn_dir, room_dims)
	var env_pos: String = OS.get_environment("FILMATION_PLAYER_POS")
	if spawn_dir.is_empty() and not env_pos.is_empty():
		var parts: PackedStringArray = env_pos.split(",")
		if parts.size() == 3:
			spawn_pos = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	if OS.get_environment("FILMATION_PLAYER_FREEZE") == "1":
		player.enable_player_input = false
	_last_safe_spawn = spawn_pos
	player.position = spawn_pos
	preview_root.add_child(player)
	player.reset_physics_interpolation()
	player.sync_shader_world_pos()
	if player.drop_shadow != null:
		player.drop_shadow.call_deferred("update_shadow")

	_wire_preview_doorways(doorways)

	_build_grid_overlay(room_dims, spawn_pos)
	_update_hud()


func _resolve_preview_spawn(doorways: Node3D, spawn_dir: String, room_dims: Vector3) -> Vector3:
	if doorways != null:
		if not spawn_dir.is_empty():
			var preferred: Marker3D = doorways.get_node_or_null("Spawn_" + spawn_dir) as Marker3D
			if preferred != null:
				return preferred.position
		var first_any: Marker3D = null
		for child: Node in doorways.get_children():
			if child is Marker3D:
				var m: Marker3D = child as Marker3D
				if first_any == null:
					first_any = m
				if m.position.y < 0.5:
					return m.position
		if first_any != null:
			return first_any.position
	return Vector3(room_dims.x * 0.5, 0.0, room_dims.z * 0.5)


func _wire_preview_doorways(doorways: Node3D) -> void:
	if doorways == null:
		return
	for child: Node in doorways.get_children():
		if child is Area3D and child.name.begins_with("Exit_"):
			var area: Area3D = child as Area3D
			area.body_entered.connect(_on_preview_exit_entered.bind(area))


func _on_preview_exit_entered(body: Node3D, exit_area: Area3D) -> void:
	if not (body is PlayerController):
		return
	if _transition_lock or _transition_cooldown > 0.0:
		return
	var dir_name: String = str(exit_area.get_meta("direction", ""))
	var target_rid: int = int(exit_area.get_meta("target_room_id", -1))
	var target_vec: Vector2i = exit_area.get_meta("target_room", Vector2i(-1, -1))
	call_deferred("transition_via_doorway", dir_name, target_rid, target_vec)


func transition_via_doorway(dir_name: String, target_rid: int, target_vec: Vector2i = Vector2i(-1, -1)) -> void:
	if _transition_lock:
		return
	var opposite_dir: String = str(PREVIEW_OPPOSITE_DIR.get(dir_name, ""))
	if _kl_mode and _kl_data != null and not _kl_room_ids.is_empty():
		if not _kl_room_ids.has(target_rid):
			return
		_transition_lock = true
		_kl_idx = _kl_room_ids.find(target_rid)
		_transition_cooldown = 0.35
		reload_room(opposite_dir)
		_transition_lock = false
		return

	if _world_rooms_by_id.has(target_vec):
		_transition_lock = true
		_room_idx = int(_world_rooms_by_id[target_vec])
		room_json_path = _world_rooms[_room_idx]
		_transition_cooldown = 0.35
		reload_room(opposite_dir)
		_transition_lock = false


func _build_grid_overlay(room_dims: Vector3, ruler_pos: Vector3) -> void:
	var imm := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.85, 0.95, 0.9)
	mat.vertex_color_use_as_albedo = true

	var w: int = int(room_dims.x)
	var d: int = int(room_dims.z)
	var y: float = 0.02

	imm.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for x: int in range(w + 1):
		imm.surface_set_color(Color(0.25, 0.85, 0.95, 0.75))
		imm.surface_add_vertex(Vector3(float(x), y, 0.0))
		imm.surface_add_vertex(Vector3(float(x), y, float(d)))
	for z: int in range(d + 1):
		imm.surface_set_color(Color(0.25, 0.85, 0.95, 0.75))
		imm.surface_add_vertex(Vector3(0.0, y, float(z)))
		imm.surface_add_vertex(Vector3(float(w), y, float(z)))

	# 1.27m simulated jump-height clearance ruler near spawn
	var rx: float = clampf(ruler_pos.x + 0.65, 0.5, float(w) - 0.5)
	var rz: float = clampf(ruler_pos.z, 0.5, float(d) - 0.5)
	imm.surface_set_color(Color(1.0, 0.82, 0.20, 1.0))
	imm.surface_add_vertex(Vector3(rx, 0.02, rz))
	imm.surface_add_vertex(Vector3(rx, 1.27, rz))
	imm.surface_add_vertex(Vector3(rx - 0.25, 1.27, rz))
	imm.surface_add_vertex(Vector3(rx + 0.25, 1.27, rz))
	imm.surface_add_vertex(Vector3(rx - 0.18, 1.0, rz))
	imm.surface_add_vertex(Vector3(rx + 0.18, 1.0, rz))
	imm.surface_end()

	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "GridAndRulerOverlay"
	grid_overlay.mesh = imm
	grid_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid_overlay.visible = _grid_visible
	preview_root.add_child(grid_overlay)


func _update_hud() -> void:
	if _hud_label == null:
		return
	var room_data: Dictionary = RoomBuilder.load_json_dict(room_json_path)
	var rname: String = str(room_data.get("name", room_json_path.get_file()))
	var rid: Variant = room_data.get("room_id", [0, 0])
	var cam_str: String = "2:1 Dimetric (-30.0°)" if _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 else "True Iso (-35.2644°)"
	if _kl_mode and _kl_data != null and not _kl_room_ids.is_empty():
		var kl_rid: int = _kl_room_ids[_kl_idx]
		var r: Dictionary = _kl_data.get_room(kl_rid)
		var kind_str: String = "Forest" if _kl_data.is_forest_room(kl_rid) else "Stone"
		var dims: Vector3 = _kl_data.get_room_dims_meters(kl_rid)
		var ex_keys: PackedStringArray = PackedStringArray()
		for k: Variant in (current_build.get("exits", {}) as Dictionary).keys():
			ex_keys.append(str(k).to_upper().left(1))
		_hud_label.text = "KL Room #%d (%d,%d) | %s | %s | %.0fx%.0fm | Exits:[%s] | %s | %s | Grid:%s\n[F1] Proj  [F2] Day/Night  [F3] Grid  [F4/Shift+F4] Prev/Next (%d/128)  [F5] KL/Demo" % [
			kl_rid,
			int(r.get("grid_x", 0)),
			int(r.get("grid_y", 0)),
			str(r.get("ink_color_name", "")),
			kind_str,
			dims.x,
			dims.z,
			",".join(ex_keys),
			cam_str,
			_lighting_preset,
			"ON" if _grid_visible else "OFF",
			_kl_idx + 1
		]
	else:
		_hud_label.text = "%s %s | %s | %s | Grid:%s\n[F1] Projection  [F2] Day/Night  [F3] Grid+Ruler  [F4] Next Room  [F5] KL 128-Room" % [
			rname,
			str(rid),
			cam_str,
			_lighting_preset,
			"ON" if _grid_visible else "OFF"
		]


func toggle_camera_mode() -> void:
	if _camera_mode == DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC:
		_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1
	else:
		_camera_mode = DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		cam_rig.set_projection_mode(_camera_mode)
	_update_hud()


func toggle_lighting_preset() -> void:
	_lighting_preset = "castle_moonlight_night" if _lighting_preset == "castle_stone_skylight" else "castle_stone_skylight"
	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	var room_dims: Vector3 = current_build.get("room_dims", Vector3(12.0, 6.0, 12.0))
	if lighting != null:
		lighting.apply_preset(DioramaLighting.load_preset_by_name(_lighting_preset), room_dims)
	_update_hud()


func toggle_grid_overlay() -> void:
	_grid_visible = not _grid_visible
	if grid_overlay != null:
		grid_overlay.visible = _grid_visible
	_update_hud()


func cycle_next_room(step_dir: int = 1) -> void:
	if _kl_mode and not _kl_room_ids.is_empty():
		_kl_idx = posmod(_kl_idx + step_dir, _kl_room_ids.size())
		reload_room()
		return
	if _world_rooms.is_empty():
		return
	_room_idx = posmod(_room_idx + step_dir, _world_rooms.size())
	room_json_path = _world_rooms[_room_idx]
	reload_room()


func toggle_kl_mode() -> void:
	if _kl_data == null or _kl_room_ids.is_empty():
		return
	_kl_mode = not _kl_mode
	reload_room()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev: InputEventKey = event as InputEventKey
		match key_ev.keycode:
			KEY_F1:
				toggle_camera_mode()
			KEY_F2:
				toggle_lighting_preset()
			KEY_F3:
				toggle_grid_overlay()
			KEY_F4:
				cycle_next_room(-1 if key_ev.shift_pressed else 1)
			KEY_F5:
				toggle_kl_mode()


func _process(delta: float) -> void:
	if _transition_cooldown > 0.0:
		_transition_cooldown = maxf(0.0, _transition_cooldown - delta)
	if player != null and is_instance_valid(player) and player.position.y < -3.0:
		player.position = _last_safe_spawn
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.sync_shader_world_pos()
	_poll_timer += delta
	if _poll_timer >= hot_reload_interval:
		_poll_timer = 0.0
		var mtime: int = FileAccess.get_modified_time(room_json_path)
		if mtime > 0 and mtime != _last_mtime:
			reload_room()
