class_name KnightLoreMainMenu
extends Control
## Full title & main menu screen for Knight Lore 3D.
## Displays authentic 1984 A.C.G. lines and ZX palette colors,
## provides Control Mode (Directional vs Rotational) & Camera Mode (Isometric vs Dimetric) selectors,
## Audio volume / mute controls, and keyboard shortcuts matching the original (0 to start, 1-5 keys).

signal start_game_requested(settings: Dictionary)
signal exit_game_requested()

const ZX_PALETTE: Dictionary = {
	"0": Color(0.0, 0.0, 0.0),        # Black
	"1": Color(0.0, 0.0, 0.95),       # Blue
	"2": Color(0.95, 0.1, 0.1),       # Red
	"3": Color(0.95, 0.1, 0.95),      # Magenta
	"4": Color(0.1, 0.95, 0.1),       # Green
	"5": Color(0.1, 0.95, 0.95),      # Cyan
	"6": Color(0.98, 0.95, 0.2),      # Yellow
	"7": Color(1.0, 1.0, 1.0),        # White
}

var _audio_mgr: ZxAudioManager
var _score_seq: KlScoreSequencer
var _strings_cfg: Dictionary = {}

var _selected_control_mode: String = "directional"
var _selected_camera_mode: String = "true_isometric"
var _master_vol: float = 0.8
var _muted: bool = false

var _title_label: Label
var _menu_labels: Array[Label] = []
var _status_label: Label
var _control_btn: Button
var _camera_btn: Button
var _mute_btn: Button
var _start_btn: Button
var _exit_btn: Button


func _init() -> void:
	name = "KnightLoreMainMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind_audio(p_mgr: ZxAudioManager, p_seq: KlScoreSequencer) -> void:
	_audio_mgr = p_mgr
	_score_seq = p_seq


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sync_viewport_size()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_sync_viewport_size):
		get_viewport().size_changed.connect(_sync_viewport_size)
	_load_strings_config("res://data/knight_lore/strings_and_ui.json")
	_build_ui()
	if _audio_mgr == null:
		_audio_mgr = ZxAudioManager.new()
		_audio_mgr.name = "MenuAudioManager"
		add_child(_audio_mgr)
	if _score_seq == null:
		_score_seq = KlScoreSequencer.new(_audio_mgr)
		_score_seq.name = "MenuScoreSequencer"
		add_child(_score_seq)
	if visible:
		_score_seq.play_cue("menu", true)


func _sync_viewport_size() -> void:
	if get_viewport() != null:
		position = Vector2.ZERO
		size = get_viewport().get_visible_rect().size


func _load_strings_config(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_strings_cfg = parsed as Dictionary


func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.06, 1.0)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 410)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.border_color = Color(0.85, 0.72, 0.28, 0.90)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# Title screen string from config
	var menu_lines: Array = (_strings_cfg.get("menu_screen", {}) as Dictionary).get("lines", [
		"KNIGHT LORE REIMAGINED"
	]) as Array

	# Main Title
	_title_label = Label.new()
	_title_label.text = str(menu_lines[0]) if not menu_lines.is_empty() else "KNIGHT LORE REIMAGINED"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", ZX_PALETTE["3"]) # Magenta
	vbox.add_child(_title_label)

	var sub_title := Label.new()
	sub_title.text = "A 3D FILMATION RE-CREATION"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 14)
	sub_title.add_theme_color_override("font_color", Color(0.68, 0.75, 0.88))
	vbox.add_child(sub_title)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Interactive Control Row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_control_btn = Button.new()
	_control_btn.text = "Control: 8-Way Directional"
	_control_btn.custom_minimum_size = Vector2(230, 38)
	_control_btn.pressed.connect(_on_toggle_control)
	btn_row.add_child(_control_btn)

	_camera_btn = Button.new()
	_camera_btn.text = "Camera: True Isometric"
	_camera_btn.custom_minimum_size = Vector2(210, 38)
	_camera_btn.pressed.connect(_on_toggle_camera)
	btn_row.add_child(_camera_btn)

	_mute_btn = Button.new()
	_mute_btn.text = "Sound: ON [M]"
	_mute_btn.custom_minimum_size = Vector2(130, 38)
	_mute_btn.pressed.connect(_on_toggle_mute)
	btn_row.add_child(_mute_btn)

	# Start & Exit Buttons
	_start_btn = Button.new()
	_start_btn.text = "► START GAME [Space / Enter] ◄"
	_start_btn.custom_minimum_size = Vector2(320, 48)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_btn.add_theme_font_size_override("font_size", 18)
	_start_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_btn)

	_exit_btn = Button.new()
	_exit_btn.text = "Exit Game [Esc]"
	_exit_btn.custom_minimum_size = Vector2(240, 38)
	_exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_exit_btn.add_theme_font_size_override("font_size", 15)
	_exit_btn.add_theme_color_override("font_color", Color(0.95, 0.62, 0.58))
	_exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(_exit_btn)

	_status_label = Label.new()
	_status_label.text = "Press Space or Enter to Enter the Castle. Tab in-game to switch controls."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	vbox.add_child(_status_label)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_0, KEY_SPACE, KEY_ENTER:
				_on_start_pressed()
			KEY_1, KEY_2, KEY_3, KEY_4:
				# Keyboard / Joystick classic rotational
				_selected_control_mode = "rotational"
				_update_control_btn()
				_play_click()
			KEY_5:
				_on_toggle_control()
			KEY_M:
				_on_toggle_mute()
			KEY_C:
				_on_toggle_camera()
			KEY_ESCAPE:
				_on_exit_pressed()


func _on_toggle_control() -> void:
	if _selected_control_mode == "directional":
		_selected_control_mode = "rotational"
	else:
		_selected_control_mode = "directional"
	_update_control_btn()
	_play_click()


func _update_control_btn() -> void:
	if _selected_control_mode == "directional":
		_control_btn.text = "Control: 8-Way Directional"
	else:
		_control_btn.text = "Control: Rotational"


func _on_toggle_camera() -> void:
	if _selected_camera_mode == "true_isometric":
		_selected_camera_mode = "dimetric_2_1"
		_camera_btn.text = "Camera: 2:1 Dimetric"
	else:
		_selected_camera_mode = "true_isometric"
		_camera_btn.text = "Camera: True Isometric"
	_play_click()


func _on_toggle_mute() -> void:
	_muted = not _muted
	if _audio_mgr != null:
		_audio_mgr.set_mute(_muted)
	_mute_btn.text = "Sound: %s [M]" % ("OFF" if _muted else "ON")
	if not _muted:
		_play_click()


func _play_click() -> void:
	if _audio_mgr != null:
		_audio_mgr.play_sfx("sfx_menu_select")


func _on_start_pressed() -> void:
	if _audio_mgr != null:
		_audio_mgr.play_sfx("sfx_menu_select")
	if _score_seq != null:
		_score_seq.stop_cue()
	var settings := {
		"control_mode": _selected_control_mode,
		"camera_mode": _selected_camera_mode,
		"muted": _muted
	}
	start_game_requested.emit(settings)


func _on_exit_pressed() -> void:
	if _audio_mgr != null:
		_audio_mgr.play_sfx("sfx_menu_select")
	exit_game_requested.emit()
	if not exit_game_requested.has_connections() and get_tree() != null:
		get_tree().quit()
