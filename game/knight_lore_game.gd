extends Node3D
## Playable Knight Lore 3D gameplay scene running Option A (Jolt 3D physics + Knight Lore rules):
## 128-room traversal, 3-slot rotating drop-climb inventory, Room 136 cauldron hint/repel bubbles,
## 40-day Sun/Moon Sabreman/Wulf transformation cycle, lives/respawn, and Directional/Rotational controls.

const OPPOSITE_DIR: Dictionary = {
	"north": "south",
	"south": "north",
	"east": "west",
	"west": "east"
}
const CAULDRON_CENTER := Vector3(4.0, 0.95, 4.0)
const PLAYER_LETHAL_RADIUS: float = 0.16
const HAZARD_CORE_SCALE: float = 0.72

var kl_data: KnightLoreData
var session: KnightLoreSession
var hud: KnightLoreHud
var room_container: Node3D
var current_build: Dictionary = {}
var player: PlayerController

var room_director: KlRoomDirector
var audio_manager: ZxAudioManager
var score_sequencer: KlScoreSequencer
var ambience_director: KlAmbienceDirector
var pause_menu: KnightLorePauseMenu
var main_menu: KnightLoreMainMenu
var _settings_dialog: KnightLoreSettingsDialog
var _save_load_dialog: KnightLoreSaveLoadDialog
var _map_dialog: KnightLoreMapDialog
var _hint_dialog: KnightLoreHintDialog
var _prologue_dialog: KnightLorePrologueDialog
var _pending_start_settings: Dictionary = {}
var _current_settings: Dictionary = {
	"lives_mode": "normal",
	"music_volume": 0.85,
	"sfx_volume": 0.90,
	"invulnerable": false,
	"jump_boost": false,
	"skip_prologue": false
}
const SETTINGS_PATH := "user://settings.json"
var _camera_mode: DioramaCameraRig.ProjectionMode = DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
var _use_rotational: bool = false
var _transition_lock: bool = false
var _transition_cooldown: float = 0.0
var _is_transforming: bool = false
var _transform_timer: float = 0.0
var _is_dying: bool = false
var _death_timer: float = 0.0
var _invuln_timer: float = 0.0
var _cauldron_timer: float = 0.4
var _victory_sequence_active: bool = false
var _victory_timeout: float = 0.0
var _victory_sparkles: Array[KlSparkleVfx] = []

var _room_entry_pos: Vector3 = Vector3(4.0, 0.0, 1.25)
var _room_entry_dir: String = ""
var _item_nodes: Dictionary = {}
var _cauldron_fx_root: Node3D
var _repel_orbs: Array[Node3D] = []
var _room_builder: RoomBuilder = RoomBuilder.new()
var _gameplay_bg_layer: CanvasLayer
var _gameplay_bg_rect: TextureRect
var _world_viewport_container: SubViewportContainer
var _world_viewport: SubViewport


func _ready() -> void:
	DioramaLighting.force_transparent_background = true

	_gameplay_bg_layer = CanvasLayer.new()
	_gameplay_bg_layer.name = "GameplayBackgroundLayer"
	_gameplay_bg_layer.layer = -10
	add_child(_gameplay_bg_layer)

	_gameplay_bg_rect = TextureRect.new()
	_gameplay_bg_rect.name = "GameplayBackgroundArt"
	_gameplay_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameplay_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gameplay_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_gameplay_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay_bg_rect.modulate = Color(0.29, 0.28, 0.28, 1.0)
	if ResourceLoader.exists("res://assets/ui/background.webp"):
		_gameplay_bg_rect.texture = load("res://assets/ui/background.webp") as Texture2D
	_gameplay_bg_layer.add_child(_gameplay_bg_rect)

	var world_layer := CanvasLayer.new()
	world_layer.name = "World3DLayer"
	world_layer.layer = 0
	add_child(world_layer)

	_world_viewport_container = SubViewportContainer.new()
	_world_viewport_container.name = "WorldViewportContainer"
	_world_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world_viewport_container.stretch = true
	_world_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_viewport_container.visible = false  # Hidden until gameplay starts
	world_layer.add_child(_world_viewport_container)

	_world_viewport = SubViewport.new()
	_world_viewport.name = "WorldSubViewport"
	_world_viewport.transparent_bg = true
	_world_viewport.own_world_3d = true
	_world_viewport.msaa_3d = Viewport.MSAA_2X
	_world_viewport.handle_input_locally = false
	_world_viewport_container.add_child(_world_viewport)

	kl_data = KnightLoreData.load_default()
	room_container = Node3D.new()
	room_container.name = "RoomContainer"
	_world_viewport.add_child(room_container)

	audio_manager = ZxAudioManager.new()
	audio_manager.name = "ZxAudioManager"
	add_child(audio_manager)

	score_sequencer = KlScoreSequencer.new(audio_manager)
	score_sequencer.name = "KlScoreSequencer"
	score_sequencer.cue_finished.connect(_on_score_cue_finished)
	add_child(score_sequencer)

	ambience_director = KlAmbienceDirector.new(audio_manager)
	ambience_director.name = "KlAmbienceDirector"
	add_child(ambience_director)

	hud = KnightLoreHud.new()
	hud.name = "KnightLoreHud"
	add_child(hud)

	pause_menu = KnightLorePauseMenu.new()
	pause_menu.name = "KnightLorePauseMenu"
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.restart_requested.connect(_start_session)
	pause_menu.return_to_menu_requested.connect(_on_return_to_main_menu)
	pause_menu.control_mode_toggled.connect(_on_pause_control_toggled)
	pause_menu.camera_mode_toggled.connect(_on_pause_camera_toggled)
	pause_menu.sound_toggled.connect(_on_pause_sound_toggled)
	pause_menu.settings_requested.connect(_on_open_settings)
	pause_menu.save_game_requested.connect(_on_open_save_dialog)
	pause_menu.load_game_requested.connect(_on_open_load_dialog)
	pause_menu.map_requested.connect(_on_pause_map_requested)
	pause_menu.hint_requested.connect(_on_pause_hint_requested)
	pause_menu.prologue_requested.connect(_on_open_prologue)
	add_child(pause_menu)

	main_menu = KnightLoreMainMenu.new()
	main_menu.name = "KnightLoreMainMenu"
	main_menu.bind_audio(audio_manager, score_sequencer)
	main_menu.start_game_requested.connect(_on_menu_start_game)
	main_menu.exit_game_requested.connect(_on_menu_exit_game)
	main_menu.settings_requested.connect(_on_open_settings)
	main_menu.load_game_requested.connect(_on_open_load_dialog)
	main_menu.prologue_requested.connect(_on_open_prologue)
	add_child(main_menu)

	_settings_dialog = KnightLoreSettingsDialog.new()
	_settings_dialog.set_audio_manager(audio_manager)
	_settings_dialog.settings_saved.connect(_apply_settings)
	add_child(_settings_dialog)

	_save_load_dialog = KnightLoreSaveLoadDialog.new()
	_save_load_dialog.set_audio_manager(audio_manager)
	_save_load_dialog.save_selected.connect(_on_save_game_selected)
	_save_load_dialog.load_selected.connect(_on_load_game_selected)
	add_child(_save_load_dialog)

	_map_dialog = KnightLoreMapDialog.new()
	_map_dialog.closed.connect(_on_map_closed)
	_map_dialog.hint_requested_for_room.connect(_on_map_hint_requested)
	add_child(_map_dialog)

	_hint_dialog = KnightLoreHintDialog.new()
	_hint_dialog.closed.connect(_on_hint_closed)
	add_child(_hint_dialog)

	_prologue_dialog = KnightLorePrologueDialog.new()
	_prologue_dialog.closed.connect(_on_prologue_closed)
	add_child(_prologue_dialog)

	_load_settings_from_disk()

	session = KnightLoreSession.new()
	session.inventory_changed.connect(_on_inventory_changed)
	session.charm_accepted.connect(_on_charm_accepted)
	session.charm_rejected.connect(_on_charm_rejected)
	session.extra_life_gained.connect(_on_extra_life_gained)
	session.quest_won.connect(_on_quest_won)
	session.game_over_triggered.connect(_on_game_over)

	# If booted directly with test environment or default run, check whether to show main menu
	var capture_end: String = OS.get_environment("FILMATION_CAPTURE_END")
	var capture_dialog: String = OS.get_environment("FILMATION_CAPTURE_DIALOG")
	var show_title: bool = OS.get_environment("FILMATION_KL_NO_MENU") != "1" and OS.get_environment("FILMATION_KL_ROOM").is_empty() and OS.get_environment("FILMATION_CAPTURE_PAUSE") != "1" and capture_end.is_empty() and capture_dialog.is_empty()
	if show_title:
		_show_main_menu()
	else:
		if main_menu != null:
			main_menu.visible = false
		# Show the 3D viewport immediately for direct-launch / capture modes.
		if _world_viewport_container != null:
			_world_viewport_container.visible = true
		if score_sequencer != null:
			score_sequencer.stop_cue(0.0)
		_start_session()
		if capture_dialog == "settings" and _settings_dialog != null:
			_settings_dialog.open(_current_settings)
		elif capture_dialog == "save" and _save_load_dialog != null:
			_save_load_dialog.open(true)
		elif capture_dialog == "load" and _save_load_dialog != null:
			_save_load_dialog.open(false)
		elif capture_dialog == "map" and _map_dialog != null:
			_open_map()
		elif capture_dialog == "hint" and _hint_dialog != null:
			_open_hint(session.current_room_id)
		elif capture_dialog == "prologue" and _prologue_dialog != null:
			_open_prologue()
		elif OS.get_environment("FILMATION_CAPTURE_PAUSE") == "1" and pause_menu != null:
			pause_menu.open(_use_rotational, _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1, false)
		elif capture_end == "victory":
			session.charms_collected = KnightLoreSession.TOTAL_CHARMS_REQUIRED
			session.day_count = 12
			session.quest_completed = true
			_finish_victory_sequence()
		elif capture_end == "game_over":
			session.lives = 0
			session.day_count = 40
			session.game_over = true
			_on_game_over("OUT OF TIME")


