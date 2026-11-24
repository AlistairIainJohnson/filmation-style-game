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
	_container.name = "Stage5WorldContainer"
	add_child_autofree(_container)
	_wm().set_room_container(_container)
	assert_true(_wm().load_world_manifest("res://data/world_graph.json"))


func after_each() -> void:
	_wm().reset_world_state()
	_cm().reset_cycle()


func test_four_room_mini_dungeon_full_circuit() -> void:
	var wm: WorldManagerNode = _wm()
	assert_eq(wm.manifest.size(), 4, "2x2 mini-dungeon must register 4 connected rooms")

	assert_true(wm.load_room(Vector2i(8, 8), "north"))
	assert_eq(wm.current_room_id, Vector2i(8, 8))

	var circuit: Array[Array] = [
		["east", Vector2i(9, 8)],
		["north", Vector2i(9, 7)],
		["west", Vector2i(8, 7)],
		["south", Vector2i(8, 8)]
	]

	for step: Array in circuit:
		var exit_dir: String = str(step[0])
		var target_id: Vector2i = step[1] as Vector2i
		await wm.transition_to_room(exit_dir, target_id, true)
		assert_eq(wm.current_room_id, target_id)
		assert_not_null(wm.active_player)
		var cam_rig: DioramaCameraRig = wm.current_build.get("camera_rig") as DioramaCameraRig
		assert_lte(cam_rig.camera.far, 80.0)
		var lighting: DioramaLighting = wm.current_build.get("lighting") as DioramaLighting
		assert_false(lighting.world_environment.environment.sdfgi_enabled)


func test_room_preview_toggles_projection_lighting_and_grid() -> void:
	var packed: PackedScene = load("res://game/tools/room_preview.tscn") as PackedScene
	assert_not_null(packed)
	var preview := packed.instantiate()
	preview.set("room_json_path", "res://data/rooms/room_09_07.json")
	add_child_autofree(preview)

	await wait_physics_frames(2)
	var cam_rig: DioramaCameraRig = preview.current_build.get("camera_rig") as DioramaCameraRig
	assert_almost_eq(cam_rig.camera.rotation_degrees.x, -35.2644, 0.02)

	preview.call("toggle_camera_mode")
	assert_almost_eq(cam_rig.camera.rotation_degrees.x, -30.0, 0.02)

	preview.call("toggle_lighting_preset")
	var lighting: DioramaLighting = preview.current_build.get("lighting") as DioramaLighting
	assert_false(lighting.world_environment.environment.sdfgi_enabled)
	assert_eq(lighting.world_environment.environment.tonemap_mode, Environment.TONE_MAPPER_AGX)

	assert_false(preview.grid_overlay.visible)
	preview.call("toggle_grid_overlay")
	assert_true(preview.grid_overlay.visible)

	preview.call("reload_room")
	assert_not_null(preview.player)
