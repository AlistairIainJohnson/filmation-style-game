class_name EntityFactory
extends RefCounted
## Instantiates deterministic Filmation puzzle entities from data/entities.json archetypes
## and binds trigger relationships across entities within a chamber.


func spawn_entities(
	entities_root: Node3D,
	entity_defs: Array,
	entities_catalog: Dictionary,
	get_mat_fn: Callable
) -> Dictionary:
	var entity_map: Dictionary = {}
	var switches: Array[Dictionary] = []

	for item: Variant in entity_defs:
		if not (item is Dictionary):
			continue
		var edef: Dictionary = item as Dictionary
		var eid: String = str(edef.get("id", "entity"))
		var arch_name: String = str(edef.get("archetype", ""))
		var arch_cfg: Dictionary = entities_catalog.get(arch_name, {}) as Dictionary
		var kind: String = str(arch_cfg.get("kinematic_kind", "static_prop"))
		var sz: Vector3 = _vec3_from_array(arch_cfg.get("size", [0.8, 0.8, 0.8]))
		var pos: Vector3 = _vec3_from_array(edef.get("pos", [0.0, 0.0, 0.0]))
		var mat: Material = get_mat_fn.call(str(arch_cfg.get("material", "oak_chest"))) as Material
		var persistent_flag: bool = bool(edef.get("persistent", true))

		var node: Node3D
		match kind:
			"pushable_block":
				var pb := PushableBlock.new()
				pb.entity_id = eid
				pb.archetype = arch_name
				pb.persistent = persistent_flag
				pb.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(pb, arch_cfg)
				node = pb
			"trigger_switch":
				var sw := TriggerSwitch.new()
				sw.entity_id = eid
				sw.archetype = arch_name
				sw.persistent = persistent_flag
				var targets_raw: Array = edef.get("triggers", []) as Array
				var typed_targets: Array[String] = []
				for t_id: Variant in targets_raw:
					typed_targets.append(str(t_id))
				sw.trigger_targets = typed_targets
				sw.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(sw, arch_cfg)
				node = sw
				switches.append({"node": sw, "targets": typed_targets})
			"animatable_gate":
				var gate := Portcullis.new()
				gate.entity_id = eid
				gate.archetype = arch_name
				gate.persistent = persistent_flag
				gate.starts_closed = bool(edef.get("starts_closed", true))
				gate.latch_open = bool(edef.get("latch_open", false))
				gate.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(gate, arch_cfg)
				node = gate
			"moving_platform":
				var plat := MovingPlatform.new()
				plat.entity_id = eid
				plat.archetype = arch_name
				plat.persistent = persistent_flag
				plat.waypoints = _parse_waypoints(edef.get("waypoints", []) as Array, pos)
				plat.move_speed = float(edef.get("move_speed", 2.0))
				plat.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(plat, arch_cfg)
				node = plat
			"collapsing_tile":
				var ctile := CollapsingTile.new()
				ctile.entity_id = eid
				ctile.archetype = arch_name
				ctile.persistent = persistent_flag
				ctile.collapse_delay = float(edef.get("collapse_delay", 0.35))
				ctile.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(ctile, arch_cfg)
				node = ctile
			"collectible":
				var col_item := CollectibleItem.new()
				col_item.entity_id = eid
				col_item.archetype = arch_name
				col_item.persistent = persistent_flag
				col_item.item_kind = str(edef.get("item_kind", "key"))
				col_item.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(col_item, arch_cfg)
				node = col_item
			"patrol_hazard":
				var haz := PatrolHazard.new()
				haz.entity_id = eid
				haz.archetype = arch_name
				haz.persistent = persistent_flag
				haz.waypoints = _parse_waypoints(edef.get("waypoints", []) as Array, pos)
				haz.patrol_speed = float(edef.get("patrol_speed", 2.2))
				haz.setup_visual_and_collider(sz, mat)
				_maybe_apply_model(haz, arch_cfg)
				node = haz
			_:
				node = _create_static_prop(arch_cfg, sz, mat, eid, arch_name, persistent_flag)

		node.name = eid
		node.position = pos
		if edef.has("rotation_y"):
			node.rotation_degrees.y = float(edef["rotation_y"])
		entities_root.add_child(node)
		entity_map[eid] = node

	# Second pass: wire switch targets
	for entry: Dictionary in switches:
		var sw_node: TriggerSwitch = entry["node"] as TriggerSwitch
		var target_ids: Array[String] = entry["targets"] as Array[String]
		var target_nodes: Array[Node] = []
		for tid: String in target_ids:
			if entity_map.has(tid):
				target_nodes.append(entity_map[tid] as Node)
		sw_node.bind_targets(target_nodes)

	return entity_map


static func _create_static_prop(
	arch_cfg: Dictionary,
	sz: Vector3,
	mat: Material,
	eid: String,
	arch_name: String,
	persistent_flag: bool
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("entity_id", eid)
	body.set_meta("archetype", arch_name)
	body.set_meta("persistent", persistent_flag)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Visual"
	mesh_inst.layers = 1
	mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	mesh_inst.position = Vector3(0.0, sz.y * 0.5, 0.0)

	var col := CollisionShape3D.new()
	col.position = Vector3(0.0, sz.y * 0.5, 0.0)

	if str(arch_cfg.get("shape", "box")) == "cylinder":
		var cyl := CylinderMesh.new()
		cyl.top_radius = sz.x * 0.5
		cyl.bottom_radius = sz.x * 0.42
		cyl.height = sz.y
		cyl.material = mat
		mesh_inst.mesh = cyl
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = sz.x * 0.5
		cyl_shape.height = sz.y
		col.shape = cyl_shape
	else:
		var box := BoxMesh.new()
		box.size = sz
		box.material = mat
		mesh_inst.mesh = box
		var box_shape := BoxShape3D.new()
		box_shape.size = sz
		col.shape = box_shape

	body.add_child(mesh_inst)
	body.add_child(col)
	var model_path: String = str(arch_cfg.get("model_path", ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed: PackedScene = ResourceLoader.load(model_path) as PackedScene
		if packed != null:
			body.remove_child(mesh_inst)
			mesh_inst.free()
			var inst: Node3D = packed.instantiate() as Node3D
			inst.name = "ModelVisual"
			_set_layer_recursive(inst)
			body.add_child(inst)
	return body


static func _maybe_apply_model(target: Node, arch_cfg: Dictionary) -> void:
	var model_path: String = str(arch_cfg.get("model_path", ""))
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return
	var packed: PackedScene = ResourceLoader.load(model_path) as PackedScene
	if packed != null and target.has_method("set_visual_model"):
		target.call("set_visual_model", packed)


static func _set_layer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.layers = 1
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child: Node in node.get_children():
		_set_layer_recursive(child)


static func _parse_waypoints(raw_wps: Array, fallback_pos: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wp: Variant in raw_wps:
		if wp is Array and wp.size() >= 3:
			out.append(Vector3(float(wp[0]), float(wp[1]), float(wp[2])))
	if out.is_empty():
		out.append(fallback_pos)
	return out


static func _vec3_from_array(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO
