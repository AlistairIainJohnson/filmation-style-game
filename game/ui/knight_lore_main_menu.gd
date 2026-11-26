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

const BACKGROUND_PATH := "res://assets/ui/background.webp"
const LOGO_PATH := "res://assets/ui/knight_lore_reimagined_logo.png"

var _audio_mgr: ZxAudioManager
var _score_seq: KlScoreSequencer
var _strings_cfg: Dictionary = {}

var _selected_control_mode: String = "directional"
var _selected_camera_mode: String = "true_isometric"
var _master_vol: float = 0.8
var _muted: bool = false
var _splash_active: bool = true

var _bg_tex_rect: TextureRect
var _logo_tex_rect: TextureRect
var _press_key_label: Label
var _menu_center: CenterContainer
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
		_layout_logo(_splash_active)


func _layout_logo(splash: bool) -> void:
	if _logo_tex_rect == null:
		return
	var vp: Vector2 = size if size.x > 0.0 and size.y > 0.0 else Vector2(1280.0, 720.0)
	var logo_aspect: float = 0.72
	if _logo_tex_rect.texture != null and _logo_tex_rect.texture.get_height() > 0:
		logo_aspect = float(_logo_tex_rect.texture.get_width()) / float(_logo_tex_rect.texture.get_height())
	if splash:
		var h: float = vp.y * 0.72
		var w: float = h * logo_aspect
		_logo_tex_rect.position = Vector2((vp.x - w) * 0.5, vp.y * 0.08)
		_logo_tex_rect.size = Vector2(w, h)
	else:
		var h: float = vp.y * 0.66
		var w: float = h * logo_aspect
		var left_x: float = maxf(vp.x * 0.075, (vp.x * 0.42 - w) * 0.5)
		_logo_tex_rect.position = Vector2(left_x, (vp.y - h) * 0.5)
		_logo_tex_rect.size = Vector2(w, h)


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
	# Warm dark fallback behind loading screen artwork
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.03, 0.02, 1.0)
	add_child(bg)

	# Full-screen illustrated background parchment
	_bg_tex_rect = TextureRect.new()
	_bg_tex_rect.name = "LoadingScreenArt"
	_bg_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BACKGROUND_PATH):
		_bg_tex_rect.texture = load(BACKGROUND_PATH) as Texture2D
	add_child(_bg_tex_rect)

	# Animated Knight Lore Reimagined logo + medallion (centered on splash, slides left for menu)
	_logo_tex_rect = TextureRect.new()
	_logo_tex_rect.name = "KnightLoreLogo"
	_logo_tex_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_logo_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOGO_PATH):
		_logo_tex_rect.texture = load(LOGO_PATH) as Texture2D
	add_child(_logo_tex_rect)

	_press_key_label = Label.new()
	_press_key_label.name = "PressAnyKeyLabel"
	_press_key_label.text = "PRESS ANY KEY TO START"
	_press_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press_key_label.anchor_left = 0.0
	_press_key_label.anchor_right = 1.0
	_press_key_label.anchor_top = 0.84
	_press_key_label.anchor_bottom = 0.92
	_press_key_label.add_theme_font_size_override("font_size", 24)
	_press_key_label.add_theme_color_override("font_color", Color(0.14, 0.07, 0.04, 0.96))
	add_child(_press_key_label)

	# Right-aligned options panel container so the logo sits cleanly on the left
	_menu_center = CenterContainer.new()
	_menu_center.anchor_left = 0.41
	_menu_center.anchor_right = 0.96
	_menu_center.anchor_top = 0.0
	_menu_center.anchor_bottom = 1.0
	add_child(_menu_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(610, 395)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.05, 0.90)
	style.border_color = Color(0.85, 0.72, 0.28, 0.92)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	panel.add_theme_stylebox_override("panel", style)
	_menu_center.add_child(panel)

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
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_control_btn = Button.new()
	_control_btn.text = "Control: 8-Way Directional"
	_control_btn.custom_minimum_size = Vector2(205, 38)
	_control_btn.pressed.connect(_on_toggle_control)
	btn_row.add_child(_control_btn)

	_camera_btn = Button.new()
	_camera_btn.text = "Camera: True Isometric"
	_camera_btn.custom_minimum_size = Vector2(190, 38)
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

	var start_stage: String = OS.get_environment("FILMATION_MENU_STAGE")
	set_splash_active(start_stage != "options")


func set_splash_active(active: bool) -> void:
	_splash_active = active
	if _menu_center != null:
		_menu_center.visible = not active
		_menu_center.modulate = Color.WHITE
	if _press_key_label != null:
		_press_key_label.visible = active
		_press_key_label.modulate = Color.WHITE
	if _bg_tex_rect != null:
		_bg_tex_rect.modulate = Color.WHITE
	_layout_logo(active)


func _dismiss_splash() -> void:
	if not _splash_active:
		return
	_splash_active = false
	_play_click()
	if _menu_center != null:
		_menu_center.visible = true
		_menu_center.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if is_inside_tree():
		var vp: Vector2 = size if size.x > 0.0 and size.y > 0.0 else Vector2(1280.0, 720.0)
		var logo_aspect: float = 0.72
		if _logo_tex_rect != null and _logo_tex_rect.texture != null and _logo_tex_rect.texture.get_height() > 0:
			logo_aspect = float(_logo_tex_rect.texture.get_width()) / float(_logo_tex_rect.texture.get_height())
		var target_h: float = vp.y * 0.66
		var target_w: float = target_h * logo_aspect
		var target_x: float = maxf(vp.x * 0.075, (vp.x * 0.42 - target_w) * 0.5)
		var target_pos := Vector2(target_x, (vp.y - target_h) * 0.5)
		var target_size := Vector2(target_w, target_h)

		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.set_ease(Tween.EASE_OUT)
		if _logo_tex_rect != null:
			tw.tween_property(_logo_tex_rect, "position", target_pos, 0.42)
			tw.tween_property(_logo_tex_rect, "size", target_size, 0.42)
		if _press_key_label != null:
			tw.tween_property(_press_key_label, "modulate:a", 0.0, 0.20)
		if _menu_center != null:
			tw.tween_property(_menu_center, "modulate:a", 1.0, 0.36).set_delay(0.10)
		tw.finished.connect(func() -> void:
			if _press_key_label != null:
				_press_key_label.visible = false
		)
	else:
		set_splash_active(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _splash_active:
		var trigger: bool = false
		if event is InputEventKey and event.pressed and not event.echo:
			trigger = true
		elif event is InputEventMouseButton and event.pressed:
			trigger = true
		if trigger:
			_dismiss_splash()
			get_viewport().set_input_as_handled()
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
