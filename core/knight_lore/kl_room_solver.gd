class_name KlRoomSolver
extends RefCounted
## 2.5D room nav-grid generator and intra-room puzzle action solver for Knight Lore.
## Constructs spatial heightmaps from room geometry, detects hazards and climbable surfaces,
## and synthesizes action plans for drop-climbing, block pushing, and cauldron delivery.

const CONFIG_PATH: String = "res://data/knight_lore/solver_config.json"

var solver_cfg: Dictionary = {}


func _init(custom_cfg: Dictionary = {}) -> void:
	if not custom_cfg.is_empty():
		solver_cfg = custom_cfg
	else:
		solver_cfg = RoomBuilder.load_json_dict(CONFIG_PATH)


func build_nav_grid(
	room_dims: Vector3,
	arch_root: Node3D,
	entities_root: Node3D,
	cfg: Dictionary = {}
) -> Dictionary:
	var active_cfg: Dictionary = cfg if not cfg.is_empty() else solver_cfg
	var cell_size: float = float(active_cfg.get("grid_cell_size_m", 0.5))
	var player_h: float = float(active_cfg.get("player_height_m", 1.36))
	var player_r: float = float(active_cfg.get("player_radius_m", 0.24))

	var cols: int = int(round(room_dims.x / cell_size))
	var rows: int = int(round(room_dims.z / cell_size))

	# Initialize grid cells
	# cell: {"surface_y": float, "blocked": bool, "lethal": bool, "penalty": float, "items": Array, "pushables": Array}
	var cells: Array = []
	for z_idx: int in range(rows):
		var row_arr: Array = []
		for x_idx: int in range(cols):
			row_arr.append({
				"surface_y": 0.0,
				"blocked": false,
				"lethal": false,
				"penalty": 0.0,
				"items": [],
				"pushables": []
			})
		cells.append(row_arr)

	var grid := {
		"room_dims": room_dims,
		"cell_size": cell_size,
		"cols": cols,
		"rows": rows,
		"cells": cells,
		"pushables": [],
		"items": []
	}

	# 1. Project Static Architecture Colliders
	if arch_root != null and is_instance_valid(arch_root):
		for child: Node in arch_root.get_children():
			if child is StaticBody3D:
				var cshape: CollisionShape3D = child.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if cshape != null and cshape.shape is BoxShape3D:
					var box: BoxShape3D = cshape.shape as BoxShape3D
					var b_pos: Vector3 = child.position + cshape.position
					var b_half: Vector3 = box.size * 0.5

					# Skip outer perimeter walls that lie outside [0, room_dims]
					if b_pos.x < -0.1 or b_pos.x > (room_dims.x + 0.1) or b_pos.z < -0.1 or b_pos.z > (room_dims.z + 0.1):
						continue
					# Skip tall 6m back walls along North (Z <= 0.25) and West (X <= 0.25)
					if (b_pos.x <= 0.25 or b_pos.z <= 0.25) and box.size.y >= 5.0:
						continue

					var min_x_idx: int = maxi(0, int(floor((b_pos.x - b_half.x) / cell_size)))
					var max_x_idx: int = mini(cols - 1, int(floor((b_pos.x + b_half.x - 0.01) / cell_size)))
					var min_z_idx: int = maxi(0, int(floor((b_pos.z - b_half.z) / cell_size)))
					var max_z_idx: int = mini(rows - 1, int(floor((b_pos.z + b_half.z - 0.01) / cell_size)))

					var top_y: float = b_pos.y + b_half.y
					for r: int in range(min_z_idx, max_z_idx + 1):
						for c: int in range(min_x_idx, max_x_idx + 1):
							var cell: Dictionary = cells[r][c] as Dictionary
							if top_y > float(cell.get("surface_y", 0.0)):
								cell["surface_y"] = top_y
								if (room_dims.y - top_y) < player_h:
									cell["blocked"] = true

	# 2. Project Dynamic Entities & Carryables
	if entities_root != null and is_instance_valid(entities_root):
		for child: Node in entities_root.get_children():
			if child is KlSpecialItem:
				var item: KlSpecialItem = child as KlSpecialItem
				if item.is_extra_life or item.is_arcing:
					continue
				var i_pos: Vector3 = item.position
				var col_idx: int = clampi(int(floor(i_pos.x / cell_size)), 0, cols - 1)
				var row_idx: int = clampi(int(floor(i_pos.z / cell_size)), 0, rows - 1)
				var cell: Dictionary = cells[row_idx][col_idx] as Dictionary
				var top_y: float = i_pos.y + 0.72 # item height
				cell["surface_y"] = maxf(float(cell.get("surface_y", 0.0)), top_y)
				(cell["items"] as Array).append(item.item_id)
				(grid["items"] as Array).append({
					"id": item.item_id,
					"type_id": item.type_id,
					"pos": i_pos
				})

			elif child is KlPushableEntity:
				var pushable: KlPushableEntity = child as KlPushableEntity
				var p_pos: Vector3 = pushable.position
				var col_idx: int = clampi(int(floor(p_pos.x / cell_size)), 0, cols - 1)
				var row_idx: int = clampi(int(floor(p_pos.z / cell_size)), 0, rows - 1)
				var cell: Dictionary = cells[row_idx][col_idx] as Dictionary
				var p_h: float = pushable.entity_height_m if "entity_height_m" in pushable else 0.75
				cell["surface_y"] = maxf(float(cell.get("surface_y", 0.0)), p_pos.y + p_h)
				(cell["pushables"] as Array).append(pushable)
				(grid["pushables"] as Array).append({
					"node": pushable,
					"pos": p_pos,
					"height": p_h
				})

			elif child.is_in_group("kl_lethal_hazards"):
				var h_pos: Vector3 = (child as Node3D).position
				var col_idx: int = clampi(int(floor(h_pos.x / cell_size)), 0, cols - 1)
				var row_idx: int = clampi(int(floor(h_pos.z / cell_size)), 0, rows - 1)
				var cell: Dictionary = cells[row_idx][col_idx] as Dictionary
				cell["lethal"] = true

				# Expand hazard proximity buffer
				var buf_penalty: float = float(active_cfg.get("edge_costs", {}).get("hazard_buffer_penalty", 6.0))
				for dr: int in [-1, 0, 1]:
					for dc: int in [-1, 0, 1]:
						var nr: int = row_idx + dr
						var nc: int = col_idx + dc
						if nr >= 0 and nr < rows and nc >= 0 and nc < cols:
							var n_cell: Dictionary = cells[nr][nc] as Dictionary
							if not bool(n_cell.get("lethal", false)):
								n_cell["penalty"] = float(n_cell.get("penalty", 0.0)) + buf_penalty

	return grid


func find_local_path(
	grid: Dictionary,
	start_pos: Vector3,
	goal_pos: Vector3,
	max_jump_height: float = 1.35
) -> Array[Dictionary]:
	var cell_size: float = float(grid.get("cell_size", 0.5))
	var cols: int = int(grid.get("cols", 16))
	var rows: int = int(grid.get("rows", 16))
	var cells: Array = grid.get("cells", []) as Array

	var start_c: int = clampi(int(floor(start_pos.x / cell_size)), 0, cols - 1)
	var start_r: int = clampi(int(floor(start_pos.z / cell_size)), 0, rows - 1)
	var goal_c: int = clampi(int(floor(goal_pos.x / cell_size)), 0, cols - 1)
	var goal_r: int = clampi(int(floor(goal_pos.z / cell_size)), 0, rows - 1)

	if start_c == goal_c and start_r == goal_r:
		return [{
			"pos": goal_pos,
			"action": &"walk"
		}]

	# 2.5D A* search on grid
	var start_key: Vector2i = Vector2i(start_c, start_r)
	var goal_key: Vector2i = Vector2i(goal_c, goal_r)

	var g_score: Dictionary = {} # Vector2i -> float
	var f_score: Dictionary = {} # Vector2i -> float
	var came_from: Dictionary = {} # Vector2i -> {"pos": Vector2i, "action": StringName}
	var open_set: Array[Vector2i] = [start_key]
	var in_open: Dictionary = {start_key: true}

	g_score[start_key] = 0.0
	f_score[start_key] = _heuristic(start_key, goal_key, cell_size)

	const DIRS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]

	while not open_set.is_empty():
		# Min f_score in open_set
		var best_idx: int = 0
		var best_f: float = float(f_score.get(open_set[0], INF))
		for i: int in range(1, open_set.size()):
			var f_val: float = float(f_score.get(open_set[i], INF))
			if f_val < best_f:
				best_f = f_val
				best_idx = i

		var current: Vector2i = open_set[best_idx]
		var cur_cell: Dictionary = cells[current.y][current.x] as Dictionary
		var cur_surf: float = float(cur_cell.get("surface_y", 0.0))
		var cur_g: float = float(g_score.get(current, INF))

		if current == goal_key:
			var goal_cell: Dictionary = cells[goal_r][goal_c] as Dictionary
			var target_y: float = maxf(float(goal_cell.get("surface_y", 0.0)), goal_pos.y)
			# If the goal's target elevation is higher than current surface plus max jump, it's unreachable directly
			if (target_y - cur_surf) > max_jump_height:
				open_set.remove_at(best_idx)
				in_open.erase(current)
				continue
			return _reconstruct_local_path(came_from, current, start_pos, goal_pos, cell_size, cells)

		open_set.remove_at(best_idx)
		in_open.erase(current)

		for d: Vector2i in DIRS:
			var neighbor: Vector2i = current + d
			if neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows:
				continue

			var is_diag: bool = (d.x != 0 and d.y != 0)
			# Diagonal corner-cutting protection
			if is_diag:
				var c1: Dictionary = cells[current.y][neighbor.x] as Dictionary
				var c2: Dictionary = cells[neighbor.y][current.x] as Dictionary
				if bool(c1.get("blocked", false)) or bool(c1.get("lethal", false)) or bool(c2.get("blocked", false)) or bool(c2.get("lethal", false)):
					continue

			var n_cell: Dictionary = cells[neighbor.y][neighbor.x] as Dictionary
			if bool(n_cell.get("blocked", false)):
				continue
			if bool(n_cell.get("lethal", false)) and neighbor != goal_key:
				continue

			var n_surf: float = float(n_cell.get("surface_y", 0.0))
			var dy: float = n_surf - cur_surf

			# Vertical reachability check
			if dy > max_jump_height:
				continue

			# Action classification
			var action: StringName = &"jump" if dy > 0.35 else &"walk"
			var move_dist: float = (1.414 * cell_size) if is_diag else cell_size
			var step_cost: float = move_dist + float(n_cell.get("penalty", 0.0))
			if action == &"jump":
				step_cost += 0.8 # Slight preference for walking over jumping

			var tentative_g: float = cur_g + step_cost
			if tentative_g < float(g_score.get(neighbor, INF)):
				came_from[neighbor] = {
					"parent": current,
					"action": action
				}
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, goal_key, cell_size)
				if not in_open.has(neighbor):
					open_set.append(neighbor)
					in_open[neighbor] = true

	return [] # No valid path found


