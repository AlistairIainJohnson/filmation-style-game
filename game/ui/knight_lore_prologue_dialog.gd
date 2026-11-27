class_name KnightLorePrologueDialog
extends CanvasLayer
## In-game prologue / instructions parchment modal for Knight Lore.
## Displays the legendary lore poem, cauldron objectives, day/night curse mechanics,
## and full control guide on an embossed parchment scroll with an optional "Do not show again" toggle.

signal closed(dont_show_again: bool)

var _strings_cfg: Dictionary = {}
var _dont_show_again: bool = false

var _title_lbl: Label
var _subtitle_lbl: Label
var _poem_lbl: Label
var _guides_container: VBoxContainer
var _dont_show_check: CheckBox
var _enter_btn: Button


func _init() -> void:
	name = "KnightLorePrologueDialog"
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_load_strings("res://data/knight_lore/strings_and_ui.json")
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			close()
			get_viewport().set_input_as_handled()


func open(dont_show_again_current: bool = false) -> void:
	_dont_show_again = dont_show_again_current
	if _dont_show_check != null:
		_dont_show_check.button_pressed = _dont_show_again
	visible = true
	if _enter_btn != null:
		_enter_btn.grab_focus()


func close() -> void:
	if _dont_show_check != null:
		_dont_show_again = _dont_show_check.button_pressed
	visible = false
	closed.emit(_dont_show_again)


func _load_strings(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_strings_cfg = parsed as Dictionary


func _build_ui() -> void:
	var prologue_cfg: Dictionary = _strings_cfg.get("prologue", {}) as Dictionary

	var backdrop := ColorRect.new()
	backdrop.name = "PrologueBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.04, 0.88)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "PrologueCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ProloguePanel"
	panel.custom_minimum_size = Vector2(720, 600)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.04, 0.96)
	style.border_color = Color(0.91, 0.76, 0.32, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(root_vbox)

	# --- Header ---
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 3)
	root_vbox.add_child(header_vbox)

	_title_lbl = Label.new()
	_title_lbl.text = prologue_cfg.get("title", "THE CURSE OF KNIGHT LORE")
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40, 1.0))
	header_vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = prologue_cfg.get("subtitle", "Forty Days & Forty Nights to Break the Lycanthropy Hex")
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.add_theme_font_size_override("font_size", 13)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 0.55, 0.90))
	header_vbox.add_child(_subtitle_lbl)

	# Decorative separator
	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.85, 0.70, 0.30, 0.45)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	root_vbox.add_child(sep)

	# --- Scrollable Body for Lore & Guide ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var body_vbox := VBoxContainer.new()
	body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(body_vbox)

	# Lore Poem Panel
	var poem_panel := PanelContainer.new()
	var poem_style := StyleBoxFlat.new()
	poem_style.bg_color = Color(0.12, 0.08, 0.06, 0.85)
	poem_style.border_color = Color(0.65, 0.48, 0.22, 0.60)
	poem_style.border_width_left = 1
	poem_style.border_width_right = 1
	poem_style.border_width_top = 1
	poem_style.border_width_bottom = 1
	poem_style.corner_radius_top_left = 6
	poem_style.corner_radius_top_right = 6
	poem_style.corner_radius_bottom_left = 6
	poem_style.corner_radius_bottom_right = 6
	poem_style.content_margin_left = 18
	poem_style.content_margin_right = 18
	poem_style.content_margin_top = 12
	poem_style.content_margin_bottom = 12
	poem_panel.add_theme_stylebox_override("panel", poem_style)
	body_vbox.add_child(poem_panel)

	var poem_lines: Array = prologue_cfg.get("poem", []) as Array
	var poem_text: String = "\n".join(poem_lines)
	_poem_lbl = Label.new()
	_poem_lbl.text = poem_text
	_poem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_poem_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_poem_lbl.add_theme_font_size_override("font_size", 13)
	_poem_lbl.add_theme_color_override("font_color", Color(0.96, 0.90, 0.78, 0.95))
	poem_panel.add_child(_poem_lbl)

	# Mechanics & Guidance Cards
	_guides_container = VBoxContainer.new()
	_guides_container.add_theme_constant_override("separation", 10)
	body_vbox.add_child(_guides_container)

	var guides: Array = prologue_cfg.get("guides", []) as Array
	for g_entry: Variant in guides:
		if not (g_entry is Dictionary):
			continue
		var g_dict: Dictionary = g_entry as Dictionary
		var card := _create_guide_card(str(g_dict.get("heading", "")), str(g_dict.get("detail", "")))
		_guides_container.add_child(card)

	# --- Footer Controls ---
	var footer_vbox := VBoxContainer.new()
	footer_vbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(footer_vbox)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 16)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	footer_vbox.add_child(bottom_row)

	_dont_show_check = CheckBox.new()
	_dont_show_check.text = prologue_cfg.get("dont_show_again_label", "Do not show prologue again on start")
	_dont_show_check.add_theme_font_size_override("font_size", 12)
	_dont_show_check.add_theme_color_override("font_color", Color(0.80, 0.76, 0.70, 0.90))
	bottom_row.add_child(_dont_show_check)

	_enter_btn = Button.new()
	_enter_btn.text = "► ENTER THE CASTLE [Space / Enter] ◄"
	_enter_btn.custom_minimum_size = Vector2(320, 40)
	_enter_btn.add_theme_font_size_override("font_size", 15)
	_enter_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.40, 1.0))
	_enter_btn.pressed.connect(close)
	bottom_row.add_child(_enter_btn)


func _create_guide_card(heading: String, detail: String) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.08, 0.07, 0.75)
	card_style.border_color = Color(0.48, 0.36, 0.18, 0.50)
	card_style.border_width_left = 1
	card_style.border_width_right = 1
	card_style.border_width_top = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 4
	card_style.corner_radius_top_right = 4
	card_style.corner_radius_bottom_left = 4
	card_style.corner_radius_bottom_right = 4
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)

	var h_lbl := Label.new()
	h_lbl.text = heading
	h_lbl.add_theme_font_size_override("font_size", 13)
	h_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.38, 1.0))
	vb.add_child(h_lbl)

	var d_lbl := Label.new()
	d_lbl.text = detail
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76, 0.92))
	vb.add_child(d_lbl)

	return card
