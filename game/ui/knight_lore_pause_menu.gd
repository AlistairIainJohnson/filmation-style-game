class_name KnightLorePauseMenu
extends CanvasLayer
## In-game pause menu modal overlay.
## Triggered by [Escape] or [P], pauses gameplay simulation, provides resume,
## control toggle, camera toggle, audio mute, and return to main menu.

signal resume_requested()
signal restart_requested()
signal return_to_menu_requested()
signal control_mode_toggled(is_rotational: bool)
signal camera_mode_toggled(is_dimetric: bool)
signal sound_toggled(muted: bool)
signal settings_requested()
signal save_game_requested()
signal load_game_requested()

var _is_rotational: bool = false
var _is_dimetric: bool = false
var _is_muted: bool = false

var _resume_btn: Button
var _control_btn: Button
var _camera_btn: Button
var _sound_btn: Button
var _settings_btn: Button
var _save_btn: Button
var _load_btn: Button
var _restart_btn: Button
var _menu_btn: Button


func _init() -> void:
	name = "KnightLorePauseMenu"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "PauseBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.56)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "PauseCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "PausePanel"
	panel.custom_minimum_size = Vector2(440, 540)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_color = Color(0.92, 0.78, 0.35, 0.90)
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
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_resume_btn = Button.new()
	_resume_btn.text = "Resume Game [Esc / P]"
	_resume_btn.custom_minimum_size = Vector2(280, 38)
	_resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(_resume_btn)

	_control_btn = Button.new()
	_control_btn.text = "Controls: 8-Way Directional [Tab]"
	_control_btn.custom_minimum_size = Vector2(280, 36)
	_control_btn.pressed.connect(_on_control_pressed)
	vbox.add_child(_control_btn)

	_camera_btn = Button.new()
	_camera_btn.text = "Camera: True Isometric"
	_camera_btn.custom_minimum_size = Vector2(280, 36)
	_camera_btn.pressed.connect(_on_camera_pressed)
	vbox.add_child(_camera_btn)

	_sound_btn = Button.new()
	_sound_btn.text = "Sound: ON [M]"
	_sound_btn.custom_minimum_size = Vector2(280, 36)
	_sound_btn.pressed.connect(_on_sound_pressed)
	vbox.add_child(_sound_btn)

	_settings_btn = Button.new()
	_settings_btn.text = "Settings..."
	_settings_btn.custom_minimum_size = Vector2(280, 36)
	_settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(_settings_btn)

	_save_btn = Button.new()
	_save_btn.text = "Save Game..."
	_save_btn.custom_minimum_size = Vector2(280, 36)
	_save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(_save_btn)

	_load_btn = Button.new()
	_load_btn.text = "Load Game..."
	_load_btn.custom_minimum_size = Vector2(280, 36)
	_load_btn.pressed.connect(_on_load_pressed)
	vbox.add_child(_load_btn)

	_restart_btn = Button.new()
	_restart_btn.text = "Restart Game [R]"
	_restart_btn.custom_minimum_size = Vector2(280, 36)
	_restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(_restart_btn)

	_menu_btn = Button.new()
	_menu_btn.text = "Return to Title Menu"
	_menu_btn.custom_minimum_size = Vector2(280, 36)
	_menu_btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(_menu_btn)


func open(p_rotational: bool, p_dimetric: bool, p_muted: bool) -> void:
	_is_rotational = p_rotational
	_is_dimetric = p_dimetric
	_is_muted = p_muted
	_update_labels()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func toggle(p_rotational: bool, p_dimetric: bool, p_muted: bool) -> void:
	if visible:
		close()
		resume_requested.emit()
	else:
		open(p_rotational, p_dimetric, p_muted)


func _update_labels() -> void:
	_control_btn.text = "Controls: %s [Tab]" % ("Rotational" if _is_rotational else "Directional")
	_camera_btn.text = "Camera: %s" % ("2:1 Dimetric" if _is_dimetric else "True Isometric")
	_sound_btn.text = "Sound: %s [M]" % ("OFF" if _is_muted else "ON")


func _on_resume_pressed() -> void:
	close()
	resume_requested.emit()


func _on_control_pressed() -> void:
	_is_rotational = not _is_rotational
	_update_labels()
	control_mode_toggled.emit(_is_rotational)


func _on_camera_pressed() -> void:
	_is_dimetric = not _is_dimetric
	_update_labels()
	camera_mode_toggled.emit(_is_dimetric)


func _on_sound_pressed() -> void:
	_is_muted = not _is_muted
	_update_labels()
	sound_toggled.emit(_is_muted)


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_save_pressed() -> void:
	save_game_requested.emit()


func _on_load_pressed() -> void:
	load_game_requested.emit()


func _on_restart_pressed() -> void:
	close()
	restart_requested.emit()


func _on_menu_pressed() -> void:
	close()
	return_to_menu_requested.emit()
