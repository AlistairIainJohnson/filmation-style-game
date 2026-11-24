class_name DioramaLighting
extends Node3D
## Modern non-retro PBR lighting rig for orthographic Filmation chambers.
## Enforces AgX tonemapping, VoxelGI, SSAO, SSIL, AreaLight3D, SHADOW_ORTHOGONAL,
## and strictly disables SDFGI to prevent orthographic striping artifacts.

var world_environment: WorldEnvironment
var key_directional_light: DirectionalLight3D
var voxel_gi: VoxelGI
var area_lights: Array[AreaLight3D] = []


static func _arr_to_color(rgb: Variant, fallback: Color = Color.WHITE) -> Color:
	if rgb is Array and rgb.size() >= 3:
		return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]), 1.0)
	return fallback


static func _arr_to_vec3(arr: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback


static func load_preset_by_name(
	preset_name: String,
	presets_path: String = "res://data/lighting_presets.json"
) -> Dictionary:
	var file: FileAccess = FileAccess.open(presets_path, FileAccess.READ)
	if file == null:
		push_error("DioramaLighting: Cannot open presets file: " + presets_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("DioramaLighting: Invalid JSON in presets file: " + presets_path)
		return {}
	var presets_dict: Dictionary = parsed as Dictionary
	if not presets_dict.has(preset_name):
		push_error("DioramaLighting: Unknown lighting preset '%s'" % preset_name)
		return {}
	return presets_dict[preset_name] as Dictionary


func apply_preset(preset: Dictionary, room_dims: Vector3) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	area_lights.clear()

	# 1. WorldEnvironment (AgX, SSAO, SSIL, Volumetric Fog, strictly NO SDFGI)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _arr_to_color(preset.get("background_color"), Color(0.06, 0.07, 0.10))

	var ambient_cfg: Dictionary = preset.get("ambient", {}) as Dictionary
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _arr_to_color(ambient_cfg.get("color"), Color(0.35, 0.40, 0.50))
	env.ambient_light_energy = float(ambient_cfg.get("energy", 0.45))

	var tm_cfg: Dictionary = preset.get("tonemap", {}) as Dictionary
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(tm_cfg.get("exposure", 1.0))
	env.tonemap_agx_white = float(tm_cfg.get("agx_white", 10.0))
	env.tonemap_agx_contrast = float(tm_cfg.get("agx_contrast", 1.25))

	var ssao_cfg: Dictionary = preset.get("ssao", {}) as Dictionary
	env.ssao_enabled = bool(ssao_cfg.get("enabled", true))
	env.ssao_radius = float(ssao_cfg.get("radius", 0.9))
	env.ssao_intensity = float(ssao_cfg.get("intensity", 2.0))
	env.ssao_power = float(ssao_cfg.get("power", 1.5))

	var ssil_cfg: Dictionary = preset.get("ssil", {}) as Dictionary
	env.ssil_enabled = bool(ssil_cfg.get("enabled", true))
	env.ssil_radius = float(ssil_cfg.get("radius", 2.5))
	env.ssil_intensity = float(ssil_cfg.get("intensity", 1.0))

	var fog_cfg: Dictionary = preset.get("volumetric_fog", {}) as Dictionary
	env.volumetric_fog_enabled = bool(fog_cfg.get("enabled", false))
	env.volumetric_fog_density = float(fog_cfg.get("density", 0.006))
	env.volumetric_fog_albedo = _arr_to_color(fog_cfg.get("albedo"), Color(0.65, 0.72, 0.82))
	env.volumetric_fog_emission = _arr_to_color(fog_cfg.get("emission"), Color(0.03, 0.04, 0.06))
	env.volumetric_fog_length = float(fog_cfg.get("length", 48.0))

	var glow_cfg: Dictionary = preset.get("glow", {}) as Dictionary
	env.glow_enabled = bool(glow_cfg.get("enabled", true))
	env.glow_intensity = float(glow_cfg.get("intensity", 0.45))
	env.glow_bloom = float(glow_cfg.get("bloom", 0.12))

	# Hard orthographic lighting invariant: NEVER enable SDFGI
	env.sdfgi_enabled = false

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = env
	add_child(world_environment)

	# 2. Orthogonal Key DirectionalLight3D
	var dir_cfg: Dictionary = preset.get("directional_light", {}) as Dictionary
	key_directional_light = DirectionalLight3D.new()
	key_directional_light.name = "KeyDirectionalLight"
	key_directional_light.light_color = _arr_to_color(dir_cfg.get("color"), Color.WHITE)
	key_directional_light.light_energy = float(dir_cfg.get("energy", 1.5))
	key_directional_light.rotation_degrees = _arr_to_vec3(dir_cfg.get("rotation_degrees"), Vector3(-50.0, 30.0, 0.0))
	key_directional_light.position = Vector3(room_dims.x * 0.5, room_dims.y + 8.0, room_dims.z * 0.5)
	key_directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key_directional_light.shadow_enabled = true
	key_directional_light.shadow_normal_bias = float(dir_cfg.get("shadow_normal_bias", 1.8))
	key_directional_light.shadow_bias = float(dir_cfg.get("shadow_bias", 0.03))
	key_directional_light.directional_shadow_pancake_size = float(dir_cfg.get("pancake_size", 20.0))
	key_directional_light.directional_shadow_max_distance = float(dir_cfg.get("max_distance", 65.0))
	add_child(key_directional_light)

	# 3. Godot 4.7 AreaLight3D Nodes
	var area_defs: Array = preset.get("area_lights", []) as Array
	for item: Variant in area_defs:
		if not (item is Dictionary):
			continue
		var al_cfg: Dictionary = item as Dictionary
		var al := AreaLight3D.new()
		al.name = str(al_cfg.get("name", "AreaLight"))
		if al_cfg.has("pos"):
			al.position = _arr_to_vec3(al_cfg["pos"])
		else:
			var rel: Vector3 = _arr_to_vec3(al_cfg.get("rel_pos"), Vector3(0.5, 0.9, 0.5))
			al.position = Vector3(rel.x * room_dims.x, rel.y * room_dims.y, rel.z * room_dims.z)
		al.rotation_degrees = _arr_to_vec3(al_cfg.get("rotation_degrees"), Vector3(-90.0, 0.0, 0.0))
		var sz_arr: Array = al_cfg.get("size", [3.0, 3.0]) as Array
		al.area_size = Vector2(float(sz_arr[0]), float(sz_arr[1]))
		al.area_range = float(al_cfg.get("range", 12.0))
		al.area_attenuation = float(al_cfg.get("attenuation", 1.4))
		al.area_normalize_energy = true
		al.light_color = _arr_to_color(al_cfg.get("color"), Color.WHITE)
		al.light_energy = float(al_cfg.get("energy", 12.0))
		al.shadow_enabled = bool(al_cfg.get("shadow_enabled", true))
		al.shadow_normal_bias = float(al_cfg.get("shadow_normal_bias", 1.5))
		add_child(al)
		area_lights.append(al)

	# 4. VoxelGI Volume Spanning Chamber
	voxel_gi = VoxelGI.new()
	voxel_gi.name = "RoomVoxelGI"
	voxel_gi.subdiv = VoxelGI.SUBDIV_64
	voxel_gi.size = Vector3(room_dims.x + 2.0, room_dims.y + 2.0, room_dims.z + 2.0)
	voxel_gi.position = Vector3(room_dims.x * 0.5, room_dims.y * 0.5, room_dims.z * 0.5)
	add_child(voxel_gi)


func bake_gi_if_supported(target_root: Node) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if voxel_gi == null or not is_instance_valid(voxel_gi) or target_root == null:
		return false
	voxel_gi.bake(target_root, false)
	return true
