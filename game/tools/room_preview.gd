extends Node3D
## Live hot-reloading room previewer for rapid Filmation level design iteration.
## Hotkeys: F1 = True Iso / 2:1 Dimetric, F2 = Day / Night, F3 = 1m Grid + Jump Ruler, F4 = Next Room.

@export var room_json_path: String = "res://data/rooms/room_08_08.json"
@export var hot_reload_interval: float = 0.5

var preview_root: Node3D
var grid_overlay: MeshInstance3D
var player: PlayerController
var current_build: Dictionary = {}

var _camera_mode: DioramaCameraRig.ProjectionMode = DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
var _lighting_preset: String = "castle_stone_skylight"
var _grid_visible: bool = false
var _last_mtime: int = 0
var _poll_timer: float = 0.0
var _world_rooms: Array[String] = []
var _room_idx: int = 0
var _hud_label: Label


func _ready() -> void:
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
	_ensure_hud()
	reload_room()


func _load_world_room_list() -> void:
	_world_rooms.clear()
	var wg: Dictionary = RoomBuilder.load_json_dict("res://data/world_graph.json")
	for entry: Variant in (wg.get("rooms", []) as Array):
		if entry is Dictionary:
			var p: String = str((entry as Dictionary).get("json_path", ""))
			if not p.is_empty():
				_world_rooms.append(p)
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


func reload_room() -> void:
	if preview_root != null and is_instance_valid(preview_root):
		remove_child(preview_root)
		preview_root.free()
	preview_root = Node3D.new()
	preview_root.name = "PreviewRoot"
	add_child(preview_root)

	var cam_mode_str: String = "dimetric_2_1" if _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 else "true_isometric"
	var builder := RoomBuilder.new()
	current_build = builder.build_room_from_path(preview_root, room_json_path, _lighting_preset, cam_mode_str)
	if current_build.is_empty():
		return

	_last_mtime = FileAccess.get_modified_time(room_json_path)

	player = PlayerController.new()
	player.name = "PreviewPlayer"
	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		player.set_camera_rig(cam_rig)

	var spawn_pos: Vector3 = Vector3(5.5, 0.0, 5.5)
	var doorways: Node3D = current_build.get("doorways_root") as Node3D
	if doorways != null:
		for child: Node in doorways.get_children():
			if child is Marker3D:
				spawn_pos = (child as Marker3D).position
				break
	player.position = spawn_pos
	preview_root.add_child(player)
	player.sync_shader_world_pos()
	if player.drop_shadow != null:
		player.drop_shadow.call_deferred("update_shadow")

	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	var arch_root: Node = current_build.get("architecture_root") as Node
	if lighting != null and arch_root != null:
		lighting.call_deferred("bake_gi_if_supported", arch_root)

	_build_grid_overlay(current_build.get("room_dims", Vector3(12.0, 6.0, 12.0)), spawn_pos)
	_update_hud()


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
	_hud_label.text = "%s %s | %s | %s | Grid:%s\n[F1] Projection  [F2] Day/Night  [F3] Grid+Ruler  [F4] Next Room" % [
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
		var arch_root: Node = current_build.get("architecture_root") as Node
		if arch_root != null:
			lighting.call_deferred("bake_gi_if_supported", arch_root)
	_update_hud()


func toggle_grid_overlay() -> void:
	_grid_visible = not _grid_visible
	if grid_overlay != null:
		grid_overlay.visible = _grid_visible
	_update_hud()


func cycle_next_room() -> void:
	if _world_rooms.is_empty():
		return
	_room_idx = (_room_idx + 1) % _world_rooms.size()
	room_json_path = _world_rooms[_room_idx]
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
				cycle_next_room()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= hot_reload_interval:
		_poll_timer = 0.0
		var mtime: int = FileAccess.get_modified_time(room_json_path)
		if mtime > 0 and mtime != _last_mtime:
			reload_room()
