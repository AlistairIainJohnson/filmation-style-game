class_name KnightLoreMapDialog
extends CanvasLayer
## In-game 16x16 world map overlay for Knight Lore Reimagined.
## Displays all 128 room outlines in faint silhouette (so the castle perimeter
## is recognizable), visited rooms in rich biome colors, the current player beacon,
## and an interactive room inspector sidebar.

signal closed()
signal room_selected(room_id: int)
signal hint_requested_for_room(room_id: int)

var _kl_data: KnightLoreData
var _current_room_id: int = 136
var _selected_room_id: int = 136
var _visited_rooms: Dictionary = {}
var _charms_collected: int = 0
var _current_requested_charm: int = 0

var _grid_buttons: Dictionary = {}  # room_id -> Button
var _stat_label: Label
var _inspector_title: Label
var _inspector_sub: Label
var _inspector_status: Label
var _inspector_exits: VBoxContainer
var _inspector_features: Label
var _hint_btn: Button

var _pulse_timer: float = 0.0
var _current_room_btn: Button = null


func _init() -> void:
	name = "KnightLoreMapDialog"
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_kl_data = KnightLoreData.load_default()
	_build_ui()


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_timer += delta * 4.0
	if _current_room_btn != null and is_instance_valid(_current_room_btn):
		var alpha: float = 0.65 + 0.35 * sin(_pulse_timer)
		_current_room_btn.modulate = Color(1.2, 1.1, 0.7, alpha)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_M:
			close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_H:
			hint_requested_for_room.emit(_selected_room_id)
			get_viewport().set_input_as_handled()


