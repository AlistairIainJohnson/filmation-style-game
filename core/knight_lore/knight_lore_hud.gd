class_name KnightLoreHud
extends CanvasLayer
## Classic Knight Lore corner-scroll HUD & Victory/Game Over overlay.
## Aligns and locks the bottom-left (Lives, Charms, Inventory) and bottom-right
## (Day/Night Sky Dial & Sun/Moon form) parchment scrolls directly to the
## projected 3D play-area diagonal edges, scaling dynamically on viewport resize.

class ScrollWingPanel extends Control:
	var is_right: bool = false
	var ui_scale: float = 1.0
	var outer_top_y: float = 12.0
	var inner_top_y: float = 120.0
	var bottom_y: float = 190.0
	var roller_w: float = 22.0
	var inner_margin: float = 16.0

	func _init(p_right: bool = false) -> void:
		is_right = p_right
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func configure_geometry(
		p_scale: float,
		p_outer_top_y: float,
		p_inner_top_y: float,
		p_bottom_y: float,
		p_roller_w: float,
		p_inner_margin: float
	) -> void:
		ui_scale = maxf(p_scale, 0.35)
		outer_top_y = p_outer_top_y
		inner_top_y = p_inner_top_y
		bottom_y = p_bottom_y
		roller_w = p_roller_w
		inner_margin = p_inner_margin
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 40.0 or h < 40.0:
			return

		var s: float = ui_scale
		var dir_x: float = -1.0 if is_right else 1.0
		var outer_x: float = (w - roller_w) if is_right else roller_w
		var inner_x: float = inner_margin if is_right else (w - inner_margin)

		var top_out_y: float = clampf(outer_top_y, 6.0 * s, h - 30.0 * s)
		var bot_y: float = clampf(bottom_y, top_out_y + 24.0 * s, h - 4.0 * s)
		var top_in_y: float = clampf(inner_top_y, top_out_y + 8.0 * s, bot_y - 16.0 * s)

		# 1. Main tapered parchment sheet aligned strictly to projected room diagonal
		var sheet_pts := PackedVector2Array([
			Vector2(outer_x, top_out_y),
			Vector2(inner_x, top_in_y),
			Vector2(inner_x + dir_x * 3.0 * s, bot_y),
			Vector2(outer_x, bot_y),
		])
		var sh_off: float = 4.0 * s
		var shadow_pts := PackedVector2Array([
			Vector2(outer_x, top_out_y + sh_off),
			Vector2(inner_x, top_in_y + sh_off),
			Vector2(inner_x + dir_x * 3.0 * s, bot_y + sh_off),
			Vector2(outer_x, bot_y + sh_off),
		])
		draw_colored_polygon(shadow_pts, Color(0.01, 0.01, 0.02, 0.52))
		draw_colored_polygon(sheet_pts, Color(0.11, 0.09, 0.07, 0.92))

		# Double antique-gold edge trim
		var border_gold := Color(0.82, 0.64, 0.30, 0.94)
		var trim_inner := Color(0.55, 0.42, 0.20, 0.58)
		draw_polyline(PackedVector2Array([
			Vector2(outer_x, top_out_y),
			Vector2(inner_x, top_in_y),
			Vector2(inner_x + dir_x * 3.0 * s, bot_y),
			Vector2(outer_x, bot_y),
		]), border_gold, maxf(1.5, 2.0 * s), true)
		draw_line(
			Vector2(outer_x + dir_x * 4.0 * s, top_out_y + 6.0 * s),
			Vector2(inner_x - dir_x * 5.0 * s, top_in_y + 4.5 * s),
			trim_inner,
			maxf(1.0, 1.0 * s)
		)

		# 2. Inner curled scroll ribbon tip beside the DAY notch
		var curl_r: float = clampf(9.5 * s, 5.0, (bot_y - top_in_y) * 0.46)
		var curl_center := Vector2(inner_x, (top_in_y + bot_y) * 0.5 + 4.0 * s)
		draw_circle(curl_center, curl_r, Color(0.15, 0.12, 0.09, 0.96))
		draw_arc(curl_center, curl_r, 0.0, TAU, 16, border_gold, maxf(1.2, 1.6 * s), true)
		draw_arc(curl_center, curl_r * 0.50, 0.2, TAU - 0.6, 12, Color(0.92, 0.76, 0.38, 0.85), maxf(1.0, 1.3 * s), true)

		# 3. Outer vertical scroll roller cylinder & turned caps
		var cyl_left: float = outer_x if is_right else (outer_x - roller_w)
		var cyl_top: float = maxf(2.0 * s, top_out_y - 6.0 * s)
		var cyl_bot: float = bot_y + 2.0 * s
		var cyl_rect := Rect2(Vector2(cyl_left, cyl_top), Vector2(roller_w, cyl_bot - cyl_top))
		draw_rect(cyl_rect, Color(0.16, 0.12, 0.09, 0.98), true)
		draw_rect(
			Rect2(Vector2(cyl_left + 3.5 * s, cyl_top + 2.0 * s), Vector2(roller_w * 0.28, (cyl_bot - cyl_top) - 4.0 * s)),
			Color(0.28, 0.22, 0.15, 0.72),
			true
		)
		draw_rect(cyl_rect, border_gold, false, maxf(1.3, 1.8 * s))

		var cx: float = cyl_left + roller_w * 0.5
		var cap_r: float = roller_w * 0.46
		for cap_y: float in [cyl_top, cyl_bot]:
			draw_circle(Vector2(cx, cap_y), cap_r, Color(0.22, 0.17, 0.12, 1.0))
			draw_arc(Vector2(cx, cap_y), cap_r, 0.0, TAU, 16, border_gold, maxf(1.2, 1.7 * s), true)
			draw_circle(Vector2(cx, cap_y), 3.6 * s, Color(0.92, 0.76, 0.38, 0.95))


