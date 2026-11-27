class_name RoomBuilder
extends RefCounted
## Constructs a modular 3D Filmation chamber from declarative JSON room data.

const HERO_CUTAWAY_HEIGHT_M: float = 1.40
const DEFAULT_MAX_CUTAWAY_TRANSPARENCY: float = 0.58

var _materials_cache: Dictionary = {}
var _entities_cache: Dictionary = {}
var _material_resources: Dictionary = {}
var _tinted_model_materials: Dictionary = {}
var _cutaway_material_resources: Dictionary = {}
var _surface_cutaway_materials: Dictionary = {}
var _forest_floor_materials: Dictionary = {}
var _dungeon_floor_materials: Dictionary = {}
var _scene_cache: Dictionary = {}
var _cutaway_shader: Shader
var _forest_floor_shader: Shader
var _dungeon_floor_shader: Shader


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
	mat.set_shader_parameter("max_cutaway_transparency", DEFAULT_MAX_CUTAWAY_TRANSPARENCY)
	if cfg.has("emission"):
		var em_arr: Array = cfg.get("emission") as Array
		mat.set_shader_parameter("emission_color", Color(float(em_arr[0]), float(em_arr[1]), float(em_arr[2]), 1.0))
		mat.set_shader_parameter("emission_energy", float(cfg.get("emission_energy", 1.0)))
	_cutaway_material_resources[mat_name] = mat
	return mat