static func _heuristic(a: Vector2i, b: Vector2i, cell_size: float) -> float:
	var dx: float = absf(float(a.x - b.x)) * cell_size
	var dz: float = absf(float(a.y - b.y)) * cell_size
	return (dx + dz) + (1.414 - 2.0) * minf(dx, dz)


static func _reconstruct_local_path(
	came_from: Dictionary,
	current: Vector2i,
	start_pos: Vector3,
	goal_pos: Vector3,
	cell_size: float,
	cells: Array
) -> Array[Dictionary]:
	var path: Array[Dictionary] = []
	var curr_node: Vector2i = current

	while came_from.has(curr_node):
		var info: Dictionary = came_from[curr_node] as Dictionary
		var parent: Vector2i = info["parent"] as Vector2i
		var action: StringName = info["action"] as StringName

		var cell: Dictionary = cells[curr_node.y][curr_node.x] as Dictionary
		var surf_y: float = float(cell.get("surface_y", 0.0))
		var pt := Vector3(
			(float(curr_node.x) + 0.5) * cell_size,
			surf_y,
			(float(curr_node.y) + 0.5) * cell_size
		)
		if curr_node == current:
			pt = goal_pos

		path.push_front({
			"pos": pt,
			"action": action
		})
		curr_node = parent

	return path