func _show_main_menu(show_splash: bool = true) -> void:
	if pause_menu != null:
		pause_menu.close()
	if main_menu != null:
		if not show_splash:
			main_menu.set_splash_active(false)
		main_menu.visible = true
	if hud != null:
		hud.visible = false
	# Hide the 3D world so it does not render behind the menu.
	if _world_viewport_container != null:
		_world_viewport_container.visible = false
	if audio_manager != null:
		audio_manager.stop_ambience(0.4)
	if score_sequencer != null and not score_sequencer.is_playing("menu"):
		score_sequencer.play_cue("menu", true)


func _on_menu_start_game(settings: Dictionary) -> void:
	var skip_prologue: bool = bool(_current_settings.get("skip_prologue", false))
	if not skip_prologue and _prologue_dialog != null:
		_pending_start_settings = settings.duplicate()
		_open_prologue()
		return
	_execute_start_game(settings)


func _execute_start_game(settings: Dictionary) -> void:
	if main_menu != null:
		main_menu.visible = false
	if hud != null:
		hud.visible = true
	# Restore the 3D world display now that gameplay is starting.
	if _world_viewport_container != null:
		_world_viewport_container.visible = true
	var c_mode: String = str(settings.get("control_mode", "directional"))
	_use_rotational = (c_mode == "rotational")
	var cam_m: String = str(settings.get("camera_mode", "true_isometric"))
	_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 if cam_m == "dimetric_2_1" else DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
	var is_muted: bool = bool(settings.get("muted", false))
	if audio_manager != null:
		audio_manager.set_mute(is_muted)
	if score_sequencer != null:
		score_sequencer.play_cue("start_game", false)
	_start_session()


func _on_menu_exit_game() -> void:
	if get_tree() != null:
		get_tree().quit()


func _on_pause_resume() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_pause_toggle")


func _on_pause_control_toggled(is_rot: bool) -> void:
	_use_rotational = is_rot
	if player != null:
		player.set_rotational_mode(_use_rotational)
	_refresh_hud()
	if audio_manager != null:
		audio_manager.play_sfx("sfx_menu_select")


func _on_pause_camera_toggled(is_dimetric: bool) -> void:
	_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 if is_dimetric else DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		cam_rig.set_projection_mode(_camera_mode)
		if hud != null:
			hud.refresh_scroll_layout()
	if audio_manager != null:
		audio_manager.play_sfx("sfx_menu_select")


func _on_pause_sound_toggled(is_muted: bool) -> void:
	if audio_manager != null:
		audio_manager.set_mute(is_muted)


func _on_return_to_main_menu() -> void:
	_show_main_menu(false)


func _start_session() -> void:
	if hud != null:
		hud.hide_end_screen()
	var env_room_str: String = OS.get_environment("FILMATION_KL_ROOM")
	var override_rid: int = int(env_room_str) if not env_room_str.is_empty() else -1
	session.start_new_game(kl_data, -1, override_rid)
	_apply_settings_to_session_and_player()

	if OS.get_environment("FILMATION_KL_FORCE_NIGHT") == "1":
		session.is_night = true
		session.is_wulf = true

	_is_transforming = false
	_is_dying = false
	_victory_sequence_active = false
	_victory_timeout = 0.0
	_victory_sparkles.clear()
	_invuln_timer = 1.0
	if score_sequencer != null and not score_sequencer.is_playing("start_game"):
		score_sequencer.stop_cue(0.0)
	_load_room(session.current_room_id, "")
	if hud != null:
		hud.show_toast("Deliver 14 charms to Melkhior's Cauldron (Room 136) before Day 40!", 3.2)