func _create_cutaway_material_from_standard(src_mat: StandardMaterial3D) -> ShaderMaterial:
	var cache_key: int = src_mat.get_instance_id()
	if _surface_cutaway_materials.has(cache_key):
		return _surface_cutaway_materials[cache_key] as ShaderMaterial
	if _cutaway_shader == null:
		_cutaway_shader = load("res://core/shaders/foreground_cutaway.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _cutaway_shader
	mat.set_shader_parameter("albedo_color", src_mat.albedo_color)
	mat.set_shader_parameter("metallic_val", src_mat.metallic)
	mat.set_shader_parameter("roughness_val", src_mat.roughness)
	mat.set_shader_parameter("max_cutaway_transparency", DEFAULT_MAX_CUTAWAY_TRANSPARENCY)
	if src_mat.emission_enabled:
		mat.set_shader_parameter("emission_color", src_mat.emission)
		mat.set_shader_parameter("emission_energy", src_mat.emission_energy_multiplier)
	_surface_cutaway_materials[cache_key] = mat
	return mat


static func should_block_use_cutaway(blk: Dictionary, pos: Vector3, sz: Vector3) -> bool:
	if blk.has("cutaway"):
		return bool(blk.get("cutaway"))
	var blk_type: String = str(blk.get("type", "")).to_lower()
	if blk_type.contains("pillar") or blk_type.contains("column") or blk_type.contains("arch"):
		return true
	return (pos.y + sz.y) > HERO_CUTAWAY_HEIGHT_M


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


static func _compute_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var rel := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			rel = (cur as Node3D).transform * rel
		cur = cur.get_parent()
	return rel


static func _collect_mesh_instances_recursive(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances_recursive(child, out)


static func _attach_cutaway_shadow_caster(body: Node3D, opaque_mat: Material) -> void:
	if body.get_node_or_null("ShadowCaster") != null:
		return
	var sources: Array[MeshInstance3D] = []
	var model_root: Node = body.get_node_or_null("PillarModel")
	if model_root == null:
		model_root = body.get_node_or_null("BlockModel")
	if model_root == null:
		model_root = body.get_node_or_null("ArchModel")
	if model_root == null:
		model_root = body.get_node_or_null("ModelVisual")
	var proxy_mesh: MeshInstance3D = body.get_node_or_null("Mesh") as MeshInstance3D
	if model_root != null:
		_collect_mesh_instances_recursive(model_root, sources)
		if proxy_mesh != null:
			proxy_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif proxy_mesh != null:
		sources.append(proxy_mesh)

	if sources.is_empty():
		return

	var caster_root := Node3D.new()
	caster_root.name = "ShadowCaster"
	body.add_child(caster_root)

	for idx: int in range(sources.size()):
		var src_mi: MeshInstance3D = sources[idx]
		src_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if src_mi.mesh == null:
			continue
		var shadow_mi := MeshInstance3D.new()
		shadow_mi.name = "ShadowMesh_%02d" % idx
		shadow_mi.mesh = src_mi.mesh
		shadow_mi.transform = _compute_relative_transform(src_mi, body)
		shadow_mi.layers = 1
		shadow_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shadow_mi.material_override = opaque_mat
		shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		caster_root.add_child(shadow_mi)


func build_room_from_path(
	parent: Node3D,
	room_json_path: String,
	lighting_override: String = "",
	camera_mode_override: String = ""
) -> Dictionary:
	var room_data: Dictionary = load_json_dict(room_json_path)
	if room_data.is_empty():
		return {}
	var gi_path: String = DioramaLighting.get_room_json_gi_path(room_json_path)
	return build_room_into(parent, room_data, lighting_override, camera_mode_override, gi_path)


func build_room_into(
	parent: Node3D,
	room_data: Dictionary,
	lighting_override: String = "",
	camera_mode_override: String = "",
	voxel_gi_path: String = ""
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
			_attach_cutaway_shadow_caster(blk_node, get_material(mat_name))
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
			_attach_cutaway_shadow_caster(occ_node, get_material(mat_name))
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
	if not voxel_gi_path.is_empty():
		lighting.apply_prebaked_gi(voxel_gi_path)

	return {
		"room_dims": room_dims,
		"camera_rig": camera_rig,
		"lighting": lighting,
		"voxel_gi_path": voxel_gi_path,
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

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	arch_root.add_child(floor_body)

	var walkable: Array[bool] = []
	var visited: Array[bool] = []
	walkable.resize(width * depth)
	visited.resize(width * depth)

	for x: int in range(width):
		for z: int in range(depth):
			var idx: int = z * width + x
			if void_lookup.has(Vector2i(x, z)):
				walkable[idx] = false
				visited[idx] = true
				continue
			walkable[idx] = true
			visited[idx] = false
			var tile_mat: StandardMaterial3D = mat_primary if ((x + z) % 2 == 0) else mat_checker
			var tile_node := Node3D.new()
			tile_node.name = "Tile_%02d_%02d" % [x, z]
			tile_node.position = Vector3(float(x) + 0.5, -thickness * 0.5, float(z) + 0.5)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.name = "Mesh"
			mesh_inst.layers = 1
			mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1.0, thickness, 1.0)
			box_mesh.material = tile_mat
			mesh_inst.mesh = box_mesh
			tile_node.add_child(mesh_inst)
			floor_group.add_child(tile_node)

	# Merge contiguous walkable cells into maximal BoxShape3D colliders to eliminate tile-seam snags.
	for z: int in range(depth):
		for x: int in range(width):
			var start_idx: int = z * width + x
			if visited[start_idx] or not walkable[start_idx]:
				continue
			var rw: int = 1
			while x + rw < width:
				var next_idx: int = z * width + (x + rw)
				if visited[next_idx] or not walkable[next_idx]:
					break
				rw += 1
			var rd: int = 1
			while z + rd < depth:
				var row_ok: bool = true
				for dx: int in range(rw):
					var cell_idx: int = (z + rd) * width + (x + dx)
					if visited[cell_idx] or not walkable[cell_idx]:
						row_ok = false
						break
				if not row_ok:
					break
				rd += 1
			for dz: int in range(rd):
				for dx: int in range(rw):
					visited[(z + dz) * width + (x + dx)] = true
			var col_shape := CollisionShape3D.new()
			var col_box := BoxShape3D.new()
			col_box.size = Vector3(float(rw), thickness, float(rd))
			col_shape.shape = col_box
			col_shape.position = Vector3(float(x) + float(rw) * 0.5, -thickness * 0.5, float(z) + float(rd) * 0.5)
			floor_body.add_child(col_shape)


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

	# Corner join pillars so walls & curbs meet seamlessly with zero gaps (full-height colliders prevent climbing)
	var low_wall_stone: String = "res://assets/props/low_wall_stone.glb"
	_create_static_box(arch_root, "Corner_NW", Vector3(-t * 0.5, height * 0.5, -t * 0.5), Vector3(t, height, t), wall_mat)
	var c_ne: StaticBody3D = _create_static_box(arch_root, "Corner_NE", Vector3(width + t * 0.5, curb_h * 0.5, -t * 0.5), Vector3(t, curb_h, t), curb_mat, height)
	_attach_low_corner_cap(c_ne, low_wall_stone, t, curb_h)
	var c_sw: StaticBody3D = _create_static_box(arch_root, "Corner_SW", Vector3(-t * 0.5, curb_h * 0.5, depth + t * 0.5), Vector3(t, curb_h, t), curb_mat, height)
	_attach_low_corner_cap(c_sw, low_wall_stone, t, curb_h)
	var c_se: StaticBody3D = _create_static_box(arch_root, "Corner_SE", Vector3(width + t * 0.5, curb_h * 0.5, depth + t * 0.5), Vector3(t, curb_h, t), curb_mat, height)
	_attach_low_corner_cap(c_se, low_wall_stone, t, curb_h)

	var floor_cfg: Dictionary = room_data.get("floor", {}) as Dictionary
	var sill_floor_mat: Material = get_material(str(floor_cfg.get("material", "stone_floor")))
	var panel_glb: String = "res://assets/props/wall_stone_panel.glb"
	var lintel_glb: String = "res://assets/props/wall_stone_lintel.glb"
	var arch_glb: String = "res://assets/props/arch_stone_doorway.glb"

	# North Back Wall (along X: 0..width at Z = -t/2)
	_build_wall_along_x(arch_root, doorways_root, "north", -t * 0.5, width, height, t, exits.get("north", {}) as Dictionary, wall_mat, trim_mat, true, panel_glb, lintel_glb, arch_glb, height, "", sill_floor_mat)
	# West Back Wall (along Z: 0..depth at X = -t/2)
	_build_wall_along_z(arch_root, doorways_root, "west", -t * 0.5, depth, height, t, exits.get("west", {}) as Dictionary, wall_mat, trim_mat, true, panel_glb, lintel_glb, arch_glb, height, "", sill_floor_mat)
	# South Foreground Low Wall (along X: 0..width at Z = depth + t/2)
	_build_wall_along_x(arch_root, doorways_root, "south", depth + t * 0.5, width, curb_h, t, exits.get("south", {}) as Dictionary, curb_mat, trim_mat, false, panel_glb, lintel_glb, arch_glb, height, low_wall_stone, sill_floor_mat)
	# East Foreground Low Wall (along Z: 0..depth at X = width + t/2)
	_build_wall_along_z(arch_root, doorways_root, "east", width + t * 0.5, depth, curb_h, t, exits.get("east", {}) as Dictionary, curb_mat, trim_mat, false, panel_glb, lintel_glb, arch_glb, height, low_wall_stone, sill_floor_mat)


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
	along_x: bool,
	panel_glb_path: String = "res://assets/props/wall_stone_panel.glb"
) -> void:
	var span: float = seg_end - seg_start
	if span <= 0.2:
		return
	var panel_scene: PackedScene = _load_prop_scene(panel_glb_path)
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
	along_x: bool,
	lintel_glb_path: String = "res://assets/props/wall_stone_lintel.glb"
) -> void:
	var span: float = seg_end - seg_start
	if span <= 0.2 or lintel_h <= 0.2:
		return
	var panel_scene: PackedScene = _load_prop_scene(lintel_glb_path)
	if panel_scene == null:
		return
	var base_h: float = 3.0
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
		inst.scale = Vector3(seg_w / 2.0, lintel_h / base_h, 1.0)
		_configure_static_model_recursive(inst)
		arch_root.add_child(inst)
		cursor += seg_w
		idx += 1


func _attach_low_wall_span(
	arch_root: Node3D,
	prefix: String,
	seg_start: float,
	seg_end: float,
	fixed_coord: float,
	along_x: bool,
	low_wall_glb_path: String
) -> void:
	var span: float = seg_end - seg_start
	if span <= 0.1 or low_wall_glb_path.is_empty():
		return
	var wall_scene: PackedScene = _load_prop_scene(low_wall_glb_path)
	if wall_scene == null:
		return
	var cursor: float = seg_start
	var idx: int = 0
	while cursor < seg_end - 0.05:
		var seg_w: float = minf(2.0, seg_end - cursor)
		var inst: Node3D = wall_scene.instantiate() as Node3D
		inst.name = "%s_%02d" % [prefix, idx]
		if along_x:
			inst.position = Vector3(cursor + seg_w * 0.5, 0.0, fixed_coord)
		else:
			inst.position = Vector3(fixed_coord, 0.0, cursor + seg_w * 0.5)
			inst.rotation_degrees.y = 90.0
		inst.scale = Vector3(seg_w / 2.0, 1.0, 1.0)
		_configure_static_model_recursive(inst)
		arch_root.add_child(inst)
		cursor += seg_w
		idx += 1


func _attach_low_corner_cap(
	corner_body: StaticBody3D,
	low_wall_glb_path: String,
	t: float,
	curb_h: float
) -> void:
	if corner_body == null or low_wall_glb_path.is_empty():
		return
	var wall_scene: PackedScene = _load_prop_scene(low_wall_glb_path)
	if wall_scene == null:
		return
	var inst: Node3D = wall_scene.instantiate() as Node3D
	inst.name = "LowCornerModel"
	inst.position = Vector3(0.0, -curb_h * 0.5, 0.0)
	inst.scale = Vector3(t / 2.0, 1.0, 1.0)
	_configure_static_model_recursive(inst)
	corner_body.add_child(inst)
	_hide_body_proxy_mesh(corner_body, low_wall_glb_path)


func _hide_body_proxy_mesh(body: StaticBody3D, glb_path: String) -> void:
	if body == null or glb_path.is_empty():
		return
	var proxy: MeshInstance3D = body.get_node_or_null("Mesh") as MeshInstance3D
	if proxy != null:
		proxy.visible = false


func _create_doorway_sill(
	arch_root: Node3D,
	dir_name: String,
	center_pos: Vector3,
	door_w: float,
	along_x: bool,
	outward_sign: float,
	sill_floor_mat: Material = null,
	wall_thickness: float = 0.5
) -> void:
	var sill := StaticBody3D.new()
	sill.name = "DoorwaySill_" + dir_name
	sill.collision_layer = 1
	sill.collision_mask = 0
	sill.position = center_pos

	var vis_floor := MeshInstance3D.new()
	vis_floor.name = "SillFloorMesh"
	vis_floor.layers = 1
	vis_floor.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var vis_box := BoxMesh.new()
	var vis_depth: float = maxf(0.1, wall_thickness)
	vis_box.size = Vector3(door_w, 0.5, vis_depth) if along_x else Vector3(vis_depth, 0.5, door_w)
	vis_box.material = sill_floor_mat if sill_floor_mat != null else get_material("stone_floor")
	vis_floor.mesh = vis_box
	vis_floor.position = Vector3(0.0, -0.25, outward_sign * vis_depth * 0.5) if along_x else Vector3(outward_sign * vis_depth * 0.5, -0.25, 0.0)
	sill.add_child(vis_floor)

	# Back-wall doorways (North/West, outward_sign < 0) get a solid dark void backing
	# so transparent 3D backgrounds do not leak through open archways.
	if outward_sign < 0.0:
		var void_mesh := MeshInstance3D.new()
		void_mesh.name = "DoorwayVoidMesh"
		void_mesh.layers = 1
		var void_box := BoxMesh.new()
		void_box.size = Vector3(door_w, 3.0, 0.06) if along_x else Vector3(0.06, 3.0, door_w)
		var void_mat := StandardMaterial3D.new()
		void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		void_mat.albedo_color = Color(0.015, 0.015, 0.02, 1.0)
		void_box.material = void_mat
		void_mesh.mesh = void_box
		void_mesh.position = Vector3(0.0, 1.5, outward_sign * (vis_depth + 0.02)) if along_x else Vector3(outward_sign * (vis_depth + 0.02), 1.5, 0.0)
		sill.add_child(void_mesh)

	var floor_col := CollisionShape3D.new()
	floor_col.name = "SillFloor"
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(door_w + 0.4, 0.5, 1.4) if along_x else Vector3(1.4, 0.5, door_w + 0.4)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.25, outward_sign * 0.55) if along_x else Vector3(outward_sign * 0.55, -0.25, 0.0)
	sill.add_child(floor_col)

	var stop_col := CollisionShape3D.new()
	stop_col.name = "SillBackstop"
	var stop_box := BoxShape3D.new()
	stop_box.size = Vector3(door_w + 0.4, 3.2, 0.25) if along_x else Vector3(0.25, 3.2, door_w + 0.4)
	stop_col.shape = stop_box
	stop_col.position = Vector3(0.0, 1.6, outward_sign * 1.25) if along_x else Vector3(outward_sign * 1.25, 1.6, 0.0)
	sill.add_child(stop_col)

	arch_root.add_child(sill)


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
	is_tall_wall: bool,
	panel_glb_path: String = "res://assets/props/wall_stone_panel.glb",
	lintel_glb_path: String = "res://assets/props/wall_stone_lintel.glb",
	arch_glb_path: String = "res://assets/props/arch_stone_doorway.glb",
	full_wall_h: float = 6.0,
	low_wall_glb_path: String = "",
	sill_floor_mat: Material = null,
	high_cutout: Dictionary = {}
) -> void:
	if exit_cfg.is_empty():
		if is_tall_wall:
			_create_static_box(arch_root, "Wall_" + dir_name, Vector3(span_x * 0.5, wall_h * 0.5, z_center), Vector3(span_x, wall_h, t), wall_mat)
			_attach_wall_masonry_span(arch_root, "WallMasonry_" + dir_name, 0.0, span_x, wall_h, 0.02, true, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_" + dir_name, 0.0, span_x, z_center, true, low_wall_glb_path)
			if high_cutout.is_empty():
				var w_body: StaticBody3D = _create_static_box(arch_root, "Wall_" + dir_name, Vector3(span_x * 0.5, wall_h * 0.5, z_center), Vector3(span_x, wall_h, t), wall_mat, full_wall_h)
				_hide_body_proxy_mesh(w_body, low_wall_glb_path)
			else:
				var cut_start: float = float(high_cutout.get("start", 0.0))
				var cut_end: float = float(high_cutout.get("end", 0.0))
				var cut_elev: float = float(high_cutout.get("elev_m", 3.0))
				if cut_start > 0.05:
					var wb_l: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiL" % dir_name, Vector3(cut_start * 0.5, wall_h * 0.5, z_center), Vector3(cut_start, wall_h, t), wall_mat, full_wall_h)
					_hide_body_proxy_mesh(wb_l, low_wall_glb_path)
				var wb_mid: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiMid" % dir_name, Vector3((cut_start + cut_end) * 0.5, wall_h * 0.5, z_center), Vector3(cut_end - cut_start, wall_h, t), wall_mat, cut_elev)
				_hide_body_proxy_mesh(wb_mid, low_wall_glb_path)
				if span_x - cut_end > 0.05:
					var wb_r: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiR" % dir_name, Vector3((cut_end + span_x) * 0.5, wall_h * 0.5, z_center), Vector3(span_x - cut_end, wall_h, t), wall_mat, full_wall_h)
					_hide_body_proxy_mesh(wb_r, low_wall_glb_path)
		return

	var door_pos: Array = exit_cfg.get("door_pos", [0, 0]) as Array
	var door_x: float = float(door_pos[0])
	var door_w: float = float(exit_cfg.get("width", 2))
	var door_h: float = minf(float(exit_cfg.get("height", 3.0)), wall_h)

	if door_x > 0.0:
		var col_h_l: float = -1.0 if is_tall_wall else full_wall_h
		var wl_body: StaticBody3D = _create_static_box(arch_root, "Wall_%s_L" % dir_name, Vector3(door_x * 0.5, wall_h * 0.5, z_center), Vector3(door_x, wall_h, t), wall_mat, col_h_l)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_L" % dir_name, 0.0, door_x, wall_h, 0.02, true, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_%s_L" % dir_name, 0.0, door_x, z_center, true, low_wall_glb_path)
			_hide_body_proxy_mesh(wl_body, low_wall_glb_path)
	var right_start: float = door_x + door_w
	var right_len: float = span_x - right_start
	if right_len > 0.0:
		var col_h_r: float = -1.0 if is_tall_wall else full_wall_h
		var wr_body: StaticBody3D = _create_static_box(arch_root, "Wall_%s_R" % dir_name, Vector3(right_start + right_len * 0.5, wall_h * 0.5, z_center), Vector3(right_len, wall_h, t), wall_mat, col_h_r)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_R" % dir_name, right_start, span_x, wall_h, 0.02, true, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_%s_R" % dir_name, right_start, span_x, z_center, true, low_wall_glb_path)
			_hide_body_proxy_mesh(wr_body, low_wall_glb_path)
	var is_tree_arch: bool = arch_glb_path.contains("tree")
	var arch_z: float = (0.18 if dir_name == "north" else z_center - 0.18) if is_tree_arch else (z_center + 0.12)
	if is_tall_wall and wall_h > door_h:
		var lintel_h: float = wall_h - door_h
		_create_static_box(arch_root, "Wall_%s_Lintel" % dir_name, Vector3(door_x + door_w * 0.5, door_h + lintel_h * 0.5, z_center), Vector3(door_w, lintel_h, t), wall_mat)
		_attach_wall_lintel_masonry(arch_root, "WallLintelMasonry_" + dir_name, door_x, door_x + door_w, door_h, lintel_h, 0.02, true, lintel_glb_path)
		var trim_box: StaticBody3D = _create_static_box(arch_root, "Trim_%s_Top" % dir_name, Vector3(door_x + door_w * 0.5, door_h + 0.1, z_center), Vector3(door_w + 0.3, 0.2, t + 0.12), trim_mat)
		var arch_scene: PackedScene = _load_prop_scene(arch_glb_path)
		if arch_scene != null:
			var arch_inst: Node3D = arch_scene.instantiate() as Node3D
			arch_inst.name = "Arch_" + dir_name
			arch_inst.position = Vector3(door_x + door_w * 0.5, 0.0, arch_z)
			_configure_static_model_recursive(arch_inst)
			arch_root.add_child(arch_inst)
			var trim_mesh: MeshInstance3D = trim_box.get_node_or_null("Mesh") as MeshInstance3D
			if trim_mesh != null:
				trim_mesh.visible = false
	if is_tall_wall and bool(exit_cfg.get("biome_transition", false)):
		_attach_biome_transition_indicator(
			arch_root,
			dir_name,
			Vector3(door_x + door_w * 0.5, 0.0, arch_z),
			door_w,
			bool(exit_cfg.get("target_is_forest", false)),
			false
		)

	var outward_sign: float = -1.0 if dir_name == "north" else 1.0
	var edge_z: float = 0.0 if dir_name == "north" else float(door_pos[1]) + 1.0
	_create_doorway_sill(arch_root, dir_name, Vector3(door_x + door_w * 0.5, 0.0, edge_z), door_w, true, outward_sign, sill_floor_mat, t)

	var spawn := Marker3D.new()
	spawn.name = "Spawn_" + dir_name
	var spawn_z: float = 0.75 if dir_name == "north" else float(door_pos[1]) + 0.25
	spawn.position = Vector3(door_x + door_w * 0.5, 0.0, spawn_z)
	spawn.set_meta("direction", dir_name)
	spawn.set_meta("target_room", exit_cfg.get("target_room", [0, 0]))
	if exit_cfg.has("target_room_id"):
		spawn.set_meta("target_room_id", int(exit_cfg.get("target_room_id", 0)))
	doorways_root.add_child(spawn)

	var exit_area := Area3D.new()
	exit_area.name = "Exit_" + dir_name
	exit_area.collision_layer = 8
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	var exit_z: float = -0.60 if dir_name == "north" else float(door_pos[1]) + 1.60
	exit_area.position = Vector3(door_x + door_w * 0.5, 1.1, exit_z)
	var exit_col := CollisionShape3D.new()
	var exit_box := BoxShape3D.new()
	exit_box.size = Vector3(door_w * 0.9, 2.2, 0.36)
	exit_col.shape = exit_box
	exit_area.add_child(exit_col)
	exit_area.set_meta("direction", dir_name)
	var tr_arr: Array = exit_cfg.get("target_room", [0, 0]) as Array
	exit_area.set_meta("target_room", Vector2i(int(tr_arr[0]), int(tr_arr[1])))
	if exit_cfg.has("target_room_id"):
		exit_area.set_meta("target_room_id", int(exit_cfg.get("target_room_id", 0)))
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
	is_tall_wall: bool,
	panel_glb_path: String = "res://assets/props/wall_stone_panel.glb",
	lintel_glb_path: String = "res://assets/props/wall_stone_lintel.glb",
	arch_glb_path: String = "res://assets/props/arch_stone_doorway.glb",
	full_wall_h: float = 6.0,
	low_wall_glb_path: String = "",
	sill_floor_mat: Material = null,
	high_cutout: Dictionary = {}
) -> void:
	if exit_cfg.is_empty():
		if is_tall_wall:
			_create_static_box(arch_root, "Wall_" + dir_name, Vector3(x_center, wall_h * 0.5, span_z * 0.5), Vector3(t, wall_h, span_z), wall_mat)
			_attach_wall_masonry_span(arch_root, "WallMasonry_" + dir_name, 0.0, span_z, wall_h, 0.02, false, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_" + dir_name, 0.0, span_z, x_center, false, low_wall_glb_path)
			if high_cutout.is_empty():
				var w_body: StaticBody3D = _create_static_box(arch_root, "Wall_" + dir_name, Vector3(x_center, wall_h * 0.5, span_z * 0.5), Vector3(t, wall_h, span_z), wall_mat, full_wall_h)
				_hide_body_proxy_mesh(w_body, low_wall_glb_path)
			else:
				var cut_start: float = float(high_cutout.get("start", 0.0))
				var cut_end: float = float(high_cutout.get("end", 0.0))
				var cut_elev: float = float(high_cutout.get("elev_m", 3.0))
				if cut_start > 0.05:
					var wb_l: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiL" % dir_name, Vector3(x_center, wall_h * 0.5, cut_start * 0.5), Vector3(t, wall_h, cut_start), wall_mat, full_wall_h)
					_hide_body_proxy_mesh(wb_l, low_wall_glb_path)
				var wb_mid: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiMid" % dir_name, Vector3(x_center, wall_h * 0.5, (cut_start + cut_end) * 0.5), Vector3(t, wall_h, cut_end - cut_start), wall_mat, cut_elev)
				_hide_body_proxy_mesh(wb_mid, low_wall_glb_path)
				if span_z - cut_end > 0.05:
					var wb_r: StaticBody3D = _create_static_box(arch_root, "Wall_%s_HiR" % dir_name, Vector3(x_center, wall_h * 0.5, (cut_end + span_z) * 0.5), Vector3(t, wall_h, span_z - cut_end), wall_mat, full_wall_h)
					_hide_body_proxy_mesh(wb_r, low_wall_glb_path)
		return

	var door_pos: Array = exit_cfg.get("door_pos", [0, 0]) as Array
	var door_z: float = float(door_pos[1])
	var door_w: float = float(exit_cfg.get("width", 2))
	var door_h: float = minf(float(exit_cfg.get("height", 3.0)), wall_h)

	if door_z > 0.0:
		var col_h_l: float = -1.0 if is_tall_wall else full_wall_h
		var wl_body: StaticBody3D = _create_static_box(arch_root, "Wall_%s_L" % dir_name, Vector3(x_center, wall_h * 0.5, door_z * 0.5), Vector3(t, wall_h, door_z), wall_mat, col_h_l)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_L" % dir_name, 0.0, door_z, wall_h, 0.02, false, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_%s_L" % dir_name, 0.0, door_z, x_center, false, low_wall_glb_path)
			_hide_body_proxy_mesh(wl_body, low_wall_glb_path)
	var right_start: float = door_z + door_w
	var right_len: float = span_z - right_start
	if right_len > 0.0:
		var col_h_r: float = -1.0 if is_tall_wall else full_wall_h
		var wr_body: StaticBody3D = _create_static_box(arch_root, "Wall_%s_R" % dir_name, Vector3(x_center, wall_h * 0.5, right_start + right_len * 0.5), Vector3(t, wall_h, right_len), wall_mat, col_h_r)
		if is_tall_wall:
			_attach_wall_masonry_span(arch_root, "WallMasonry_%s_R" % dir_name, right_start, span_z, wall_h, 0.02, false, panel_glb_path)
		else:
			_attach_low_wall_span(arch_root, "LowWall_%s_R" % dir_name, right_start, span_z, x_center, false, low_wall_glb_path)
			_hide_body_proxy_mesh(wr_body, low_wall_glb_path)
	var is_tree_arch: bool = arch_glb_path.contains("tree")
	var arch_x: float = (0.18 if dir_name == "west" else x_center - 0.18) if is_tree_arch else (x_center + 0.12)
	if is_tall_wall and wall_h > door_h:
		var lintel_h: float = wall_h - door_h
		_create_static_box(arch_root, "Wall_%s_Lintel" % dir_name, Vector3(x_center, door_h + lintel_h * 0.5, door_z + door_w * 0.5), Vector3(t, lintel_h, door_w), wall_mat)
		_attach_wall_lintel_masonry(arch_root, "WallLintelMasonry_" + dir_name, door_z, door_z + door_w, door_h, lintel_h, 0.02, false, lintel_glb_path)
		var trim_box: StaticBody3D = _create_static_box(arch_root, "Trim_%s_Top" % dir_name, Vector3(x_center, door_h + 0.1, door_z + door_w * 0.5), Vector3(t + 0.12, 0.2, door_w + 0.3), trim_mat)
		var arch_scene: PackedScene = _load_prop_scene(arch_glb_path)
		if arch_scene != null:
			var arch_inst: Node3D = arch_scene.instantiate() as Node3D
			arch_inst.name = "Arch_" + dir_name
			arch_inst.position = Vector3(arch_x, 0.0, door_z + door_w * 0.5)
			arch_inst.rotation_degrees.y = 90.0
			_configure_static_model_recursive(arch_inst)
			arch_root.add_child(arch_inst)
			var trim_mesh: MeshInstance3D = trim_box.get_node_or_null("Mesh") as MeshInstance3D
			if trim_mesh != null:
				trim_mesh.visible = false
	if is_tall_wall and bool(exit_cfg.get("biome_transition", false)):
		_attach_biome_transition_indicator(
			arch_root,
			dir_name,
			Vector3(arch_x, 0.0, door_z + door_w * 0.5),
			door_w,
			bool(exit_cfg.get("target_is_forest", false)),
			false
		)

	var outward_sign: float = -1.0 if dir_name == "west" else 1.0
	var edge_x: float = 0.0 if dir_name == "west" else float(door_pos[0]) + 1.0
	_create_doorway_sill(arch_root, dir_name, Vector3(edge_x, 0.0, door_z + door_w * 0.5), door_w, false, outward_sign, sill_floor_mat, t)

	var spawn := Marker3D.new()
	spawn.name = "Spawn_" + dir_name
	var spawn_x: float = 0.75 if dir_name == "west" else float(door_pos[0]) + 0.25
	spawn.position = Vector3(spawn_x, 0.0, door_z + door_w * 0.5)
	spawn.set_meta("direction", dir_name)
	spawn.set_meta("target_room", exit_cfg.get("target_room", [0, 0]))
	if exit_cfg.has("target_room_id"):
		spawn.set_meta("target_room_id", int(exit_cfg.get("target_room_id", 0)))
	doorways_root.add_child(spawn)

	var exit_area := Area3D.new()
	exit_area.name = "Exit_" + dir_name
	exit_area.collision_layer = 8
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	var exit_x: float = -0.60 if dir_name == "west" else float(door_pos[0]) + 1.60
	exit_area.position = Vector3(exit_x, 1.1, door_z + door_w * 0.5)
	var exit_col := CollisionShape3D.new()
	var exit_box := BoxShape3D.new()
	exit_box.size = Vector3(0.36, 2.2, door_w * 0.9)
	exit_col.shape = exit_box
	exit_area.add_child(exit_col)
	exit_area.set_meta("direction", dir_name)
	var tr_arr: Array = exit_cfg.get("target_room", [0, 0]) as Array
	exit_area.set_meta("target_room", Vector2i(int(tr_arr[0]), int(tr_arr[1])))
	if exit_cfg.has("target_room_id"):
		exit_area.set_meta("target_room_id", int(exit_cfg.get("target_room_id", 0)))
	doorways_root.add_child(exit_area)


