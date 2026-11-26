class_name KnightLoreSaveLoadDialog
extends CanvasLayer
## Modal dialog for Saving and Loading game state to/from disk files.
## Supports 3 save slots (Slot 1, Slot 2, Slot 3) with timestamp, room, day, lives info.

signal save_selected(slot_index: int, slot_path: String)
signal load_selected(slot_index: int, slot_path: String)
signal closed()

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3

var is_save_mode: bool = true  # true = Save Game, false = Load Game

var _slot_buttons: Array[Button] = []
var _slot_info_labels: Array[Label] = []
var _title_label: Label
var _audio_mgr: ZxAudioManager


func _init() -> void:
	name = "KnightLoreSaveLoadDialog"
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func set_audio_manager(mgr: ZxAudioManager) -> void:
	_audio_mgr = mgr


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "SaveLoadBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.70)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "SaveLoadCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "SaveLoadPanel"
	panel.custom_minimum_size = Vector2(460, 420)

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
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "SAVE GAME"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(_title_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_slot_buttons.clear()
	_slot_info_labels.clear()

	for slot_idx: int in range(1, SLOT_COUNT + 1):
		var slot_box := VBoxContainer.new()
		slot_box.add_theme_constant_override("separation", 4)

		var btn := Button.new()
		btn.text = "Slot %d" % slot_idx
		btn.custom_minimum_size = Vector2(380, 42)
		btn.pressed.connect(_on_slot_pressed.bind(slot_idx))
		slot_box.add_child(btn)
		_slot_buttons.append(btn)

		var info := Label.new()
		info.text = "Empty Slot"
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
		slot_box.add_child(info)
		_slot_info_labels.append(info)

		vbox.add_child(slot_box)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(200, 36)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(_on_cancel_pressed)
	vbox.add_child(cancel_btn)


func open(p_save_mode: bool) -> void:
	is_save_mode = p_save_mode
	_title_label.text = "SAVE GAME" if is_save_mode else "LOAD GAME"
	_refresh_slots()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _refresh_slots() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	for slot_idx: int in range(1, SLOT_COUNT + 1):
		var path: String = "%s/slot_%d.json" % [SAVE_DIR, slot_idx]
		var btn: Button = _slot_buttons[slot_idx - 1]
		var info_lbl: Label = _slot_info_labels[slot_idx - 1]

		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					var d: Dictionary = parsed as Dictionary
					var meta: Dictionary = d.get("metadata", {}) as Dictionary
					var room_id: int = int(meta.get("room_id", 0))
					var day: int = int(meta.get("day", 1))
					var time_str: String = str(meta.get("saved_at", ""))
					var charms: int = int(meta.get("charms", 0))
					btn.text = "%s Slot %d — Room #%d" % ["Save to" if is_save_mode else "Load", slot_idx, room_id]
					info_lbl.text = "Day %d | Charms %d/14 | %s" % [day, charms, time_str]
					btn.disabled = false
				else:
					btn.text = "%s Slot %d (Corrupted)" % ["Save to" if is_save_mode else "Load", slot_idx]
					info_lbl.text = "Corrupted save file"
					btn.disabled = not is_save_mode
			else:
				btn.text = "%s Slot %d" % ["Save to" if is_save_mode else "Load", slot_idx]
				info_lbl.text = "Empty Slot"
				btn.disabled = not is_save_mode
		else:
			btn.text = "%s Slot %d [Empty]" % ["Save to" if is_save_mode else "Load", slot_idx]
			info_lbl.text = "Empty Slot"
			btn.disabled = not is_save_mode


func _on_slot_pressed(slot_idx: int) -> void:
	_play_click()
	var path: String = "%s/slot_%d.json" % [SAVE_DIR, slot_idx]
	if is_save_mode:
		save_selected.emit(slot_idx, path)
	else:
		load_selected.emit(slot_idx, path)
	close()


func _on_cancel_pressed() -> void:
	_play_click()
	close()


func _play_click() -> void:
	if _audio_mgr != null:
		_audio_mgr.play_sfx("sfx_menu_select")