func open(
	current_room_id: int,
	visited_rooms: Dictionary,
	charms_collected: int = 0,
	requested_charm: int = 0
) -> void:
	_current_room_id = current_room_id
	_selected_room_id = current_room_id
	_visited_rooms = visited_rooms.duplicate()
	_charms_collected = charms_collected
	_current_requested_charm = requested_charm
	_refresh_map_grid()
	_inspect_room(_selected_room_id)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func toggle(
	current_room_id: int,
	visited_rooms: Dictionary,
	charms_collected: int = 0,
	requested_charm: int = 0
) -> void:
	if visible:
		close()
	else:
		open(current_room_id, visited_rooms, charms_collected, requested_charm)


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "MapBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.85)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "MapCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_panel := PanelContainer.new()
	main_panel.name = "MapPanel"
	main_panel.custom_minimum_size = Vector2(980, 640)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	panel_style.border_color = Color(0.92, 0.78, 0.35, 0.90)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	main_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(main_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(root_vbox)

	# --- Header ---
	var header_hbox := HBoxContainer.new()
	root_vbox.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "CASTLE & WOODLAND WORLD MAP"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.45, 1.0))
	title_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "16x16 Strategic Diorama Grid — 128 Chambers"
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60, 0.80))
	title_vbox.add_child(sub_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close Map [M]"
	close_btn.custom_minimum_size = Vector2(130, 32)
	close_btn.pressed.connect(close)
	header_hbox.add_child(close_btn)

	# --- Body HBox ---
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 18)
	root_vbox.add_child(body_hbox)

	# --- Left: 16x16 Grid Map ---
	var grid_panel := PanelContainer.new()
	grid_panel.custom_minimum_size = Vector2(490, 490)
	var grid_panel_style := StyleBoxFlat.new()
	grid_panel_style.bg_color = Color(0.04, 0.05, 0.08, 0.90)
	grid_panel_style.border_color = Color(0.35, 0.32, 0.25, 0.60)
	grid_panel_style.border_width_left = 1
	grid_panel_style.border_width_right = 1
	grid_panel_style.border_width_top = 1
	grid_panel_style.border_width_bottom = 1
	grid_panel_style.content_margin_left = 6
	grid_panel_style.content_margin_right = 6
	grid_panel_style.content_margin_top = 6
	grid_panel_style.content_margin_bottom = 6
	grid_panel.add_theme_stylebox_override("panel", grid_panel_style)
	body_hbox.add_child(grid_panel)

	var map_grid := GridContainer.new()
	map_grid.columns = 16
	map_grid.add_theme_constant_override("h_separation", 2)
	map_grid.add_theme_constant_override("v_separation", 2)
	grid_panel.add_child(map_grid)

	_build_grid_buttons(map_grid)

	# --- Right: Room Inspector Sidebar ---
	var inspector_panel := PanelContainer.new()
	inspector_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var insp_style := StyleBoxFlat.new()
	insp_style.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	insp_style.border_color = Color(0.55, 0.45, 0.28, 0.70)
	insp_style.border_width_left = 1
	insp_style.border_width_right = 1
	insp_style.border_width_top = 1
	insp_style.border_width_bottom = 1
	insp_style.content_margin_left = 14
	insp_style.content_margin_right = 14
	insp_style.content_margin_top = 12
	insp_style.content_margin_bottom = 12
	inspector_panel.add_theme_stylebox_override("panel", insp_style)
	body_hbox.add_child(inspector_panel)

	var insp_vbox := VBoxContainer.new()
	insp_vbox.add_theme_constant_override("separation", 10)
	inspector_panel.add_child(insp_vbox)

	_inspector_title = Label.new()
	_inspector_title.text = "CHAMBER INSPECTOR"
	_inspector_title.add_theme_font_size_override("font_size", 16)
	_inspector_title.add_theme_color_override("font_color", Color(0.94, 0.82, 0.45, 1.0))
	insp_vbox.add_child(_inspector_title)

	_inspector_sub = Label.new()
	_inspector_sub.text = "Select any chamber to inspect connections"
	_inspector_sub.add_theme_font_size_override("font_size", 12)
	_inspector_sub.add_theme_color_override("font_color", Color(0.70, 0.68, 0.62, 0.85))
	insp_vbox.add_child(_inspector_sub)

	_inspector_status = Label.new()
	_inspector_status.text = "Status: Unknown"
	_inspector_status.add_theme_font_size_override("font_size", 13)
	insp_vbox.add_child(_inspector_status)

	var sep1 := HSeparator.new()
	insp_vbox.add_child(sep1)

	var exits_header := Label.new()
	exits_header.text = "DOORWAY PORTALS:"
	exits_header.add_theme_font_size_override("font_size", 13)
	exits_header.add_theme_color_override("font_color", Color(0.85, 0.75, 0.48, 1.0))
	insp_vbox.add_child(exits_header)

	_inspector_exits = VBoxContainer.new()
	_inspector_exits.add_theme_constant_override("separation", 4)
	insp_vbox.add_child(_inspector_exits)

	var sep2 := HSeparator.new()
	insp_vbox.add_child(sep2)

	var feat_header := Label.new()
	feat_header.text = "CHAMBER FEATURES:"
	feat_header.add_theme_font_size_override("font_size", 13)
	feat_header.add_theme_color_override("font_color", Color(0.85, 0.75, 0.48, 1.0))
	insp_vbox.add_child(feat_header)

	_inspector_features = Label.new()
	_inspector_features.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_features.text = "No features detected."
	_inspector_features.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp_vbox.add_child(_inspector_features)

	_hint_btn = Button.new()
	_hint_btn.text = "Consult Melkhior's Wisdom [H]"
	_hint_btn.pressed.connect(_on_hint_button_pressed)
	insp_vbox.add_child(_hint_btn)

	# --- Footer Stats & Legend ---
	var footer_hbox := HBoxContainer.new()
	root_vbox.add_child(footer_hbox)

	_stat_label = Label.new()
	_stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_label.text = "Exploration Progress: 0 / 128 Chambers Discovered"
	_stat_label.add_theme_font_size_override("font_size", 12)
	_stat_label.add_theme_color_override("font_color", Color(0.82, 0.80, 0.74, 1.0))
	footer_hbox.add_child(_stat_label)

	var legend_lbl := Label.new()
	legend_lbl.text = "🟡 Current  ⚱️ Cauldron  🟨 Yellow  🟪 Magenta  🟦 Cyan  🟩 Green  ⬛ Unexplored"
	legend_lbl.add_theme_font_size_override("font_size", 11)
	legend_lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.60, 0.85))
	footer_hbox.add_child(legend_lbl)


