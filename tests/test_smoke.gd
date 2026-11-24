extends GutTest


func test_engine_is_godot_4_7_plus() -> void:
	var info: Dictionary = Engine.get_version_info()
	assert_eq(int(info.get("major", 0)), 4, "Engine major version must be 4")
	assert_gte(int(info.get("minor", 0)), 7, "Engine minor version must be >= 7")


func test_jolt_physics_enabled() -> void:
	var physics_engine: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	assert_eq(physics_engine, "Jolt Physics", "Jolt Physics 3D must be configured as default physics engine")


func test_player_world_pos_shader_global_exists() -> void:
	assert_true(
		ProjectSettings.has_setting("shader_globals/player_world_pos"),
		"Global shader parameter player_world_pos must be defined in project.godot"
	)


func test_smoke_scene_loads_with_orthographic_camera() -> void:
	var packed: PackedScene = load("res://game/rooms/smoke_scene.tscn") as PackedScene
	assert_not_null(packed, "Smoke scene PackedScene should load cleanly")

	var scene_root: Node3D = packed.instantiate() as Node3D
	assert_not_null(scene_root, "Smoke scene root must be a Node3D")
	add_child_autofree(scene_root)

	var cam: Camera3D = scene_root.get_node_or_null("DioramaCamera") as Camera3D
	assert_not_null(cam, "Smoke scene must contain DioramaCamera")
	assert_eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL, "Camera must use orthogonal projection")
	assert_lte(cam.far, 80.0, "Camera3D.far must stay <= 80.0 for orthographic shadow precision")

	var world_env: WorldEnvironment = scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_not_null(world_env, "Smoke scene must contain WorldEnvironment")
	assert_not_null(world_env.environment, "WorldEnvironment must have an Environment resource")
	assert_false(world_env.environment.sdfgi_enabled, "SDFGI must NEVER be enabled under orthographic cameras")
