extends GutTest


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


func test_all_manifest_glb_assets_load_in_godot() -> void:
	var paths: Array[String] = [
		"res://assets/props/pushable_chest.glb",
		"res://assets/props/cauldron.glb",
		"res://assets/props/collectible_key.glb",
		"res://assets/props/stone_pillar.glb",
		"res://assets/props/arch_stone_doorway.glb",
		"res://assets/props/wall_stone_panel.glb",
		"res://assets/props/portcullis_gate.glb",
		"res://assets/props/stone_block.glb",
		"res://assets/props/moving_platform.glb",
		"res://assets/props/collapsing_tile.glb",
		"res://assets/props/pressure_plate.glb",
		"res://assets/characters/hero_knight.glb",
		"res://assets/characters/patrol_sentinel.glb",
		"res://assets/characters/hero_explorer.glb",
		"res://assets/characters/hero_werewolf.glb"
	]

	for p: String in paths:
		assert_true(ResourceLoader.exists(p), "GLB must be imported in Godot: " + p)
		var packed: PackedScene = ResourceLoader.load(p) as PackedScene
		assert_not_null(packed, "Failed to load GLB scene: " + p)
		var inst: Node = packed.instantiate()
		add_child_autofree(inst)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(inst, meshes)
		assert_gt(meshes.size(), 0, "GLB must contain at least one MeshInstance3D: " + p)

		if p.contains("/characters/"):
			var skel: Skeleton3D = HumanoidAnimationLibrary.find_skeleton(inst)
			assert_not_null(skel, "Character GLB must contain Skeleton3D: " + p)
			assert_ne(skel.find_bone("Hips"), -1, "Rig must expose SkeletonProfileHumanoid Hips bone")
			assert_ne(skel.find_bone("LeftUpperArm"), -1, "Rig must expose LeftUpperArm bone")
			assert_ne(skel.find_bone("RightUpperLeg"), -1, "Rig must expose RightUpperLeg bone")


func test_shared_humanoid_animation_library_drives_both_characters() -> void:
	var lib: AnimationLibrary = HumanoidAnimationLibrary.ensure_saved_resource()
	assert_not_null(lib)
	for clip: StringName in [&"idle", &"walk", &"push", &"jump", &"fall", &"land"]:
		assert_true(lib.has_animation(clip), "Shared AnimationLibrary missing clip: " + str(clip))

	for char_path: String in ["res://assets/characters/hero_knight.glb", "res://assets/characters/patrol_sentinel.glb"]:
		var packed: PackedScene = ResourceLoader.load(char_path) as PackedScene
		var inst: Node = packed.instantiate()
		add_child_autofree(inst)
		var anim_p: AnimationPlayer = HumanoidAnimationLibrary.attach_to_character(inst)
		assert_not_null(anim_p)
		assert_true(anim_p.has_animation(&"walk"))
		anim_p.play(&"walk")
		assert_eq(anim_p.current_animation, "walk")


func test_player_uses_rigged_hero_on_isolated_visual_layer() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(12, 0.5, 12)
	fc.shape = fb
	floor_body.position = Vector3(6, -0.25, 6)
	floor_body.add_child(fc)
	arena.add_child(floor_body)

	var player := PlayerController.new()
	player.enable_player_input = false
	player.position = Vector3(6.0, 0.0, 6.0)
	arena.add_child(player)

	assert_not_null(player.visual_root.get_node_or_null("HeroModel"), "Player must load normalized hero_explorer.glb")
	assert_eq(player.active_model_path, "res://assets/characters/hero_explorer.glb")
	assert_not_null(player.anim_player, "Player must attach shared HumanoidAnimationLibrary player")

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(player.visual_root, meshes)
	assert_gt(meshes.size(), 0)
	for mi: MeshInstance3D in meshes:
		assert_eq(mi.layers, PlayerController.PLAYER_VISUAL_LAYER, "Hero mesh must stay on layer 2 so drop shadow decal ignores it")

	await wait_physics_frames(4)
	player.step_movement(Vector2(1.0, 0.0), false, 1.0 / 60.0)
	assert_eq(player.current_anim_state, &"walk")
	player.step_movement(Vector2.ZERO, true, 1.0 / 60.0)
	assert_eq(player.current_anim_state, &"jump")


