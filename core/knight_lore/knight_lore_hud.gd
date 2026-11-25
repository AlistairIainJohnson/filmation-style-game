class_name KnightLoreHud
extends CanvasLayer
## HUD & Victory/Game Over overlay for the playable Knight Lore 3D gameplay session.

var _room_label: Label
var _day_label: Label
var _phase_label: Label
var _cycle_bar: ProgressBar
var _charms_label: Label
var _lives_label: Label
var _control_label: Label

var _slot_panels: Array[PanelContainer] = []
var _slot_swatches: Array[ColorRect] = []
var _slot_names: Array[Label] = []

var _toast_label: Label
var _toast_timer: float = 0.0

var _end_overlay: PanelContainer
var _end_title: Label
var _end_body: Label
var _end_stats: Label
var _end_prompt: Label


func _init() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Top status strip
	var top_panel := PanelContainer.new()
	top_panel.name = "TopBar"
	top_panel.position = Vector2(16, 12)
	top_panel.custom_minimum_size = Vector2(1248, 44)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.06, 0.07, 0.09, 0.80)
	top_style.corner_radius_top_left = 6
	top_style.corner_radius_top_right = 6
	top_style.corner_radius_bottom_left = 6
	top_style.corner_radius_bottom_right = 6
	top_panel.add_theme_stylebox_override("panel", top_style)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 14)
	top_margin.add_theme_constant_override("margin_right", 14)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)

	_room_label = _make_label("ROOM #47 | Stone", 15, Color(0.92, 0.94, 0.98))
	_day_label = _make_label("DAY 1/40", 15, Color(0.98, 0.86, 0.40))
	_phase_label = _make_label("SUN (HUMAN)", 15, Color(1.0, 0.82, 0.30))

	_cycle_bar = ProgressBar.new()
	_cycle_bar.min_value = 0.0
	_cycle_bar.max_value = 100.0
	_cycle_bar.value = 0.0
	_cycle_bar.show_percentage = false
	_cycle_bar.custom_minimum_size = Vector2(110, 14)
	_cycle_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_charms_label = _make_label("CHARMS 0/14", 15, Color(0.35, 0.95, 0.95))
	_lives_label = _make_label("LIVES 5", 15, Color(1.0, 0.45, 0.45))
	_control_label = _make_label("[Tab] Directional", 14, Color(0.75, 0.85, 0.95))

	for w: Control in [_room_label, _day_label, _phase_label, _cycle_bar, _charms_label, _lives_label, _control_label]:
		top_row.add_child(w)
	top_margin.add_child(top_row)
	top_panel.add_child(top_margin)
	root.add_child(top_panel)

	# 2. Toast banner above inventory
	_toast_label = _make_label("", 16, Color(1.0, 0.95, 0.65))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.position = Vector2(240, 565)
	_toast_label.custom_minimum_size = Vector2(800, 28)
	_toast_label.visible = false
	root.add_child(_toast_label)

	# 3. Bottom 3-slot inventory & controls bar
	var bot_panel := PanelContainer.new()
	bot_panel.name = "BottomInventoryBar"
	bot_panel.position = Vector2(210, 602)
	bot_panel.custom_minimum_size = Vector2(860, 102)
	bot_panel.add_theme_stylebox_override("panel", top_style)

	var bot_margin := MarginContainer.new()
	bot_margin.add_theme_constant_override("margin_left", 16)
	bot_margin.add_theme_constant_override("margin_right", 16)
	bot_margin.add_theme_constant_override("margin_top", 8)
	bot_margin.add_theme_constant_override("margin_bottom", 8)
	var bot_col := VBoxContainer.new()
	bot_col.add_theme_constant_override("separation", 6)

	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 14)

	for i: int in range(3):
		var sp := PanelContainer.new()
		sp.custom_minimum_size = Vector2(250, 52)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.12, 0.14, 0.18, 0.95)
		st.border_width_left = 2
		st.border_width_right = 2
		st.border_width_top = 2
		st.border_width_bottom = 2
		st.border_color = Color(0.95, 0.78, 0.25, 0.9) if i == 2 else Color(0.32, 0.36, 0.44, 0.9)
		st.corner_radius_top_left = 4
		st.corner_radius_top_right = 4
		st.corner_radius_bottom_left = 4
		st.corner_radius_bottom_right = 4
		sp.add_theme_stylebox_override("panel", st)

		var sm := MarginContainer.new()
		sm.add_theme_constant_override("margin_left", 8)
		sm.add_theme_constant_override("margin_right", 8)
		sm.add_theme_constant_override("margin_top", 6)
		sm.add_theme_constant_override("margin_bottom", 6)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = Color(0.30, 0.32, 0.36, 1.0)

		var lbl_tag := "[DROP]" if i == 2 else ("#%d" % (i + 1))
		var nm_lbl := _make_label("%s: Empty" % lbl_tag, 14, Color(0.88, 0.90, 0.95))
		nm_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		hbox.add_child(swatch)
		hbox.add_child(nm_lbl)
		sm.add_child(hbox)
		sp.add_child(sm)
		slots_row.add_child(sp)

		_slot_panels.append(sp)
		_slot_swatches.append(swatch)
		_slot_names.append(nm_lbl)

	var help_lbl := _make_label("WASD/Arrows: Move  |  Space: Jump (Hold Higher)  |  E: Pick/Drop-Climb  |  Tab: Controls  |  F1: Proj  |  R: Restart", 12, Color(0.70, 0.75, 0.82))
	help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	bot_col.add_child(slots_row)
	bot_col.add_child(help_lbl)
	bot_margin.add_child(bot_col)
	bot_panel.add_child(bot_margin)
	root.add_child(bot_panel)

	# 4. Victory / Game Over Modal Overlay
	_end_overlay = PanelContainer.new()
	_end_overlay.name = "EndScreenOverlay"
	_end_overlay.position = Vector2(310, 140)
	_end_overlay.custom_minimum_size = Vector2(660, 380)
	_end_overlay.visible = false
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0.05, 0.05, 0.08, 0.94)
	end_style.border_width_left = 3
	end_style.border_width_right = 3
	end_style.border_width_top = 3
	end_style.border_width_bottom = 3
	end_style.border_color = Color(0.95, 0.80, 0.32, 1.0)
	end_style.corner_radius_top_left = 8
	end_style.corner_radius_top_right = 8
	end_style.corner_radius_bottom_left = 8
	end_style.corner_radius_bottom_right = 8
	_end_overlay.add_theme_stylebox_override("panel", end_style)

	var em := MarginContainer.new()
	em.add_theme_constant_override("margin_left", 28)
	em.add_theme_constant_override("margin_right", 28)
	em.add_theme_constant_override("margin_top", 24)
	em.add_theme_constant_override("margin_bottom", 24)
	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 16)

	_end_title = _make_label("GAME OVER", 30, Color(1.0, 0.85, 0.30))
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_body = _make_label("", 17, Color(0.86, 0.92, 0.98))
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_stats = _make_label("", 18, Color(0.42, 0.96, 0.88))
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_prompt = _make_label("Press [Enter] or [R] to Play Again", 16, Color(0.95, 0.95, 0.95))
	_end_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	for c: Control in [_end_title, _end_body, _end_stats, _end_prompt]:
		ev.add_child(c)
	em.add_child(ev)
	_end_overlay.add_child(em)
	root.add_child(_end_overlay)


