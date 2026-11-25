extends GutTest


func test_knight_lore_data_loads_all_128_rooms() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	assert_not_null(kl)
	assert_eq(kl.get_room_ids().size(), 128, "rooms.json must contain all 128 Knight Lore rooms")
	assert_eq(kl.backgrounds.size(), 24, "backgrounds.json must contain all 24 templates")
	assert_eq(kl.special_spawns.size(), 32, "rooms.json must contain all 32 special object spawns")
	assert_true(kl.has_room(136), "Cauldron Hub room 136 must exist")
	for start_rid: int in [47, 68, 143, 179]:
		assert_true(kl.has_room(start_rid), "Start room %d must exist" % start_rid)


func test_coordinate_conversion_and_neighbor_math() -> void:
	var center_pos: Vector3 = KnightLoreData.kl_to_room_pos(128.0, 128.0, 128.0, 64.0, 64.0, 128.0)
	assert_almost_eq(center_pos.distance_to(Vector3(4.0, 0.0, 4.0)), 0.0, 0.001)

	var high_arch_pos: Vector3 = KnightLoreData.kl_to_room_pos(128.0, 64.0, 176.0, 32.0, 64.0, 128.0)
	assert_almost_eq(high_arch_pos.x, 2.0, 0.001)
	assert_almost_eq(high_arch_pos.y, 3.0, 0.001)
	assert_almost_eq(high_arch_pos.z, 8.0, 0.001)

	var block_sz: Vector3 = KnightLoreData.kl_size_to_meters(8.0, 8.0, 12.0)
	assert_almost_eq(block_sz.distance_to(Vector3(1.0, 0.75, 1.0)), 0.0, 0.001)

	assert_eq(KnightLoreData.get_neighbor_room_id(136, "north"), 152)
	assert_eq(KnightLoreData.get_neighbor_room_id(136, "south"), 120)
	assert_eq(KnightLoreData.get_neighbor_room_id(136, "east"), 137)
	assert_eq(KnightLoreData.get_neighbor_room_id(136, "west"), 135)


func test_build_key_knight_lore_chambers() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var builder := RoomBuilder.new()

	# Room 136: Cauldron Hub + Melkhior + 4 exits
	var host_136 := Node3D.new()
	add_child_autofree(host_136)
	var res_136: Dictionary = builder.build_knight_lore_room(host_136, 136, kl)
	assert_false(res_136.is_empty())
	assert_false(bool(res_136.get("is_forest", true)))
	var arch_136: Node3D = res_136.get("architecture_root") as Node3D
	assert_not_null(arch_136.get_node_or_null("CauldronHub"), "Room 136 must build CauldronHub")
	var wiz: Node3D = arch_136.get_node_or_null("MelkhiorWizard") as Node3D
	assert_not_null(wiz, "Room 136 must build MelkhiorWizard")
	assert_not_null(wiz.get_node_or_null("ModelVisual"), "MelkhiorWizard must use melkhior_wizard.glb")
	assert_not_null(HumanoidAnimationLibrary.find_skeleton(wiz), "MelkhiorWizard must expose Skeleton3D")
	assert_not_null(arch_136.get_node_or_null("FloorCollision"), "KL room must expose merged FloorCollision")

	for dir_sill: String in ["north", "south", "west", "east"]:
		assert_not_null(arch_136.get_node_or_null("DoorwaySill_" + dir_sill), "Open doorway must include solid DoorwaySill_" + dir_sill)
	var sill_mesh_136_s: MeshInstance3D = arch_136.get_node_or_null("DoorwaySill_south/SillFloorMesh") as MeshInstance3D
	assert_not_null(sill_mesh_136_s)
	assert_lte((sill_mesh_136_s.mesh as BoxMesh).size.z, 0.51, "South portal sill floor must end flush with outer wall thickness")
	assert_lte(absf(sill_mesh_136_s.position.z), 0.26, "South portal sill floor center must sit inside wall thickness")

	var dw_136: Node3D = res_136.get("doorways_root") as Node3D
	var south_exit: Area3D = dw_136.get_node_or_null("Exit_south") as Area3D
	var east_exit: Area3D = dw_136.get_node_or_null("Exit_east") as Area3D
	var south_spawn_136: Marker3D = dw_136.get_node_or_null("Spawn_south") as Marker3D
	var east_spawn_136: Marker3D = dw_136.get_node_or_null("Spawn_east") as Marker3D
	assert_not_null(south_exit)
	assert_not_null(east_exit)
	assert_gt(south_exit.position.z, 8.5, "Exit_south must sit inside South portal past depth bounds")
	assert_gt(east_exit.position.x, 8.5, "Exit_east must sit inside East portal past width bounds")
	assert_lt(south_spawn_136.position.z, 7.5, "Spawn_south must sit safely inside floor")
	assert_lt(east_spawn_136.position.x, 7.5, "Spawn_east must sit safely inside floor")

	var fg_136: Node3D = res_136.get("foreground_root") as Node3D
	assert_not_null(fg_136.get_node_or_null("Foreground_Arch_south"), "Room 136 south arch must support cutaway")
	assert_not_null(fg_136.get_node_or_null("Foreground_Arch_south/ShadowCaster"), "Foreground arch must keep opaque ShadowCaster")
	assert_not_null(fg_136.get_node_or_null("Foreground_Arch_east"), "Room 136 east arch must support cutaway")

	# Room 8: Forest Room uses organic ForestFloorMesh, projecting tree arches, spikes & enchanted ball GLBs
	var host_8 := Node3D.new()
	add_child_autofree(host_8)
	var res_8: Dictionary = builder.build_knight_lore_room(host_8, 8, kl)
	assert_true(bool(res_8.get("is_forest", false)), "Room 8 must be detected as a Forest room")
	var arch_8: Node3D = res_8.get("architecture_root") as Node3D
	var forest_floor_8: MeshInstance3D = arch_8.get_node_or_null("ForestFloorMesh") as MeshInstance3D
	assert_not_null(forest_floor_8, "Forest room must build procedural ForestFloorMesh")
	assert_null(arch_8.get_node_or_null("ForestFloorDetail"), "Forest floor must not use flat CylinderMesh polka-dots")
	assert_null(arch_8.get_node_or_null("FloorTiles"), "Forest room must not use dungeon checkerboard tiles")
	assert_true((forest_floor_8.mesh as BoxMesh).material is ShaderMaterial, "Forest floor must use organic ShaderMaterial")
	var arch_n_8: Node3D = arch_8.get_node_or_null("Arch_north") as Node3D
	assert_not_null(arch_n_8, "Forest room must build woodland Arch_north")
	assert_gte(arch_n_8.position.z, 0.14, "Woodland North gateway must project inside room so walls never clip it")
	var lintel_n_8: Node3D = arch_8.get_node_or_null("WallLintelMasonry_north_00") as Node3D
	assert_not_null(lintel_n_8, "Woodland doorway lintel must attach tree_wall_lintel")
	assert_gte(lintel_n_8.position.z, 0.01, "Woodland lintel must align with WallMasonry plane")
	assert_not_null(arch_8.get_node_or_null("LowWall_south_00"), "Forest foreground border must attach low_wall_woodland")
	assert_not_null(arch_8.get_node_or_null("DoorwaySill_north/SillFloorMesh"), "Open portal must extend visible floor into threshold")
	var sill_mesh_8_n: MeshInstance3D = arch_8.get_node_or_null("DoorwaySill_north/SillFloorMesh") as MeshInstance3D
	assert_lte((sill_mesh_8_n.mesh as BoxMesh).size.z, 0.51, "North portal sill floor must not stick out past outer wall")
	assert_lte((sill_mesh_8_n.mesh as BoxMesh).size.x, 2.01, "North portal sill floor width must match doorway width")
	var dw_8: Node3D = res_8.get("doorways_root") as Node3D
	var exit_n_8: Area3D = dw_8.get_node_or_null("Exit_north") as Area3D
	assert_not_null(exit_n_8)
	assert_lte(exit_n_8.position.z, -0.5, "Portal exit trigger must sit inside doorway beyond room boundary")
	assert_not_null(arch_8.get_node_or_null("BiomeTransition_north"), "Forest Room 8 North exit -> Stone Room 24 must show stone transition indicator")
	var fg_8: Node3D = res_8.get("foreground_root") as Node3D
	assert_null(fg_8.get_node_or_null("Foreground_Arch_east/BiomeTransition_east"), "Forest->Forest Room 8 East exit must not attach biome indicator")
	var ent_8: Node3D = res_8.get("entities_root") as Node3D
	var found_ent_model: bool = false
	for child: Node in ent_8.get_children():
		if child.get_node_or_null("ModelVisual") != null:
			found_ent_model = true
			break
	assert_true(found_ent_model, "Forest room hazards/entities must use Phase 2 GLB models")

	# Room 109: Props + Gargoyle + Charm Spawn Preview + Projecting West Tree Gateway
	var host_109 := Node3D.new()
	add_child_autofree(host_109)
	var res_109: Dictionary = builder.build_knight_lore_room(host_109, 109, kl)
	var arch_109: Node3D = res_109.get("architecture_root") as Node3D
	var arch_w_109: Node3D = arch_109.get_node_or_null("Arch_west") as Node3D
	assert_not_null(arch_w_109)
	assert_gte(arch_w_109.position.x, 0.14, "Woodland West gateway must project inside room so walls never clip it")
	assert_not_null(arch_109.get_node_or_null("BiomeTransition_west"), "Forest Room 109 West exit -> Stone Room 108 must show biome indicator")
	var ent_109: Node3D = res_109.get("entities_root") as Node3D
	assert_not_null(ent_109.get_node_or_null("SpecialSpawn_00/ModelVisual"), "Room 109 must render collectible charm ModelVisual")

	# Room 47: Stone Start Room -> North exit into Forest Room 63 + full-height foreground wall blocker
	var host_47 := Node3D.new()
	add_child_autofree(host_47)
	var res_47: Dictionary = builder.build_knight_lore_room(host_47, 47, kl)
	var arch_47: Node3D = res_47.get("architecture_root") as Node3D
	assert_not_null(arch_47.get_node_or_null("FloorTiles"), "Stone room must keep dungeon floor tiles")
	assert_not_null(arch_47.get_node_or_null("LowWall_east_00"), "Dungeon foreground curb must attach low_wall_stone")
	var wall_e_47_col: CollisionShape3D = arch_47.get_node_or_null("Wall_east/CollisionShape3D") as CollisionShape3D
	assert_not_null(wall_e_47_col)
	assert_gte((wall_e_47_col.shape as BoxShape3D).size.y, 5.5, "Foreground perimeter wall must have full-height collider to prevent climbing")
	assert_not_null(arch_47.get_node_or_null("DoorwaySill_north/SillFloorMesh"), "Stone portal must extend visible floor into threshold")
	assert_not_null(arch_47.get_node_or_null("BiomeTransition_north"), "Stone Room 47 North exit -> Forest Room 63 must show mossy biome indicator")
	assert_null(arch_47.get_node_or_null("BiomeTransition_west"), "Stone->Stone Room 47 West exit must not attach biome indicator")
	assert_null(arch_136.get_node_or_null("BiomeTransition_north"), "Cauldron Hub Room 136 must have no biome indicators")

	# Room 16: Narrow 4x8m Room with elevated high_arch_south + base ledges + split curb collision
	var host_16 := Node3D.new()
	add_child_autofree(host_16)
	var res_16: Dictionary = builder.build_knight_lore_room(host_16, 16, kl)
	var dims_16: Vector3 = res_16.get("room_dims", Vector3.ZERO) as Vector3
	assert_almost_eq(dims_16.x, 4.0, 0.01)
	assert_almost_eq(dims_16.z, 8.0, 0.01)
	var arch_16: Node3D = res_16.get("architecture_root") as Node3D
	var hi_mid_col: CollisionShape3D = arch_16.get_node_or_null("Wall_south_HiMid/CollisionShape3D") as CollisionShape3D
	assert_not_null(hi_mid_col, "High arch south wall must split curb collision below elevated portal")
	assert_lte((hi_mid_col.shape as BoxShape3D).size.y, 3.05, "High arch south doorway must stay clear above 3.0m elevation")
	var hi_l_col: CollisionShape3D = arch_16.get_node_or_null("Wall_south_HiL/CollisionShape3D") as CollisionShape3D
	assert_not_null(hi_l_col)
	assert_gte((hi_l_col.shape as BoxShape3D).size.y, 5.5, "Flanking foreground curb outside high arch must stay full-height")
	var dw_16: Node3D = res_16.get("doorways_root") as Node3D
	var south_spawn: Marker3D = dw_16.get_node_or_null("Spawn_south") as Marker3D
	assert_not_null(south_spawn)
	assert_almost_eq(south_spawn.position.y, 3.0, 0.01, "High arch south spawn must sit at 3.0m elevation")

	# Room 64: guard_square duplicate zero-height entry must not double-spawn
	var host_64 := Node3D.new()
	add_child_autofree(host_64)
	var res_64: Dictionary = builder.build_knight_lore_room(host_64, 64, kl)
	var ent_64: Node3D = res_64.get("entities_root") as Node3D
	var guard_nodes: int = 0
	for child: Node in ent_64.get_children():
		if child.name.contains("guard_square"):
			guard_nodes += 1
	assert_eq(guard_nodes, 1, "Two-part guard sprite rows must merge into 1 3D sentinel")