class DayNightDial extends Control:
	var is_night: bool = false
	var progress: float = 0.0
	var _pulse_time: float = 0.0

	func set_cycle(p_night: bool, p_progress: float) -> void:
		var clamped: float = clampf(p_progress, 0.0, 1.0)
		if is_night != p_night or absf(progress - clamped) > 0.002:
			is_night = p_night
			progress = clamped
			queue_redraw()

	func _process(delta: float) -> void:
		if progress >= 0.72:
			_pulse_time += delta
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 8.0 or h <= 8.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		var warning: bool = progress >= 0.78

		var day_sky := Color(0.12, 0.30, 0.54, 0.96)
		var dusk_sky := Color(0.55, 0.24, 0.15, 0.96)
		var night_sky := Color(0.05, 0.08, 0.20, 0.96)
		var dawn_sky := Color(0.32, 0.23, 0.44, 0.96)
		var shift_t: float = clampf((progress - 0.65) / 0.35, 0.0, 1.0)
		var bg_col: Color = night_sky.lerp(dawn_sky, shift_t) if is_night else day_sky.lerp(dusk_sky, shift_t)
		draw_rect(rect, bg_col, true)

		var border_col := Color(0.80, 0.64, 0.30, 0.95)
		if warning:
			var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 9.0)
			border_col = (Color(0.45, 0.85, 1.0, 1.0) if is_night else Color(1.0, 0.62, 0.22, 1.0)).lerp(Color.WHITE, pulse * 0.45)
		draw_rect(rect, border_col, false, 2.4 if warning else 2.0)
		draw_rect(Rect2(Vector2(3.0, 3.0), size - Vector2(6.0, 6.0)), Color(0.42, 0.72, 0.48, 0.42), false, 1.0)

		if is_night:
			for sp: Vector2 in [
				Vector2(w * 0.11, h * 0.24),
				Vector2(w * 0.26, h * 0.42),
				Vector2(w * 0.52, h * 0.20),
				Vector2(w * 0.76, h * 0.36),
				Vector2(w * 0.90, h * 0.24),
			]:
				draw_circle(sp, 1.3, Color(0.86, 0.93, 1.0, 0.78))

		var horiz_y: float = h - 8.0
		var center_x: float = w * 0.5
		var rx: float = w * 0.38
		var ry: float = h - 18.0
		draw_line(Vector2(8.0, horiz_y), Vector2(w - 8.0, horiz_y), Color(0.75, 0.82, 0.92, 0.40), 1.2)
		var prev_pt := Vector2(center_x - rx, horiz_y)
		for step_i: int in range(1, 25):
			var ang: float = PI * (1.0 - float(step_i) / 24.0)
			var pt := Vector2(center_x + cos(ang) * rx, horiz_y - sin(ang) * ry)
			draw_line(prev_pt, pt, Color(1.0, 1.0, 1.0, 0.22), 1.2)
			prev_pt = pt

		var body_ang: float = PI * (1.0 - progress)
		var body_pos := Vector2(center_x + cos(body_ang) * rx, horiz_y - sin(body_ang) * ry)
		if is_night:
			draw_circle(body_pos, 10.5, Color(0.55, 0.76, 1.0, 0.25))
			draw_circle(body_pos, 7.0, Color(0.88, 0.94, 1.0, 1.0))
			draw_circle(body_pos + Vector2(3.0, -1.8), 5.6, bg_col)
		else:
			var sun_col: Color = Color(1.0, 0.86, 0.28, 1.0).lerp(Color(1.0, 0.45, 0.18, 1.0), shift_t)
			draw_circle(body_pos, 11.0, Color(sun_col.r, sun_col.g, sun_col.b, 0.28))
			draw_circle(body_pos, 6.8, sun_col)
			for ray_i: int in range(8):
				var ra: float = TAU * float(ray_i) / 8.0
				draw_line(body_pos + Vector2(cos(ra), sin(ra)) * 8.0, body_pos + Vector2(cos(ra), sin(ra)) * 10.8, sun_col, 1.2)

		var font: Font = ThemeDB.fallback_font
		if font != null:
			var tag: String = ("DAWN SOON!" if is_night else "DUSK SOON!") if warning else ("NIGHT" if is_night else "DAY")
			draw_string(font, Vector2(8.0, 14.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, border_col if warning else Color(0.92, 0.95, 1.0, 0.88))


const LEFT_CONTENT_BASE_SIZE := Vector2(246.0, 74.0)
const RIGHT_CONTENT_BASE_SIZE := Vector2(188.0, 72.0)
const DAY_CENTER_BASE_SIZE := Vector2(110.0, 26.0)

var _root: Control
var _top_left_panel: PanelContainer
var _top_right_panel: PanelContainer
var _left_scroll_host: Control
var _left_wing: ScrollWingPanel
var _left_content: VBoxContainer
var _right_scroll_host: Control
var _right_wing: ScrollWingPanel
var _right_content: VBoxContainer
var _day_center: VBoxContainer

var _room_label: Label
var _day_label: Label
var _phase_label: Label
var _day_night_dial: DayNightDial
var _charms_label: Label
var _lives_label: Label
var _control_label: Label

var _slot_panels: Array[PanelContainer] = []
var _slot_swatches: Array[ColorRect] = []
var _slot_names: Array[Label] = []

var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: float = 0.0

var _end_overlay: PanelContainer
var _end_title: Label
var _end_body: Label
var _end_stats: Label
var _end_prompt: Label

var _bound_camera: Camera3D = null
var _bound_room_dims: Vector3 = Vector3(8.0, 6.0, 8.0)
var _bound_wall_t: float = 0.5
var _last_vp_size: Vector2 = Vector2.ZERO
var _last_cam_size: float = -1.0
var _last_cam_basis: Basis = Basis.IDENTITY


func _init() -> void:
	layer = 20
	_build_ui()


func _ready() -> void:
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(refresh_scroll_layout):
		vp.size_changed.connect(refresh_scroll_layout)
	refresh_scroll_layout()


func _make_badge_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.07, 0.06, 0.84)
	st.border_width_left = 1
	st.border_width_right = 1
	st.border_width_top = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.72, 0.56, 0.26, 0.85)
	st.corner_radius_top_left = 5
	st.corner_radius_top_right = 5
	st.corner_radius_bottom_left = 5
	st.corner_radius_bottom_right = 5
	return st


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 1. Top-Left compact room badge & Top-Right controls badge
	_top_left_panel = PanelContainer.new()
	_top_left_panel.name = "TopLeftBadge"
	_top_left_panel.anchor_left = 0.0
	_top_left_panel.anchor_top = 0.0
	_top_left_panel.offset_left = 16.0
	_top_left_panel.offset_top = 12.0
	_top_left_panel.add_theme_stylebox_override("panel", _make_badge_style())
	var tlm := MarginContainer.new()
	tlm.add_theme_constant_override("margin_left", 12)
	tlm.add_theme_constant_override("margin_right", 12)
	tlm.add_theme_constant_override("margin_top", 6)
	tlm.add_theme_constant_override("margin_bottom", 6)
	_room_label = _make_label("ROOM #47 | Dungeon", 14, Color(0.95, 0.92, 0.86))
	tlm.add_child(_room_label)
	_top_left_panel.add_child(tlm)
	_root.add_child(_top_left_panel)

	_top_right_panel = PanelContainer.new()
	_top_right_panel.name = "TopRightBadge"
	_top_right_panel.anchor_left = 1.0
	_top_right_panel.anchor_right = 1.0
	_top_right_panel.anchor_top = 0.0
	_top_right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_top_right_panel.offset_right = -16.0
	_top_right_panel.offset_top = 12.0
	_top_right_panel.add_theme_stylebox_override("panel", _make_badge_style())
	var trm := MarginContainer.new()
	trm.add_theme_constant_override("margin_left", 12)
	trm.add_theme_constant_override("margin_right", 12)
	trm.add_theme_constant_override("margin_top", 6)
	trm.add_theme_constant_override("margin_bottom", 6)
	_control_label = _make_label("[Tab] Directional  |  [P] Pause", 13, Color(0.84, 0.88, 0.94))
	trm.add_child(_control_label)
	_top_right_panel.add_child(trm)
	_root.add_child(_top_right_panel)

	# 2. Top-Center toast banner above room apex (pill-backed for contrast over parchment frame)
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastPanel"
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.offset_top = 12.0
	_toast_panel.add_theme_stylebox_override("panel", _make_badge_style())
	_toast_panel.visible = false
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 14)
	tm.add_theme_constant_override("margin_right", 14)
	tm.add_theme_constant_override("margin_top", 5)
	tm.add_theme_constant_override("margin_bottom", 5)
	_toast_label = _make_label("", 14, Color(1.0, 0.94, 0.60))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.add_child(_toast_label)
	_toast_panel.add_child(tm)
	_root.add_child(_toast_panel)

	# 3. Bottom-Left Scroll Triangle (Top-Left anchor preset so layout scales via position/size/scale without warnings)
	_left_scroll_host = Control.new()
	_left_scroll_host.name = "BottomLeftScroll"
	_left_scroll_host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left_scroll_host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_left_wing = ScrollWingPanel.new(false)
	_left_wing.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left_scroll_host.add_child(_left_wing)

	_left_content = VBoxContainer.new()
	_left_content.name = "LeftScrollContent"
	_left_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left_content.size = LEFT_CONTENT_BASE_SIZE
	_left_content.add_theme_constant_override("separation", 5)
	_left_scroll_host.add_child(_left_content)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 14)
	_lives_label = _make_label("LIVES 5", 13, Color(1.0, 0.80, 0.36))
	_charms_label = _make_label("CHARMS 0/14", 13, Color(0.42, 0.94, 0.94))
	stats_row.add_child(_lives_label)
	stats_row.add_child(_charms_label)
	_left_content.add_child(stats_row)

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 4)
	for i: int in range(3):
		var sp := PanelContainer.new()
		sp.custom_minimum_size = Vector2(78, 42)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.14, 0.12, 0.10, 0.94)
		st.border_width_left = 2
		st.border_width_right = 2
		st.border_width_top = 2
		st.border_width_bottom = 2
		st.border_color = Color(0.95, 0.78, 0.25, 0.92) if i == 2 else Color(0.44, 0.36, 0.22, 0.85)
		st.corner_radius_top_left = 4
		st.corner_radius_top_right = 4
		st.corner_radius_bottom_left = 4
		st.corner_radius_bottom_right = 4
		sp.add_theme_stylebox_override("panel", st)

		var sm := MarginContainer.new()
		sm.add_theme_constant_override("margin_left", 4)
		sm.add_theme_constant_override("margin_right", 4)
		sm.add_theme_constant_override("margin_top", 3)
		sm.add_theme_constant_override("margin_bottom", 3)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = Color(0.30, 0.28, 0.26, 1.0)

		var lbl_tag := "[DROP]" if i == 2 else ("#%d" % (i + 1))
		var nm_lbl := _make_label("%s: Empty" % lbl_tag, 10, Color(0.92, 0.90, 0.86))
		nm_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm_lbl.custom_minimum_size = Vector2(50, 0)

		hbox.add_child(swatch)
		hbox.add_child(nm_lbl)
		sm.add_child(hbox)
		sp.add_child(sm)
		slots_row.add_child(sp)

		_slot_panels.append(sp)
		_slot_swatches.append(swatch)
		_slot_names.append(nm_lbl)

	_left_content.add_child(slots_row)
	_root.add_child(_left_scroll_host)

	# 4. Bottom-Center V-Notch: DAY counter (framed directly below the room apex)
	_day_center = VBoxContainer.new()
	_day_center.name = "BottomCenterDay"
	_day_center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_day_center.size = DAY_CENTER_BASE_SIZE
	_day_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_center.alignment = BoxContainer.ALIGNMENT_END
	_day_center.add_theme_constant_override("separation", 0)

	_day_label = _make_label("DAY 1/40", 16, Color(0.98, 0.82, 0.36))
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.94))
	_day_label.add_theme_constant_override("outline_size", 4)
	_day_center.add_child(_day_label)
	_root.add_child(_day_center)

	# 5. Bottom-Right Scroll Triangle: Arched Day/Night Dial + Sun/Moon form
	_right_scroll_host = Control.new()
	_right_scroll_host.name = "BottomRightScroll"
	_right_scroll_host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_right_scroll_host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_right_wing = ScrollWingPanel.new(true)
	_right_wing.set_anchors_preset(Control.PRESET_FULL_RECT)
	_right_scroll_host.add_child(_right_wing)

	_right_content = VBoxContainer.new()
	_right_content.name = "RightScrollContent"
	_right_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_right_content.size = RIGHT_CONTENT_BASE_SIZE
	_right_content.alignment = BoxContainer.ALIGNMENT_END
	_right_content.add_theme_constant_override("separation", 4)
	_right_scroll_host.add_child(_right_content)

	_day_night_dial = DayNightDial.new()
	_day_night_dial.name = "DayNightDial"
	_day_night_dial.custom_minimum_size = Vector2(182, 50)
	_day_night_dial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_phase_label = _make_label("SUN (HUMAN)", 12, Color(1.0, 0.84, 0.30))
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_right_content.add_child(_day_night_dial)
	_right_content.add_child(_phase_label)
	_root.add_child(_right_scroll_host)

	# 6. Centered Victory / Game Over Modal Overlay
	_end_overlay = PanelContainer.new()
	_end_overlay.name = "EndScreenOverlay"
	_end_overlay.anchor_left = 0.5
	_end_overlay.anchor_right = 0.5
	_end_overlay.anchor_top = 0.5
	_end_overlay.anchor_bottom = 0.5
	_end_overlay.offset_left = -330.0
	_end_overlay.offset_right = 330.0
	_end_overlay.offset_top = -190.0
	_end_overlay.offset_bottom = 190.0
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
	_root.add_child(_end_overlay)


func bind_room_camera(camera: Camera3D, room_dims: Vector3, wall_thickness: float = 0.5) -> void:
	_bound_camera = camera
	_bound_room_dims = room_dims
	_bound_wall_t = wall_thickness
	refresh_scroll_layout()


static func project_ortho_point(cam: Camera3D, vp_size: Vector2, world_pt: Vector3) -> Vector2:
	if cam == null or not is_instance_valid(cam):
		return Vector2.ZERO
	var local_p: Vector3 = cam.global_transform.affine_inverse() * world_pt
	var px_per_m: float = vp_size.y / maxf(cam.size, 0.001)
	return Vector2(
		vp_size.x * 0.5 + local_p.x * px_per_m,
		vp_size.y * 0.5 - local_p.y * px_per_m
	)


func refresh_scroll_layout() -> void:
	if _left_scroll_host == null or _right_scroll_host == null or _day_center == null:
		return
	var vp: Viewport = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	if vp_size.x < 120.0 or vp_size.y < 120.0:
		vp_size = Vector2(1280.0, 720.0)

	var p_left := Vector2(vp_size.x * 0.22, vp_size.y * 0.69)
	var p_bottom := Vector2(vp_size.x * 0.50, vp_size.y * 0.978)
	var p_right := Vector2(vp_size.x * 0.78, vp_size.y * 0.69)

	var cam_ready: bool = _bound_camera != null and is_instance_valid(_bound_camera) and _bound_camera.is_inside_tree()
	if cam_ready:
		var t: float = _bound_wall_t
		var l_3d := Vector3(-t, 0.0, _bound_room_dims.z + t)
		var b_3d := Vector3(_bound_room_dims.x + t, 0.0, _bound_room_dims.z + t)
		var r_3d := Vector3(_bound_room_dims.x + t, 0.0, -t)
		p_left = project_ortho_point(_bound_camera, vp_size, l_3d)
		p_bottom = project_ortho_point(_bound_camera, vp_size, b_3d)
		p_right = project_ortho_point(_bound_camera, vp_size, r_3d)
		_last_cam_size = _bound_camera.size
		_last_cam_basis = _bound_camera.global_transform.basis
	else:
		_last_cam_size = -1.0

	_last_vp_size = vp_size

	var half_w: float = maxf((p_right.x - p_left.x) * 0.5, 140.0)
	var s: float = clampf(half_w / 358.0, 0.45, 2.5)
	var gap: float = 8.0 * s
	var roller_w: float = 20.0 * s
	var inner_margin: float = 14.0 * s
	var notch_half_w: float = 48.0 * s
	var bot_y: float = vp_size.y - 6.0 * s

	var slope_l: float = (p_bottom.y - p_left.y) / maxf(p_bottom.x - p_left.x, 1.0)
	var slope_r: float = (p_bottom.y - p_right.y) / maxf(p_right.x - p_bottom.x, 1.0)

	var left_outer_x: float = maxf(p_left.x, roller_w + 4.0 * s)
	var left_inner_x: float = clampf(p_bottom.x - notch_half_w, left_outer_x + 120.0 * s, p_bottom.x - 36.0 * s)
	var right_outer_x: float = minf(p_right.x, vp_size.x - roller_w - 4.0 * s)
	var right_inner_x: float = clampf(p_bottom.x + notch_half_w, p_bottom.x + 36.0 * s, right_outer_x - 120.0 * s)

	# Keep inner scroll content cleanly inside narrow viewports by bounding scale to parchment span
	var max_content_scale: float = minf(
		maxf((left_inner_x - left_outer_x) - 10.0 * s, 90.0) / LEFT_CONTENT_BASE_SIZE.x,
		maxf((right_outer_x - right_inner_x) - 10.0 * s, 90.0) / RIGHT_CONTENT_BASE_SIZE.x
	)
	var content_s: float = clampf(minf(s, max_content_scale), 0.42, 2.4)

	var left_top_outer_y: float = clampf(p_left.y + gap + (left_outer_x - p_left.x) * slope_l, 40.0, bot_y - 84.0 * s)
	var left_top_inner_y: float = clampf(p_left.y + gap + (left_inner_x - p_left.x) * slope_l, left_top_outer_y + 18.0 * s, bot_y - 22.0 * s)
	var right_top_outer_y: float = clampf(p_right.y + gap + (p_right.x - right_outer_x) * slope_r, 40.0, bot_y - 84.0 * s)
	var right_top_inner_y: float = clampf(p_right.y + gap + (p_right.x - right_inner_x) * slope_r, right_top_outer_y + 18.0 * s, bot_y - 22.0 * s)

	# Left scroll wing anchored from roller edge to bottom-center V-notch
	var l_host_y: float = left_top_outer_y - 10.0 * s
	var l_host_h: float = (bot_y + 6.0 * s) - l_host_y
	_left_scroll_host.position = Vector2(left_outer_x - roller_w, l_host_y)
	_left_scroll_host.size = Vector2((left_inner_x - left_outer_x) + roller_w + inner_margin, l_host_h)
	_left_wing.configure_geometry(s, left_top_outer_y - l_host_y, left_top_inner_y - l_host_y, bot_y - l_host_y, roller_w, inner_margin)
	_left_content.size = LEFT_CONTENT_BASE_SIZE
	_left_content.scale = Vector2(content_s, content_s)
	_left_content.position = Vector2(
		roller_w + 8.0 * s,
		(bot_y - l_host_y) - LEFT_CONTENT_BASE_SIZE.y * content_s - 6.0 * s
	)

	# Right scroll wing anchored from bottom-center V-notch to right roller edge
	var r_host_y: float = right_top_outer_y - 10.0 * s
	var r_host_h: float = (bot_y + 6.0 * s) - r_host_y
	_right_scroll_host.position = Vector2(right_inner_x - inner_margin, r_host_y)
	_right_scroll_host.size = Vector2((right_outer_x - right_inner_x) + roller_w + inner_margin, r_host_h)
	_right_wing.configure_geometry(s, right_top_outer_y - r_host_y, right_top_inner_y - r_host_y, bot_y - r_host_y, roller_w, inner_margin)
	_right_content.size = RIGHT_CONTENT_BASE_SIZE
	_right_content.scale = Vector2(content_s, content_s)
	_right_content.position = Vector2(
		_right_scroll_host.size.x - roller_w - RIGHT_CONTENT_BASE_SIZE.x * content_s - 8.0 * s,
		(bot_y - r_host_y) - RIGHT_CONTENT_BASE_SIZE.y * content_s - 6.0 * s
	)

	# Bottom-center V-notch DAY counter centered directly under projected room corner B_3d
	_day_center.size = DAY_CENTER_BASE_SIZE
	_day_center.scale = Vector2(content_s, content_s)
	_day_center.position = Vector2(
		p_bottom.x - DAY_CENTER_BASE_SIZE.x * 0.5 * content_s,
		bot_y - DAY_CENTER_BASE_SIZE.y * content_s
	)

	# Scale top badges & toast proportionally without touching anchor invariants
	if _top_left_panel != null:
		_top_left_panel.scale = Vector2(content_s, content_s)
		_top_left_panel.offset_left = 14.0 * content_s
		_top_left_panel.offset_top = 10.0 * content_s
	if _top_right_panel != null:
		_top_right_panel.pivot_offset = Vector2(_top_right_panel.size.x, 0.0)
		_top_right_panel.scale = Vector2(content_s, content_s)
		_top_right_panel.offset_right = -14.0 * content_s
		_top_right_panel.offset_top = 10.0 * content_s


func _make_label(text: String, font_size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	return lbl


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false

	var vp: Viewport = get_viewport()
	if vp != null:
		var vp_sz: Vector2 = vp.get_visible_rect().size
		var cam_dirty: bool = false
		if _bound_camera != null and is_instance_valid(_bound_camera) and _bound_camera.is_inside_tree():
			if absf(_bound_camera.size - _last_cam_size) > 0.001 or not _bound_camera.global_transform.basis.is_equal_approx(_last_cam_basis):
				cam_dirty = true
		if vp_sz != _last_vp_size or cam_dirty:
			refresh_scroll_layout()


func show_toast(msg: String, duration: float = 2.2) -> void:
	if _toast_label == null or _toast_panel == null:
		return
	_toast_label.text = msg
	_toast_panel.visible = not msg.is_empty()
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
	if _day_night_dial != null:
		_day_night_dial.set_cycle(is_night, progress)
	_charms_label.text = "CHARMS %d/%d" % [charms, KnightLoreSession.TOTAL_CHARMS_REQUIRED]
	if lives >= KnightLoreSession.INFINITE_LIVES:
		_lives_label.text = "LIVES INF"
	else:
		_lives_label.text = "LIVES %d" % maxi(lives, 0)
	_control_label.text = "[Tab] %s  |  [P] Pause" % ("Rotational" if is_rotational else "Directional")


func update_inventory(slots: Array) -> void:
	for i: int in range(3):
		var t_id: int = int(slots[i]) if i < slots.size() else -1
		var lbl_tag: String = "[DROP]" if i == 2 else ("#%d" % (i + 1))
		_slot_names[i].text = "%s\n%s" % [lbl_tag, KnightLoreSession.get_charm_name(t_id)]
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