func _load_room(room_id: int, spawn_dir: String) -> void:
	_transition_lock = true
	_item_nodes.clear()
	_repel_orbs.clear()
	_victory_sparkles.clear()
	_cauldron_fx_root = null
	room_director = null

	if player != null and is_instance_valid(player) and player.get_parent() != null:
		player.get_parent().remove_child(player)

	for child: Node in room_container.get_children():
		room_container.remove_child(child)
		child.free()

	var room_node := Node3D.new()
	room_node.name = "Room_%03d" % room_id
	room_container.add_child(room_node)

	var cam_mode_str: String = "dimetric_2_1" if _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 else "true_isometric"
	var lit_preset: String = "castle_moonlight_night" if session.is_night else "castle_stone_skylight"
	current_build = _room_builder.build_knight_lore_room(room_node, room_id, kl_data, lit_preset, cam_mode_str, true)
	if current_build.is_empty():
		_transition_lock = false
		return

	if _gameplay_bg_rect != null:
		_gameplay_bg_rect.modulate = Color(0.15, 0.16, 0.23, 1.0) if session.is_night else Color(0.29, 0.28, 0.28, 1.0)
	var is_forest: bool = bool(current_build.get("is_forest", false))
	if audio_manager != null:
		audio_manager.apply_biome("woodland" if is_forest else "dungeon")
	if ambience_director != null:
		ambience_director.set_biome("woodland" if is_forest else "dungeon")
		ambience_director.set_cycle(session.is_night)
	if score_sequencer != null and not score_sequencer.is_playing():
		score_sequencer.play_cue("gameplay_night" if session.is_night else "gameplay_day", true)

	var ent_root: Node3D = current_build.get("entities_root") as Node3D
	_cauldron_fx_root = Node3D.new()
	_cauldron_fx_root.name = "CauldronFX"
	room_node.add_child(_cauldron_fx_root)
	_cauldron_timer = 0.35

	for item_entry: Dictionary in session.get_room_items(room_id):
		_spawn_special_item_node(item_entry, ent_root)

	if player == null or not is_instance_valid(player):
		player = PlayerController.new()
		player.name = "HeroPlayer"
		player.stepped.connect(_on_player_stepped)
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)
		player.pushed.connect(_on_player_pushed)
	player.allow_mode_toggle_hotkey = false
	player.input_locked = false
	player.velocity = Vector3.ZERO
	if player.visual_root != null:
		player.visual_root.scale = Vector3.ONE
	player.set_rotational_mode(_use_rotational)
	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		player.set_camera_rig(cam_rig)

	var doorways: Node3D = current_build.get("doorways_root") as Node3D
	var room_dims: Vector3 = current_build.get("room_dims", Vector3(8.0, 6.0, 8.0))
	if hud != null and cam_rig != null:
		hud.bind_room_camera(cam_rig.camera, room_dims, 0.5)
	var spawn_pos: Vector3 = _resolve_spawn_pos(doorways, spawn_dir, room_dims)
	player.position = spawn_pos
	player.set_night_form(session.is_wulf)
	_sync_player_jump_params()
	room_node.add_child(player)
	player.reset_physics_interpolation()
	player.sync_shader_world_pos()
	if player.drop_shadow != null:
		player.drop_shadow.call_deferred("update_shadow")

	_room_entry_pos = spawn_pos
	_room_entry_dir = spawn_dir

	_wire_doorways(doorways)

	room_director = KlRoomDirector.new()
	room_director.name = "KlRoomDirector"
	room_director.portcullis_slammed.connect(_on_portcullis_slammed)
	room_director.entity_stepped.connect(_on_entity_stepped)
	room_node.add_child(room_director)
	room_director.activate_room(
		room_id,
		room_dims,
		current_build.get("architecture_root") as Node3D,
		ent_root,
		doorways,
		session,
		player,
		kl_data.entities_cfg
	)
	KlSparkleVfx.spawn_burst(room_node, spawn_pos + Vector3(0.0, 0.55, 0.0), &"appear")

	_refresh_hud()
	_transition_lock = false


func _resolve_spawn_pos(doorways: Node3D, spawn_dir: String, room_dims: Vector3) -> Vector3:
	var raw_pos := Vector3(room_dims.x * 0.5, 0.0, room_dims.z * 0.5)
	if doorways != null:
		if not spawn_dir.is_empty():
			var preferred: Marker3D = doorways.get_node_or_null("Spawn_" + spawn_dir) as Marker3D
			if preferred != null:
				raw_pos = preferred.position
		else:
			var first_any: Marker3D = null
			for child: Node in doorways.get_children():
				if child is Marker3D:
					var m: Marker3D = child as Marker3D
					if first_any == null:
						first_any = m
					if m.position.y < 0.5:
						raw_pos = m.position
						break
			if raw_pos == Vector3(room_dims.x * 0.5, 0.0, room_dims.z * 0.5) and first_any != null:
				raw_pos = first_any.position

	# Geometric AABB test against architecture blocks in current_build to guarantee
	# the player spawns safely atop any threshold blocks/steps without relying on async physics ticks
	var arch_root: Node3D = current_build.get("architecture_root") as Node3D
	if arch_root != null:
		var p_radius: float = 0.28
		for child: Node in arch_root.get_children():
			if child is StaticBody3D:
				var cshape: CollisionShape3D = child.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if cshape != null and cshape.shape is BoxShape3D:
					var box: BoxShape3D = cshape.shape as BoxShape3D
					var b_pos: Vector3 = child.position + cshape.position
					var b_half: Vector3 = box.size * 0.5
					# Check 2D horizontal overlap with player cylinder
					if absf(raw_pos.x - b_pos.x) < (b_half.x + p_radius) and absf(raw_pos.z - b_pos.z) < (b_half.z + p_radius):
						var block_top: float = b_pos.y + b_half.y
						if block_top > raw_pos.y and block_top <= 1.55:
							raw_pos.y = block_top

	return raw_pos


func _spawn_special_item_node(entry: Dictionary, parent_node: Node3D) -> KlSpecialItem:
	if parent_node == null:
		return null
	var item := KlSpecialItem.new()
	var iid: int = int(entry.get("id", -1))
	var tid: int = int(entry.get("type_id", 0))
	var pos: Vector3 = entry.get("pos", Vector3(4.0, 0.0, 4.0)) as Vector3
	item.configure(iid, tid, pos)
	if tid == 7:
		item.extra_life_touched.connect(_on_extra_life_touched)
	parent_node.add_child(item)
	_item_nodes[iid] = item
	return item


