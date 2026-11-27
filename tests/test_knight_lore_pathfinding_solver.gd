extends GutTest
## Test suite for Knight Lore World Router (128-room graph A*) and
## Room Solver (2.5D nav-grid, drop-climb staircases, and cauldron delivery).

var kl_data: KnightLoreData
var session: KnightLoreSession
var builder: RoomBuilder
var router: KlWorldRouter
var solver: KlRoomSolver


func before_each() -> void:
	kl_data = KnightLoreData.load_default()
	session = KnightLoreSession.new()
	builder = RoomBuilder.new()
	router = KlWorldRouter.new(kl_data)
	solver = KlRoomSolver.new()


func test_world_router_connects_all_starts_to_cauldron() -> void:
	# Cauldron is Room 136; Start rooms are [47, 68, 143, 179]
	var cauldron_rid: int = 136
	var start_rooms: Array[int] = [47, 68, 143, 179]

	for start_rid: int in start_rooms:
		var path: Array[Dictionary] = router.find_room_path(start_rid, cauldron_rid)
		assert_gt(path.size(), 0, "Start room %d should have a valid path to Cauldron 136" % start_rid)
		assert_eq(path[0]["from_room"], start_rid, "Path should start at start_room %d" % start_rid)
		assert_eq(path[path.size() - 1]["to_room"], cauldron_rid, "Path should terminate at Cauldron 136")

		# Verify room-to-room neighbor integrity along each step
		for step: Dictionary in path:
			var u: int = int(step["from_room"])
			var v: int = int(step["to_room"])
			var dir_name: String = str(step["direction"])
			var expected_v: int = KnightLoreData.get_neighbor_room_id(u, dir_name)
			assert_eq(v, expected_v, "Step from %d via %s should equal %d" % [u, dir_name, expected_v])


func test_world_router_reaches_all_32_special_spawns() -> void:
	var cauldron_rid: int = 136
	var spawn_rooms: Dictionary = {}
	for sp_v: Variant in kl_data.special_spawns:
		var sp: Dictionary = sp_v as Dictionary
		var rid: int = int(sp.get("room_id", -1))
		if rid >= 0:
			spawn_rooms[rid] = true

	assert_gt(spawn_rooms.size(), 0, "Special spawns should be present in kl_data")

	for rid_v: Variant in spawn_rooms.keys():
		var rid: int = int(rid_v)
		var path_to: Array[Dictionary] = router.find_room_path(cauldron_rid, rid)
		var path_back: Array[Dictionary] = router.find_room_path(rid, cauldron_rid)

		if rid == cauldron_rid:
			continue
		assert_gt(path_to.size(), 0, "Cauldron should reach spawn room %d" % rid)
		assert_gt(path_back.size(), 0, "Spawn room %d should reach Cauldron" % rid)


func test_objective_planner_selects_nearest_charm_and_routes_to_cauldron() -> void:
	session.start_new_game(kl_data, 12345, 47)
	var req_charm: int = session.get_next_required_charm()
	assert_true(req_charm >= 0, "First required charm should be valid")

	var plan: Dictionary = router.plan_next_objective(session, kl_data)
	assert_eq(str(plan.get("goal_type", "")), "fetch_charm", "Should plan to fetch first charm")
	assert_eq(int(plan.get("charm_type", -1)), req_charm, "Planned charm must match required charm")
	var target_rid: int = int(plan.get("target_room", -1))
	assert_true(kl_data.has_room(target_rid), "Target room %d must exist" % target_rid)

	# Simulate picking up the charm into inventory
	session.inventory[0] = req_charm
	var plan_after_pickup: Dictionary = router.plan_next_objective(session, kl_data)
	assert_eq(str(plan_after_pickup.get("goal_type", "")), "deliver_cauldron", "Should plan to deliver to cauldron when carried")
	assert_eq(int(plan_after_pickup.get("target_room", -1)), 136, "Target should be Cauldron Room 136")


func test_room_solver_nav_grid_avoids_spikes_and_walls() -> void:
	var root := Node3D.new()
	add_child(root)

	# Build Room 47 (starting room with floor layout)
	var build: Dictionary = builder.build_knight_lore_room(root, 47, kl_data, "castle_stone_skylight", "true_isometric", false)
	assert_false(build.is_empty(), "Room 47 build should succeed")

	var room_dims: Vector3 = build["room_dims"] as Vector3
	var arch_root: Node3D = build["architecture_root"] as Node3D
	var ent_root: Node3D = build["entities_root"] as Node3D

	var grid: Dictionary = solver.build_nav_grid(room_dims, arch_root, ent_root)
	assert_eq(int(grid["cols"]), 16, "Room 47 should have 16 cols (8m / 0.5m)")
	assert_eq(int(grid["rows"]), 16, "Room 47 should have 16 rows (8m / 0.5m)")

	# Path from south portal threshold to north doorway
	var start_pos := Vector3(4.0, 0.0, 7.2)
	var goal_pos := Vector3(4.0, 0.0, 1.2)
	var local_path: Array[Dictionary] = solver.find_local_path(grid, start_pos, goal_pos, 1.35)

	assert_gt(local_path.size(), 0, "Room 47 should have a traversable path between doorway thresholds")

	# Check that no waypoint sits on a lethal hazard cell
	var cell_size: float = float(grid["cell_size"])
	var cells: Array = grid["cells"] as Array
	for wp: Dictionary in local_path:
		var p: Vector3 = wp["pos"] as Vector3
		var c_idx: int = clampi(int(floor(p.x / cell_size)), 0, 15)
		var r_idx: int = clampi(int(floor(p.z / cell_size)), 0, 15)
		var cell: Dictionary = cells[r_idx][c_idx] as Dictionary
		assert_false(bool(cell.get("lethal", false)), "Waypoint at (%.1f, %.1f) must not be lethal" % [p.x, p.z])

	root.free()