func test_all_128_knight_lore_rooms_build_without_errors() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var builder := RoomBuilder.new()
	var ids: Array[int] = kl.get_room_ids()
	assert_eq(ids.size(), 128)
	for rid: int in ids:
		var host := Node3D.new()
		var res: Dictionary = builder.build_knight_lore_room(host, rid, kl)
		assert_false(res.is_empty(), "Room %d failed to build" % rid)
		var rig: DioramaCameraRig = res.get("camera_rig") as DioramaCameraRig
		assert_not_null(rig)
		assert_lte(rig.camera.far, 80.0)
		var lighting: DioramaLighting = res.get("lighting") as DioramaLighting
		assert_false(lighting.world_environment.environment.sdfgi_enabled)
		assert_not_null(lighting.voxel_gi.data, "Room %d must attach pre-baked VoxelGIData" % rid)
		assert_true(ResourceLoader.exists(DioramaLighting.get_knight_lore_gi_path(rid)), "Pre-baked VoxelGIData missing for room %d" % rid)
		host.free()

	var cached_a: VoxelGIData = DioramaLighting.load_prebaked_gi_data(DioramaLighting.get_knight_lore_gi_path(47))
	var cached_b: VoxelGIData = DioramaLighting.load_prebaked_gi_data(DioramaLighting.get_knight_lore_gi_path(47))
	assert_not_null(cached_a)
	assert_eq(cached_a, cached_b, "Repeated VoxelGIData lookups must return cached instance")


func test_room_preview_doorway_transition_does_not_drop_player() -> void:
	var prev_env_kl: String = OS.get_environment("FILMATION_KL_ROOM")
	OS.set_environment("FILMATION_KL_ROOM", "136")
	var packed: PackedScene = ResourceLoader.load("res://game/tools/room_preview.tscn") as PackedScene
	assert_not_null(packed)
	var preview: Node3D = packed.instantiate() as Node3D
	add_child_autofree(preview)

	await wait_physics_frames(3)
	assert_eq(int(preview.current_build.get("room_id", -1)), 136)
	var player: PlayerController = preview.player
	assert_not_null(player)
	assert_gte(player.position.y, -0.05, "Player must stand cleanly on floor in Room 136")

	# Transition through North, South, East, West doors and step physics frames to verify zero void-falls
	preview.call("transition_via_doorway", "north", 152, Vector2i(-1, -1))
	await wait_physics_frames(15)
	assert_eq(int(preview.current_build.get("room_id", -1)), 152, "North doorway must transition Room 136 -> Room 152")
	assert_gte(preview.player.position.y, -0.05, "Player must not fall into void after North doorway transition")

	preview.call("transition_via_doorway", "south", 136, Vector2i(-1, -1))
	await wait_physics_frames(15)
	assert_eq(int(preview.current_build.get("room_id", -1)), 136, "South doorway must transition Room 152 -> Room 136")
	assert_gte(preview.player.position.y, -0.05, "Player must not fall into void after South doorway transition")

	OS.set_environment("FILMATION_KL_ROOM", prev_env_kl)


