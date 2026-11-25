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

var kl_data: KnightLoreData
var session: KnightLoreSession
var hud: KnightLoreHud
var room_container: Node3D
var current_build: Dictionary = {}
var player: PlayerController

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

var _room_entry_pos: Vector3 = Vector3(4.0, 0.0, 1.25)
var _room_entry_dir: String = ""
var _item_nodes: Dictionary = {}
var _cauldron_fx_root: Node3D
var _repel_orbs: Array[Node3D] = []
var _room_builder: RoomBuilder = RoomBuilder.new()


func _ready() -> void:
	kl_data = KnightLoreData.load_default()
	room_container = Node3D.new()
	room_container.name = "RoomContainer"
	add_child(room_container)

	hud = KnightLoreHud.new()
	hud.name = "KnightLoreHud"
	add_child(hud)

	session = KnightLoreSession.new()
	session.inventory_changed.connect(_on_inventory_changed)
	session.charm_accepted.connect(_on_charm_accepted)
	session.charm_rejected.connect(_on_charm_rejected)
	session.extra_life_gained.connect(_on_extra_life_gained)
	session.quest_won.connect(_on_quest_won)
	session.game_over_triggered.connect(_on_game_over)

	_start_session()


func _start_session() -> void:
	if hud != null:
		hud.hide_end_screen()
	var env_room_str: String = OS.get_environment("FILMATION_KL_ROOM")
	var override_rid: int = int(env_room_str) if not env_room_str.is_empty() else -1
	session.start_new_game(kl_data, -1, override_rid)

	if OS.get_environment("FILMATION_KL_FORCE_NIGHT") == "1":
		session.is_night = true
		session.is_wulf = true

	_is_transforming = false
	_is_dying = false
	_invuln_timer = 1.0
	_load_room(session.current_room_id, "")
	if hud != null:
		hud.show_toast("Deliver 14 charms to Melkhior's Cauldron (Room 136) before Day 40!", 3.2)


func _load_room(room_id: int, spawn_dir: String) -> void:
	_transition_lock = true
	_item_nodes.clear()
	_repel_orbs.clear()
	_cauldron_fx_root = null

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
	var spawn_pos: Vector3 = _resolve_spawn_pos(doorways, spawn_dir, room_dims)
	player.position = spawn_pos
	player.set_night_form(session.is_wulf)
	player.jump_height = 1.35 * (1.22 if session.is_wulf else 1.0)
	player.recompute_jump_constants()
	room_node.add_child(player)
	player.reset_physics_interpolation()
	player.sync_shader_world_pos()
	if player.drop_shadow != null:
		player.drop_shadow.call_deferred("update_shadow")

	_room_entry_pos = spawn_pos
	_room_entry_dir = spawn_dir

	_wire_doorways(doorways)

	_refresh_hud()
	_transition_lock = false


func _resolve_spawn_pos(doorways: Node3D, spawn_dir: String, room_dims: Vector3) -> Vector3:
	if doorways != null:
		if not spawn_dir.is_empty():
			var preferred: Marker3D = doorways.get_node_or_null("Spawn_" + spawn_dir) as Marker3D
			if preferred != null:
				return preferred.position
		var first_any: Marker3D = null
		for child: Node in doorways.get_children():
			if child is Marker3D:
				var m: Marker3D = child as Marker3D
				if first_any == null:
					first_any = m
				if m.position.y < 0.5:
					return m.position
		if first_any != null:
			return first_any.position
	return Vector3(room_dims.x * 0.5, 0.0, room_dims.z * 0.5)


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
		if k.keycode == KEY_F1:
			_camera_mode = DioramaCameraRig.ProjectionMode.DIMETRIC_2_1 if _camera_mode == DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC else DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC
			var cam_rig: DioramaCameraRig = current_build.get("camera_rig") as DioramaCameraRig
			if cam_rig != null:
				cam_rig.set_projection_mode(_camera_mode)
		elif k.keycode == KEY_R:
			_start_session()


func _physics_process(delta: float) -> void:
	if _transition_cooldown > 0.0:
		_transition_cooldown = maxf(0.0, _transition_cooldown - delta)
	if _invuln_timer > 0.0:
		_invuln_timer = maxf(0.0, _invuln_timer - delta)

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
			else:
				player.position.y += 0.76
				player.velocity.y = maxf(player.velocity.y, 0.0)
				player.reset_physics_interpolation()
				hud.show_toast("Dropped %s (Climb!)" % KnightLoreSession.get_charm_name(int(d_entry.get("type_id", 0))))
		"rotated":
			hud.show_toast("Cycled Inventory Slots")
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


func _on_extra_life_touched(item_id: int) -> void:
	if session.collect_extra_life(item_id) and _item_nodes.has(item_id):
		var node: KlSpecialItem = _item_nodes[item_id] as KlSpecialItem
		_item_nodes.erase(item_id)
		if node != null and is_instance_valid(node):
			node.queue_free()


func _begin_transformation() -> void:
	_is_transforming = true
	_transform_timer = 1.4
	if player != null:
		player.input_locked = true
	hud.show_toast("THE CURSE TAKES HOLD..." if session.is_night else "DAWN BREAKS — TRANSFORMING!", 1.5)