func _wire_doorways(doorways: Node3D) -> void:
	if doorways == null:
		return
	for child: Node in doorways.get_children():
		if child is Area3D and child.name.begins_with("Exit_"):
			var area: Area3D = child as Area3D
			area.body_entered.connect(_on_exit_entered.bind(area))


func _on_exit_entered(body: Node3D, exit_area: Area3D) -> void:
	if body != player or _transition_lock or _transition_cooldown > 0.0 or _is_dying or _is_transforming:
		return
	var dir_name: String = str(exit_area.get_meta("direction", ""))
	var target_rid: int = int(exit_area.get_meta("target_room_id", -1))
	if target_rid < 0 or not kl_data.has_room(target_rid):
		return
	call_deferred("_transition_to_room", dir_name, target_rid)


func _transition_to_room(dir_name: String, target_rid: int) -> void:
	if _transition_lock:
		return
	_save_active_item_positions()
	_transition_cooldown = 0.35
	var opp: String = str(OPPOSITE_DIR.get(dir_name, ""))
	session.enter_room(target_rid, opp)
	_load_room(target_rid, opp)


func _save_active_item_positions() -> void:
	var pos_by_id: Dictionary = {}
	for iid_v: Variant in _item_nodes.keys():
		var item: KlSpecialItem = _item_nodes[iid_v] as KlSpecialItem
		if item != null and is_instance_valid(item) and not item.is_arcing:
			pos_by_id[int(iid_v)] = item.position
	session.save_room_item_positions(session.current_room_id, pos_by_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_P:
			if _prologue_dialog != null and _prologue_dialog.visible:
				_prologue_dialog.close()
				get_viewport().set_input_as_handled()
				return
			if _hint_dialog != null and _hint_dialog.visible:
				_hint_dialog.close()
				get_viewport().set_input_as_handled()
				return
			if _map_dialog != null and _map_dialog.visible:
				_map_dialog.close()
				get_viewport().set_input_as_handled()
				return
			if pause_menu != null and (main_menu == null or not main_menu.visible):
				var is_dim: bool = (_camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1)
				var is_mut: bool = audio_manager.muted if audio_manager != null else false
				pause_menu.toggle(_use_rotational, is_dim, is_mut)
				if audio_manager != null:
					audio_manager.play_sfx("sfx_pause_toggle")
				get_viewport().set_input_as_handled()
				return
		elif k.keycode == KEY_M:
			if main_menu == null or not main_menu.visible:
				_toggle_map()
				get_viewport().set_input_as_handled()
				return
		elif k.keycode == KEY_H:
			if main_menu == null or not main_menu.visible:
				_toggle_hint(session.current_room_id if session != null else 136)
				get_viewport().set_input_as_handled()
				return
		elif k.keycode == KEY_N:
			if audio_manager != null:
				var m: bool = audio_manager.toggle_mute()
				if hud != null:
					hud.show_toast("Sound: %s" % ("OFF" if m else "ON"), 1.2)
		elif k.keycode == KEY_F1:
			_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 if _camera_mode == DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC else DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
			var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
			if cam_rig != null:
				cam_rig.set_projection_mode(_camera_mode)
				if hud != null:
					hud.refresh_scroll_layout()
		elif k.keycode == KEY_R:
			_start_session()


func _physics_process(delta: float) -> void:
	if _transition_cooldown > 0.0:
		_transition_cooldown = maxf(0.0, _transition_cooldown - delta)
	if _invuln_timer > 0.0:
		_invuln_timer = maxf(0.0, _invuln_timer - delta)

	if _victory_sequence_active:
		if player != null:
			player.input_locked = true
		_victory_timeout -= delta
		if _victory_timeout <= 0.0:
			_finish_victory_sequence()
		return

	if session.quest_completed or session.game_over:
		if player != null:
			player.input_locked = true
		if Input.is_action_just_pressed("interact"):
			_start_session()
		return

	if Input.is_action_just_pressed("toggle_move_mode"):
		_use_rotational = not _use_rotational
		if player != null:
			player.set_rotational_mode(_use_rotational)
		if hud != null:
			hud.show_toast("Controls: %s" % ("Classic Rotational" if _use_rotational else "Directional (8-Way)"), 1.6)
		_refresh_hud()

	if _is_dying:
		_death_timer -= delta
		if player != null and player.visual_root != null:
			player.visual_root.rotation.y += 12.0 * delta
		if _death_timer <= 0.0:
			_finish_player_death()
		return

	if _is_transforming:
		_transform_timer -= delta
		if player != null and player.visual_root != null:
			var pulse: float = 1.0 + 0.16 * sin(_transform_timer * 24.0)
			player.visual_root.scale = Vector3(pulse, pulse, pulse)
		if _transform_timer <= 0.0:
			_finish_transformation()
		else:
			_check_hazards()
		return

	if Input.is_action_just_pressed("interact") and player != null:
		_handle_interact()

	session.advance_cycle(delta)
	if session.game_over:
		return
	if session.pending_transform and player != null and player.is_on_floor():
		_begin_transformation()
		return

	if session.current_room_id == KnightLoreSession.CAULDRON_ROOM_ID and not session.quest_completed:
		_update_cauldron_room_spawner(delta)

	_check_hazards()
	_refresh_hud()


func _handle_interact() -> void:
	if _gameplay_bg_rect != null:
		_gameplay_bg_rect.modulate = Color(0.15, 0.16, 0.23, 1.0) if session.is_night else Color(0.29, 0.28, 0.28, 1.0)
	var is_forest: bool = bool(current_build.get("is_forest", false))
	if audio_manager != null:
		audio_manager.apply_biome("woodland" if is_forest else "dungeon")
	if ambience_director != null:
		ambience_director.set_biome("woodland" if is_forest else "dungeon")
		ambience_director.set_cycle(session.is_night)
	if score_sequencer != null and not score_sequencer.is_playing():
		score_sequencer.play_cue("gameplay_night" if session.is_night else "gameplay_day", true)

	var ent_root: Node3D = current_build.get("entities_root") as Node3D
	var closest_item: KlSpecialItem = null
	var best_dist: float = 0.95
	for iid_v: Variant in _item_nodes.keys():
		var item: KlSpecialItem = _item_nodes[iid_v] as KlSpecialItem
		if item == null or not is_instance_valid(item) or item.is_extra_life or item.is_arcing:
			continue
		var horiz_d: float = Vector2(item.global_position.x - player.global_position.x, item.global_position.z - player.global_position.z).length()
		var vert_d: float = absf(item.global_position.y - player.global_position.y)
		if horiz_d <= best_dist and vert_d <= 0.78:
			best_dist = horiz_d
			closest_item = item

	if closest_item != null:
		var pick_res: Dictionary = session.pickup_item(closest_item.item_id, player.position)
		if bool(pick_res.get("ok", false)):
			var picked_tid: int = int(pick_res.get("picked_type", 0))
			_item_nodes.erase(closest_item.item_id)
			closest_item.queue_free()
			var displaced: Dictionary = pick_res.get("displaced_item", {}) as Dictionary
			if not displaced.is_empty():
				_spawn_special_item_node(displaced, ent_root)
				if player.check_headroom_clear(0.76):
					player.position.y += 0.76
					player.reset_physics_interpolation()
			hud.show_toast("Picked up %s" % KnightLoreSession.get_charm_name(picked_tid))
			if audio_manager != null:
				audio_manager.play_sfx("sfx_pickup_item")
			_refresh_hud()
			return

	var headroom_ok: bool = player.check_headroom_clear(0.76)
	var drop_res: Dictionary = session.drop_or_rotate(session.current_room_id, player.position, headroom_ok)
	match str(drop_res.get("action", "")):
		"dropped":
			var d_entry: Dictionary = drop_res.get("dropped_item", {}) as Dictionary
			var d_node: KlSpecialItem = _spawn_special_item_node(d_entry, ent_root)
			if bool(drop_res.get("is_cauldron_drop", false)) and d_node != null:
				player.input_locked = true
				var d_id: int = int(d_entry.get("id", -1))
				var d_tid: int = int(d_entry.get("type_id", 0))
				d_node.position = player.position + Vector3(0.0, 0.20, 0.0)
				d_node.launch_cauldron_arc(CAULDRON_CENTER, Callable(self, "_on_cauldron_arc_done").bind(d_id, d_tid))
				if audio_manager != null:
					audio_manager.play_sfx("sfx_fall_or_drop", 4.0)
			else:
				player.position.y += 0.76
				player.velocity.y = maxf(player.velocity.y, 0.0)
				player.reset_physics_interpolation()
				hud.show_toast("Dropped %s (Climb!)" % KnightLoreSession.get_charm_name(int(d_entry.get("type_id", 0))))
				if audio_manager != null:
					audio_manager.play_sfx("sfx_menu_select")
		"rotated":
			hud.show_toast("Cycled Inventory Slots")
			if audio_manager != null:
				audio_manager.play_sfx("sfx_menu_select")
		"room_full":
			hud.show_toast("Too many charms already placed in this room!")
		"blocked_headroom":
			hud.show_toast("Not enough headroom to drop-climb!")
	_refresh_hud()


func _on_cauldron_arc_done(item_id: int, charm_type: int) -> void:
	if _item_nodes.has(item_id):
		var node: KlSpecialItem = _item_nodes[item_id] as KlSpecialItem
		_item_nodes.erase(item_id)
		if node != null and is_instance_valid(node):
			node.queue_free()
	session.resolve_cauldron_item(charm_type)
	if player != null and is_instance_valid(player) and not session.quest_completed:
		player.input_locked = false
	_refresh_hud()


func _on_portcullis_slammed() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_portcullis_slam")


func _on_entity_stepped(pos: Vector3) -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_step_guard_wizard", pos.x + pos.z)


func _on_score_cue_finished(cue_name: String) -> void:
	if cue_name == "start_game" and (main_menu == null or not main_menu.visible) and not session.game_over and not session.quest_completed:
		if score_sequencer != null:
			score_sequencer.play_cue("gameplay_night" if session.is_night else "gameplay_day", true)


func _on_player_stepped(pos: Vector3) -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_step_player", pos.x + pos.z)


func _on_player_jumped() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_jump")


func _on_player_landed() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_bounce")


func _on_player_pushed() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_push_block")


func _on_extra_life_touched(item_id: int) -> void:
	if session.collect_extra_life(item_id) and _item_nodes.has(item_id):
		var node: KlSpecialItem = _item_nodes[item_id] as KlSpecialItem
		_item_nodes.erase(item_id)
		if node != null and is_instance_valid(node):
			node.queue_free()
		if audio_manager != null:
			audio_manager.play_sfx("sfx_appear_sparkles")


func _begin_transformation() -> void:
	_is_transforming = true
	_transform_timer = 1.4
	if audio_manager != null:
		audio_manager.play_sfx("sfx_transform")
	if player != null:
		player.input_locked = true
		var fx_parent: Node3D = _cauldron_fx_root if (_cauldron_fx_root != null and is_instance_valid(_cauldron_fx_root)) else room_container
		KlSparkleVfx.spawn_burst(fx_parent, player.global_position + Vector3(0.0, 0.65, 0.0), &"transform", player)
	hud.show_toast("THE CURSE TAKES HOLD..." if session.is_night else "DAWN BREAKS — TRANSFORMING!", 1.5)


func _finish_transformation() -> void:
	_is_transforming = false
	session.complete_transformation()
	if player != null:
		player.input_locked = false
		if player.visual_root != null:
			player.visual_root.scale = Vector3.ONE
		player.set_night_form(session.is_wulf)
		_sync_player_jump_params()
	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	if lighting != null:
		var preset_name: String = "castle_moonlight_night" if session.is_night else "castle_stone_skylight"
		lighting.apply_preset(DioramaLighting.load_preset_by_name(preset_name), current_build.get("room_dims", Vector3(8, 6, 8)))
	if ambience_director != null:
		ambience_director.set_cycle(session.is_night)
	if score_sequencer != null:
		score_sequencer.play_cue("gameplay_night" if session.is_night else "gameplay_day", true)
	hud.show_toast("TRANSFORMED INTO WEREWOLF!" if session.is_wulf else "RESTORED TO HUMAN FORM!", 2.0)
	_refresh_hud()


func _update_cauldron_room_spawner(delta: float) -> void:
	var j: int = _repel_orbs.size() - 1
	while j >= 0:
		if _repel_orbs[j] == null or not is_instance_valid(_repel_orbs[j]):
			_repel_orbs.remove_at(j)
		j -= 1

	_cauldron_timer -= delta
	if _cauldron_timer <= 0.0:
		_cauldron_timer = 2.6
		if session.is_wulf:
			_spawn_repel_spell()
		else:
			_spawn_cauldron_hint_bubble()


func _spawn_cauldron_hint_bubble() -> void:
	if _cauldron_fx_root == null or not is_instance_valid(_cauldron_fx_root):
		return
	var next_charm: int = session.get_next_required_charm()
	if next_charm < 0:
		return

	var bubble := Node3D.new()
	bubble.name = "CauldronHintBubble"
	bubble.position = CAULDRON_CENTER + Vector3(0.0, 0.25, 0.0)

	var orb_mesh := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.34
	sph.height = 0.68
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.70, 0.95, 1.0, 0.12)
	b_mat.emission_enabled = true
	b_mat.emission = Color(0.40, 0.85, 1.0)
	b_mat.emission_energy_multiplier = 0.35
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.cull_mode = BaseMaterial3D.CULL_BACK
	b_mat.roughness = 0.1
	b_mat.metallic = 0.1
	sph.material = b_mat
	orb_mesh.mesh = sph
	bubble.add_child(orb_mesh)

	var glb_path: String = KnightLoreSession.get_charm_glb_path(next_charm)
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var item_vis: Node3D = packed.instantiate() as Node3D
			item_vis.position = Vector3(0.0, -0.18, 0.0)
			item_vis.scale = Vector3(1.15, 1.15, 1.15)
			bubble.add_child(item_vis)

	_cauldron_fx_root.add_child(bubble)
	var tw: Tween = bubble.create_tween()
	tw.set_parallel(true)
	tw.tween_property(bubble, "position:y", CAULDRON_CENTER.y + 1.55, 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bubble, "rotation:y", TAU, 2.0)
	tw.chain().tween_callback(bubble.queue_free)