func test_room_08_08_entities_use_normalized_3d_models_with_exact_colliders() -> void:
	var host := Node3D.new()
	add_child_autofree(host)

	var builder := RoomBuilder.new()
	var result: Dictionary = builder.build_room_from_path(host, "res://data/rooms/room_08_08.json")
	var entity_map: Dictionary = result.get("entity_map", {}) as Dictionary

	var chest := entity_map.get("chest_01") as PushableBlock
	assert_not_null(chest)
	assert_not_null(chest.get_node_or_null("ModelVisual"), "PushableBlock must use pushable_chest.glb visual")
	var col_shape: BoxShape3D = chest.collision_shape.shape as BoxShape3D
	assert_almost_eq(col_shape.size.x, 0.98, 0.001, "Kinematic PushableBlock collider size must remain exact")
	assert_almost_eq(col_shape.size.y, 1.00, 0.001)

	var cauldron: Node = entity_map.get("cauldron_01") as Node
	assert_not_null(cauldron.get_node_or_null("ModelVisual"), "Cauldron must use cauldron.glb visual")

	var gate: Node = entity_map.get("gate_01") as Node
	assert_not_null(gate.get_node_or_null("ModelVisual"), "Portcullis must use portcullis_gate.glb visual")

	var plate: Node = entity_map.get("plate_01") as Node
	assert_not_null(plate.get_node_or_null("ModelVisual"), "TriggerSwitch must use pressure_plate.glb visual")

	var host_east := Node3D.new()
	add_child_autofree(host_east)
	var east_res: Dictionary = builder.build_room_from_path(host_east, "res://data/rooms/room_09_08.json")
	var east_map: Dictionary = east_res.get("entity_map", {}) as Dictionary
	var mplat: Node = east_map.get("plat_east_01") as Node
	assert_not_null(mplat.get_node_or_null("ModelVisual"), "MovingPlatform must use moving_platform.glb visual")

	var host_vault := Node3D.new()
	add_child_autofree(host_vault)
	var vault_res: Dictionary = builder.build_room_from_path(host_vault, "res://data/rooms/room_08_07.json")
	var vault_map: Dictionary = vault_res.get("entity_map", {}) as Dictionary
	var ctile: Node = vault_map.get("crumble_01") as Node
	assert_not_null(ctile.get_node_or_null("ModelVisual"), "CollapsingTile must use collapsing_tile.glb visual")


