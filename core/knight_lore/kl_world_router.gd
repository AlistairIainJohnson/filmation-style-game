class_name KlWorldRouter
extends RefCounted
## 128-room world graph router and macro objective planner for Knight Lore.
## Builds a weighted directed graph of room connectivity and plans optimal multi-room
## routes and quest delivery goals.

const CONFIG_PATH: String = "res://data/knight_lore/solver_config.json"

var solver_cfg: Dictionary = {}
var kl_data: KnightLoreData
var _adj: Dictionary = {} # room_id (int) -> Array[Dictionary]
var _room_meta: Dictionary = {} # room_id (int) -> Dictionary


func _init(data: KnightLoreData = null, custom_cfg: Dictionary = {}) -> void:
	if not custom_cfg.is_empty():
		solver_cfg = custom_cfg
	else:
		solver_cfg = RoomBuilder.load_json_dict(CONFIG_PATH)
	if data != null:
		setup(data)


func setup(data: KnightLoreData) -> void:
	kl_data = data
	build_graph(kl_data, solver_cfg)


func build_graph(data: KnightLoreData, cfg: Dictionary) -> void:
	kl_data = data
	solver_cfg = cfg
	_adj.clear()
	_room_meta.clear()

	var edge_costs: Dictionary = solver_cfg.get("edge_costs", {}) as Dictionary
	var std_cost: float = float(edge_costs.get("standard_exit", 1.0))
	var high_cost: float = float(edge_costs.get("high_arch_exit", 4.5))
	var hazard_penalty: float = float(edge_costs.get("hazard_room_penalty", 1.5))
	var lethal_types: Array = solver_cfg.get("lethal_types", []) as Array
	var pushable_types: Array = solver_cfg.get("pushable_types", []) as Array
	var moving_types: Array = solver_cfg.get("moving_platform_types", []) as Array

	var room_ids: Array[int] = kl_data.get_room_ids()
	for rid: int in room_ids:
		var r_data: Dictionary = kl_data.get_room(rid)
		var fg_list: Array = r_data.get("foregrounds", []) as Array
		var has_hazards: bool = false
		var has_pushables: bool = false
		var has_moving: bool = false

		for fg_v: Variant in fg_list:
			if fg_v is Dictionary:
				var tname: String = str((fg_v as Dictionary).get("type_name", ""))
				if lethal_types.has(tname):
					has_hazards = true
				if pushable_types.has(tname):
					has_pushables = true
				if moving_types.has(tname):
					has_moving = true

		_room_meta[rid] = {
			"has_hazards": has_hazards,
			"has_pushables": has_pushables,
			"has_moving": has_moving,
			"is_forest": kl_data.is_forest_room(rid)
		}

	for rid: int in room_ids:
		_adj[rid] = []
		var exits: Dictionary = kl_data.get_room_exits(rid)
		for dir_name: String in exits.keys():
			var exit_info: Dictionary = exits[dir_name] as Dictionary
			var target_rid: int = int(exit_info.get("target_room_id", -1))
			if not kl_data.has_room(target_rid):
				continue

			var is_high: bool = bool(exit_info.get("high", false))
			var elev: float = float(exit_info.get("elevation_m", 0.0))
			var base_c: float = high_cost if is_high else std_cost
			var dst_meta: Dictionary = _room_meta.get(target_rid, {}) as Dictionary
			if bool(dst_meta.get("has_hazards", false)):
				base_c += hazard_penalty

			_adj[rid].append({
				"to": target_rid,
				"dir": dir_name,
				"is_high": is_high,
				"elevation_m": elev,
				"base_cost": base_c
			})