func _spawn_repel_spell() -> void:
	if _cauldron_fx_root == null or not is_instance_valid(_cauldron_fx_root) or _repel_orbs.size() >= 2:
		return
	var fg_types: Dictionary = kl_data.entities_cfg.get("foreground_types", {}) as Dictionary
	var spell_cfg: Dictionary = fg_types.get("25", {"behavior": "chase_player", "params": {"speed": 4, "near_arch_speed": 1}}) as Dictionary
	var sz: Vector3 = KnightLoreData.kl_size_to_meters(float(spell_cfg.get("w", 5)), float(spell_cfg.get("d", 5)), float(spell_cfg.get("h", 12)))
	var orb := KlHazardEntity.new()
	orb.name = "CauldronRepelSpell"
	orb.configure("repel_spell", spell_cfg, sz, Vector3(CAULDRON_CENTER.x, 0.45, CAULDRON_CENTER.z), true)
	var packed: PackedScene = ResourceLoader.load("res://assets/props/item_crystal_ball.glb") as PackedScene
	if packed != null:
		var vis: Node3D = packed.instantiate() as Node3D
		vis.name = "ModelVisual"
		RoomBuilder._configure_static_model_recursive(vis)
		orb.add_child(vis)
	_cauldron_fx_root.add_child(orb)
	if room_director != null:
		orb.bind_director(room_director)
	orb.simulation_active = true
	_repel_orbs.append(orb)