func plan_room_puzzle(
	grid: Dictionary,
	start_pos: Vector3,
	goal_pos: Vector3,
	context: Dictionary = {}
) -> Dictionary:
	var is_wulf: bool = bool(context.get("is_wulf", false))
	var carried_items: int = int(context.get("carried_items", 0))
	var room_id: int = int(context.get("room_id", 0))

	var jump_human: float = float(solver_cfg.get("jump_apex_human_m", 1.35))
	var jump_wulf: float = float(solver_cfg.get("jump_apex_wulf_m", 1.65))
	var current_jump: float = jump_wulf if is_wulf else jump_human
	var drop_lift: float = float(solver_cfg.get("drop_climb_lift_m", 0.72))

	# 1. Direct path attempt
	var direct_path: Array[Dictionary] = find_local_path(grid, start_pos, goal_pos, current_jump)
	if not direct_path.is_empty():
		return {
			"solvable": true,
			"strategy": &"direct",
			"steps": direct_path
		}

	# 2. Form Synergy Check (Wait for Werewolf if Human)
	if not is_wulf:
		var wulf_path: Array[Dictionary] = find_local_path(grid, start_pos, goal_pos, jump_wulf)
		if not wulf_path.is_empty():
			return {
				"solvable": true,
				"strategy": &"wait_for_night",
				"steps": [{ "action": &"wait_for_night" }] + wulf_path
			}

	# 3. Drop-Climb Staircase Strategy
	var cell_size: float = float(grid.get("cell_size", 0.5))
	var cols: int = int(grid.get("cols", 16))
	var rows: int = int(grid.get("rows", 16))
	var cells: Array = grid.get("cells", []) as Array

	var goal_c: int = clampi(int(floor(goal_pos.x / cell_size)), 0, cols - 1)
	var goal_r: int = clampi(int(floor(goal_pos.z / cell_size)), 0, rows - 1)

	# Search adjacent approach cells around goal
	var best_approach: Vector2i = Vector2i(-1, -1)
	var best_needed_drops: int = 999
	var best_approach_path: Array[Dictionary] = []

	const NEIGHBORS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	var max_room_carryables: int = int(solver_cfg.get(
		"max_room_carryables_cauldron" if room_id == 136 else "max_room_carryables_default",
		4
	))
	var room_active_carryables: int = (grid.get("items", []) as Array).size()

	for d: Vector2i in NEIGHBORS:
		var n: Vector2i = Vector2i(goal_c, goal_r) + d
		if n.x < 0 or n.x >= cols or n.y < 0 or n.y >= rows:
			continue
		var n_cell: Dictionary = cells[n.y][n.x] as Dictionary
		if bool(n_cell.get("blocked", false)) or bool(n_cell.get("lethal", false)):
			continue

		var approach_pos := Vector3((float(n.x) + 0.5) * cell_size, float(n_cell.get("surface_y", 0.0)), (float(n.y) + 0.5) * cell_size)
		var to_approach: Array[Dictionary] = find_local_path(grid, start_pos, approach_pos, current_jump)
		if to_approach.is_empty() and start_pos.distance_to(approach_pos) > cell_size:
			continue

		var vertical_gap: float = goal_pos.y - approach_pos.y
		var needed_drops: int = maxi(1, int(ceil((vertical_gap - current_jump) / drop_lift)))

		if needed_drops <= carried_items and (room_active_carryables + needed_drops) <= max_room_carryables:
			if needed_drops < best_needed_drops:
				best_needed_drops = needed_drops
				best_approach = n
				best_approach_path = to_approach

	if best_approach != Vector2i(-1, -1):
		var steps: Array[Dictionary] = []
		steps.append_array(best_approach_path)
		for drop_idx: int in range(best_needed_drops):
			steps.append({
				"action": &"drop_climb",
				"drop_index": drop_idx + 1,
				"lift_height": drop_lift
			})
		steps.append({
			"action": &"jump",
			"pos": goal_pos
		})
		return {
			"solvable": true,
			"strategy": &"drop_climb_staircase",
			"needed_drops": best_needed_drops,
			"steps": steps
		}

	# 4. Pushable Block Strategy
	var pushables: Array = grid.get("pushables", []) as Array
	for p_info: Dictionary in pushables:
		var p_pos: Vector3 = p_info["pos"] as Vector3
		var to_pushable: Array[Dictionary] = find_local_path(grid, start_pos, p_pos, current_jump)
		if not to_pushable.is_empty():
			return {
				"solvable": true,
				"strategy": &"push_block",
				"pushable_pos": p_pos,
				"steps": to_pushable + [
					{"action": &"push_to_target", "target": goal_pos},
					{"action": &"jump_onto_block"},
					{"action": &"jump", "pos": goal_pos}
				]
			}

	return {
		"solvable": false,
		"strategy": &"none",
		"reason": "Elevation unreachable with current items and form"
	}