func _build_grid_buttons(map_grid: GridContainer) -> void:
	_grid_buttons.clear()
	# In Knight Lore, (grid_y * 16) + grid_x = room_id.
	# Top row corresponds to grid_y = 15 (North), bottom row to grid_y = 0 (South).
	for row: int in range(16):
		var gy: int = 15 - row
		for col: int in range(16):
			var gx: int = col
			var rid: int = (gy * 16) + gx
			var has_room: bool = _kl_data.has_room(rid) if _kl_data != null else false

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(28, 28)
			btn.focus_mode = Control.FOCUS_NONE

			if has_room:
				btn.text = "%d" % rid if rid >= 100 else "%02d" % rid
				btn.add_theme_font_size_override("font_size", 9)
				btn.pressed.connect(_on_room_button_clicked.bind(rid))
				_grid_buttons[rid] = btn
			else:
				# Void / empty coordinate slot
				btn.disabled = true
				btn.flat = true
				btn.modulate = Color(0.1, 0.1, 0.1, 0.15)

			map_grid.add_child(btn)


func _refresh_map_grid() -> void:
	_current_room_btn = null
	var visited_count: int = 0

	for rid: int in _grid_buttons.keys():
		var btn: Button = _grid_buttons[rid] as Button
		if btn == null:
			continue

		var is_visited: bool = bool(_visited_rooms.get(rid, false))
		var is_current: bool = (rid == _current_room_id)
		var is_cauldron: bool = (rid == 136)
		var is_forest: bool = _kl_data.is_forest_room(rid) if _kl_data != null else false

		if is_visited:
			visited_count += 1

		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3

		if is_current:
			_current_room_btn = btn
			style.bg_color = Color(0.85, 0.65, 0.15, 0.95)
			style.border_color = Color(1.0, 0.95, 0.50, 1.0)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			btn.add_theme_color_override("font_color", Color(0.12, 0.05, 0.02, 1.0))
		elif is_cauldron and (is_visited or bool(_visited_rooms.get(136, false))):
			style.bg_color = Color(0.65, 0.48, 0.18, 0.90)
			style.border_color = Color(0.95, 0.85, 0.35, 0.95)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			btn.add_theme_color_override("font_color", Color(0.98, 0.92, 0.70, 1.0))
		elif is_visited:
			var r_data: Dictionary = _kl_data.get_room(rid) if _kl_data != null else {}
			var ink_name: String = str(r_data.get("ink_color_name", "Yellow"))
			match ink_name:
				"Magenta":
					style.bg_color = Color(0.40, 0.14, 0.38, 0.90)
					style.border_color = Color(0.85, 0.40, 0.82, 0.85)
				"Cyan":
					style.bg_color = Color(0.12, 0.32, 0.40, 0.90)
					style.border_color = Color(0.35, 0.78, 0.88, 0.85)
				"Green":
					style.bg_color = Color(0.15, 0.35, 0.18, 0.90)
					style.border_color = Color(0.38, 0.82, 0.42, 0.85)
				_: # Yellow / default
					style.bg_color = Color(0.42, 0.36, 0.14, 0.90)
					style.border_color = Color(0.88, 0.82, 0.35, 0.85)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			btn.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88, 1.0))
		else:
			# Unvisited room — faint silhouette outline so the castle's perimeter is recognizable
			style.bg_color = Color(0.10, 0.11, 0.14, 0.50)
			style.border_color = Color(0.25, 0.27, 0.32, 0.45)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			btn.add_theme_color_override("font_color", Color(0.40, 0.42, 0.46, 0.50))

		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)

	var pct: float = (float(visited_count) / 128.0) * 100.0
	_stat_label.text = "Exploration: %d / 128 Chambers (%.1f%%)  |  Charms Delivered: %d / 14" % [visited_count, pct, _charms_collected]


func _on_room_button_clicked(room_id: int) -> void:
	_selected_room_id = room_id
	_inspect_room(room_id)
	room_selected.emit(room_id)


func _on_hint_button_pressed() -> void:
	hint_requested_for_room.emit(_selected_room_id)