static func is_player_in_hazard_core(player_pos: Vector3, haz_center: Vector3, haz_box_size: Vector3) -> bool:
	var p_min_y: float = player_pos.y + 0.08
	var p_max_y: float = player_pos.y + 1.15
	var h_half_y: float = haz_box_size.y * 0.44
	if p_max_y <= (haz_center.y - h_half_y) or p_min_y >= (haz_center.y + h_half_y):
		return false

	var h_half_x: float = maxf(haz_box_size.x * 0.5 * HAZARD_CORE_SCALE, 0.10)
	var h_half_z: float = maxf(haz_box_size.z * 0.5 * HAZARD_CORE_SCALE, 0.10)
	var closest_x: float = clampf(player_pos.x, haz_center.x - h_half_x, haz_center.x + h_half_x)
	var closest_z: float = clampf(player_pos.z, haz_center.z - h_half_z, haz_center.z + h_half_z)
	return Vector2(player_pos.x - closest_x, player_pos.z - closest_z).length() < PLAYER_LETHAL_RADIUS


func _check_hazards() -> void:
	if player == null or _is_dying or _invuln_timer > 0.0 or _transition_lock or _victory_sequence_active or (session != null and session.invulnerable):
		return
	if player.position.y < -3.0:
		_trigger_player_death()
		return
	for haz: Node in get_tree().get_nodes_in_group("kl_lethal_hazards"):
		if not (haz is PhysicsBody3D) or not is_instance_valid(haz) or not haz.is_inside_tree():
			continue
		var hb: PhysicsBody3D = haz as PhysicsBody3D
		var col_shape: CollisionShape3D = hb.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col_shape == null or not (col_shape.shape is BoxShape3D):
			continue
		var bsz: Vector3 = (col_shape.shape as BoxShape3D).size
		if is_player_in_hazard_core(player.global_position, col_shape.global_position, bsz):
			_trigger_player_death()
			return


func _trigger_player_death() -> void:
	if (session != null and session.invulnerable) or _is_dying or _invuln_timer > 0.0 or session.game_over or session.quest_completed or _victory_sequence_active:
		return
	_is_dying = true
	_death_timer = 0.75
	if audio_manager != null:
		audio_manager.play_sfx("sfx_death_sparkles")
	if player != null:
		player.input_locked = true
		var fx_parent: Node3D = _cauldron_fx_root if (_cauldron_fx_root != null and is_instance_valid(_cauldron_fx_root)) else room_container
		KlSparkleVfx.spawn_burst(fx_parent, player.global_position + Vector3(0.0, 0.65, 0.0), &"death")
	hud.show_toast("STRUCK BY DUNGEON CURSE!", 1.2)


func _finish_player_death() -> void:
	_is_dying = false
	var res: Dictionary = session.apply_player_death()
	if bool(res.get("game_over", false)):
		return
	_invuln_timer = 1.25
	if player != null:
		player.input_locked = false
		if player.visual_root != null:
			player.visual_root.scale = Vector3.ONE
		player.position = _room_entry_pos
		player.velocity = Vector3.ZERO
		player.set_night_form(session.is_wulf)
		player.reset_physics_interpolation()
		player.sync_shader_world_pos()
		var fx_parent: Node3D = _cauldron_fx_root if (_cauldron_fx_root != null and is_instance_valid(_cauldron_fx_root)) else room_container
		KlSparkleVfx.spawn_burst(fx_parent, _room_entry_pos + Vector3(0.0, 0.55, 0.0), &"appear")
	_refresh_hud()


func _refresh_hud() -> void:
	if hud == null or session == null:
		return
	if _gameplay_bg_rect != null:
		_gameplay_bg_rect.modulate = Color(0.15, 0.16, 0.23, 1.0) if session.is_night else Color(0.29, 0.28, 0.28, 1.0)
	var is_forest: bool = bool(current_build.get("is_forest", false))
	hud.update_status(
		session.current_room_id,
		is_forest,
		session.day_count,
		session.is_night,
		session.is_wulf,
		session.half_day_progress,
		session.charms_collected,
		session.lives,
		_use_rotational
	)
	hud.update_inventory(session.inventory)


func _on_inventory_changed(slots: Array) -> void:
	if hud != null:
		hud.update_inventory(slots)


