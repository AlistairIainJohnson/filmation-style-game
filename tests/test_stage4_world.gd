extends GutTest

var _container: Node3D


func _wm() -> WorldManagerNode:
	return get_node("/root/WorldManager") as WorldManagerNode


func _cm() -> CycleManagerNode:
	return get_node("/root/CycleManager") as CycleManagerNode


func before_each() -> void:
	_cm().reset_cycle()
	_wm().reset_world_state()
	_container = Node3D.new()
	_container.name = "TestWorldContainer"
	add_child_autofree(_container)
	_wm().set_room_container(_container)
	assert_true(_wm().load_world_manifest("res://data/world_graph.json"))


func after_each() -> void:
	_wm().reset_world_state()
	_cm().reset_cycle()


func test_world_graph_loads_and_preloads_neighbors() -> void:
	var wm: WorldManagerNode = _wm()
	assert_gte(wm.manifest.size(), 3, "World manifest should register at least 3 rooms")
	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	assert_eq(wm.current_room_id, Vector2i(8, 8))

	for _i: int in range(20):
		wm.poll_threaded_loads()
		if wm.is_scene_preloaded("res://core/world/chamber_shell.tscn"):
			break
		await wait_physics_frames(1)

	assert_true(
		wm.is_scene_preloaded("res://core/world/chamber_shell.tscn"),
		"Cooperative threaded preloader must complete chamber_shell.tscn load"
	)


func test_multi_room_persistence_roundtrip() -> void:
	var wm: WorldManagerNode = _wm()
	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	var entity_map_88: Dictionary = wm.current_build.get("entity_map", {}) as Dictionary
	var chest := entity_map_88.get("chest_01") as PushableBlock
	var plate := entity_map_88.get("plate_01") as TriggerSwitch
	var gate := entity_map_88.get("gate_01") as Portcullis

	await wait_physics_frames(4)
	chest.global_position = Vector3(4.5, 0.0, 3.5)
	await wait_physics_frames(45)
	assert_true(plate.is_pressed, "Plate should be depressed before exiting room")
	assert_true(gate.is_open, "Gate should be open before exiting room")

	# Exit East to (9,8)
	await wm.transition_to_room("east", Vector2i(9, 8), true)
	assert_eq(wm.current_room_id, Vector2i(9, 8))
	assert_lt(wm.active_player.position.x, 2.5, "Player should spawn near West doorway")

	# Collect key_01 in (9,8)
	var entity_map_98: Dictionary = wm.current_build.get("entity_map", {}) as Dictionary
	var key_item := entity_map_98.get("key_01") as CollectibleItem
	assert_not_null(key_item)
	wm.active_player.global_position = key_item.global_position
	wm.active_player.force_update_transform()
	await wait_physics_frames(5)
	assert_true(key_item.is_collected)
	assert_true(wm.player_inventory.has("key_01"))

	# Return West to (8,8) and assert persisted chest/plate/gate state
	await wm.transition_to_room("west", Vector2i(8, 8), true)
	assert_eq(wm.current_room_id, Vector2i(8, 8))
	assert_gt(wm.active_player.position.x, 9.0, "Player should spawn near East doorway")

	var reloaded_map_88: Dictionary = wm.current_build.get("entity_map", {}) as Dictionary
	var reloaded_chest := reloaded_map_88.get("chest_01") as PushableBlock
	var reloaded_plate := reloaded_map_88.get("plate_01") as TriggerSwitch
	var reloaded_gate := reloaded_map_88.get("gate_01") as Portcullis
	await wait_physics_frames(4)
	assert_almost_eq(reloaded_chest.global_position.x, 4.5, 0.05)
	assert_almost_eq(reloaded_chest.global_position.z, 3.5, 0.05)
	assert_true(reloaded_plate.is_pressed, "Persisted chest must keep pressure plate active on re-entry")
	assert_true(reloaded_gate.is_open, "Persisted gate state must remain open on re-entry")

	# Re-enter (9,8) and verify key remains collected
	await wm.transition_to_room("east", Vector2i(9, 8), true)
	var reloaded_key := (wm.current_build.get("entity_map", {}) as Dictionary).get("key_01") as CollectibleItem
	assert_true(reloaded_key.is_collected, "Collected item must stay collected across room re-entry")


func test_doorway_area3d_triggers_transition() -> void:
	var wm: WorldManagerNode = _wm()
	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	await wait_physics_frames(4)

	# Move player into Exit_east Area3D threshold (x=11.72, z=6.0)
	wm.active_player.global_position = Vector3(11.72, 0.0, 6.0)
	wm.active_player.force_update_transform()
	await wait_physics_frames(8)

	assert_eq(wm.current_room_id, Vector2i(9, 8), "Entering Exit_east Area3D must transition to room (9,8)")


func test_cycle_manager_day_night_lighting_and_jump_height() -> void:
	var wm: WorldManagerNode = _wm()
	var cm: CycleManagerNode = _cm()
	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	assert_eq(cm.current_phase, CycleManagerNode.Phase.DAY)
	assert_eq(wm.active_player.active_model_path, "res://assets/characters/hero_explorer.glb")
	var day_jump: float = wm.active_player.jump_height
	assert_almost_eq(day_jump, 1.35, 0.01)

	cm.advance_time(cm.day_duration_sec + 1.0)
	assert_eq(cm.current_phase, CycleManagerNode.Phase.NIGHT)
	assert_eq(wm.active_player.active_model_path, "res://assets/characters/hero_werewolf.glb")
	assert_gt(wm.active_player.jump_height, day_jump + 0.2, "Night phase must boost player jump height")

	var lighting: DioramaLighting = wm.current_build.get("lighting") as DioramaLighting
	var env: Environment = lighting.world_environment.environment
	assert_false(env.sdfgi_enabled, "Night transition must preserve sdfgi_enabled = false")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)

	cm.advance_time(cm.night_duration_sec + 1.0)
	assert_eq(cm.current_phase, CycleManagerNode.Phase.DAY)
	assert_eq(cm.day_count, 2)
	assert_eq(wm.active_player.active_model_path, "res://assets/characters/hero_explorer.glb")
	assert_almost_eq(wm.active_player.jump_height, 1.35, 0.01)


func test_world_save_load_snapshot_roundtrip() -> void:
	var wm: WorldManagerNode = _wm()
	var cm: CycleManagerNode = _cm()
	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	var chest := (wm.current_build.get("entity_map", {}) as Dictionary).get("chest_01") as PushableBlock
	chest.global_position = Vector3(7.5, 0.0, 4.5)
	wm.player_inventory.append("vault_key_test")
	cm.set_phase(CycleManagerNode.Phase.NIGHT)

	var snapshot: Dictionary = wm.serialize_world_save()
	wm.reset_world_state()
	cm.reset_cycle()

	assert_true(wm.hydrate_world_save(snapshot))
	assert_eq(wm.current_room_id, Vector2i(8, 8))
	assert_eq(cm.current_phase, CycleManagerNode.Phase.NIGHT)
	assert_true(wm.player_inventory.has("vault_key_test"))
	var restored_chest := (wm.current_build.get("entity_map", {}) as Dictionary).get("chest_01") as PushableBlock
	assert_almost_eq(restored_chest.global_position.x, 7.5, 0.05)
	assert_almost_eq(restored_chest.global_position.z, 4.5, 0.05)