func _inspect_room(room_id: int) -> void:
	if _kl_data == null or not _kl_data.has_room(room_id):
		return

	var is_visited: bool = bool(_visited_rooms.get(room_id, false))
	var is_current: bool = (room_id == _current_room_id)
	var is_forest: bool = _kl_data.is_forest_room(room_id)
	var is_cauldron: bool = (room_id == 136)

	var room_data: Dictionary = _kl_data.get_room(room_id)
	var gx: int = int(room_data.get("grid_x", room_id & 0x0F))
	var gy: int = int(room_data.get("grid_y", (room_id >> 4) & 0x0F))

	if is_current:
		_inspector_title.text = "ROOM %03d — CURRENT LOCATION" % room_id
		_inspector_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
		_inspector_status.text = "Status: You Are Here"
		_inspector_status.add_theme_color_override("font_color", Color(0.95, 0.82, 0.30, 1.0))
	elif is_cauldron:
		_inspector_title.text = "ROOM 136 — CAULDRON HUB"
		_inspector_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.40, 1.0))
		_inspector_status.text = "Status: " + ("Explored" if is_visited else "Discovered via Lore")
		_inspector_status.add_theme_color_override("font_color", Color(0.90, 0.78, 0.40, 1.0))
	elif is_visited:
		_inspector_title.text = "ROOM %03d — %s" % [room_id, "WOODLAND GLADE" if is_forest else "CASTLE CHAMBER"]
		_inspector_title.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72, 1.0))
		_inspector_status.text = "Status: Explored"
		_inspector_status.add_theme_color_override("font_color", Color(0.40, 0.85, 0.45, 1.0))
	else:
		_inspector_title.text = "ROOM %03d — UNEXPLORED" % room_id
		_inspector_title.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70, 0.80))
		_inspector_status.text = "Status: Unexplored Territory"
		_inspector_status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70, 0.80))

	var ink_name: String = str(room_data.get("ink_color_name", "Yellow"))
	_inspector_sub.text = "Biome: %s  |  Ink: %s  |  Grid: [X: %d, Y: %d]" % [
		"Woodland Forest" if is_forest else "Castle Dungeon",
		ink_name,
		gx,
		gy
	]

	# Clear previous exits
	for child: Node in _inspector_exits.get_children():
		child.queue_free()

	var exits: Dictionary = _kl_data.get_room_exits(room_id)
	if exits.is_empty():
		var no_ex := Label.new()
		no_ex.text = "No doorway portals detected"
		no_ex.add_theme_font_size_override("font_size", 12)
		_inspector_exits.add_child(no_ex)
	else:
		for dir_name: String in ["north", "east", "south", "west"]:
			if not exits.has(dir_name):
				continue
			var ex: Dictionary = exits[dir_name] as Dictionary
			var target_id: int = int(ex.get("target_room_id", -1))
			var is_high: bool = bool(ex.get("high", false))
			var is_tree: bool = bool(ex.get("tree", false))

			var ex_lbl := Label.new()
			var type_str: String = "Doorway"
			if is_high:
				type_str = "High Arch [3.0m Elevation]"
			elif is_tree:
				type_str = "Tree Arch"

			ex_lbl.text = "• %s: %s → Room %03d" % [dir_name.capitalize(), type_str, target_id]
			ex_lbl.add_theme_font_size_override("font_size", 12)
			if is_high:
				ex_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35, 1.0))
			else:
				ex_lbl.add_theme_color_override("font_color", Color(0.80, 0.78, 0.72, 1.0))
			_inspector_exits.add_child(ex_lbl)

	# Chamber features
	var hint_data: Dictionary = KnightLoreHintEngine.get_room_hint(room_id, _kl_data, null)
	var feats: Array[String] = []
	if is_cauldron:
		feats.append("• Sacred Cauldron of Melkhior")
	if bool(hint_data.get("has_special_spawn", false)):
		feats.append("• Sacred Quest Charm Spawn Point")
	for h_name: String in (hint_data.get("hazards_detected", []) as Array):
		feats.append("• Hazard: " + h_name)
	for p_name: String in (hint_data.get("pushables_detected", []) as Array):
		feats.append("• Interactive: " + p_name)

	if feats.is_empty():
		_inspector_features.text = "Standard castle architecture with stone floor tiles."
	else:
		_inspector_features.text = "\n".join(feats)
