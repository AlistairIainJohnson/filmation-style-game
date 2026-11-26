class_name KnightLoreSettingsDialog
extends CanvasLayer
## Modal dialog for gameplay and audio settings:
## - Lives mode: Normal (5), 99 Lives, Infinite Lives
## - Music and Sound volume sliders / steppers
## - Character Invulnerability toggle
## - Jump Boost (increased height & length) toggle

signal settings_saved(settings: Dictionary)
signal closed()

var _lives_mode: String = "normal"  # "normal", "99", "infinite"
var _music_volume: float = 0.85
var _sfx_volume: float = 0.90
var _invulnerable: bool = false
var _jump_boost: bool = false

var _lives_btn: Button
var _music_slider: HSlider
var _music_val_label: Label
var _sfx_slider: HSlider
var _sfx_val_label: Label
var _invuln_btn: Button
var _jump_btn: Button
var _audio_mgr: ZxAudioManager


func _init() -> void:
	name = "KnightLoreSettingsDialog"
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func set_audio_manager(mgr: ZxAudioManager) -> void:
	_audio_mgr = mgr


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "SettingsBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.70)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "SettingsCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(480, 480)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.97)
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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- 1. Lives Mode ---
	var lives_row := HBoxContainer.new()
	var lives_lbl := Label.new()
	lives_lbl.text = "Starting Lives:"
	lives_lbl.custom_minimum_size = Vector2(160, 0)
	lives_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	lives_row.add_child(lives_lbl)

	_lives_btn = Button.new()
	_lives_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lives_btn.pressed.connect(_on_lives_cycle_pressed)
	lives_row.add_child(_lives_btn)
	vbox.add_child(lives_row)

	# --- 2. Music Volume ---
	var mus_row := HBoxContainer.new()
	var mus_lbl := Label.new()
	mus_lbl.text = "Music Volume:"
	mus_lbl.custom_minimum_size = Vector2(160, 0)
	mus_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	mus_row.add_child(mus_lbl)

	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.value = _music_volume
	_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_slider.value_changed.connect(_on_music_slider_changed)
	mus_row.add_child(_music_slider)

	_music_val_label = Label.new()
	_music_val_label.custom_minimum_size = Vector2(45, 0)
	_music_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_music_val_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	mus_row.add_child(_music_val_label)
	vbox.add_child(mus_row)

	# --- 3. Sound (SFX) Volume ---
	var sfx_row := HBoxContainer.new()
	var sfx_lbl := Label.new()
	sfx_lbl.text = "Sound FX Volume:"
	sfx_lbl.custom_minimum_size = Vector2(160, 0)
	sfx_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	sfx_row.add_child(sfx_lbl)

	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.value = _sfx_volume
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	sfx_row.add_child(_sfx_slider)

	_sfx_val_label = Label.new()
	_sfx_val_label.custom_minimum_size = Vector2(45, 0)
	_sfx_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sfx_val_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	sfx_row.add_child(_sfx_val_label)
	vbox.add_child(sfx_row)

	# --- 4. Invulnerability ---
	var inv_row := HBoxContainer.new()
	var inv_lbl := Label.new()
	inv_lbl.text = "Invulnerability:"
	inv_lbl.custom_minimum_size = Vector2(160, 0)
	inv_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	inv_row.add_child(inv_lbl)

	_invuln_btn = Button.new()
	_invuln_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invuln_btn.pressed.connect(_on_invuln_toggled)
	inv_row.add_child(_invuln_btn)
	vbox.add_child(inv_row)

	# --- 5. Jump Height & Length Boost ---
	var jmp_row := HBoxContainer.new()
	var jmp_lbl := Label.new()
	jmp_lbl.text = "Jump Boost:"
	jmp_lbl.custom_minimum_size = Vector2(160, 0)
	jmp_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	jmp_row.add_child(jmp_lbl)

	_jump_btn = Button.new()
	_jump_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jump_btn.pressed.connect(_on_jump_toggled)
	jmp_row.add_child(_jump_btn)
	vbox.add_child(jmp_row)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# --- Close Button ---
	var close_btn := Button.new()
	close_btn.text = "Back / Save Settings"
	close_btn.custom_minimum_size = Vector2(240, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)

	_update_display()


func open(current_settings: Dictionary) -> void:
	_lives_mode = str(current_settings.get("lives_mode", "normal"))
	_music_volume = float(current_settings.get("music_volume", 0.85))
	_sfx_volume = float(current_settings.get("sfx_volume", 0.90))
	_invulnerable = bool(current_settings.get("invulnerable", false))
	_jump_boost = bool(current_settings.get("jump_boost", false))

	_music_slider.value = _music_volume
	_sfx_slider.value = _sfx_volume
	_update_display()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func get_settings() -> Dictionary:
	return {
		"lives_mode": _lives_mode,
		"music_volume": _music_volume,
		"sfx_volume": _sfx_volume,
		"invulnerable": _invulnerable,
		"jump_boost": _jump_boost
	}


func _update_display() -> void:
	var lives_text: String = "Normal (5)"
	if _lives_mode == "99":
		lives_text = "99 Lives"
	elif _lives_mode == "infinite":
		lives_text = "Infinite Lives"
	_lives_btn.text = lives_text

	_music_val_label.text = "%d%%" % int(round(_music_volume * 100.0))
	_sfx_val_label.text = "%d%%" % int(round(_sfx_volume * 100.0))

	_invuln_btn.text = "ON" if _invulnerable else "OFF"
	_jump_btn.text = "ON (High & Far)" if _jump_boost else "OFF (Normal)"


func _on_lives_cycle_pressed() -> void:
	match _lives_mode:
		"normal":
			_lives_mode = "99"
		"99":
			_lives_mode = "infinite"
		_:
			_lives_mode = "normal"
	_play_click()
	_update_display()
	_emit_change()


func _on_music_slider_changed(val: float) -> void:
	_music_volume = val
	if _audio_mgr != null:
		_audio_mgr.set_music_volume(_music_volume)
	_update_display()
	_emit_change()


func _on_sfx_slider_changed(val: float) -> void:
	_sfx_volume = val
	if _audio_mgr != null:
		_audio_mgr.set_sfx_volume(_sfx_volume)
	_update_display()
	_emit_change()


func _on_invuln_toggled() -> void:
	_invulnerable = not _invulnerable
	_play_click()
	_update_display()
	_emit_change()


func _on_jump_toggled() -> void:
	_jump_boost = not _jump_boost
	_play_click()
	_update_display()
	_emit_change()


func _on_close_pressed() -> void:
	_play_click()
	close()


func _emit_change() -> void:
	settings_saved.emit(get_settings())


func _play_click() -> void:
	if _audio_mgr != null:
		_audio_mgr.play_sfx("sfx_menu_select")
