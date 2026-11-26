class_name KnightLoreHintDialog
extends CanvasLayer
## In-game puzzle hint dialog displaying "Melkhior's Wisdom" for any chamber.
## Evaluates the current room's geometry, elevated exits, active hazards,
## and quest status to deliver actionable step-by-step guidance.

signal closed()

var _kl_data: KnightLoreData
var _session: KnightLoreSession

var _title_lbl: Label
var _sub_lbl: Label
var _challenge_lbl: Label
var _solution_lbl: Label
var _warning_lbl: Label
var _synergy_lbl: Label
var _close_btn: Button


func _init() -> void:
	name = "KnightLoreHintDialog"
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_kl_data = KnightLoreData.load_default()
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_H:
			close()
			get_viewport().set_input_as_handled()


func open(room_id: int, session: KnightLoreSession = null) -> void:
	_session = session
	_refresh_hint(room_id)
	visible = true
	if _close_btn != null:
		_close_btn.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func toggle(room_id: int, session: KnightLoreSession = null) -> void:
	if visible:
		close()
	else:
		open(room_id, session)


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "HintBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.82)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "HintCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "HintPanel"
	panel.custom_minimum_size = Vector2(660, 520)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	style.border_color = Color(0.92, 0.78, 0.35, 0.92)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(root_vbox)

	# --- Header ---
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	root_vbox.add_child(header_vbox)

	var super_lbl := Label.new()
	super_lbl.text = "MELKHIOR'S WISDOM"
	super_lbl.add_theme_font_size_override("font_size", 12)
	super_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.35, 0.90))
	header_vbox.add_child(super_lbl)

	_title_lbl = Label.new()
	_title_lbl.text = "CHAMBER HINT"
	_title_lbl.add_theme_font_size_override("font_size", 20)
	_title_lbl.add_theme_color_override("font_color", Color(0.96, 0.88, 0.50, 1.0))
	header_vbox.add_child(_title_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.text = "Tactical Guidance & Puzzle Solution"
	_sub_lbl.add_theme_font_size_override("font_size", 12)
	_sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.70, 0.64, 0.85))
	header_vbox.add_child(_sub_lbl)

	var sep1 := HSeparator.new()
	root_vbox.add_child(sep1)

	# --- Scrollable Body Content ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(content_vbox)

	# 1. The Challenge
	var c_sec := _create_section_card("CHAMBER OBSTACLE", Color(0.92, 0.82, 0.45, 1.0))
	content_vbox.add_child(c_sec)
	_challenge_lbl = _create_body_label()
	c_sec.add_child(_challenge_lbl)

	# 2. Tactical Solution
	var s_sec := _create_section_card("TACTICAL SOLUTION & PUZZLE STEPS", Color(0.45, 0.85, 0.55, 1.0))
	content_vbox.add_child(s_sec)
	_solution_lbl = _create_body_label()
	s_sec.add_child(_solution_lbl)

	# 3. Hazard Warnings
	var w_sec := _create_section_card("HAZARD WARNINGS", Color(0.95, 0.45, 0.40, 1.0))
	content_vbox.add_child(w_sec)
	_warning_lbl = _create_body_label()
	w_sec.add_child(_warning_lbl)

	# 4. Form Synergy
	var f_sec := _create_section_card("LYCANTHROPY ADVANTAGE", Color(0.60, 0.75, 0.95, 1.0))
	content_vbox.add_child(f_sec)
	_synergy_lbl = _create_body_label()
	f_sec.add_child(_synergy_lbl)

	var sep2 := HSeparator.new()
	root_vbox.add_child(sep2)

	# --- Footer ---
	var footer_hbox := HBoxContainer.new()
	root_vbox.add_child(footer_hbox)

	var prompt_lbl := Label.new()
	prompt_lbl.text = "Press [H] or [Esc] to return to the game"
	prompt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_lbl.add_theme_font_size_override("font_size", 11)
	prompt_lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.60, 0.80))
	footer_hbox.add_child(prompt_lbl)

	_close_btn = Button.new()
	_close_btn.text = "Close Hint [H]"
	_close_btn.custom_minimum_size = Vector2(130, 32)
	_close_btn.pressed.connect(close)
	footer_hbox.add_child(_close_btn)


func _create_section_card(section_title: String, title_color: Color) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var title_lbl := Label.new()
	title_lbl.text = section_title
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", title_color)
	vbox.add_child(title_lbl)

	return vbox


func _create_body_label() -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82, 0.95))
	return lbl


func _refresh_hint(room_id: int) -> void:
	var hint: Dictionary = KnightLoreHintEngine.get_room_hint(room_id, _kl_data, _session)

	_title_lbl.text = str(hint.get("title", "Room %d" % room_id)).to_upper()
	var is_forest: bool = bool(hint.get("is_forest", false))
	_sub_lbl.text = "Biome: %s  |  Chamber ID: %03d" % [
		"Woodland Forest" if is_forest else "Castle Dungeon",
		room_id
	]

	_challenge_lbl.text = str(hint.get("challenge", "A passageway through the castle."))
	_solution_lbl.text = str(hint.get("solution", "Proceed through doorway portals carefully."))
	_warning_lbl.text = str(hint.get("warning", "Watch your step."))
	_synergy_lbl.text = str(hint.get("form_synergy", "Use your form to best advantage."))
