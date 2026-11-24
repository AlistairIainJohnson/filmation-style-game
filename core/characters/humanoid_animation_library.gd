class_name HumanoidAnimationLibrary
extends RefCounted
## Shared procedural AnimationLibrary targeting SkeletonProfileHumanoid bone names.
## Saved to res://assets/animations/humanoid_core.res so any rigged character GLB inherits
## idle, walk, push, jump, fall, and land immediately.

const LIBRARY_PATH: String = "res://assets/animations/humanoid_core.res"
const LIBRARY_FORMAT_VERSION: int = 3
const ANIMATED_BONES: Array[String] = [
	"Spine",
	"Chest",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"RightUpperArm",
	"RightLowerArm",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"RightUpperLeg",
	"RightLowerLeg"
]


static func ensure_saved_resource() -> AnimationLibrary:
	if ResourceLoader.exists(LIBRARY_PATH):
		var loaded: Resource = ResourceLoader.load(LIBRARY_PATH)
		if loaded is AnimationLibrary and int(loaded.get_meta(&"format_version", 1)) == LIBRARY_FORMAT_VERSION:
			return loaded as AnimationLibrary

	return rebuild_and_save_resource()


static func rebuild_and_save_resource() -> AnimationLibrary:
	var lib: AnimationLibrary = build_library()
	var dir_path: String = ProjectSettings.globalize_path(LIBRARY_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir_path)
	var err: Error = ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		push_warning("HumanoidAnimationLibrary: Failed to save %s (%s)" % [LIBRARY_PATH, error_string(err)])
	return lib


static func build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.set_meta(&"format_version", LIBRARY_FORMAT_VERSION)
	lib.add_animation(&"idle", _make_idle_anim())
	lib.add_animation(&"walk", _make_walk_anim())
	lib.add_animation(&"push", _make_push_anim())
	lib.add_animation(&"jump", _make_jump_anim())
	lib.add_animation(&"fall", _make_fall_anim())
	lib.add_animation(&"land", _make_land_anim())
	return lib


static func find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child: Node in root_node.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null:
			return found
	return null


static func attach_to_character(model_root: Node) -> AnimationPlayer:
	var skel: Skeleton3D = find_skeleton(model_root)
	var player := AnimationPlayer.new()
	player.name = "HumanoidAnimPlayer"
	model_root.add_child(player)
	if skel == null:
		return player

	var base_lib: AnimationLibrary = ensure_saved_resource()
	var rel_path: String = str(model_root.get_path_to(skel))
	var bound_lib := AnimationLibrary.new()

	for anim_name: StringName in base_lib.get_animation_list():
		var src_anim: Animation = base_lib.get_animation(anim_name)
		var dup: Animation = src_anim.duplicate(true) as Animation
		for t_idx: int in range(dup.get_track_count()):
			var old_path: String = str(dup.track_get_path(t_idx))
			var colon_idx: int = old_path.find(":")
			var sub_name: String = old_path.substr(colon_idx) if colon_idx >= 0 else ""
			dup.track_set_path(t_idx, NodePath(rel_path + sub_name))
			if dup.track_get_type(t_idx) == Animation.TYPE_ROTATION_3D and colon_idx >= 0:
				var bone_name: String = old_path.substr(colon_idx + 1)
				var bone_idx: int = skel.find_bone(bone_name)
				if bone_idx >= 0:
					var parent_idx: int = skel.get_bone_parent(bone_idx)
					var parent_global_rest_q: Quaternion = Quaternion.IDENTITY
					if parent_idx >= 0:
						parent_global_rest_q = skel.get_bone_global_rest(parent_idx).basis.get_rotation_quaternion().normalized()
					var local_rest_q: Quaternion = skel.get_bone_rest(bone_idx).basis.get_rotation_quaternion().normalized()
					var prev_q: Quaternion = Quaternion.IDENTITY
					for k_idx: int in range(dup.track_get_key_count(t_idx)):
						var delta_model_q: Quaternion = (dup.track_get_key_value(t_idx, k_idx) as Quaternion).normalized()
						var pose_q: Quaternion = (parent_global_rest_q.inverse() * delta_model_q * parent_global_rest_q * local_rest_q).normalized()
						if k_idx > 0 and prev_q.dot(pose_q) < 0.0:
							pose_q = -pose_q
						dup.track_set_key_value(t_idx, k_idx, pose_q)
						prev_q = pose_q
		bound_lib.add_animation(anim_name, dup)

	player.add_animation_library(&"", bound_lib)
	return player


