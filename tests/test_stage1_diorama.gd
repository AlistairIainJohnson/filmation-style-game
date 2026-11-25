extends GutTest


func test_true_isometric_camera_angles_and_size() -> void:
	var rig := DioramaCameraRig.new()
	add_child_autofree(rig)
	rig.configure_for_room(Vector3(12.0, 6.0, 12.0), DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC, 0.10)

	var cam: Camera3D = rig.camera
	assert_not_null(cam)
	assert_eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(cam.rotation_degrees.y, 45.0, 0.01)
	assert_almost_eq(cam.rotation_degrees.x, -35.2644, 0.01)
	assert_gt(absf(cam.rotation_degrees.x - (-26.565)), 5.0, "Never use 2D slope -26.565 as 3D pitch")
	assert_almost_eq(cam.size, 16.17, 0.05)
	assert_lte(cam.far, 80.0)


func test_dimetric_2_1_camera_angles_and_size() -> void:
	var rig := DioramaCameraRig.new()
	add_child_autofree(rig)
	rig.configure_for_room(Vector3(12.0, 6.0, 12.0), DioramaCameraRig.ProjectionMode.DIMETRIC_2_1, 0.10)

	var cam: Camera3D = rig.camera
	assert_almost_eq(cam.rotation_degrees.y, 45.0, 0.01)
	assert_almost_eq(cam.rotation_degrees.x, -30.0, 0.01)
	assert_almost_eq(cam.size, 15.05, 0.05)


func test_camera_xz_basis_vectors() -> void:
	var rig := DioramaCameraRig.new()
	add_child_autofree(rig)
	rig.configure_for_room(Vector3(12.0, 6.0, 12.0), DioramaCameraRig.ProjectionMode.TRUE_ISOMETRIC, 0.10)

	var right_xz: Vector3 = rig.get_camera_right_xz()
	var forward_xz: Vector3 = rig.get_camera_forward_xz()
	assert_almost_eq(right_xz.length(), 1.0, 0.001)
	assert_almost_eq(forward_xz.length(), 1.0, 0.001)
	assert_almost_eq(right_xz.y, 0.0, 0.0001)
	assert_almost_eq(forward_xz.y, 0.0, 0.0001)
	assert_almost_eq(right_xz.dot(forward_xz), 0.0, 0.001)


func test_diorama_lighting_presets_enforce_invariants() -> void:
	for preset_name: String in ["castle_stone_skylight", "castle_moonlight_night"]:
		var preset: Dictionary = DioramaLighting.load_preset_by_name(preset_name)
		assert_false(preset.is_empty(), "Preset should load: " + preset_name)

		var lighting := DioramaLighting.new()
		add_child_autofree(lighting)
		lighting.apply_preset(preset, Vector3(12.0, 6.0, 12.0))

		var env: Environment = lighting.world_environment.environment
		assert_not_null(env)
		assert_false(env.sdfgi_enabled, "SDFGI must NEVER be enabled under orthographic camera")
		assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)
		assert_true(env.ssao_enabled)
		assert_true(env.ssil_enabled)
		assert_eq(lighting.key_directional_light.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
		assert_gte(lighting.area_lights.size(), 1)
		assert_not_null(lighting.voxel_gi)


func test_room_builder_builds_room_08_08_from_json() -> void:
	var host := Node3D.new()
	add_child_autofree(host)

	var builder := RoomBuilder.new()
	var result: Dictionary = builder.build_room_from_path(host, "res://data/rooms/room_08_08.json")
	assert_false(result.is_empty())

	var arch_root: Node3D = result.get("architecture_root") as Node3D
	var floor_tiles: Node3D = arch_root.get_node_or_null("FloorTiles") as Node3D
	assert_not_null(floor_tiles)
	assert_eq(floor_tiles.get_child_count(), 140, "12x12 floor minus 4 void cells = 140 tiles")

	var doorways: Node3D = result.get("doorways_root") as Node3D
	assert_not_null(doorways.get_node_or_null("Spawn_north"))
	assert_not_null(doorways.get_node_or_null("Spawn_east"))

	var fg_root: Node3D = result.get("foreground_root") as Node3D
	assert_eq(fg_root.get_child_count(), 1)
	assert_true(fg_root.get_child(0).is_in_group("foreground_occluders"))

	var entities_root: Node3D = result.get("entities_root") as Node3D
	assert_eq(entities_root.get_child_count(), 5)

	var rig: DioramaCameraRig = result.get("camera_rig") as DioramaCameraRig
	assert_not_null(rig)
	assert_eq(rig.camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_lte(rig.camera.far, 80.0)

	var lighting: DioramaLighting = result.get("lighting") as DioramaLighting
	assert_not_null(lighting)
	assert_not_null(lighting.voxel_gi.data, "Room 08_08 must attach pre-baked VoxelGIData")
	var pre_gi_data: VoxelGIData = lighting.voxel_gi.data
	lighting.apply_preset(DioramaLighting.load_preset_by_name("castle_moonlight_night"), Vector3(12.0, 6.0, 12.0))
	assert_eq(lighting.voxel_gi.data, pre_gi_data, "Preset switch must preserve pre-baked VoxelGIData")