func plan_cauldron_delivery(
	session: KnightLoreSession,
	player_pos: Vector3,
	grid: Dictionary,
	cauldron_center: Vector3
) -> Dictionary:
	var steps: Array[Dictionary] = []
	var req_type: int = session.get_next_required_charm()

	# If Werewolf, wait for Day/Human so Melkhior doesn't fire Repel Spells
	if session.is_wulf:
		steps.append({"action": &"wait_for_day"})

	# Inventory FIFO Rotation Planning
	# drop_or_rotate() drops inventory[2].
	var target_slot: int = -1
	for idx: int in range(session.inventory.size()):
		if session.inventory[idx] == req_type:
			target_slot = idx
			break

	if target_slot == -1:
		return {
			"solvable": false,
			"reason": "Required charm %d is not in inventory" % req_type
		}

	# If required item is in slot 0 or 1, compute how many cycles/rotations are needed
	var rotations_needed: int = 0
	if target_slot == 1:
		rotations_needed = 1
	elif target_slot == 0:
		rotations_needed = 2

	for r: int in range(rotations_needed):
		steps.append({
			"action": &"rotate_inventory",
			"rotation_step": r + 1
		})

	# Find throw approach tile adjacent to cauldron rim
	var approach_pos := cauldron_center + Vector3(0.0, 0.0, 1.35)
	var local_path: Array[Dictionary] = find_local_path(grid, player_pos, approach_pos, 1.35)
	if not local_path.is_empty():
		steps.append_array(local_path)
	else:
		steps.append({"action": &"walk", "pos": approach_pos})

	# Jump and drop into cauldron at apex
	var min_drop_y: float = float(solver_cfg.get("cauldron_drop_min_y_m", 0.65))
	steps.append({
		"action": &"jump_and_interact",
		"min_y": min_drop_y,
		"target": cauldron_center
	})

	return {
		"solvable": true,
		"steps": steps
	}