func _on_charm_accepted(charm_type: int, collected: int, total: int) -> void:
	if _cauldron_fx_root != null and is_instance_valid(_cauldron_fx_root):
		KlSparkleVfx.spawn_burst(_cauldron_fx_root, CAULDRON_CENTER + Vector3(0.0, 0.25, 0.0), &"cauldron_accept")
	if audio_manager != null:
		audio_manager.play_sfx("sfx_cauldron_accept")
	if hud != null:
		hud.show_toast("CAULDRON ACCEPTED %s (%d/%d)!" % [KnightLoreSession.get_charm_name(charm_type).to_upper(), collected, total], 2.5)


func _on_charm_rejected(charm_type: int) -> void:
	if _cauldron_fx_root != null and is_instance_valid(_cauldron_fx_root):
		KlSparkleVfx.spawn_burst(_cauldron_fx_root, CAULDRON_CENTER + Vector3(0.0, 0.25, 0.0), &"cauldron_reject")
	if audio_manager != null:
		audio_manager.play_sfx("sfx_cauldron_reject")
	if hud != null:
		hud.show_toast("WRONG CHARM (%s)! WATCH THE CAULDRON BUBBLE!" % KnightLoreSession.get_charm_name(charm_type).to_upper(), 2.8)


func _on_extra_life_gained(new_lives: int) -> void:
	if audio_manager != null:
		audio_manager.play_sfx("sfx_appear_sparkles")
	if hud != null:
		hud.show_toast("EXTRA LIFE GAINED! (%d)" % new_lives, 2.2)
	_refresh_hud()


func _on_quest_won() -> void:
	if (
		session.current_room_id == KnightLoreSession.CAULDRON_ROOM_ID
		and player != null
		and is_instance_valid(player)
		and _cauldron_fx_root != null
		and is_instance_valid(_cauldron_fx_root)
	):
		_start_victory_sequence()
	else:
		_finish_victory_sequence()
	_refresh_hud()


func _start_victory_sequence() -> void:
	_victory_sequence_active = true
	_victory_timeout = 2.6
	_victory_sparkles.clear()
	_invuln_timer = 99.0
	if player != null:
		player.input_locked = true
	if room_director != null:
		room_director.deactivate_hazards()
	for orb: Node3D in _repel_orbs:
		if orb != null and is_instance_valid(orb):
			orb.queue_free()
	_repel_orbs.clear()

	if hud != null:
		hud.show_toast("THE CURSE IS LIFTED!", 2.5)

	var arch_root: Node3D = current_build.get("architecture_root") as Node3D
	if arch_root != null:
		for child: Node in arch_root.get_children():
			if child is Node3D and bool(child.get_meta("kl_victory_block", false)):
				var blk: Node3D = child as Node3D
				var spos: Vector3 = blk.global_position
				blk.visible = false
				var vs: KlSparkleVfx = KlSparkleVfx.spawn_victory_sparkle(_cauldron_fx_root, spos, player, 2.25)
				if vs != null:
					vs.converged.connect(_on_victory_sparkle_converged)
					_victory_sparkles.append(vs)

	if _victory_sparkles.is_empty():
		for i: int in range(6):
			var ang: float = TAU * float(i) / 6.0
			var rpos: Vector3 = CAULDRON_CENTER + Vector3(cos(ang) * 1.1, 0.25, sin(ang) * 1.1)
			var vs: KlSparkleVfx = KlSparkleVfx.spawn_victory_sparkle(_cauldron_fx_root, rpos, player, 2.25)
			if vs != null:
				vs.converged.connect(_on_victory_sparkle_converged)
				_victory_sparkles.append(vs)


func _on_victory_sparkle_converged(_sparkle: KlSparkleVfx) -> void:
	if _victory_sequence_active:
		_finish_victory_sequence()


func _finish_victory_sequence() -> void:
	_victory_sequence_active = false
	_victory_sparkles.clear()
	if score_sequencer != null:
		score_sequencer.play_cue("game_complete", false)
	elif audio_manager != null:
		audio_manager.play_tune("game_complete", false)
	if hud != null:
		hud.show_end_screen(true, session)
	_refresh_hud()


func _on_game_over(reason: String) -> void:
	if score_sequencer != null:
		score_sequencer.play_cue("game_over", false)
	elif audio_manager != null:
		audio_manager.play_tune("game_over", false)
	if hud != null:
		hud.show_end_screen(false, session, reason)
	_refresh_hud()


func _sync_player_jump_params() -> void:
	if player == null or not is_instance_valid(player):
		return
	var boost: bool = bool(_current_settings.get("jump_boost", false))
	player.jump_boost = boost
	var boost_mult: float = 1.45 if boost else 1.0
	player.jump_height = 1.35 * boost_mult * (1.22 if (session != null and session.is_wulf) else 1.0)
	player.recompute_jump_constants()


func _load_settings_from_disk() -> void:
	if OS.get_environment("FILMATION_KL_NO_MENU") == "1" or not OS.get_environment("FILMATION_KL_ROOM").is_empty() or not OS.get_environment("FILMATION_CAPTURE_END").is_empty():
		return
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		for k: String in d:
			_current_settings[k] = d[k]


func _save_settings_to_disk() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_current_settings, "\t"))
		f.close()


func _apply_settings(dict: Dictionary) -> void:
	for k: String in dict:
		_current_settings[k] = dict[k]
	_apply_settings_to_session_and_player()
	_save_settings_to_disk()


func _apply_settings_to_session_and_player() -> void:
	if session != null:
		var mode: String = str(_current_settings.get("lives_mode", "normal"))
		match mode:
			"99":
				session.lives = 99
				session.infinite_lives = false
			"infinite":
				session.lives = KnightLoreSession.INFINITE_LIVES
				session.infinite_lives = true
			_:
				if session.lives == 99 or session.lives >= KnightLoreSession.INFINITE_LIVES:
					session.lives = KnightLoreSession.STARTING_LIVES
				session.infinite_lives = false
		session.invulnerable = bool(_current_settings.get("invulnerable", false))
		_refresh_hud()

	_sync_player_jump_params()

	if audio_manager != null:
		audio_manager.set_music_volume(float(_current_settings.get("music_volume", 0.85)))
		audio_manager.set_sfx_volume(float(_current_settings.get("sfx_volume", 0.90)))


func _on_open_settings() -> void:
	if _settings_dialog != null:
		_settings_dialog.open(_current_settings)


func _on_open_save_dialog() -> void:
	if _save_load_dialog != null:
		_save_load_dialog.open(true)


func _on_open_load_dialog() -> void:
	if _save_load_dialog != null:
		_save_load_dialog.open(false)