func _finish_transformation() -> void:
	_is_transforming = false
	session.complete_transformation()
	if player != null:
		player.input_locked = false
		if player.visual_root != null:
			player.visual_root.scale = Vector3.ONE
		player.set_night_form(session.is_wulf)
		player.jump_height = 1.35 * (1.22 if session.is_wulf else 1.0)
		player.recompute_jump_constants()
	var lighting: DioramaLighting = current_build.get("lighting") as DioramaLighting
	if lighting != null:
		var preset_name: String = "castle_moonlight_night" if session.is_night else "castle_stone_skylight"
		lighting.apply_preset(DioramaLighting.load_preset_by_name(preset_name), current_build.get("room_dims", Vector3(8, 6, 8)))
	hud.show_toast("TRANSFORMED INTO WEREWOLF!" if session.is_wulf else "RESTORED TO HUMAN FORM!", 2.0)
	_refresh_hud()


func _update_cauldron_room_spawner(delta: float) -> void:
	_cauldron_timer -= delta
	if _cauldron_timer <= 0.0:
		_cauldron_timer = 2.6
		if session.is_wulf:
			_spawn_repel_spell()
		else:
			_spawn_cauldron_hint_bubble()

	# Move active homing Repel Spell orbs toward Wulf player
	var i: int = _repel_orbs.size() - 1
	while i >= 0:
		var orb: Node3D = _repel_orbs[i]
		if orb == null or not is_instance_valid(orb):
			_repel_orbs.remove_at(i)
		elif player != null:
			var target: Vector3 = player.global_position + Vector3(0.0, 0.55, 0.0)
			var to_p: Vector3 = target - orb.global_position
			var dist: float = to_p.length()
			if dist < 0.55:
				orb.queue_free()
				_repel_orbs.remove_at(i)
				_trigger_player_death()
				return
			elif dist > 0.01:
				orb.global_position += (to_p / dist) * 2.4 * delta
		i -= 1


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
	b_mat.albedo_color = Color(0.35, 0.98, 0.85, 0.36)
	b_mat.emission_enabled = true
	b_mat.emission = Color(0.25, 0.95, 0.78)
	b_mat.emission_energy_multiplier = 1.4
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sph.material = b_mat
	orb_mesh.mesh = sph
	bubble.add_child(orb_mesh)

	var glb_path: String = KnightLoreSession.get_charm_glb_path(next_charm)
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var item_vis: Node3D = packed.instantiate() as Node3D
			item_vis.position = Vector3(0.0, -0.22, 0.0)
			item_vis.scale = Vector3(0.75, 0.75, 0.75)
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
	var orb := Node3D.new()
	orb.name = "CauldronRepelSpell"
	orb.position = CAULDRON_CENTER + Vector3(0.0, 0.30, 0.0)
	var packed: PackedScene = ResourceLoader.load("res://assets/props/item_crystal_ball.glb") as PackedScene
	if packed != null:
		var vis: Node3D = packed.instantiate() as Node3D
		orb.add_child(vis)
	_cauldron_fx_root.add_child(orb)
	_repel_orbs.append(orb)


func _check_hazards() -> void:
	if player == null or _is_dying or _invuln_timer > 0.0 or _transition_lock:
		return
	if player.position.y < -3.0:
		_trigger_player_death()
		return
	for i: int in range(player.get_slide_collision_count()):
		var col: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider is Node and (collider as Node).is_in_group("kl_lethal_hazards"):
			_trigger_player_death()
			return
	for haz: Node in get_tree().get_nodes_in_group("kl_lethal_hazards"):
		if not (haz is StaticBody3D) or not is_instance_valid(haz):
			continue
		var hb: StaticBody3D = haz as StaticBody3D
		var col_shape: CollisionShape3D = hb.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col_shape == null or not (col_shape.shape is BoxShape3D):
			continue
		var bsz: Vector3 = (col_shape.shape as BoxShape3D).size
		var diff: Vector3 = player.global_position + Vector3(0.0, 0.45, 0.0) - hb.global_position
		if absf(diff.x) < (bsz.x * 0.5 + 0.24) and absf(diff.z) < (bsz.z * 0.5 + 0.24) and absf(diff.y) < (bsz.y * 0.5 + 0.48):
			_trigger_player_death()
			return


func _trigger_player_death() -> void:
	if _is_dying or _invuln_timer > 0.0 or session.game_over or session.quest_completed:
		return
	_is_dying = true
	_death_timer = 0.75
	if player != null:
		player.input_locked = true
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
	_refresh_hud()


func _refresh_hud() -> void:
	if hud == null or session == null:
		return
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
	if hud != null:
		hud.show_toast("CAULDRON ACCEPTED %s (%d/%d)!" % [KnightLoreSession.get_charm_name(charm_type).to_upper(), collected, total], 2.5)


func _on_charm_rejected(charm_type: int) -> void:
	if hud != null:
		hud.show_toast("WRONG CHARM (%s)! WATCH THE CAULDRON BUBBLE!" % KnightLoreSession.get_charm_name(charm_type).to_upper(), 2.8)


func _on_extra_life_gained(new_lives: int) -> void:
	if hud != null:
		hud.show_toast("EXTRA LIFE GAINED! (%d)" % new_lives, 2.2)
	_refresh_hud()


func _on_quest_won() -> void:
	if hud != null:
		hud.show_end_screen(true, session)
	_refresh_hud()


func _on_game_over(reason: String) -> void:
	if hud != null:
		hud.show_end_screen(false, session, reason)
	_refresh_hud()