func test_humanoid_animations_preserve_anatomical_pose_and_stride() -> void:
	for char_path: String in [
		"res://assets/characters/hero_knight.glb",
		"res://assets/characters/patrol_sentinel.glb",
		"res://assets/characters/hero_explorer.glb",
		"res://assets/characters/hero_werewolf.glb"
	]:
		var packed: PackedScene = ResourceLoader.load(char_path) as PackedScene
		assert_not_null(packed, "Failed to load character GLB: " + char_path)
		var inst: Node = packed.instantiate()
		add_child_autofree(inst)

		var skel: Skeleton3D = HumanoidAnimationLibrary.find_skeleton(inst)
		assert_not_null(skel, "Missing Skeleton3D on " + char_path)
		var anim_p: AnimationPlayer = HumanoidAnimationLibrary.attach_to_character(inst)
		assert_not_null(anim_p)

		var idx_hips: int = skel.find_bone("Hips")
		var idx_chest: int = skel.find_bone("Chest")
		var idx_head: int = skel.find_bone("Head")
		var idx_l_upleg: int = skel.find_bone("LeftUpperLeg")
		var idx_l_loleg: int = skel.find_bone("LeftLowerLeg")
		var idx_l_foot: int = skel.find_bone("LeftFoot")
		var idx_r_upleg: int = skel.find_bone("RightUpperLeg")
		var idx_r_loleg: int = skel.find_bone("RightLowerLeg")
		var idx_r_foot: int = skel.find_bone("RightFoot")
		var idx_l_hand: int = skel.find_bone("LeftHand")
		var idx_r_hand: int = skel.find_bone("RightHand")

		var rest_l_foot: Vector3 = skel.get_bone_global_rest(idx_l_foot).origin
		var rest_r_foot: Vector3 = skel.get_bone_global_rest(idx_r_foot).origin

		for clip: StringName in [&"idle", &"walk", &"push", &"jump", &"fall", &"land"]:
			var anim: Animation = anim_p.get_animation(clip)
			assert_not_null(anim, "Missing clip " + str(clip))
			var anim_len: float = anim.length
			for frac: float in [0.0, 0.25, 0.5, 0.75]:
				var t: float = anim_len * frac
				anim_p.play(clip)
				anim_p.seek(t, true)

				var hips: Vector3 = skel.get_bone_global_pose(idx_hips).origin
				var chest: Vector3 = skel.get_bone_global_pose(idx_chest).origin
				var head: Vector3 = skel.get_bone_global_pose(idx_head).origin
				var l_upleg: Vector3 = skel.get_bone_global_pose(idx_l_upleg).origin
				var l_loleg: Vector3 = skel.get_bone_global_pose(idx_l_loleg).origin
				var l_foot: Vector3 = skel.get_bone_global_pose(idx_l_foot).origin
				var r_upleg: Vector3 = skel.get_bone_global_pose(idx_r_upleg).origin
				var r_loleg: Vector3 = skel.get_bone_global_pose(idx_r_loleg).origin
				var r_foot: Vector3 = skel.get_bone_global_pose(idx_r_foot).origin
				var l_hand: Vector3 = skel.get_bone_global_pose(idx_l_hand).origin
				var r_hand: Vector3 = skel.get_bone_global_pose(idx_r_hand).origin

				assert_gt(head.y, chest.y, "%s %s t=%.2f Head must stay above Chest" % [char_path, clip, t])
				assert_gt(chest.y, hips.y, "%s %s t=%.2f Chest must stay above Hips" % [char_path, clip, t])
				assert_lt(l_loleg.y, l_upleg.y, "%s %s t=%.2f LeftLowerLeg below LeftUpperLeg" % [char_path, clip, t])
				assert_lt(r_loleg.y, r_upleg.y, "%s %s t=%.2f RightLowerLeg below RightUpperLeg" % [char_path, clip, t])
				assert_lt(l_foot.y, l_loleg.y, "%s %s t=%.2f LeftFoot below LeftLowerLeg" % [char_path, clip, t])
				assert_lt(r_foot.y, r_loleg.y, "%s %s t=%.2f RightFoot below RightLowerLeg" % [char_path, clip, t])
				assert_lt(l_foot.y, hips.y, "%s %s t=%.2f LeftFoot must stay below Hips" % [char_path, clip, t])
				assert_lt(r_foot.y, hips.y, "%s %s t=%.2f RightFoot must stay below Hips" % [char_path, clip, t])
				assert_lt(l_hand.y, head.y, "%s %s t=%.2f LeftHand must stay below Head" % [char_path, clip, t])
				assert_lt(r_hand.y, head.y, "%s %s t=%.2f RightHand must stay below Head" % [char_path, clip, t])

		anim_p.play(&"walk")
		anim_p.seek(0.0, true)
		var w0_l_foot: Vector3 = skel.get_bone_global_pose(idx_l_foot).origin
		var w0_r_foot: Vector3 = skel.get_bone_global_pose(idx_r_foot).origin
		var w0_l_hand: Vector3 = skel.get_bone_global_pose(idx_l_hand).origin
		var w0_r_hand: Vector3 = skel.get_bone_global_pose(idx_r_hand).origin
		assert_gt(w0_l_foot.z, w0_r_foot.z + 0.15, "walk t=0.0 LeftFoot should stride forward of RightFoot")
		assert_gt(w0_r_hand.z, w0_l_hand.z + 0.08, "walk t=0.0 RightHand should swing contra-laterally forward")

		anim_p.seek(0.3, true)
		var w1_l_foot: Vector3 = skel.get_bone_global_pose(idx_l_foot).origin
		var w1_r_foot: Vector3 = skel.get_bone_global_pose(idx_r_foot).origin
		var w1_l_hand: Vector3 = skel.get_bone_global_pose(idx_l_hand).origin
		var w1_r_hand: Vector3 = skel.get_bone_global_pose(idx_r_hand).origin
		assert_gt(w1_r_foot.z, w1_l_foot.z + 0.15, "walk t=0.3 RightFoot should stride forward of LeftFoot")
		assert_gt(w1_l_hand.z, w1_r_hand.z + 0.08, "walk t=0.3 LeftHand should swing contra-laterally forward")

		anim_p.play(&"idle")
		anim_p.seek(0.0, true)
		var idle_l_foot: Vector3 = skel.get_bone_global_pose(idx_l_foot).origin
		var idle_r_foot: Vector3 = skel.get_bone_global_pose(idx_r_foot).origin
		assert_lt(absf(idle_l_foot.z - rest_l_foot.z), 0.03, "walk->idle must restore LeftFoot to rest")
		assert_lt(absf(idle_r_foot.z - rest_r_foot.z), 0.03, "walk->idle must restore RightFoot to rest")


func test_player_swaps_between_explorer_day_and_werewolf_night_forms() -> void:
	var player := PlayerController.new()
	player.enable_player_input = false
	add_child_autofree(player)

	assert_eq(player.active_model_path, "res://assets/characters/hero_explorer.glb")
	player.set_night_form(true)
	assert_eq(player.active_model_path, "res://assets/characters/hero_werewolf.glb")
	assert_not_null(player.anim_player)
	assert_true(player.anim_player.has_animation(&"walk"))

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(player.visual_root, meshes)
	assert_gt(meshes.size(), 0)
	for mi: MeshInstance3D in meshes:
		assert_eq(mi.layers, PlayerController.PLAYER_VISUAL_LAYER)

	player.set_night_form(false)
	assert_eq(player.active_model_path, "res://assets/characters/hero_explorer.glb")