static func _add_rot_track(anim: Animation, bone: String, keys: Array[Array]) -> void:
	var idx: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(idx, NodePath("Skeleton3D:" + bone))
	anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	for kf: Array in keys:
		var time_sec: float = float(kf[0])
		var euler_deg: Vector3 = kf[1] as Vector3
		var q: Quaternion = Quaternion.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
		anim.rotation_track_insert_key(idx, time_sec, q)


static func _fill_missing_neutral_tracks(anim: Animation) -> void:
	var keyed_bones: Dictionary = {}
	for t_idx: int in range(anim.get_track_count()):
		var p_str: String = str(anim.track_get_path(t_idx))
		var colon_idx: int = p_str.find(":")
		if colon_idx >= 0:
			keyed_bones[p_str.substr(colon_idx + 1)] = true

	for bone_name: String in ANIMATED_BONES:
		if not keyed_bones.has(bone_name):
			_add_rot_track(anim, bone_name, [[0.0, Vector3.ZERO], [anim.length, Vector3.ZERO]])


static func _make_idle_anim() -> Animation:
	var a := Animation.new()
	a.length = 3.2
	a.loop_mode = Animation.LOOP_LINEAR
	_add_rot_track(a, "Chest", [[0.0, Vector3(0, 0, 0)], [0.8, Vector3(2.5, 0, 0)], [1.6, Vector3(0, 0, 0)], [2.4, Vector3(2.5, 0, 0)], [3.2, Vector3(0, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(0, 0, 0)], [0.7, Vector3(-2, 22, 0)], [1.4, Vector3(0, 0, 0)], [2.2, Vector3(-2, -22, 0)], [3.2, Vector3(0, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a


static func _make_walk_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.6
	a.loop_mode = Animation.LOOP_LINEAR
	_add_rot_track(a, "LeftUpperLeg", [[0.0, Vector3(-28, 0, 0)], [0.3, Vector3(28, 0, 0)], [0.6, Vector3(-28, 0, 0)]])
	_add_rot_track(a, "LeftLowerLeg", [[0.0, Vector3(10, 0, 0)], [0.3, Vector3(22, 0, 0)], [0.6, Vector3(10, 0, 0)]])
	_add_rot_track(a, "RightUpperLeg", [[0.0, Vector3(28, 0, 0)], [0.3, Vector3(-28, 0, 0)], [0.6, Vector3(28, 0, 0)]])
	_add_rot_track(a, "RightLowerLeg", [[0.0, Vector3(22, 0, 0)], [0.3, Vector3(10, 0, 0)], [0.6, Vector3(22, 0, 0)]])
	_add_rot_track(a, "LeftUpperArm", [[0.0, Vector3(22, 0, 0)], [0.3, Vector3(-22, 0, 0)], [0.6, Vector3(22, 0, 0)]])
	_add_rot_track(a, "LeftLowerArm", [[0.0, Vector3(-12, 0, 0)], [0.3, Vector3(-18, 0, 0)], [0.6, Vector3(-12, 0, 0)]])
	_add_rot_track(a, "RightUpperArm", [[0.0, Vector3(-22, 0, 0)], [0.3, Vector3(22, 0, 0)], [0.6, Vector3(-22, 0, 0)]])
	_add_rot_track(a, "RightLowerArm", [[0.0, Vector3(-18, 0, 0)], [0.3, Vector3(-12, 0, 0)], [0.6, Vector3(-18, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(5, -5, 0)], [0.3, Vector3(5, 5, 0)], [0.6, Vector3(5, -5, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-3, 0, 0)], [0.6, Vector3(-3, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a


static func _make_push_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_add_rot_track(a, "Spine", [[0.0, Vector3(14, 0, 0)], [0.5, Vector3(14, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(6, 0, 0)], [0.5, Vector3(6, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-10, 0, 0)], [0.5, Vector3(-10, 0, 0)]])
	_add_rot_track(a, "LeftUpperArm", [[0.0, Vector3(-65, 0, -8)], [0.5, Vector3(-65, 0, -8)]])
	_add_rot_track(a, "LeftLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.5, Vector3(-15, 0, 0)]])
	_add_rot_track(a, "RightUpperArm", [[0.0, Vector3(-65, 0, 8)], [0.5, Vector3(-65, 0, 8)]])
	_add_rot_track(a, "RightLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.5, Vector3(-15, 0, 0)]])
	_add_rot_track(a, "LeftUpperLeg", [[0.0, Vector3(-20, 0, 0)], [0.25, Vector3(20, 0, 0)], [0.5, Vector3(-20, 0, 0)]])
	_add_rot_track(a, "LeftLowerLeg", [[0.0, Vector3(18, 0, 0)], [0.5, Vector3(18, 0, 0)]])
	_add_rot_track(a, "RightUpperLeg", [[0.0, Vector3(20, 0, 0)], [0.25, Vector3(-20, 0, 0)], [0.5, Vector3(20, 0, 0)]])
	_add_rot_track(a, "RightLowerLeg", [[0.0, Vector3(18, 0, 0)], [0.5, Vector3(18, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a


static func _make_jump_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.3
	a.loop_mode = Animation.LOOP_NONE
	_add_rot_track(a, "Spine", [[0.0, Vector3(6, 0, 0)], [0.3, Vector3(6, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-5, 0, 0)], [0.3, Vector3(-5, 0, 0)]])
	_add_rot_track(a, "LeftUpperArm", [[0.0, Vector3(-35, 0, 18)], [0.3, Vector3(-55, 0, 24)]])
	_add_rot_track(a, "LeftLowerArm", [[0.0, Vector3(-20, 0, 0)], [0.3, Vector3(-20, 0, 0)]])
	_add_rot_track(a, "RightUpperArm", [[0.0, Vector3(-35, 0, -18)], [0.3, Vector3(-55, 0, -24)]])
	_add_rot_track(a, "RightLowerArm", [[0.0, Vector3(-20, 0, 0)], [0.3, Vector3(-20, 0, 0)]])
	_add_rot_track(a, "LeftUpperLeg", [[0.0, Vector3(-25, 0, 0)], [0.3, Vector3(-35, 0, 0)]])
	_add_rot_track(a, "LeftLowerLeg", [[0.0, Vector3(25, 0, 0)], [0.3, Vector3(40, 0, 0)]])
	_add_rot_track(a, "RightUpperLeg", [[0.0, Vector3(15, 0, 0)], [0.3, Vector3(20, 0, 0)]])
	_add_rot_track(a, "RightLowerLeg", [[0.0, Vector3(15, 0, 0)], [0.3, Vector3(25, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a


static func _make_fall_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.4
	a.loop_mode = Animation.LOOP_LINEAR
	_add_rot_track(a, "Spine", [[0.0, Vector3(8, 0, 0)], [0.4, Vector3(8, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(6, 0, 0)], [0.4, Vector3(6, 0, 0)]])
	_add_rot_track(a, "LeftUpperArm", [[0.0, Vector3(-55, 0, 32)], [0.2, Vector3(-65, 0, 38)], [0.4, Vector3(-55, 0, 32)]])
	_add_rot_track(a, "LeftLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.4, Vector3(-15, 0, 0)]])
	_add_rot_track(a, "RightUpperArm", [[0.0, Vector3(-55, 0, -32)], [0.2, Vector3(-65, 0, -38)], [0.4, Vector3(-55, 0, -32)]])
	_add_rot_track(a, "RightLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.4, Vector3(-15, 0, 0)]])
	_add_rot_track(a, "LeftUpperLeg", [[0.0, Vector3(-18, 0, 0)], [0.2, Vector3(-12, 0, 0)], [0.4, Vector3(-18, 0, 0)]])
	_add_rot_track(a, "LeftLowerLeg", [[0.0, Vector3(25, 0, 0)], [0.4, Vector3(25, 0, 0)]])
	_add_rot_track(a, "RightUpperLeg", [[0.0, Vector3(-10, 0, 0)], [0.2, Vector3(-16, 0, 0)], [0.4, Vector3(-10, 0, 0)]])
	_add_rot_track(a, "RightLowerLeg", [[0.0, Vector3(25, 0, 0)], [0.4, Vector3(25, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a


static func _make_land_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.25
	a.loop_mode = Animation.LOOP_NONE
	_add_rot_track(a, "Spine", [[0.0, Vector3(15, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(5, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-8, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "LeftUpperArm", [[0.0, Vector3(-20, 0, 12)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "LeftLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "RightUpperArm", [[0.0, Vector3(-20, 0, -12)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "RightLowerArm", [[0.0, Vector3(-15, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "LeftUpperLeg", [[0.0, Vector3(-28, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "LeftLowerLeg", [[0.0, Vector3(42, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "RightUpperLeg", [[0.0, Vector3(-28, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_add_rot_track(a, "RightLowerLeg", [[0.0, Vector3(42, 0, 0)], [0.25, Vector3(0, 0, 0)]])
	_fill_missing_neutral_tracks(a)
	return a