func _make_label(text: String, font_size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	return lbl


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		if _toast_timer <= 0.0 and _toast_label != null:
			_toast_label.visible = false


func show_toast(msg: String, duration: float = 2.2) -> void:
	if _toast_label == null:
		return
	_toast_label.text = msg
	_toast_label.visible = not msg.is_empty()
	_toast_timer = duration


func update_status(
	room_id: int,
	is_forest: bool,
	day_count: int,
	is_night: bool,
	is_wulf: bool,
	progress: float,
	charms: int,
	lives: int,
	is_rotational: bool
) -> void:
	_room_label.text = "ROOM #%d | %s" % [room_id, "Woodland" if is_forest else "Dungeon"]
	_day_label.text = "DAY %d/%d" % [day_count, KnightLoreSession.MAX_DAYS]
	var celestial: String = "MOON" if is_night else "SUN"
	var form: String = "WULF" if is_wulf else "HUMAN"
	_phase_label.text = "%s (%s)" % [celestial, form]
	var phase_col: Color = Color(0.62, 0.78, 1.0) if is_night else Color(1.0, 0.84, 0.30)
	_phase_label.add_theme_color_override("font_color", phase_col)
	_cycle_bar.value = clampf(progress * 100.0, 0.0, 100.0)
	_charms_label.text = "CHARMS %d/%d" % [charms, KnightLoreSession.TOTAL_CHARMS_REQUIRED]
	_lives_label.text = "LIVES %d" % maxi(lives, 0)
	_control_label.text = "[Tab] %s" % ("Rotational" if is_rotational else "Directional")


func update_inventory(slots: Array) -> void:
	for i: int in range(3):
		var t_id: int = int(slots[i]) if i < slots.size() else -1
		var lbl_tag: String = "[DROP]" if i == 2 else ("#%d" % (i + 1))
		_slot_names[i].text = "%s: %s" % [lbl_tag, KnightLoreSession.get_charm_name(t_id)]
		_slot_swatches[i].color = KnightLoreSession.get_charm_color(t_id)


func show_end_screen(victory: bool, session: KnightLoreSession, reason: String = "") -> void:
	var ui_cfg: Dictionary = session.kl_data.ui_cfg if session.kl_data != null else {}
	if victory:
		var v_lines: Array = (ui_cfg.get("game_complete_screen", {}) as Dictionary).get("lines", ["THE SPELL HAS BROKEN", "YOU ARE FREE", "GO FORTH TO MIREMARE"]) as Array
		_end_title.text = "SPELL BROKEN — VICTORY!"
		_end_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.60))
		_end_body.text = "\n".join(PackedStringArray(v_lines))
	else:
		_end_title.text = "GAME OVER" + ("" if reason.is_empty() else (" — " + reason))
		_end_title.add_theme_color_override("font_color", Color(1.0, 0.40, 0.35))
		_end_body.text = "Melkhior's curse claims the dungeon.\nExplore rooms and deliver all 14 charms to Room 136!"

	_end_stats.text = "DAYS ELAPSED: %d   |   QUEST COMPLETED: %d%%\nCHARMS COLLECTED: %d/14   |   OVERALL RATING: %s" % [
		session.day_count,
		session.get_quest_percent(),
		session.charms_collected,
		session.get_rating_label()
	]
	_end_overlay.visible = true


func hide_end_screen() -> void:
	_end_overlay.visible = false