func find_room_path(from_rid: int, to_rid: int, capabilities: Dictionary = {}) -> Array[Dictionary]:
	if from_rid == to_rid:
		return []
	if not kl_data.has_room(from_rid) or not kl_data.has_room(to_rid):
		return []

	var allow_high: bool = bool(capabilities.get("allow_high_arches", true))
	var is_wulf: bool = bool(capabilities.get("is_wulf", false))
	var carried_items: int = int(capabilities.get("carried_items", 0))

	# Dijkstra / A* over 128-room graph
	# dist: room_id -> float
	# prev: room_id -> {"from": int, "edge": Dictionary}
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var visited: Dictionary = {}

	dist[from_rid] = 0.0

	var open_set: Array[int] = [from_rid]

	while not open_set.is_empty():
		# Find min dist node in open_set
		var best_idx: int = 0
		var best_d: float = float(dist.get(open_set[0], INF))
		for i: int in range(1, open_set.size()):
			var cur_rid: int = open_set[i]
			var d: float = float(dist.get(cur_rid, INF))
			if d < best_d:
				best_d = d
				best_idx = i

		var u: int = open_set[best_idx]
		open_set.remove_at(best_idx)
		visited[u] = true

		if u == to_rid:
			break

		var edges: Array = _adj.get(u, []) as Array
		for edge_v: Variant in edges:
			var edge: Dictionary = edge_v as Dictionary
			var v: int = int(edge.get("to", -1))
			if visited.has(v):
				continue

			var is_high: bool = bool(edge.get("is_high", false))
			if is_high and not allow_high:
				continue

			var edge_cost: float = float(edge.get("base_cost", 1.0))
			if is_high:
				var u_meta: Dictionary = _room_meta.get(u, {}) as Dictionary
				var has_climb_support: bool = bool(u_meta.get("has_pushables", false)) or bool(u_meta.get("has_moving", false))
				if not has_climb_support:
					# High arch requires drop-climb or high jump
					var max_jump: float = float(solver_cfg.get("jump_apex_wulf_m" if is_wulf else "jump_apex_human_m", 1.35))
					var drop_lift: float = float(solver_cfg.get("drop_climb_lift_m", 0.72))
					var high_elev: float = float(solver_cfg.get("high_arch_elevation_m", 3.0))
					var reachable: float = max_jump + (carried_items * drop_lift)
					if reachable < (high_elev - 0.10):
						edge_cost += 30.0 # Heavy penalty if currently under-geared to scale
					else:
						edge_cost += 6.0

			var alt: float = best_d + edge_cost
			if alt < float(dist.get(v, INF)):
				dist[v] = alt
				prev[v] = {
					"from": u,
					"edge": edge
				}
				if not open_set.has(v):
					open_set.append(v)

	if not prev.has(to_rid):
		return []

	# Reconstruct path
	var path: Array[Dictionary] = []
	var curr: int = to_rid
	while curr != from_rid:
		var step_info: Dictionary = prev.get(curr, {}) as Dictionary
		if step_info.is_empty():
			break
		var edge: Dictionary = step_info.get("edge", {}) as Dictionary
		var p_from: int = int(step_info.get("from", -1))
		path.push_front({
			"from_room": p_from,
			"to_room": curr,
			"direction": str(edge.get("dir", "")),
			"is_high": bool(edge.get("is_high", false)),
			"cost": float(edge.get("base_cost", 1.0))
		})
		curr = p_from

	return path


func plan_next_objective(session: KnightLoreSession, data: KnightLoreData = null) -> Dictionary:
	if data != null:
		kl_data = data
	if kl_data == null or session == null:
		return {}

	var req_type: int = session.get_next_required_charm()
	var sim: Dictionary = kl_data.entities_cfg.get("simulation_constants", {}) as Dictionary
	var cauldron_rid: int = int(sim.get("cauldron_room_id", 136))

	if req_type < 0:
		return {
			"goal_type": &"quest_complete",
			"target_room": cauldron_rid,
			"room_path": []
		}

	# Check if required charm is already in session inventory
	var carried_slot: int = -1
	var carried_count: int = 0
	for idx: int in range(session.inventory.size()):
		var tid: int = session.inventory[idx]
		if tid >= 0:
			carried_count += 1
		if tid == req_type and carried_slot == -1:
			carried_slot = idx

	var caps := {
		"is_wulf": session.is_wulf,
		"carried_items": carried_count,
		"allow_high_arches": true
	}

	# Case 1: Already carrying the required charm -> head straight to Cauldron Room
	if carried_slot >= 0:
		var path_to_cauldron: Array[Dictionary] = find_room_path(session.current_room_id, cauldron_rid, caps)
		return {
			"goal_type": &"deliver_cauldron",
			"target_room": cauldron_rid,
			"charm_type": req_type,
			"inventory_slot": carried_slot,
			"room_path": path_to_cauldron
		}

	# Case 2: Charm is out in the castle -> find the closest reachable instance
	var candidate_items: Array[Dictionary] = []
	for it: Dictionary in session.world_items:
		if bool(it.get("active", false)) and int(it.get("type_id", -1)) == req_type:
			candidate_items.append(it)

	if candidate_items.is_empty():
		return {
			"goal_type": &"unreachable",
			"error": "No active world items match required charm %d" % req_type
		}

	var best_item: Dictionary = {}
	var best_path: Array[Dictionary] = []
	var best_cost: float = INF

	for it: Dictionary in candidate_items:
		var target_rid: int = int(it.get("room_id", -1))
		var path: Array[Dictionary] = find_room_path(session.current_room_id, target_rid, caps)
		if path.is_empty() and session.current_room_id != target_rid:
			continue
		var total_cost: float = 0.0
		for step: Dictionary in path:
			total_cost += float(step.get("cost", 1.0))
		if total_cost < best_cost:
			best_cost = total_cost
			best_item = it
			best_path = path

	if best_item.is_empty():
		return {
			"goal_type": &"unreachable",
			"error": "No reachable path to required charm %d" % req_type
		}

	return {
		"goal_type": &"fetch_charm",
		"target_room": int(best_item.get("room_id", -1)),
		"target_item_id": int(best_item.get("id", -1)),
		"charm_type": req_type,
		"target_pos": best_item.get("pos", Vector3.ZERO),
		"room_path": best_path
	}