func test_room_109_tall_boulders_and_gargoyles_cutaway_behind_hero() -> void:
	var kl: KnightLoreData = KnightLoreData.load_default()
	var host := Node3D.new()
	add_child_autofree(host)

	var builder := RoomBuilder.new()
	var res: Dictionary = builder.build_knight_lore_room(host, 109, kl)
	var arch: Node3D = res.get("architecture_root") as Node3D
	var ent: Node3D = res.get("entities_root") as Node3D
	var rig: DioramaCameraRig = res.get("camera_rig") as DioramaCameraRig

	var table_node: Node3D = ent.get_node_or_null("FG_10_table") as Node3D
	assert_not_null(table_node)
	assert_false(table_node.is_in_group("foreground_occluders"), "Low 0.75m oak table must remain opaque")

	var tall_rocks: Array[Node3D] = []
	for child: Node in arch.get_children():
		if child.name.contains("_rock"):
			var r_node: Node3D = child as Node3D
			tall_rocks.append(r_node)
			assert_true(r_node.is_in_group("foreground_occluders"), "%s in tall stack must enable cutaway" % r_node.name)
			assert_not_null(r_node.get_node_or_null("ShadowCaster"), "%s must keep solid ShadowCaster" % r_node.name)
	assert_eq(tall_rocks.size(), 8, "Room 109 must cutaway-enable all 8 boulders in its 3.0m columns/arch")

	var garg_node: Node3D = ent.get_node_or_null("FG_09_gargoyle") as Node3D
	assert_not_null(garg_node)
	assert_true(garg_node.is_in_group("foreground_occluders"), "Perched gargoyle at 3.0m top must enable cutaway")
	assert_not_null(garg_node.get_node_or_null("ShadowCaster"))

	var player := PlayerController.new()
	player.enable_player_input = false
	player.set_camera_rig(rig)
	player.position = Vector3(3.6, 0.0, 1.6)
	host.add_child(player)
	await wait_physics_frames(2)
	player.sync_shader_world_pos()

	var any_active_behind: bool = false
	for r_node: Node3D in tall_rocks:
		if bool(r_node.get_meta("cutaway_active", false)):
			any_active_behind = true
			break
	assert_true(any_active_behind, "Walking behind Room 109 boulder column must activate cutaway")

	player.position = Vector3(5.6, 0.0, 6.6)
	player.sync_shader_world_pos()
	var any_active_front: bool = false
	for r_node: Node3D in tall_rocks:
		if bool(r_node.get_meta("cutaway_active", false)):
			any_active_front = true
			break
	assert_false(any_active_front, "Walking in front of Room 109 boulder column must keep blocks opaque")