func _create_static_box(
	parent: Node3D,
	node_name: String,
	center_pos: Vector3,
	size: Vector3,
	material: Material,
	collision_h: float = -1.0
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
	var effective_h: float = collision_h if collision_h > size.y else size.y
	shape.size = Vector3(size.x, effective_h, size.z)
	col.shape = shape
	if effective_h > size.y:
		col.position = Vector3(0.0, (effective_h - size.y) * 0.5, 0.0)

	body.add_child(mesh_inst)
	body.add_child(col)
	parent.add_child(body)
	return body


static func _vec3_from_array(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func _get_tinted_material(mat_name: String, tag: String, tint: Color) -> StandardMaterial3D:
	_ensure_catalogs()
	if tag.is_empty() and tint.is_equal_approx(Color.WHITE):
		return get_material(mat_name)
	var key: String = "%s__%s" % [mat_name, tag]
	if _material_resources.has(key):
		return _material_resources[key] as StandardMaterial3D
	var dup: StandardMaterial3D = get_material(mat_name).duplicate() as StandardMaterial3D
	dup.albedo_color = Color(
		clampf(dup.albedo_color.r * tint.r, 0.0, 1.0),
		clampf(dup.albedo_color.g * tint.g, 0.0, 1.0),
		clampf(dup.albedo_color.b * tint.b, 0.0, 1.0),
		dup.albedo_color.a
	)
	_material_resources[key] = dup
	return dup


func _tint_static_model_recursive(node: Node, tag: String, tint: Color) -> void:
	if tag.is_empty() and tint.is_equal_approx(Color.WHITE):
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			for s_idx: int in range(mi.mesh.get_surface_count()):
				var base_mat: Material = mi.get_active_material(s_idx)
				if base_mat is StandardMaterial3D:
					var cache_key: String = "%d__%s" % [base_mat.get_instance_id(), tag]
					var tinted_mat: StandardMaterial3D = _tinted_model_materials.get(cache_key) as StandardMaterial3D
					if tinted_mat == null:
						tinted_mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						tinted_mat.albedo_color = Color(
							clampf(tinted_mat.albedo_color.r * tint.r, 0.0, 1.0),
							clampf(tinted_mat.albedo_color.g * tint.g, 0.0, 1.0),
							clampf(tinted_mat.albedo_color.b * tint.b, 0.0, 1.0),
							tinted_mat.albedo_color.a
						)
						_tinted_model_materials[cache_key] = tinted_mat
					mi.set_surface_override_material(s_idx, tinted_mat)
	for child: Node in node.get_children():
		_tint_static_model_recursive(child, tag, tint)


func _tint_direct_children(parent_node: Node, start_idx: int, tag: String, tint: Color) -> void:
	var children: Array[Node] = parent_node.get_children()
	for i: int in range(start_idx, children.size()):
		_tint_static_model_recursive(children[i], tag, tint)


func build_knight_lore_room(
	parent: Node3D,
	room_id: int,
	kl_data: KnightLoreData,
	lighting_override: String = "",
	camera_mode_override: String = "",
	skip_special_previews: bool = false
) -> Dictionary:
	_ensure_catalogs()
	var room: Dictionary = kl_data.get_room(room_id)
	if room.is_empty():
		push_error("RoomBuilder: Unknown Knight Lore room_id %d" % room_id)
		return {}

	var room_dims: Vector3 = kl_data.get_room_dims_meters(room_id)
	var width_m: float = room_dims.x
	var depth_m: float = room_dims.z
	var height_m: float = room_dims.y
	var half_x: float = float(room.get("half_x", 64))
	var half_y: float = float(room.get("half_y", 64))
	var floor_z: float = float(room.get("floor_z", 128))
	var ink_name: String = str(room.get("ink_color_name", "Yellow"))
	var is_forest: bool = kl_data.is_forest_room(room_id)
	var ink_tint: Color = KnightLoreData.get_subtle_room_tint(ink_name)
	var wall_tint: Color = ink_tint
	var backdrop_tint: Color = ink_tint
	var wall_tag: String = ink_name
	var floor_tint: Color = ink_tint
	if is_forest:
		wall_tag = "forest_" + ink_name
		if ink_name == "Yellow":
			backdrop_tint = Color(0.42, 0.38, 0.20, 1.0)  # Autumn amber / golden canopy
			floor_tint = Color(0.82, 0.82, 0.58, 1.0)     # Golden-dappled moss
		elif ink_name == "Magenta":
			backdrop_tint = Color(0.34, 0.24, 0.36, 1.0)  # Eldritch twilight violet / magenta
			floor_tint = Color(0.72, 0.64, 0.76, 1.0)     # Twilight purple-dappled moss
		else:
			backdrop_tint = Color(0.32, 0.44, 0.26, 1.0)
			floor_tint = Color(0.76, 0.86, 0.70, 1.0)
	var exits_meta: Dictionary = kl_data.get_room_exits(room_id)
	var panel_glb: String = "res://assets/props/tree_wall_panel.glb" if is_forest else "res://assets/props/wall_stone_panel.glb"
	var lintel_glb: String = "res://assets/props/tree_wall_lintel.glb" if is_forest else "res://assets/props/wall_stone_lintel.glb"
	var arch_glb: String = "res://assets/props/arch_tree_doorway.glb" if is_forest else "res://assets/props/arch_stone_doorway.glb"

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

	# 1. Organic Forest Floor or Weathered Dungeon Flagstones + Merged FloorCollision (Option 2A subtle room tint)
	var sill_floor_mat: Material = null
	if is_forest:
		sill_floor_mat = _build_kl_forest_floor(arch_root, int(roundf(width_m)), int(roundf(depth_m)), 0.5, floor_tint)
	else:
		var dung_mat: ShaderMaterial = _get_dungeon_floor_material(floor_tint)
		_build_kl_floor(arch_root, int(roundf(width_m)), int(roundf(depth_m)), 0.5, dung_mat)
		sill_floor_mat = dung_mat

	# 2. Perimeter Walls, Corner Caps & Doorways
	var t: float = 0.5
	var curb_h: float = 0.4
	var wall_mat: StandardMaterial3D = _get_tinted_material("stone_wall", wall_tag + "_wall", backdrop_tint)
	var curb_tint: Color = Color(0.76, 0.72, 0.58, 1.0) if is_forest else backdrop_tint
	var curb_mat: StandardMaterial3D = _get_tinted_material("doorway_trim" if is_forest else "foreground_curb", wall_tag + "_curb", curb_tint)
	var trim_mat: StandardMaterial3D = get_material("doorway_trim")
	var low_wall_glb: String = "res://assets/props/low_wall_woodland.glb" if is_forest else "res://assets/props/low_wall_stone.glb"

	_create_static_box(arch_root, "Corner_NW", Vector3(-t * 0.5, height_m * 0.5, -t * 0.5), Vector3(t, height_m, t), wall_mat)
	var kl_ne: StaticBody3D = _create_static_box(arch_root, "Corner_NE", Vector3(width_m + t * 0.5, curb_h * 0.5, -t * 0.5), Vector3(t, curb_h, t), curb_mat, height_m)
	_attach_low_corner_cap(kl_ne, low_wall_glb, t, curb_h)
	var kl_sw: StaticBody3D = _create_static_box(arch_root, "Corner_SW", Vector3(-t * 0.5, curb_h * 0.5, depth_m + t * 0.5), Vector3(t, curb_h, t), curb_mat, height_m)
	_attach_low_corner_cap(kl_sw, low_wall_glb, t, curb_h)
	var kl_se: StaticBody3D = _create_static_box(arch_root, "Corner_SE", Vector3(width_m + t * 0.5, curb_h * 0.5, depth_m + t * 0.5), Vector3(t, curb_h, t), curb_mat, height_m)
	_attach_low_corner_cap(kl_se, low_wall_glb, t, curb_h)

	var south_high_cutout: Dictionary = {}
	var east_high_cutout: Dictionary = {}
	var perimeter_exits: Dictionary = {}
	for dir_name: String in ["north", "west", "south", "east"]:
		if not exits_meta.has(dir_name):
			continue
		var ex: Dictionary = exits_meta[dir_name] as Dictionary
		var is_high: bool = bool(ex.get("high", false))
		if is_high and (dir_name == "south" or dir_name == "east"):
			var cut_center: float = (width_m * 0.5) if dir_name == "south" else (depth_m * 0.5)
			var cut_cfg: Dictionary = {"start": cut_center - 1.0, "end": cut_center + 1.0, "elev_m": float(ex.get("elevation_m", 3.0))}
			if dir_name == "south":
				south_high_cutout = cut_cfg
			else:
				east_high_cutout = cut_cfg
			continue
		var target_rid: int = int(ex.get("target_room_id", room_id))
		var dpos: Array = [0, 0]
		match dir_name:
			"north":
				dpos = [width_m * 0.5 - 1.0, 0.0]
			"south":
				dpos = [width_m * 0.5 - 1.0, depth_m - 1.0]
			"west":
				dpos = [0.0, depth_m * 0.5 - 1.0]
			"east":
				dpos = [width_m - 1.0, depth_m * 0.5 - 1.0]
		perimeter_exits[dir_name] = {
			"door_pos": dpos,
			"width": 2.0,
			"height": 3.0,
			"target_room_id": target_rid,
			"target_room": [target_rid & 0x0F, (target_rid >> 4) & 0x0F],
			"target_is_forest": bool(ex.get("target_is_forest", is_forest)),
			"biome_transition": bool(ex.get("biome_transition", false))
		}

	var pre_walls_count: int = arch_root.get_child_count()
	_build_wall_along_x(arch_root, doorways_root, "north", -t * 0.5, width_m, height_m, t, perimeter_exits.get("north", {}) as Dictionary, wall_mat, trim_mat, true, panel_glb, lintel_glb, arch_glb, height_m, "", sill_floor_mat)
	_build_wall_along_z(arch_root, doorways_root, "west", -t * 0.5, depth_m, height_m, t, perimeter_exits.get("west", {}) as Dictionary, wall_mat, trim_mat, true, panel_glb, lintel_glb, arch_glb, height_m, "", sill_floor_mat)
	_build_wall_along_x(arch_root, doorways_root, "south", depth_m + t * 0.5, width_m, curb_h, t, perimeter_exits.get("south", {}) as Dictionary, curb_mat, trim_mat, false, panel_glb, lintel_glb, arch_glb, height_m, low_wall_glb, sill_floor_mat, south_high_cutout)
	_build_wall_along_z(arch_root, doorways_root, "east", width_m + t * 0.5, depth_m, curb_h, t, perimeter_exits.get("east", {}) as Dictionary, curb_mat, trim_mat, false, panel_glb, lintel_glb, arch_glb, height_m, low_wall_glb, sill_floor_mat, east_high_cutout)
	_tint_direct_children(arch_root, pre_walls_count, wall_tag, wall_tint)

	# 3. Elevated High Arches, Foreground Cutaway Arches, Portcullis Gates, Cauldron & Wizard
	_build_kl_background_features(arch_root, fg_root, doorways_root, kl_data, room, exits_meta, half_x, half_y, floor_z, wall_tag, backdrop_tint, ink_tint, is_forest, sill_floor_mat)

	# 4. Foreground Room Obstacles, Pushables, Enemies, Hazards & Collectible Previews
	_build_kl_foreground_objects(arch_root, entities_root, room, kl_data.entities_cfg, half_x, half_y, floor_z, ink_name, ink_tint)
	if not skip_special_previews:
		_build_kl_special_spawn_previews(entities_root, kl_data, room_id, half_x, half_y, floor_z)

	# 5. Orthographic Camera & PBR Lighting
	var cam_cfg_mode: String = camera_mode_override if not camera_mode_override.is_empty() else "true_isometric"
	var camera_rig := DioramaCameraRig.new()
	camera_rig.name = "DioramaCameraRig"
	parent.add_child(camera_rig)
	camera_rig.configure_for_room(room_dims, DioramaCameraRig.mode_from_string(cam_cfg_mode), 0.12)

	var preset_name: String = lighting_override if not lighting_override.is_empty() else "castle_stone_skylight"
	var preset: Dictionary = DioramaLighting.load_preset_by_name(preset_name)
	var lighting := DioramaLighting.new()
	lighting.name = "DioramaLighting"
	parent.add_child(lighting)
	lighting.apply_preset(preset, room_dims)
	var gi_path: String = DioramaLighting.get_knight_lore_gi_path(room_id)
	lighting.apply_prebaked_gi(gi_path)

	return {
		"room_id": room_id,
		"room_dims": room_dims,
		"is_forest": is_forest,
		"ink_color": ink_name,
		"exits": exits_meta,
		"camera_rig": camera_rig,
		"lighting": lighting,
		"voxel_gi_path": gi_path,
		"architecture_root": arch_root,
		"foreground_root": fg_root,
		"doorways_root": doorways_root,
		"entities_root": entities_root
	}


func _build_kl_floor(
	arch_root: Node3D,
	width: int,
	depth: int,
	thickness: float,
	mat_floor: Material
) -> void:
	var floor_group := Node3D.new()
	floor_group.name = "FloorTiles"
	arch_root.add_child(floor_group)

	for x: int in range(width):
		for z: int in range(depth):
			var tile_node := Node3D.new()
			tile_node.name = "Tile_%02d_%02d" % [x, z]
			tile_node.position = Vector3(float(x) + 0.5, -thickness * 0.5, float(z) + 0.5)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.name = "Mesh"
			mesh_inst.layers = 1
			mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1.0, thickness, 1.0)
			box_mesh.material = mat_floor
			mesh_inst.mesh = box_mesh
			tile_node.add_child(mesh_inst)
			floor_group.add_child(tile_node)

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(float(width), thickness, float(depth))
	col_shape.shape = col_box
	col_shape.position = Vector3(float(width) * 0.5, -thickness * 0.5, float(depth) * 0.5)
	floor_body.add_child(col_shape)
	arch_root.add_child(floor_body)


func _get_dungeon_floor_material(tint: Color) -> ShaderMaterial:
	var key: String = "%.2f_%.2f_%.2f" % [tint.r, tint.g, tint.b]
	if _dungeon_floor_materials.has(key):
		return _dungeon_floor_materials[key] as ShaderMaterial
	if _dungeon_floor_shader == null:
		_dungeon_floor_shader = load("res://core/shaders/dungeon_floor.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _dungeon_floor_shader
	mat.set_shader_parameter("room_tint", tint)
	_dungeon_floor_materials[key] = mat
	return mat


func _get_forest_floor_material(tint: Color) -> ShaderMaterial:
	var key: String = "%.2f_%.2f_%.2f" % [tint.r, tint.g, tint.b]
	if _forest_floor_materials.has(key):
		return _forest_floor_materials[key] as ShaderMaterial
	if _forest_floor_shader == null:
		_forest_floor_shader = load("res://core/shaders/forest_floor.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _forest_floor_shader
	mat.set_shader_parameter("room_tint", tint)
	_forest_floor_materials[key] = mat
	return mat


func _build_kl_forest_floor(
	arch_root: Node3D,
	width: int,
	depth: int,
	thickness: float,
	tint: Color
) -> ShaderMaterial:
	var forest_mat: ShaderMaterial = _get_forest_floor_material(tint)
	var floor_mesh_node := MeshInstance3D.new()
	floor_mesh_node.name = "ForestFloorMesh"
	floor_mesh_node.layers = 1
	floor_mesh_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	floor_mesh_node.position = Vector3(float(width) * 0.5, -thickness * 0.5, float(depth) * 0.5)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(float(width), thickness, float(depth))
	box_mesh.material = forest_mat
	floor_mesh_node.mesh = box_mesh
	arch_root.add_child(floor_mesh_node)

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(float(width), thickness, float(depth))
	col_shape.shape = col_box
	col_shape.position = Vector3(float(width) * 0.5, -thickness * 0.5, float(depth) * 0.5)
	floor_body.add_child(col_shape)
	arch_root.add_child(floor_body)
	return forest_mat


func _attach_biome_transition_indicator(
	host_root: Node3D,
	dir_name: String,
	origin_pos: Vector3,
	_door_w: float,
	to_forest: bool,
	_is_cutaway_local: bool = false
) -> void:
	var glb_path: String = "res://assets/props/door_trim_to_forest.glb" if to_forest else "res://assets/props/door_trim_to_stone.glb"
	var trim_scene: PackedScene = _load_prop_scene(glb_path)
	if trim_scene == null:
		return
	var root := Node3D.new()
	root.name = "BiomeTransition_" + dir_name
	root.position = origin_pos
	if dir_name == "east" or dir_name == "west":
		root.rotation_degrees.y = 90.0
	var trim_inst: Node3D = trim_scene.instantiate() as Node3D
	trim_inst.name = "TransitionTrimModel"
	_configure_static_model_recursive(trim_inst)
	root.add_child(trim_inst)
	host_root.add_child(root)


func _apply_cutaway_materials_recursive(node: Node, fallback_mat_name: String) -> void:
	if node.name == "ShadowCaster":
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.name == "Mesh" and mi.mesh is BoxMesh:
			var bm: BoxMesh = mi.mesh as BoxMesh
			bm.material = _create_cutaway_material(fallback_mat_name)
		elif mi.mesh != null:
			mi.material_override = null
			for s_idx: int in range(mi.mesh.get_surface_count()):
				var active_mat: Material = mi.get_active_material(s_idx)
				var cut_mat: ShaderMaterial = (
					_create_cutaway_material_from_standard(active_mat as StandardMaterial3D)
					if (active_mat is StandardMaterial3D)
					else _create_cutaway_material(fallback_mat_name)
				)
				mi.set_surface_override_material(s_idx, cut_mat)
		mi.set_instance_shader_parameter(&"cutaway_active", 0.0)
	for child: Node in node.get_children():
		_apply_cutaway_materials_recursive(child, fallback_mat_name)


func _enable_cutaway_on_body(body: Node3D, fallback_mat_name: String) -> void:
	_attach_cutaway_shadow_caster(body, get_material(fallback_mat_name))
	_apply_cutaway_materials_recursive(body, fallback_mat_name)
	if not body.is_in_group("foreground_occluders"):
		body.add_to_group("foreground_occluders")
	body.set_meta("cutaway", true)
	body.set_meta("cutaway_active", false)


func _build_kl_background_features(
	arch_root: Node3D,
	fg_root: Node3D,
	doorways_root: Node3D,
	kl_data: KnightLoreData,
	room: Dictionary,
	exits_meta: Dictionary,
	half_x: float,
	half_y: float,
	floor_z: float,
	wall_tag: String,
	wall_tint: Color,
	ink_tint: Color,
	is_forest: bool = false,
	sill_floor_mat: Material = null
) -> void:
	var width_m: float = (half_x * 2.0) / KnightLoreData.UNITS_PER_METER
	var depth_m: float = (half_y * 2.0) / KnightLoreData.UNITS_PER_METER

	# Foreground SE/SW cutaway arches & elevated high_arch markers
	for dir_name: String in ["south", "east"]:
		if not exits_meta.has(dir_name):
			continue
		var ex: Dictionary = exits_meta[dir_name] as Dictionary
		var is_high: bool = bool(ex.get("high", false))
		var is_tree_arch: bool = is_forest or bool(ex.get("tree", false))
		var elev_m: float = float(ex.get("elevation_m", 0.0))
		var target_rid: int = int(ex.get("target_room_id", 0))

		var arch_pos: Vector3 = Vector3(width_m * 0.5, elev_m, depth_m + 0.14) if dir_name == "south" else Vector3(width_m + 0.14, elev_m, depth_m * 0.5)
		var proxy_size: Vector3 = Vector3(2.2, 3.2, 0.55) if dir_name == "south" else Vector3(0.55, 3.2, 2.2)
		var mat_key: String = "tree_arch" if is_tree_arch else "stone_wall"
		var cutaway_mat: ShaderMaterial = _create_cutaway_material(mat_key)
		var arch_occ: StaticBody3D = _create_static_box(fg_root, "Foreground_Arch_" + dir_name, arch_pos + Vector3(0.0, proxy_size.y * 0.5, 0.0), proxy_size, cutaway_mat)
		var arch_col: CollisionShape3D = arch_occ.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if arch_col != null:
			arch_col.disabled = true

		var arch_glb_path: String = "res://assets/props/arch_tree_doorway.glb" if is_tree_arch else "res://assets/props/arch_stone_doorway.glb"
		var arch_scene: PackedScene = _load_prop_scene(arch_glb_path)
		if arch_scene != null:
			var arch_inst: Node3D = arch_scene.instantiate() as Node3D
			arch_inst.name = "ArchModel"
			arch_inst.position = Vector3(0.0, -proxy_size.y * 0.5, 0.0)
			if dir_name == "east":
				arch_inst.rotation_degrees.y = 90.0
			_configure_static_model_recursive(arch_inst)
			arch_occ.add_child(arch_inst)
			var proxy_mesh: MeshInstance3D = arch_occ.get_node_or_null("Mesh") as MeshInstance3D
			if proxy_mesh != null:
				proxy_mesh.visible = false
		if bool(ex.get("biome_transition", false)):
			var to_forest_fg: bool = bool(ex.get("target_is_forest", is_forest))
			_attach_biome_transition_indicator(arch_occ, dir_name, Vector3(0.0, -proxy_size.y * 0.5, 0.0), 2.0, to_forest_fg, true)
		_enable_cutaway_on_body(arch_occ, mat_key)

		if is_high:
			var high_edge_pos: Vector3 = Vector3(width_m * 0.5, elev_m, depth_m) if dir_name == "south" else Vector3(width_m, elev_m, depth_m * 0.5)
			_create_doorway_sill(arch_root, "high_" + dir_name, high_edge_pos, 2.0, dir_name == "south", 1.0, sill_floor_mat, 0.5)

			var spawn := Marker3D.new()
			spawn.name = "Spawn_" + dir_name
			spawn.position = Vector3(width_m * 0.5, elev_m, depth_m - 0.65) if dir_name == "south" else Vector3(width_m - 0.65, elev_m, depth_m * 0.5)
			spawn.set_meta("direction", dir_name)
			spawn.set_meta("target_room_id", target_rid)
			spawn.set_meta("elevation_m", elev_m)
			doorways_root.add_child(spawn)

			var exit_area := Area3D.new()
			exit_area.name = "Exit_" + dir_name
			exit_area.collision_layer = 8
			exit_area.collision_mask = 2
			exit_area.monitoring = true
			exit_area.position = (Vector3(width_m * 0.5, elev_m + 1.1, depth_m + 0.60) if dir_name == "south" else Vector3(width_m + 0.60, elev_m + 1.1, depth_m * 0.5))
			var exit_col := CollisionShape3D.new()
			var exit_box := BoxShape3D.new()
			exit_box.size = Vector3(1.8, 2.2, 0.36) if dir_name == "south" else Vector3(0.36, 2.2, 1.8)
			exit_col.shape = exit_box
			exit_area.add_child(exit_col)
			exit_area.set_meta("direction", dir_name)
			exit_area.set_meta("target_room_id", target_rid)
			exit_area.set_meta("elevation_m", elev_m)
			doorways_root.add_child(exit_area)

	# Render special templates: high_arch_*_base, gate_*, cauldron, wizard
	var bg_ids: Array = room.get("background_ids", []) as Array
	var bg_names: Array = room.get("background_names", []) as Array
	for idx: int in range(bg_ids.size()):
		var bg_id: int = int(bg_ids[idx])
		var bg_name: String = str(bg_names[idx]) if idx < bg_names.size() else ""
		var objs: Array = kl_data.get_background_objects(bg_id)
		if bg_name == "high_arch_e_base" or bg_name == "high_arch_s_base":
			for o_idx: int in range(objs.size()):
				var obj: Dictionary = objs[o_idx] as Dictionary
				var pos: Vector3 = KnightLoreData.kl_to_room_pos(float(obj.get("x", 128)), float(obj.get("y", 128)), float(obj.get("z", 164)), half_x, half_y, floor_z)
				var sz: Vector3 = KnightLoreData.kl_size_to_meters(float(obj.get("w", 8)), float(obj.get("d", 8)), float(obj.get("h", 12)))
				var mat: StandardMaterial3D = _get_tinted_material("stone_ledge", wall_tag + "_ledge", ink_tint)
				var ledge: StaticBody3D = _create_static_box(arch_root, "HighArchBase_%s_%d" % [bg_name, o_idx], pos + Vector3(0.0, sz.y * 0.5, 0.0), sz, mat)
				_spawn_glb_visual_on_node(ledge, "res://assets/props/stone_block.glb", sz, Vector3(1.0, 1.0, 1.0), Vector3(0.0, -sz.y * 0.5, 0.0), 0.0, wall_tag, ink_tint)
				if (pos.y + sz.y) > HERO_CUTAWAY_HEIGHT_M:
					_enable_cutaway_on_body(ledge, "stone_ledge")

				# Create solid foundation masonry from the floor (y=0) up to the arch base ledge (y=pos.y)
				# to prevent pushable chests/blocks from falling into empty floor voids beneath high archways
				if pos.y > 0.1:
					var found_sz := Vector3(sz.x, pos.y, sz.z)
					var found_pos := Vector3(pos.x, pos.y * 0.5, pos.z)
					var foundation: StaticBody3D = _create_static_box(arch_root, "HighArchFoundation_%s_%d" % [bg_name, o_idx], found_pos, found_sz, mat)
					_spawn_glb_visual_on_node(foundation, "res://assets/props/stone_pillar.glb", found_sz, Vector3(found_sz.x, found_sz.y, found_sz.z), Vector3(0.0, -found_pos.y, 0.0), 0.0, wall_tag, ink_tint)
					if (pos.y) > HERO_CUTAWAY_HEIGHT_M:
						_enable_cutaway_on_body(foundation, "stone_ledge")
		elif bg_name.begins_with("gate_"):
			var bg_fg_types: Dictionary = kl_data.entities_cfg.get("foreground_types", {}) as Dictionary
			var gate_tid: String = "27" if (bg_name == "gate_e" or bg_name == "gate_w") else "26"
			var gate_cfg: Dictionary = bg_fg_types.get(gate_tid, {"behavior": "portcullis"}) as Dictionary
			for o_idx: int in range(objs.size()):
				var obj: Dictionary = objs[o_idx] as Dictionary
				var pos: Vector3 = KnightLoreData.kl_to_room_pos(float(obj.get("x", 128)), float(obj.get("y", 128)), float(obj.get("z", 160)), half_x, half_y, floor_z)
				var sz: Vector3 = KnightLoreData.kl_size_to_meters(float(obj.get("w", 12)), float(obj.get("d", 1)), float(obj.get("h", 32)))
				var gate_body := KlPortcullisGate.new()
				gate_body.name = "BG_Gate_%s_%d" % [bg_name, o_idx]
				gate_body.configure(bg_name, gate_cfg, sz, pos)
				arch_root.add_child(gate_body)
				var rot_y: float = 90.0 if (bg_name == "gate_e" or bg_name == "gate_w") else 0.0
				_spawn_glb_visual_on_node(gate_body, "res://assets/props/portcullis_gate.glb", sz, Vector3(1.9, 2.6, 0.24), Vector3.ZERO, rot_y, "", Color.WHITE)
				if (pos.y + sz.y) > HERO_CUTAWAY_HEIGHT_M:
					_enable_cutaway_on_body(gate_body, "iron_portcullis")
		elif bg_name == "cauldron":
			var pos: Vector3 = KnightLoreData.kl_to_room_pos(128.0, 128.0, 128.0, half_x, half_y, floor_z)
			var sz := Vector3(1.25, 1.15, 1.25)
			var caul_body: StaticBody3D = _create_static_box(arch_root, "CauldronHub", pos + Vector3(0.0, sz.y * 0.5, 0.0), sz, get_material("cauldron_glow"))
			_spawn_glb_visual_on_node(caul_body, "res://assets/props/cauldron.glb", sz, Vector3(0.95, 0.95, 0.95), Vector3(0.0, -sz.y * 0.5, 0.0), 0.0, "", Color.WHITE)
		elif bg_name == "wizard" and objs.size() > 0:
			var wobj: Dictionary = objs[0] as Dictionary
			var wpos: Vector3 = KnightLoreData.kl_to_room_pos(float(wobj.get("x", 152)), float(wobj.get("y", 104)), float(wobj.get("z", 128)), half_x, half_y, floor_z)
			var wsz: Vector3 = KnightLoreData.kl_size_to_meters(float(wobj.get("w", 5)), float(wobj.get("d", 5)), float(wobj.get("h", 24)))
			_spawn_melkhior_wizard(arch_root, wpos, wsz, kl_data.entities_cfg)


func _build_kl_foreground_objects(
	arch_root: Node3D,
	entities_root: Node3D,
	room: Dictionary,
	entities_cfg: Dictionary,
	half_x: float,
	half_y: float,
	floor_z: float,
	ink_name: String,
	ink_tint: Color
) -> void:
	var fgs: Array = room.get("foregrounds", []) as Array
	var fg_types: Dictionary = entities_cfg.get("foreground_types", {}) as Dictionary
	var count: int = fgs.size()
	var fg_pos: Array[Vector3] = []
	var fg_sz: Array[Vector3] = []
	var fg_valid: Array[bool] = []
	fg_pos.resize(count)
	fg_sz.resize(count)
	fg_valid.resize(count)

	for idx: int in range(count):
		var fg: Dictionary = fgs[idx] as Dictionary
		if int(fg.get("h", 0)) <= 0 or bool(fg.get("ignore_3d", false)):
			fg_valid[idx] = false
			continue
		fg_valid[idx] = true
		fg_pos[idx] = KnightLoreData.kl_to_room_pos(float(fg.get("x", 128)), float(fg.get("y", 128)), float(fg.get("z", 128)), half_x, half_y, floor_z)
		fg_sz[idx] = KnightLoreData.kl_size_to_meters(float(fg.get("w", 8)), float(fg.get("d", 8)), float(fg.get("h", 12)))

	for idx: int in range(count):
		if not fg_valid[idx]:
			continue
		var fg: Dictionary = fgs[idx] as Dictionary
		var type_id_str: String = str(int(fg.get("type_id", 0)))
		var type_cfg: Dictionary = fg_types.get(type_id_str, {}) as Dictionary
		var type_name: String = str(fg.get("type_name", type_cfg.get("name", "block")))
		var behavior: String = str(type_cfg.get("behavior", ""))
		var pos: Vector3 = fg_pos[idx]
		var sz: Vector3 = fg_sz[idx]
		var node_name: String = "FG_%02d_%s" % [idx, type_name]

		var col_top_y: float = pos.y + sz.y
		for j: int in range(count):
			if not fg_valid[j]:
				continue
			var other_p: Vector3 = fg_pos[j]
			if absf(other_p.x - pos.x) <= 0.45 and absf(other_p.z - pos.z) <= 0.45:
				col_top_y = maxf(col_top_y, other_p.y + fg_sz[j].y)

		var created_body: Node3D = null
		var fallback_mat: String = "stone_ledge"
		match behavior:
			"static_solid":
				if type_name == "rock":
					var rock_mat: StandardMaterial3D = _get_tinted_material("stone_pillar", "rock", Color(0.75, 0.72, 0.70))
					created_body = _create_static_box(arch_root, node_name, pos + Vector3(0.0, sz.y * 0.5, 0.0), sz, rock_mat)
					_spawn_glb_visual_on_node(created_body, "res://assets/props/rock_obstacle.glb", sz, Vector3(0.9, 0.75, 0.9), Vector3(0.0, -sz.y * 0.5, 0.0), 25.0, "", Color.WHITE)
					fallback_mat = "stone_pillar"
				else:
					var mat_blk: StandardMaterial3D = _get_tinted_material("stone_ledge", ink_name + "_blk", ink_tint)
					created_body = _create_static_box(arch_root, node_name, pos + Vector3(0.0, sz.y * 0.5, 0.0), sz, mat_blk)
					created_body.set_meta("kl_victory_block", true)
					_spawn_glb_visual_on_node(created_body, "res://assets/props/stone_block.glb", sz, Vector3(1.0, 1.0, 1.0), Vector3(0.0, -sz.y * 0.5, 0.0), 0.0, ink_name, ink_tint)
					fallback_mat = "stone_ledge"
			"static_deadly", "static_fire_unused":
				created_body = _spawn_kl_hazard_prop(entities_root, node_name, type_name, pos, sz)
				fallback_mat = "hazard_crimson"
			"pushable_sliding", "pushable_stop":
				var push_ent := KlPushableEntity.new()
				push_ent.name = node_name
				push_ent.configure(type_name, type_cfg, sz, pos)
				entities_root.add_child(push_ent)
				var push_vis: Dictionary = _get_kl_entity_visual_spec(type_name)
				_spawn_glb_visual_on_node(
					push_ent,
					str(push_vis["glb"]),
					sz,
					push_vis["dims"] as Vector3,
					Vector3.ZERO,
					0.0,
					str(push_vis["tint_tag"]),
					push_vis["tint"] as Color
				)
				created_body = push_ent
				fallback_mat = "oak_chest" if type_name != "moveable_block" else "platform_stone"
			"moving_platform_ew", "moving_platform_ns", "dropping_block", "collapsing_block":
				var dyn_blk := KlDynamicBlock.new()
				dyn_blk.name = node_name
				dyn_blk.configure(type_name, type_cfg, sz, pos, idx)
				entities_root.add_child(dyn_blk)
				var dyn_vis: Dictionary = _get_kl_entity_visual_spec(type_name)
				_spawn_glb_visual_on_node(
					dyn_blk,
					str(dyn_vis["glb"]),
					sz,
					dyn_vis["dims"] as Vector3,
					Vector3.ZERO,
					0.0,
					str(dyn_vis["tint_tag"]),
					dyn_vis["tint"] as Color
				)
				created_body = dyn_blk
				fallback_mat = "cracked_tile" if behavior == "collapsing_block" else "platform_stone"
			"portcullis":
				var gate_ent := KlPortcullisGate.new()
				gate_ent.name = node_name
				gate_ent.configure(type_name, type_cfg, sz, pos)
				entities_root.add_child(gate_ent)
				var g_rot: float = 90.0 if type_name == "gate_ud_2" else 0.0
				_spawn_glb_visual_on_node(gate_ent, "res://assets/props/portcullis_gate.glb", sz, Vector3(1.9, 2.6, 0.24), Vector3.ZERO, g_rot, "", Color.WHITE)
				created_body = gate_ent
				fallback_mat = "iron_portcullis"
			"falling_spike_ball", "patrol_ew", "patrol_ns", "patrol_square_cw", "vertical_bouncer", "bouncing_ball_ai", "random_diagonal", "chase_player":
				var haz_ent := KlHazardEntity.new()
				haz_ent.name = node_name
				haz_ent.configure(type_name, type_cfg, sz, pos)
				entities_root.add_child(haz_ent)
				var haz_vis: Dictionary = _get_kl_entity_visual_spec(type_name)
				_spawn_glb_visual_on_node(
					haz_ent,
					str(haz_vis["glb"]),
					sz,
					haz_vis["dims"] as Vector3,
					Vector3.ZERO,
					0.0,
					str(haz_vis["tint_tag"]),
					haz_vis["tint"] as Color
				)
				haz_ent.attach_visual_support()
				if type_name == "guard_ew" or type_name == "guard_square":
					var guard_vis: Node = haz_ent.get_node_or_null("ModelVisual")
					if guard_vis != null:
						haz_ent.set_animation_player(HumanoidAnimationLibrary.attach_to_character(guard_vis))
				created_body = haz_ent
				fallback_mat = "hazard_crimson"
			_:
				created_body = _create_static_box(entities_root, node_name, pos + Vector3(0.0, sz.y * 0.5, 0.0), sz, get_material("stone_ledge"))
				fallback_mat = "stone_ledge"

		if created_body != null and col_top_y > HERO_CUTAWAY_HEIGHT_M:
			_enable_cutaway_on_body(created_body, fallback_mat)


static func _get_kl_entity_visual_spec(type_name: String) -> Dictionary:
	match type_name:
		"chest":
			return {"glb": "res://assets/props/pushable_chest.glb", "dims": Vector3(0.98, 1.0, 0.98), "tint_tag": "", "tint": Color.WHITE}
		"table":
			return {"glb": "res://assets/props/pushable_table.glb", "dims": Vector3(0.95, 0.75, 0.95), "tint_tag": "", "tint": Color.WHITE}
		"moveable_block":
			return {"glb": "res://assets/props/stone_block.glb", "dims": Vector3(1.0, 1.0, 1.0), "tint_tag": "moveable", "tint": Color(0.84, 0.92, 1.05)}
		"dropping_block":
			return {"glb": "res://assets/props/dropping_block.glb", "dims": Vector3(0.95, 0.75, 0.95), "tint_tag": "", "tint": Color.WHITE}
		"collapsing_block":
			return {"glb": "res://assets/props/collapsing_tile.glb", "dims": Vector3(0.98, 0.25, 0.98), "tint_tag": "", "tint": Color.WHITE}
		"block_ew", "block_ns":
			return {"glb": "res://assets/props/moving_platform.glb", "dims": Vector3(1.9, 0.35, 1.9), "tint_tag": "", "tint": Color.WHITE}
		"guard_ew", "guard_square":
			return {"glb": "res://assets/characters/patrol_sentinel.glb", "dims": Vector3(0.75, 1.45, 0.75), "tint_tag": "", "tint": Color.WHITE}
		"gargoyle":
			return {"glb": "res://assets/props/hazard_gargoyle.glb", "dims": Vector3(0.75, 0.85, 0.75), "tint_tag": "", "tint": Color.WHITE}
		"spike", "spike_high":
			return {"glb": "res://assets/props/hazard_spikes.glb", "dims": Vector3(0.80, 0.65, 0.80), "tint_tag": "", "tint": Color.WHITE}
		"spike_ball_fall", "spike_ball_high_fall":
			return {"glb": "res://assets/props/hazard_spiked_ball.glb", "dims": Vector3(0.75, 0.75, 0.75), "tint_tag": "", "tint": Color.WHITE}
		"fire_ew", "fire_ns":
			return {"glb": "res://assets/props/hazard_fire.glb", "dims": Vector3(0.70, 0.80, 0.70), "tint_tag": "", "tint": Color.WHITE}
		"ghost":
			return {"glb": "res://assets/props/enemy_ghost.glb", "dims": Vector3(0.70, 0.90, 0.70), "tint_tag": "", "tint": Color.WHITE}
		"repel_spell":
			return {"glb": "res://assets/props/item_crystal_ball.glb", "dims": Vector3(0.50, 0.55, 0.50), "tint_tag": "repel_emerald", "tint": Color(0.28, 1.0, 0.55, 1.0)}
		_:
			return {"glb": "res://assets/props/hazard_ball.glb", "dims": Vector3(0.75, 0.75, 0.75), "tint_tag": "", "tint": Color.WHITE}


func _spawn_glb_visual_on_node(
	host_node: Node3D,
	res_path: String,
	target_sz: Vector3,
	base_dims: Vector3,
	offset: Vector3,
	rot_y_deg: float,
	tint_tag: String,
	tint: Color
) -> void:
	var packed: PackedScene = _load_prop_scene(res_path)
	if packed == null:
		return
	var inst: Node3D = packed.instantiate() as Node3D
	inst.name = "ModelVisual"
	inst.position = offset
	inst.rotation_degrees.y = rot_y_deg
	var use_x: float = target_sz.x
	var use_z: float = target_sz.z
	if absf(rot_y_deg - 90.0) < 1.0 or absf(rot_y_deg + 90.0) < 1.0:
		use_x = target_sz.z
		use_z = target_sz.x
	inst.scale = Vector3(
		use_x / maxf(base_dims.x, 0.05),
		target_sz.y / maxf(base_dims.y, 0.05),
		use_z / maxf(base_dims.z, 0.05)
	)
	_configure_static_model_recursive(inst)
	if not tint_tag.is_empty():
		_tint_static_model_recursive(inst, tint_tag, tint)
	host_node.add_child(inst)
	var proxy: MeshInstance3D = host_node.get_node_or_null("Mesh") as MeshInstance3D
	if proxy != null:
		proxy.visible = false


func _spawn_melkhior_wizard(parent: Node3D, pos: Vector3, sz: Vector3, entities_cfg: Dictionary) -> void:
	var bg_specs: Dictionary = entities_cfg.get("special_background_entities", {}) as Dictionary
	var wiz_cfg: Dictionary = bg_specs.get("wizard", {"behavior": "patrol_square_cw", "params": {"speed": 2, "directions": ["W", "N", "E", "S"]}}) as Dictionary
	var wiz := KlHazardEntity.new()
	wiz.name = "MelkhiorWizard"
	wiz.configure("wizard", wiz_cfg, sz, pos)
	parent.add_child(wiz)

	var wiz_scene: PackedScene = _load_prop_scene("res://assets/characters/melkhior_wizard.glb")
	if wiz_scene != null:
		var inst: Node3D = wiz_scene.instantiate() as Node3D
		inst.name = "ModelVisual"
		_configure_static_model_recursive(inst)
		wiz.add_child(inst)
		wiz.attach_visual_support()
		wiz.set_animation_player(HumanoidAnimationLibrary.attach_to_character(inst))
		return

	var robe_mat := StandardMaterial3D.new()
	robe_mat.albedo_color = Color(0.28, 0.18, 0.52, 1.0)
	var robe := MeshInstance3D.new()
	var robe_cyl := CylinderMesh.new()
	robe_cyl.material = robe_mat
	robe.mesh = robe_cyl
	robe.position = Vector3(0.0, 0.65, 0.0)
	wiz.add_child(robe)


func _spawn_kl_hazard_prop(
	parent: Node3D,
	node_name: String,
	type_name: String,
	pos: Vector3,
	sz: Vector3
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	# Non-solid lethal trigger geometry matching KlHazardEntity so the player
	# cannot stand atop spikes or get pushed outside is_player_in_hazard_core().
	body.collision_layer = 0
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, sz.y * 0.5, 0.0)
	body.set_meta("kl_type", type_name)
	body.set_meta("kl_lethal", true)
	body.set_meta("kl_visual_size", sz)
	body.add_to_group("kl_lethal_hazards")
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(sz.x * 0.76, sz.y * 0.88, sz.z * 0.76)
	col.shape = cbox
	body.add_child(col)

	var proxy := MeshInstance3D.new()
	proxy.name = "Mesh"
	proxy.visible = false
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pbox := BoxMesh.new()
	pbox.size = sz
	pbox.material = get_material("hazard_crimson")
	proxy.mesh = pbox
	body.add_child(proxy)

	var glb_path: String = "res://assets/props/hazard_ball.glb"
	var base_dims := Vector3(0.75, 0.75, 0.75)
	var tint_tag: String = ""
	var tint: Color = Color.WHITE
	match type_name:
		"gargoyle":
			glb_path = "res://assets/props/hazard_gargoyle.glb"
			base_dims = Vector3(0.75, 0.85, 0.75)
		"spike", "spike_high":
			glb_path = "res://assets/props/hazard_spikes.glb"
			base_dims = Vector3(0.80, 0.65, 0.80)
		"spike_ball_fall", "spike_ball_high_fall":
			glb_path = "res://assets/props/hazard_spiked_ball.glb"
			base_dims = Vector3(0.75, 0.75, 0.75)
		"fire_ew", "fire_ns":
			glb_path = "res://assets/props/hazard_fire.glb"
			base_dims = Vector3(0.70, 0.80, 0.70)
		"ghost":
			glb_path = "res://assets/props/enemy_ghost.glb"
			base_dims = Vector3(0.70, 0.90, 0.70)
		"repel_spell":
			glb_path = "res://assets/props/item_crystal_ball.glb"
			base_dims = Vector3(0.50, 0.55, 0.50)
			tint_tag = "repel_emerald"
			tint = Color(0.28, 1.0, 0.55, 1.0)
		_:
			glb_path = "res://assets/props/hazard_ball.glb"
			base_dims = Vector3(0.75, 0.75, 0.75)

	parent.add_child(body)
	_spawn_glb_visual_on_node(body, glb_path, sz, base_dims, Vector3(0.0, -sz.y * 0.5, 0.0), 0.0, tint_tag, tint)
	return body


func _build_kl_special_spawn_previews(
	entities_root: Node3D,
	kl_data: KnightLoreData,
	room_id: int,
	half_x: float,
	half_y: float,
	floor_z: float
) -> void:
	const ITEM_GLBS: Array[String] = [
		"res://assets/props/item_diamond.glb",
		"res://assets/props/item_poison.glb",
		"res://assets/props/item_boot.glb",
		"res://assets/props/item_chalice.glb",
		"res://assets/props/item_cup.glb",
		"res://assets/props/item_bottle.glb",
		"res://assets/props/item_crystal_ball.glb",
		"res://assets/props/item_extra_life.glb"
	]
	for sp_v: Variant in kl_data.special_spawns:
		if not (sp_v is Dictionary):
			continue
		var sp: Dictionary = sp_v as Dictionary
		if int(sp.get("room_id", -1)) != room_id:
			continue
		var sp_idx: int = int(sp.get("index", 0))
		var pos: Vector3 = KnightLoreData.kl_to_room_pos(float(sp.get("x", 128)), float(sp.get("y", 128)), float(sp.get("z", 128)), half_x, half_y, floor_z)
		var item_node := Node3D.new()
		item_node.name = "SpecialSpawn_%02d" % sp_idx
		item_node.position = pos
		item_node.set_meta("kl_type", "special_item")
		item_node.set_meta("spawn_index", sp_idx)
		entities_root.add_child(item_node)
		var glb_path: String = ITEM_GLBS[posmod(sp_idx, ITEM_GLBS.size())]
		_spawn_glb_visual_on_node(item_node, glb_path, Vector3(0.55, 0.55, 0.55), Vector3(0.55, 0.55, 0.55), Vector3.ZERO, 0.0, "", Color.WHITE)