func test_room_solver_plans_drop_climb_for_room_168_pillar() -> void:
	var root := Node3D.new()
	add_child(root)

	# Room 168 contains a high stone pillar with native charm at y = 3.0m
	var build: Dictionary = builder.build_knight_lore_room(root, 168, kl_data, "castle_stone_skylight", "true_isometric", false)
	assert_false(build.is_empty(), "Room 168 build should succeed")

	var room_dims: Vector3 = build["room_dims"] as Vector3
	var arch_root: Node3D = build["architecture_root"] as Node3D
	var ent_root: Node3D = build["entities_root"] as Node3D

	var grid: Dictionary = solver.build_nav_grid(room_dims, arch_root, ent_root)

	var start_pos := Vector3(4.0, 0.0, 7.0)
	var pillar_goal := Vector3(6.5, 3.0, 5.5)

	# 1. Unsolvable with 0 carried items (goal is at 3.0m, human jump is 1.35m)
	var plan_0: Dictionary = solver.plan_room_puzzle(grid, start_pos, pillar_goal, {
		"is_wulf": false,
		"carried_items": 0,
		"room_id": 168
	})
	assert_false(bool(plan_0.get("solvable", false)), "Should be unsolvable with 0 items")

	# 2. Solvable with 3 carried charms using drop-climb staircase (+2.16m elevation)
	var plan_3: Dictionary = solver.plan_room_puzzle(grid, start_pos, pillar_goal, {
		"is_wulf": false,
		"carried_items": 3,
		"room_id": 168
	})
	assert_true(bool(plan_3.get("solvable", false)), "Should be solvable with 3 carried charms")
	assert_eq(str(plan_3.get("strategy", "")), "drop_climb_staircase", "Strategy should be drop_climb_staircase")
	assert_true(int(plan_3.get("needed_drops", 0)) <= 3, "Needed drops should not exceed 3 carried charms")

	var drop_actions: int = 0
	for step: Dictionary in (plan_3.get("steps", []) as Array):
		if str(step.get("action", "")) == "drop_climb":
			drop_actions += 1
	assert_gt(drop_actions, 0, "Plan must contain drop_climb actions")

	root.free()


func test_cauldron_delivery_plan_rotates_fifo_and_waits_for_day() -> void:
	session.start_new_game(kl_data, 12345, 136)
	var req_charm: int = session.get_next_required_charm()

	# Scenario A: Werewolf form -> should wait for Day
	session.is_wulf = true
	session.inventory = [req_charm, -1, -1] # item in slot 0 (needs 2 rotations to reach slot 2)

	var grid := {
		"room_dims": Vector3(8.0, 6.0, 8.0),
		"cell_size": 0.5,
		"cols": 16,
		"rows": 16,
		"cells": [],
		"items": [],
		"pushables": []
	}
	# Empty floor
	for r: int in range(16):
		var row_a: Array = []
		for c: int in range(16):
			row_a.append({"surface_y": 0.0, "blocked": false, "lethal": false, "penalty": 0.0})
		(grid["cells"] as Array).append(row_a)

	var cauldron_pos := Vector3(4.0, 0.95, 4.0)
	var player_pos := Vector3(4.0, 0.0, 1.5)

	var plan_night: Dictionary = solver.plan_cauldron_delivery(session, player_pos, grid, cauldron_pos)
	assert_true(bool(plan_night.get("solvable", false)), "Should find solvable delivery plan")

	var steps: Array = plan_night.get("steps", []) as Array
	assert_eq(str(steps[0].get("action", "")), "wait_for_day", "First action for Werewolf should be wait_for_day")

	var rotation_steps: int = 0
	var throw_found: bool = false
	for st_v: Variant in steps:
		var st: Dictionary = st_v as Dictionary
		if str(st.get("action", "")) == "rotate_inventory":
			rotation_steps += 1
		elif str(st.get("action", "")) == "jump_and_interact":
			throw_found = true
			assert_true(float(st.get("min_y", 0.0)) >= 0.65, "Throw must satisfy cauldron minimum elevation 0.65m")

	assert_eq(rotation_steps, 2, "Slot 0 requires 2 rotations to shift to slot 2 for dropping")
	assert_true(throw_found, "Must include jump_and_interact cauldron throw step")