func _toggle_map() -> void:
	if _map_dialog == null:
		return
	if _map_dialog.visible:
		_map_dialog.close()
	else:
		_open_map()


func _open_map() -> void:
	if _map_dialog == null:
		return
	if pause_menu != null and pause_menu.visible:
		pause_menu.close()
	if _hint_dialog != null and _hint_dialog.visible:
		_hint_dialog.close()
	get_tree().paused = true
	var cur_rid: int = session.current_room_id if session != null else 136
	var visited: Dictionary = session.visited_rooms if session != null else {}
	var charms: int = session.charms_collected if session != null else 0
	var req_charm: int = session.get_next_required_charm() if session != null else 0
	_map_dialog.open(cur_rid, visited, charms, req_charm)
	if audio_manager != null:
		audio_manager.play_sfx("sfx_menu_select")


func _on_map_closed() -> void:
	if (_hint_dialog == null or not _hint_dialog.visible) and (pause_menu == null or not pause_menu.visible):
		get_tree().paused = false


func _toggle_hint(room_id: int) -> void:
	if _hint_dialog == null:
		return
	if _hint_dialog.visible:
		_hint_dialog.close()
	else:
		_open_hint(room_id)


func _open_hint(room_id: int) -> void:
	if _hint_dialog == null:
		return
	if pause_menu != null and pause_menu.visible:
		pause_menu.close()
	get_tree().paused = true
	_hint_dialog.open(room_id, session)
	if audio_manager != null:
		audio_manager.play_sfx("sfx_menu_select")


func _on_hint_closed() -> void:
	if (_map_dialog == null or not _map_dialog.visible) and (pause_menu == null or not pause_menu.visible):
		get_tree().paused = false


func _on_map_hint_requested(room_id: int) -> void:
	_open_hint(room_id)


func _on_open_prologue() -> void:
	_open_prologue()


func _open_prologue() -> void:
	if _prologue_dialog == null:
		return
	if pause_menu != null and pause_menu.visible:
		pause_menu.close()
	get_tree().paused = true
	var skip_p: bool = bool(_current_settings.get("skip_prologue", false))
	_prologue_dialog.open(skip_p)
	if audio_manager != null:
		audio_manager.play_sfx("sfx_menu_select")


func _on_prologue_closed(dont_show_again: bool) -> void:
	_current_settings["skip_prologue"] = dont_show_again
	_save_settings_to_disk()
	if (_map_dialog == null or not _map_dialog.visible) and (_hint_dialog == null or not _hint_dialog.visible) and (pause_menu == null or not pause_menu.visible):
		get_tree().paused = false
	if not _pending_start_settings.is_empty():
		var settings_to_start: Dictionary = _pending_start_settings.duplicate()
		_pending_start_settings.clear()
		_execute_start_game(settings_to_start)


func _on_pause_map_requested() -> void:
	_open_map()


func _on_pause_hint_requested() -> void:
	var rid: int = session.current_room_id if session != null else 136
	_open_hint(rid)


func _on_save_game_selected(slot_idx: int, slot_path: String) -> void:
	var err: Error = save_game_to_slot(slot_idx, slot_path)
	if err == OK:
		if hud != null:
			hud.show_toast("Game Saved to Slot %d!" % slot_idx, 2.0)
		if audio_manager != null:
			audio_manager.play_sfx("sfx_potion_pickup")
	else:
		if hud != null:
			hud.show_toast("Failed to Save Game!", 2.0)


func _on_load_game_selected(slot_idx: int, slot_path: String) -> void:
	var err: Error = load_game_from_slot(slot_idx, slot_path)
	if err == OK:
		if main_menu != null and main_menu.visible:
			main_menu.visible = false
		if _world_viewport_container != null:
			_world_viewport_container.visible = true
		if hud != null:
			hud.visible = true
			hud.show_toast("Game Loaded from Slot %d!" % slot_idx, 2.5)
		if pause_menu != null and pause_menu.visible:
			pause_menu.close()
		if audio_manager != null:
			audio_manager.play_sfx("sfx_potion_pickup")
	else:
		if hud != null:
			hud.show_toast("Failed to Load Game!", 2.0)


func save_game_to_slot(slot_idx: int, path: String) -> Error:
	var dir_path: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var now_dict: Dictionary = Time.get_datetime_dict_from_system()
	var time_str: String = "%04d-%02d-%02d %02d:%02d" % [
		now_dict.get("year", 2026),
		now_dict.get("month", 1),
		now_dict.get("day", 1),
		now_dict.get("hour", 0),
		now_dict.get("minute", 0)
	]

	var p_pos: Array = [0.0, 0.0, 0.0]
	var p_rot: float = 0.0
	if player != null and is_instance_valid(player):
		p_pos = [player.position.x, player.position.y, player.position.z]
		p_rot = player.rotation.y

	var save_data := {
		"version": 1,
		"metadata": {
			"slot": slot_idx,
			"room_id": session.current_room_id,
			"day": session.day_count,
			"is_night": session.is_night,
			"charms": session.charms_collected,
			"lives": session.lives,
			"saved_at": time_str
		},
		"settings": _current_settings.duplicate(),
		"game_state": {
			"camera_mode": "dimetric_2_1" if _camera_mode == DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 else "true_isometric",
			"use_rotational": _use_rotational,
			"player_pos": p_pos,
			"player_rot_y": p_rot
		},
		"session": session.serialize_state()
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return OK


func load_game_from_slot(_slot_idx: int, path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json_str: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return ERR_PARSE_ERROR
	var data: Dictionary = parsed as Dictionary

	var loaded_settings: Dictionary = data.get("settings", {}) as Dictionary
	if not loaded_settings.is_empty():
		_apply_settings(loaded_settings)

	var gs: Dictionary = data.get("game_state", {}) as Dictionary
	_use_rotational = bool(gs.get("use_rotational", false))
	var cam_str: String = str(gs.get("camera_mode", "true_isometric"))
	_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 if cam_str == "dimetric_2_1" else DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC

	var sess_data: Dictionary = data.get("session", {}) as Dictionary
	session.hydrate_state(sess_data)

	_is_transforming = false
	_is_dying = false
	_victory_sequence_active = false
	_victory_timeout = 0.0
	_invuln_timer = 1.0

	_load_room(session.current_room_id, "")

	var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		cam_rig.set_projection_mode(_camera_mode)

	if player != null and is_instance_valid(player):
		var p_arr: Array = gs.get("player_pos", []) as Array
		if p_arr.size() >= 3:
			player.position = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
			player.reset_physics_interpolation()
			player.sync_shader_world_pos()
		player.rotation.y = float(gs.get("player_rot_y", 0.0))
		player.set_night_form(session.is_wulf)
		_sync_player_jump_params()

	_refresh_hud()
	return OK
