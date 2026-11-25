extends Node3D
## Loads and renders a declarative JSON room diorama with optional CLI environment overrides,
## and spawns the deterministic PlayerController.

@export var room_json_path: String = "res://data/rooms/room_08_08.json"
@export var lighting_preset_override: String = ""
@export var camera_mode_override: String = ""

var build_result: Dictionary = {}
var player: PlayerController


func _ready() -> void:
	var env_preset: String = OS.get_environment("FILMATION_LIGHTING_PRESET")
	var effective_lighting: String = env_preset if not env_preset.is_empty() else lighting_preset_override
	var env_cam: String = OS.get_environment("FILMATION_CAMERA_MODE")
	var effective_cam: String = env_cam if not env_cam.is_empty() else camera_mode_override

	var builder := RoomBuilder.new()
	build_result = builder.build_room_from_path(self, room_json_path, effective_lighting, effective_cam)

	if OS.get_environment("FILMATION_STAGE3_DEMO") == "1":
		var entity_map: Dictionary = build_result.get("entity_map", {}) as Dictionary
		var chest_01: PushableBlock = entity_map.get("chest_01") as PushableBlock
		var chest_02: PushableBlock = entity_map.get("chest_02") as PushableBlock
		if chest_01 != null:
			chest_01.position = Vector3(4.5, 0.0, 3.5)
		if chest_02 != null:
			chest_02.position = Vector3(4.5, 1.0, 3.5)

	_spawn_player(effective_lighting)


func _spawn_player(effective_lighting: String = "") -> void:
	player = PlayerController.new()
	player.name = "Player"
	if OS.get_environment("FILMATION_PLAYER_NIGHT_FORM") == "1" or effective_lighting == "castle_moonlight_night":
		player.set_night_form(true)

	var cam_rig: DioramaCameraRig = build_result.get("camera_rig") as DioramaCameraRig
	if cam_rig != null:
		player.set_camera_rig(cam_rig)

	var spawn_pos: Vector3 = Vector3(5.5, 0.0, 4.5)
	var doorways: Node3D = build_result.get("doorways_root") as Node3D
	if doorways != null:
		var spawn_marker: Marker3D = doorways.get_node_or_null("Spawn_north") as Marker3D
		if spawn_marker != null:
			spawn_pos = spawn_marker.position

	var env_pos: String = OS.get_environment("FILMATION_PLAYER_POS")
	if not env_pos.is_empty():
		var parts: PackedStringArray = env_pos.split(",")
		if parts.size() == 3:
			spawn_pos = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

	if OS.get_environment("FILMATION_PLAYER_FREEZE") == "1":
		player.enable_player_input = false

	player.position = spawn_pos
	add_child(player)

	var env_yaw: String = OS.get_environment("FILMATION_PLAYER_YAW_DEG")
	if not env_yaw.is_empty() and player.visual_root != null:
		player.visual_root.rotation_degrees.y = float(env_yaw)

	var env_anim: String = OS.get_environment("FILMATION_PLAYER_ANIM")
	if not env_anim.is_empty() and player.anim_player != null and player.anim_player.has_animation(StringName(env_anim)):
		player.anim_player.play(StringName(env_anim))
		var env_anim_time: String = OS.get_environment("FILMATION_PLAYER_ANIM_TIME")
		if not env_anim_time.is_empty():
			player.anim_player.seek(float(env_anim_time), true)
			player.anim_player.pause()

	player.sync_shader_world_pos()
	if player.drop_shadow != null:
		player.drop_shadow.call_deferred("update_shadow")
