class_name RoomBuilder
extends RefCounted
## Constructs a modular 3D Filmation chamber from declarative JSON room data.

var _materials_cache: Dictionary = {}
var _entities_cache: Dictionary = {}
var _material_resources: Dictionary = {}
var _cutaway_material_resources: Dictionary = {}
var _scene_cache: Dictionary = {}
var _cutaway_shader: Shader


static func load_json_dict(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RoomBuilder: Failed to open JSON file: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("RoomBuilder: Expected JSON Dictionary in: " + path)
		return {}
	return parsed as Dictionary


func _ensure_catalogs() -> void:
	if _materials_cache.is_empty():
		_materials_cache = load_json_dict("res://data/materials.json")
	if _entities_cache.is_empty():
		_entities_cache = load_json_dict("res://data/entities.json")


func get_material(mat_name: String) -> StandardMaterial3D:
	_ensure_catalogs()
	if _material_resources.has(mat_name):
		return _material_resources[mat_name] as StandardMaterial3D

	var cfg: Dictionary = _materials_cache.get(mat_name, {}) as Dictionary
	var mat := StandardMaterial3D.new()
	var albedo_arr: Array = cfg.get("albedo", [0.5, 0.5, 0.5]) as Array
	mat.albedo_color = Color(float(albedo_arr[0]), float(albedo_arr[1]), float(albedo_arr[2]), 1.0)
	mat.metallic = float(cfg.get("metallic", 0.0))
	mat.roughness = float(cfg.get("roughness", 0.8))
	if cfg.has("emission"):
		var em_arr: Array = cfg.get("emission") as Array
		mat.emission_enabled = true
		mat.emission = Color(float(em_arr[0]), float(em_arr[1]), float(em_arr[2]), 1.0)
		mat.emission_energy_multiplier = float(cfg.get("emission_energy", 1.0))
	_material_resources[mat_name] = mat
	return mat


func _create_cutaway_material(mat_name: String) -> ShaderMaterial:
	_ensure_catalogs()
	if _cutaway_material_resources.has(mat_name):
		return _cutaway_material_resources[mat_name] as ShaderMaterial

	if _cutaway_shader == null:
		_cutaway_shader = load("res://core/shaders/foreground_cutaway.gdshader") as Shader
	var cfg: Dictionary = _materials_cache.get(mat_name, {}) as Dictionary
	var albedo_arr: Array = cfg.get("albedo", [0.47, 0.46, 0.44]) as Array
	var mat := ShaderMaterial.new()
	mat.shader = _cutaway_shader
	mat.set_shader_parameter("albedo_color", Color(float(albedo_arr[0]), float(albedo_arr[1]), float(albedo_arr[2]), 1.0))
	mat.set_shader_parameter("metallic_val", float(cfg.get("metallic", 0.04)))
	mat.set_shader_parameter("roughness_val", float(cfg.get("roughness", 0.78)))
	_cutaway_material_resources[mat_name] = mat
	return mat


static func should_block_use_cutaway(blk: Dictionary, pos: Vector3, sz: Vector3) -> bool:
	if blk.has("cutaway"):
		return bool(blk.get("cutaway"))
	var blk_type: String = str(blk.get("type", "")).to_lower()
	if blk_type.contains("pillar") or blk_type.contains("column") or blk_type.contains("arch"):
		return true
	return (pos.y + sz.y) >= 2.0


func _load_prop_scene(res_path: String) -> PackedScene:
	if _scene_cache.has(res_path):
		return _scene_cache[res_path] as PackedScene
	if not ResourceLoader.exists(res_path):
		return null
	var packed: PackedScene = ResourceLoader.load(res_path) as PackedScene
	if packed != null:
		_scene_cache[res_path] = packed
	return packed


static func _configure_static_model_recursive(node: Node, override_mat: Material = null, cutaway_active_zero: bool = false) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		if override_mat != null:
			mi.material_override = override_mat
		if cutaway_active_zero:
			mi.set_instance_shader_parameter(&"cutaway_active", 0.0)
	for child: Node in node.get_children():
		_configure_static_model_recursive(child, override_mat, cutaway_active_zero)


func build_room_from_path(
	parent: Node3D,
	room_json_path: String,
	lighting_override: String = "",
	camera_mode_override: String = ""
) -> Dictionary:
	var room_data: Dictionary = load_json_dict(room_json_path)
	if room_data.is_empty():
		return {}
	return build_room_into(parent, room_data, lighting_override, camera_mode_override)


func build_room_into(
	parent: Node3D,
	room_data: Dictionary,
	lighting_override: String = "",
	camera_mode_override: String = ""
) -> Dictionary:
	_ensure_catalogs()

	var dims_cfg: Dictionary = room_data.get("dimensions", {}) as Dictionary
	var width: float = float(dims_cfg.get("width", 12.0))
	var depth: float = float(dims_cfg.get("depth", 12.0))
	var height: float = float(dims_cfg.get("height", 6.0))
	var room_dims := Vector3(width, height, depth)

	var arch_root := Node3D.new()
	arch_root.name = "Architecture"
	parent.add_child(arch_root)

	var fg_root := Node3D.new()
	fg_root.name = "ForegroundOccluders"
	parent.add_child(fg_root)

	var doorways_root := Node3D.new()
	doorways_root.name = "Doorways"
	parent.add_child(doorways_root)

	var entities_root := Node3D.new()
	entities_root.name = "Entities"
	parent.add_child(entities_root)

	# 1. Floor Tiles (1.0 m grid, walking surface strictly at y = 0.0)
	_build_floor(arch_root, room_data, int(width), int(depth))

	# 2. Back Walls (North/West), Corner Cap, Foreground Curbs (South/East) & Doorway Markers
	var exits: Dictionary = room_data.get("exits", {}) as Dictionary
	_build_perimeter_walls(arch_root, doorways_root, room_data, width, depth, height, exits)

	# 3. Interior Architectural Blocks
	var blocks: Array = room_data.get("blocks", []) as Array
	for i: int in range(blocks.size()):
		var blk: Dictionary = blocks[i] as Dictionary
		var pos: Vector3 = _vec3_from_array(blk.get("pos", [0, 0, 0]))
		var sz: Vector3 = _vec3_from_array(blk.get("size", [1, 1, 1]))
		var mat_name: String = str(blk.get("material", "stone_pillar"))
		var blk_type: String = str(blk.get("type", "block"))
		var use_cutaway: bool = should_block_use_cutaway(blk, pos, sz)
		var blk_mat: Material = _create_cutaway_material(mat_name) if use_cutaway else get_material(mat_name)
		var blk_node: StaticBody3D = _create_static_box(
			arch_root,
			"Block_%02d_%s" % [i, blk_type],
			pos + sz * 0.5,
			sz,
			blk_mat
		)
		_attach_block_or_pillar_model(blk_node, blk_type, sz, blk_mat if use_cutaway else null, use_cutaway)
		if use_cutaway:
			blk_node.add_to_group("foreground_occluders")
			blk_node.set_meta("cutaway", true)
			blk_node.set_meta("cutaway_active", false)
			var blk_mesh: MeshInstance3D = blk_node.get_node_or_null("Mesh") as MeshInstance3D
			if blk_mesh != null:
				blk_mesh.set_instance_shader_parameter(&"cutaway_active", 0.0)

	# 4. Foreground Occluders (tagged for Stage 2 cutaway shader)
	var occluders: Array = room_data.get("foreground_occluders", []) as Array
	for i: int in range(occluders.size()):
		var occ: Dictionary = occluders[i] as Dictionary
		var pos: Vector3 = _vec3_from_array(occ.get("pos", [0, 0, 0]))
		var sz: Vector3 = _vec3_from_array(occ.get("size", [1, 1, 1]))
		var mat_name: String = str(occ.get("material", "stone_pillar"))
		var occ_type: String = str(occ.get("type", "occluder"))
		var use_cutaway: bool = bool(occ.get("cutaway", true))
		var occ_mat: Material = _create_cutaway_material(mat_name) if use_cutaway else get_material(mat_name)
		var occ_node: StaticBody3D = _create_static_box(
			fg_root,
			"Foreground_%02d_%s" % [i, occ_type],
			pos + sz * 0.5,
			sz,
			occ_mat
		)
		_attach_block_or_pillar_model(occ_node, occ_type, sz, occ_mat if use_cutaway else null, use_cutaway)
		occ_node.add_to_group("foreground_occluders")
		occ_node.set_meta("cutaway", use_cutaway)
		occ_node.set_meta("cutaway_active", false)
		if use_cutaway:
			var occ_mesh: MeshInstance3D = occ_node.get_node_or_null("Mesh") as MeshInstance3D
			if occ_mesh != null:
				occ_mesh.set_instance_shader_parameter(&"cutaway_active", 0.0)

	# 5. Entities (Stage 3 deterministic puzzle entity factory)
	var entity_factory := EntityFactory.new()
	var entity_map: Dictionary = entity_factory.spawn_entities(
		entities_root,
		room_data.get("entities", []) as Array,
		_entities_cache,
		Callable(self, "get_material")
	)

	# 6. Orthographic Camera Rig
	var cam_cfg: Dictionary = room_data.get("camera", {}) as Dictionary
	var mode_str: String = camera_mode_override if not camera_mode_override.is_empty() else str(cam_cfg.get("mode", "true_isometric"))
	var margin: float = float(cam_cfg.get("margin", 0.10))
	var camera_rig := DioramaCameraRig.new()
	camera_rig.name = "DioramaCameraRig"
	parent.add_child(camera_rig)
	camera_rig.configure_for_room(room_dims, DioramaCameraRig.mode_from_string(mode_str), margin)

	# 7. Modern PBR Lighting Rig
	var preset_name: String = lighting_override if not lighting_override.is_empty() else str(room_data.get("lighting_preset", "castle_stone_skylight"))
	var preset: Dictionary = DioramaLighting.load_preset_by_name(preset_name)
	var lighting := DioramaLighting.new()
	lighting.name = "DioramaLighting"
	parent.add_child(lighting)
	lighting.apply_preset(preset, room_dims)

	return {
		"room_dims": room_dims,
		"camera_rig": camera_rig,
		"lighting": lighting,
		"architecture_root": arch_root,
		"foreground_root": fg_root,
		"doorways_root": doorways_root,
		"entities_root": entities_root,
		"entity_map": entity_map
	}


func _build_floor(arch_root: Node3D, room_data: Dictionary, width: int, depth: int) -> void:
	var floor_cfg: Dictionary = room_data.get("floor", {}) as Dictionary
	var mat_primary: StandardMaterial3D = get_material(str(floor_cfg.get("material", "stone_floor")))
	var checker_name: String = str(floor_cfg.get("checker_material", ""))
	var mat_checker: StandardMaterial3D = get_material(checker_name) if not checker_name.is_empty() else mat_primary
	var thickness: float = float(floor_cfg.get("thickness", 0.5))

	var void_lookup: Dictionary = {}
	for cell: Variant in (floor_cfg.get("void_cells", []) as Array):
		if cell is Array and cell.size() >= 2:
			void_lookup[Vector2i(int(cell[0]), int(cell[1]))] = true

	var floor_group := Node3D.new()
	floor_group.name = "FloorTiles"
	arch_root.add_child(floor_group)

	for x: int in range(width):
		for z: int in range(depth):
			if void_lookup.has(Vector2i(x, z)):
				continue
			var tile_mat: StandardMaterial3D = mat_primary if ((x + z) % 2 == 0) else mat_checker
			_create_static_box(
				floor_group,
				"Tile_%02d_%02d" % [x, z],
				Vector3(float(x) + 0.5, -thickness * 0.5, float(z) + 0.5),
				Vector3(1.0, thickness, 1.0),
				tile_mat
			)


func _build_perimeter_walls(
	arch_root: Node3D,
	doorways_root: Node3D,
	room_data: Dictionary,
	width: float,
	depth: float,
	height: float,
	exits: Dictionary
) -> void:
	var wall_cfg: Dictionary = room_data.get("walls", {}) as Dictionary
	var wall_mat: StandardMaterial3D = get_material(str(wall_cfg.get("material", "stone_wall")))
	var curb_mat: StandardMaterial3D = get_material(str(wall_cfg.get("curb_material", "foreground_curb")))
	var trim_mat: StandardMaterial3D = get_material(str(wall_cfg.get("trim_material", "doorway_trim")))
	var t: float = float(wall_cfg.get("thickness", 0.5))
	var curb_h: float = float(wall_cfg.get("curb_height", 0.4))

	# Corner join pillars so walls & curbs meet seamlessly with zero gaps
	_create_static_box(arch_root, "Corner_NW", Vector3(-t * 0.5, height * 0.5, -t * 0.5), Vector3(t, height, t), wall_mat)
	_create_static_box(arch_root, "Corner_NE", Vector3(width + t * 0.5, curb_h * 0.5, -t * 0.5), Vector3(t, curb_h, t), curb_mat)
	_create_static_box(arch_root, "Corner_SW", Vector3(-t * 0.5, curb_h * 0.5, depth + t * 0.5), Vector3(t, curb_h, t), curb_mat)
	_create_static_box(arch_root, "Corner_SE", Vector3(width + t * 0.5, curb_h * 0.5, depth + t * 0.5), Vector3(t, curb_h, t), curb_mat)

	# North Back Wall (along X: 0..width at Z = -t/2)
	_build_wall_along_x(arch_root, doorways_root, "north", -t * 0.5, width, height, t, exits.get("north", {}) as Dictionary, wall_mat, trim_mat, true)
	# West Back Wall (along Z: 0..depth at X = -t/2)
	_build_wall_along_z(arch_root, doorways_root, "west", -t * 0.5, depth, height, t, exits.get("west", {}) as Dictionary, wall_mat, trim_mat, true)
	# South Foreground Curb (along X: 0..width at Z = depth + t/2)
	_build_wall_along_x(arch_root, doorways_root, "south", depth + t * 0.5, width, curb_h, t, exits.get("south", {}) as Dictionary, curb_mat, trim_mat, false)
	# East Foreground Curb (along Z: 0..depth at X = width + t/2)
	_build_wall_along_z(arch_root, doorways_root, "east", width + t * 0.5, depth, curb_h, t, exits.get("east", {}) as Dictionary, curb_mat, trim_mat, false)


func _attach_block_or_pillar_model(
	body: StaticBody3D,
	block_type: String,
	sz: Vector3,
	cutaway_mat: Material,
	use_cutaway: bool
) -> void:
	var lower_type: String = block_type.to_lower()
	if lower_type.contains("pillar") or lower_type.contains("column") or lower_type.contains("arch"):
		var pillar_scene: PackedScene = _load_prop_scene("res://assets/props/stone_pillar.glb")
		if pillar_scene != null:
			var model: Node3D = pillar_scene.instantiate() as Node3D
			model.name = "PillarModel"
			model.position = Vector3(0.0, -sz.y * 0.5, 0.0)
			model.scale = Vector3(sz.x, sz.y / 3.5, sz.z)
			_configure_static_model_recursive(model, cutaway_mat, use_cutaway)
			body.add_child(model)
			var proxy: MeshInstance3D = body.get_node_or_null("Mesh") as MeshInstance3D
			if proxy != null:
				proxy.visible = false
		return

	if absf(sz.y - 1.0) <= 0.1 and sz.x >= 0.85 and sz.z >= 0.85:
		var block_scene: PackedScene = _load_prop_scene("res://assets/props/stone_block.glb")
		if block_scene != null:
			var group := Node3D.new()
			group.name = "BlockModel"
			var nx: int = maxi(1, int(roundf(sz.x)))
			var nz: int = maxi(1, int(roundf(sz.z)))
			var cell_w: float = sz.x / float(nx)
			var cell_d: float = sz.z / float(nz)
			for ix: int in range(nx):
				for iz: int in range(nz):
					var inst: Node3D = block_scene.instantiate() as Node3D
					inst.position = Vector3(
						-sz.x * 0.5 + (float(ix) + 0.5) * cell_w,
						-sz.y * 0.5,
						-sz.z * 0.5 + (float(iz) + 0.5) * cell_d
					)
					inst.scale = Vector3(cell_w, sz.y, cell_d)
					_configure_static_model_recursive(inst, cutaway_mat, use_cutaway)
					group.add_child(inst)
			body.add_child(group)
			var proxy_blk: MeshInstance3D = body.get_node_or_null("Mesh") as MeshInstance3D
			if proxy_blk != null:
				proxy_blk.visible = false


func _attach_wall_masonry_span(
	arch_root: Node3D,
	prefix: String,
	seg_start: float,
	seg_end: float,
	wall_h: float,
	fixed_coord: float,
	along_x: bool
) -> void:
	var span: float = seg_end - seg_start
	if span <= 0.2:
		return
	var panel_scene: PackedScene = _load_prop_scene("res://assets/props/wall_stone_panel.glb")
	if panel_scene == null:
		return
	var cursor: float = seg_start
	var idx: int = 0
	while cursor < seg_end - 0.05:
		var seg_w: float = minf(2.0, seg_end - cursor)
		var inst: Node3D = panel_scene.instantiate() as Node3D
		inst.name = "%s_%02d" % [prefix, idx]
		if along_x:
			inst.position = Vector3(cursor + seg_w * 0.5, 0.0, fixed_coord)
		else:
			inst.position = Vector3(fixed_coord, 0.0, cursor + seg_w * 0.5)
			inst.rotation_degrees.y = 90.0
		inst.scale = Vector3(seg_w / 2.0, wall_h / 6.0, 1.0)
		_configure_static_model_recursive(inst)
		arch_root.add_child(inst)
		cursor += seg_w
		idx += 1


func _attach_wall_lintel_masonry(
	arch_root: Node3D,
	prefix: String,
	seg_start: float,
	seg_end: float,
	base_y: float,
	lintel_h: float,
	fixed_coord: float,
	along_x: bool
) -> void:
	var span: float = seg_end - seg_start
	if span <= 0.2 or lintel_h <= 0.2:
		return
	var panel_scene: PackedScene = _load_prop_scene("res://assets/props/wall_stone_lintel.glb")
	if panel_scene == null:
		return
	var cursor: float = seg_start
	var idx: int = 0
	while cursor < seg_end - 0.05:
		var seg_w: float = minf(2.0, seg_end - cursor)
		var inst: Node3D = panel_scene.instantiate() as Node3D
		inst.name = "%s_%02d" % [prefix, idx]
		if along_x:
			inst.position = Vector3(cursor + seg_w * 0.5, base_y, fixed_coord)
		else:
			inst.position = Vector3(fixed_coord, base_y, cursor + seg_w * 0.5)
			inst.rotation_degrees.y = 90.0
		inst.scale = Vector3(seg_w / 2.0, lintel_h / 3.0, 1.0)
		_configure_static_model_recursive(inst)
		arch_root.add_child(inst)
		cursor += seg_w
		idx += 1


func _build_wall_along_x(
	arch_root: Node3D,
	doorways_root: Node3D,
	dir_name: String,
	z_center: float,
	span_x: float,
	wall_h: float,
	t: float,
	exit_cfg: Dictionary,
	wall_mat: StandardMaterial3D,
	trim_mat: StandardMaterial3D,
	is_tall_wall: bool
) -> void:
	if exit_cfg.is_empty():
		_create_static_box(arch_root, "Wall_" + dir_name, Vector3(span_x * 0.5, wall_h * 0.5, z_center), Vector3(span_x, wall_h, t), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_" + dir_name, 0.0, span_x, wall_h, 0.02, true)
		return

	var door_pos: Array = exit_cfg.get("door_pos", [0, 0]) as Array
	var door_x: float = float(door_pos[0])
	var door_w: float = float(exit_cfg.get("width", 2))
	var door_h: float = minf(float(exit_cfg.get("height", 3.0)), wall_h)

	if door_x > 0.0:
		_create_static_box(arch_root, "Wall_%s_L" % dir_name, Vector3(door_x * 0.5, wall_h * 0.5, z_center), Vector3(door_x, wall_h, t), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_L" % dir_name, 0.0, door_x, wall_h, 0.02, true)
	var right_start: float = door_x + door_w
	var right_len: float = span_x - right_start
	if right_len > 0.0:
		_create_static_box(arch_root, "Wall_%s_R" % dir_name, Vector3(right_start + right_len * 0.5, wall_h * 0.5, z_center), Vector3(right_len, wall_h, t), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_R" % dir_name, right_start, span_x, wall_h, 0.02, true)
	if is_tall_wall and wall_h > door_h:
		var lintel_h: float = wall_h - door_h
		_create_static_box(arch_root, "Wall_%s_Lintel" % dir_name, Vector3(door_x + door_w * 0.5, door_h + lintel_h * 0.5, z_center), Vector3(door_w, lintel_h, t), wall_mat)
		_attach_wall_lintel_masonry(arch_root, "WallLintelMasonry_" + dir_name, door_x, door_x + door_w, door_h, lintel_h, 0.02, true)
		var trim_box: StaticBody3D = _create_static_box(arch_root, "Trim_%s_Top" % dir_name, Vector3(door_x + door_w * 0.5, door_h + 0.1, z_center), Vector3(door_w + 0.3, 0.2, t + 0.12), trim_mat)
		var arch_scene: PackedScene = _load_prop_scene("res://assets/props/arch_stone_doorway.glb")
		if arch_scene != null:
			var arch_inst: Node3D = arch_scene.instantiate() as Node3D
			arch_inst.name = "Arch_" + dir_name
			arch_inst.position = Vector3(door_x + door_w * 0.5, 0.0, z_center + 0.12)
			_configure_static_model_recursive(arch_inst)
			arch_root.add_child(arch_inst)
			var trim_mesh: MeshInstance3D = trim_box.get_node_or_null("Mesh") as MeshInstance3D
			if trim_mesh != null:
				trim_mesh.visible = false

	var spawn := Marker3D.new()
	spawn.name = "Spawn_" + dir_name
	var spawn_z: float = 1.25 if dir_name == "north" else float(door_pos[1]) - 0.25
	spawn.position = Vector3(door_x + door_w * 0.5, 0.0, spawn_z)
	spawn.set_meta("direction", dir_name)
	spawn.set_meta("target_room", exit_cfg.get("target_room", [0, 0]))
	doorways_root.add_child(spawn)

	var exit_area := Area3D.new()
	exit_area.name = "Exit_" + dir_name
	exit_area.collision_layer = 8
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	var exit_z: float = 0.28 if dir_name == "north" else float(door_pos[1]) + 0.72
	exit_area.position = Vector3(door_x + door_w * 0.5, 1.1, exit_z)
	var exit_col := CollisionShape3D.new()
	var exit_box := BoxShape3D.new()
	exit_box.size = Vector3(door_w * 0.9, 2.2, 0.55)
	exit_col.shape = exit_box
	exit_area.add_child(exit_col)
	exit_area.set_meta("direction", dir_name)
	var tr_arr: Array = exit_cfg.get("target_room", [0, 0]) as Array
	exit_area.set_meta("target_room", Vector2i(int(tr_arr[0]), int(tr_arr[1])))
	doorways_root.add_child(exit_area)


func _build_wall_along_z(
	arch_root: Node3D,
	doorways_root: Node3D,
	dir_name: String,
	x_center: float,
	span_z: float,
	wall_h: float,
	t: float,
	exit_cfg: Dictionary,
	wall_mat: StandardMaterial3D,
	trim_mat: StandardMaterial3D,
	is_tall_wall: bool
) -> void:
	if exit_cfg.is_empty():
		_create_static_box(arch_root, "Wall_" + dir_name, Vector3(x_center, wall_h * 0.5, span_z * 0.5), Vector3(t, wall_h, span_z), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_" + dir_name, 0.0, span_z, wall_h, 0.02, false)
		return

	var door_pos: Array = exit_cfg.get("door_pos", [0, 0]) as Array
	var door_z: float = float(door_pos[1])
	var door_w: float = float(exit_cfg.get("width", 2))
	var door_h: float = minf(float(exit_cfg.get("height", 3.0)), wall_h)

	if door_z > 0.0:
		_create_static_box(arch_root, "Wall_%s_L" % dir_name, Vector3(x_center, wall_h * 0.5, door_z * 0.5), Vector3(t, wall_h, door_z), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_L" % dir_name, 0.0, door_z, wall_h, 0.02, false)
	var right_start: float = door_z + door_w
	var right_len: float = span_z - right_start
	if right_len > 0.0:
		_create_static_box(arch_root, "Wall_%s_R" % dir_name, Vector3(x_center, wall_h * 0.5, right_start + right_len * 0.5), Vector3(t, wall_h, right_len), wall_mat)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_R" % dir_name, right_start, span_z, wall_h, 0.02, false)
	if is_tall_wall and wall_h > door_h:
		var lintel_h: float = wall_h - door_h
		_create_static_box(arch_root, "Wall_%s_Lintel" % dir_name, Vector3(x_center, door_h + lintel_h * 0.5, door_z + door_w * 0.5), Vector3(t, lintel_h, door_w), wall_mat)
		_attach_wall_lintel_masonry(arch_root, "WallLintelMasonry_" + dir_name, door_z, door_z + door_w, door_h, lintel_h, 0.02, false)
		var trim_box: StaticBody3D = _create_static_box(arch_root, "Trim_%s_Top" % dir_name, Vector3(x_center, door_h + 0.1, door_z + door_w * 0.5), Vector3(t + 0.12, 0.2, door_w + 0.3), trim_mat)
		var arch_scene: PackedScene = _load_prop_scene("res://assets/props/arch_stone_doorway.glb")
		if arch_scene != null:
			var arch_inst: Node3D = arch_scene.instantiate() as Node3D
			arch_inst.name = "Arch_" + dir_name
			arch_inst.position = Vector3(x_center + 0.12, 0.0, door_z + door_w * 0.5)
			arch_inst.rotation_degrees.y = 90.0
			_configure_static_model_recursive(arch_inst)
			arch_root.add_child(arch_inst)
			var trim_mesh: MeshInstance3D = trim_box.get_node_or_null("Mesh") as MeshInstance3D
			if trim_mesh != null:
				trim_mesh.visible = false

	var spawn := Marker3D.new()
	spawn.name = "Spawn_" + dir_name
	var spawn_x: float = 1.25 if dir_name == "west" else float(door_pos[0]) - 0.25
	spawn.position = Vector3(spawn_x, 0.0, door_z + door_w * 0.5)
	spawn.set_meta("direction", dir_name)
	spawn.set_meta("target_room", exit_cfg.get("target_room", [0, 0]))
	doorways_root.add_child(spawn)

	var exit_area := Area3D.new()
	exit_area.name = "Exit_" + dir_name
	exit_area.collision_layer = 8
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	var exit_x: float = 0.28 if dir_name == "west" else float(door_pos[0]) + 0.72
	exit_area.position = Vector3(exit_x, 1.1, door_z + door_w * 0.5)
	var exit_col := CollisionShape3D.new()
	var exit_box := BoxShape3D.new()
	exit_box.size = Vector3(0.55, 2.2, door_w * 0.9)
	exit_col.shape = exit_box
	exit_area.add_child(exit_col)
	exit_area.set_meta("direction", dir_name)
	var tr_arr: Array = exit_cfg.get("target_room", [0, 0]) as Array
	exit_area.set_meta("target_room", Vector2i(int(tr_arr[0]), int(tr_arr[1])))
	doorways_root.add_child(exit_area)


func _create_static_box(
	parent: Node3D,
	node_name: String,
	center_pos: Vector3,
	size: Vector3,
	material: Material
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center_pos

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.layers = 1
	mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh_inst.mesh = box

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	parent.add_child(body)
	return body


static func _vec3_from_array(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO
