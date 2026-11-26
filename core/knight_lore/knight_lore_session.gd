class_name KnightLoreSession
extends RefCounted
## Pure Knight Lore rules engine: 3-slot rotating FIFO inventory & drop-climb,
## 32 world item spawns, Room 136 Cauldron 14-charm sequence, 40-day Sun/Moon
## Sabreman/Wulf transformation cycle, lives/respawn, and quest rating.

signal inventory_changed(slots: Array)
signal cycle_updated(day_count: int, is_night: bool, progress: float)
signal transform_requested(to_wulf: bool)
signal form_changed(is_wulf: bool)
signal lives_changed(lives: int)
signal charm_accepted(charm_type: int, collected: int, total: int)
signal charm_rejected(charm_type: int)
signal extra_life_gained(lives: int)
signal quest_won()
signal game_over_triggered(reason: String)

const ITEM_NAMES: Array[String] = [
	"Diamond",
	"Poison",
	"Boot",
	"Chalice",
	"Cup",
	"Bottle",
	"Crystal Ball",
	"Extra Life"
]

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

const ITEM_COLORS: Array[Color] = [
	Color(1.0, 0.18, 0.18, 1.0),   # 0: Diamond (Red)
	Color(0.95, 0.25, 0.95, 1.0),  # 1: Poison (Magenta)
	Color(0.25, 0.95, 0.30, 1.0),  # 2: Boot (Green)
	Color(0.20, 0.95, 0.98, 1.0),  # 3: Chalice (Cyan)
	Color(1.0, 0.92, 0.20, 1.0),   # 4: Cup (Yellow)
	Color(0.92, 0.94, 0.98, 1.0),  # 5: Bottle (White)
	Color(1.0, 0.28, 0.28, 1.0),   # 6: Crystal Ball (Red)
	Color(1.0, 0.95, 0.55, 1.0)    # 7: Extra Life (Gold/White)
]

const CAULDRON_ROOM_ID: int = 136
const TOTAL_CHARMS_REQUIRED: int = 14
const MAX_DAYS: int = 40
const STARTING_LIVES: int = 5
const DEFAULT_START_ROOMS: Array[int] = [47, 68, 143, 179]

var kl_data: KnightLoreData
var half_day_duration_sec: float = 28.0
var required_sequence: Array[int] = []
var world_items: Array[Dictionary] = []
var current_room_id: int = 47
var visited_rooms: Dictionary = {}

var lives: int = STARTING_LIVES
var day_count: int = 1
var is_night: bool = false
var is_wulf: bool = false
var half_day_progress: float = 0.0
var pending_transform: bool = false
var disable_spike_ball_drop: bool = false

var inventory: Array[int] = [-1, -1, -1]
var charms_collected: int = 0
var quest_completed: bool = false
var game_over: bool = false

var _next_item_id: int = 100
var _ratings_cfg: Array = []


func start_new_game(data: KnightLoreData, rng_seed: int = -1, override_start_room: int = -1) -> void:
	kl_data = data
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	var sim: Dictionary = kl_data.entities_cfg.get("simulation_constants", {}) as Dictionary
	var ui_hud: Dictionary = kl_data.ui_cfg.get("hud", {}) as Dictionary
	var base_seq: Array = sim.get("cauldron_required_base_sequence", [0, 1, 2, 3, 4, 5, 6, 3, 5, 0, 6, 1, 2, 4]) as Array
	var min_rot: int = int(sim.get("cauldron_shuffle_min_rotations", 4))
	var max_rot: int = int(sim.get("cauldron_shuffle_max_rotations", 7))
	var rot: int = rng.randi_range(mini(min_rot, max_rot), maxi(min_rot, max_rot))
	required_sequence.clear()
	if not base_seq.is_empty():
		for i: int in range(base_seq.size()):
			required_sequence.append(int(base_seq[(i + rot) % base_seq.size()]))

	world_items.clear()
	var offset: int = rng.randi_range(0, 7)
	var max_idx: int = -1
	for idx: int in range(kl_data.special_spawns.size()):
		var sp_v: Variant = kl_data.special_spawns[idx]
		if not (sp_v is Dictionary):
			continue
		var sp: Dictionary = sp_v as Dictionary
		var sp_id: int = int(sp.get("index", idx))
		max_idx = maxi(max_idx, sp_id)
		var sp_room_id: int = int(sp.get("room_id", -1))
		var room: Dictionary = kl_data.get_room(sp_room_id)
		var half_x: float = float(room.get("half_x", 64))
		var half_y: float = float(room.get("half_y", 64))
		var floor_z: float = float(room.get("floor_z", 128))
		var pos: Vector3 = KnightLoreData.kl_to_room_pos(float(sp.get("x", 128)), float(sp.get("y", 128)), float(sp.get("z", 128)), half_x, half_y, floor_z)
		world_items.append({
			"id": sp_id,
			"type_id": (offset + idx) % 8,
			"room_id": sp_room_id,
			"pos": pos,
			"active": true
		})
	_next_item_id = max_idx + 10

	var start_rooms: Array = kl_data.rooms_meta.get("start_rooms", DEFAULT_START_ROOMS) as Array
	if override_start_room >= 0 and kl_data.has_room(override_start_room):
		current_room_id = override_start_room
	elif not start_rooms.is_empty():
		current_room_id = int(start_rooms[rng.randi_range(0, start_rooms.size() - 1)])
	else:
		current_room_id = 47

	lives = int(ui_hud.get("starting_lives_total", STARTING_LIVES))
	day_count = 1
	is_night = false
	is_wulf = false
	half_day_progress = 0.0
	pending_transform = false
	disable_spike_ball_drop = false
	inventory = [-1, -1, -1]
	charms_collected = 0
	quest_completed = false
	game_over = false
	visited_rooms.clear()

	var go_cfg: Dictionary = kl_data.ui_cfg.get("game_over_screen", {}) as Dictionary
	_ratings_cfg = go_cfg.get("ratings", []) as Array

	enter_room(current_room_id, "")
	inventory_changed.emit(inventory.duplicate())
	lives_changed.emit(lives)
	cycle_updated.emit(day_count, is_night, half_day_progress)


func enter_room(room_id: int, _from_dir: String = "") -> void:
	current_room_id = room_id
	visited_rooms[room_id] = true
	disable_spike_ball_drop = false


func get_room_items(room_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in world_items:
		if bool(entry.get("active", false)) and int(entry.get("room_id", -1)) == room_id:
			out.append(entry)
	return out


func save_room_item_positions(room_id: int, pos_by_id: Dictionary) -> void:
	for entry: Dictionary in world_items:
		var iid: int = int(entry.get("id", -1))
		if int(entry.get("room_id", -1)) == room_id and pos_by_id.has(iid):
			entry["pos"] = pos_by_id[iid]


func get_next_required_charm() -> int:
	if charms_collected >= required_sequence.size():
		return -1
	return required_sequence[charms_collected]


static func get_charm_name(type_id: int) -> String:
	if type_id >= 0 and type_id < ITEM_NAMES.size():
		return ITEM_NAMES[type_id]
	return "Empty"


static func get_charm_color(type_id: int) -> Color:
	if type_id >= 0 and type_id < ITEM_COLORS.size():
		return ITEM_COLORS[type_id]
	return Color(0.35, 0.35, 0.40, 1.0)


static func get_charm_glb_path(type_id: int) -> String:
	if type_id >= 0 and type_id < ITEM_GLBS.size():
		return ITEM_GLBS[type_id]
	return ITEM_GLBS[0]


func _find_item_index(item_id: int) -> int:
	for i: int in range(world_items.size()):
		if int(world_items[i].get("id", -1)) == item_id:
			return i
	return -1


func _spawn_item_record(type_id: int, room_id: int, pos: Vector3, active: bool) -> Dictionary:
	var iid: int = _next_item_id
	_next_item_id += 1
	var entry := {
		"id": iid,
		"type_id": type_id,
		"room_id": room_id,
		"pos": pos,
		"active": active
	}
	world_items.append(entry)
	return entry


func pickup_item(item_id: int, overflow_drop_pos: Vector3) -> Dictionary:
	var idx: int = _find_item_index(item_id)
	if idx == -1:
		return {"ok": false}
	var entry: Dictionary = world_items[idx]
	if not bool(entry.get("active", false)):
		return {"ok": false}
	var type_id: int = int(entry.get("type_id", 0))
	if type_id >= 7:
		return {"ok": false}

	var room_id: int = int(entry.get("room_id", current_room_id))
	disable_spike_ball_drop = false
	entry["active"] = false
	entry["room_id"] = -1

	var displaced_type: int = inventory[2]
	inventory[2] = inventory[1]
	inventory[1] = inventory[0]
	inventory[0] = type_id

	var displaced_record: Dictionary = {}
	if displaced_type >= 0:
		displaced_record = _spawn_item_record(displaced_type, room_id, overflow_drop_pos, true)

	inventory_changed.emit(inventory.duplicate())
	return {
		"ok": true,
		"picked_type": type_id,
		"displaced_item": displaced_record
	}


func drop_or_rotate(room_id: int, drop_pos: Vector3, headroom_clear: bool) -> Dictionary:
	var drop_type: int = inventory[2]
	if drop_type < 0:
		inventory[2] = inventory[1]
		inventory[1] = inventory[0]
		inventory[0] = -1
		inventory_changed.emit(inventory.duplicate())
		return {"action": "rotated", "dropped_item": {}, "is_cauldron_drop": false}

	var active_carryables: int = 0
	for entry: Dictionary in get_room_items(room_id):
		if int(entry.get("type_id", 0)) < 7:
			active_carryables += 1
	var max_allowed: int = 1 if room_id == CAULDRON_ROOM_ID else 2
	if active_carryables >= max_allowed:
		return {"action": "room_full", "dropped_item": {}, "is_cauldron_drop": false}

	if not headroom_clear:
		return {"action": "blocked_headroom", "dropped_item": {}, "is_cauldron_drop": false}

	var is_cauldron_drop: bool = (room_id == CAULDRON_ROOM_ID and drop_pos.y >= 0.65)
	inventory[2] = inventory[1]
	inventory[1] = inventory[0]
	inventory[0] = -1

	var spawned: Dictionary = _spawn_item_record(drop_type, room_id, drop_pos, not is_cauldron_drop)
	inventory_changed.emit(inventory.duplicate())
	return {
		"action": "dropped",
		"dropped_item": spawned,
		"is_cauldron_drop": is_cauldron_drop
	}


func resolve_cauldron_item(type_id: int) -> Dictionary:
	if quest_completed or charms_collected >= required_sequence.size():
		return {"accepted": false, "victory": quest_completed, "collected": charms_collected}
	var expected: int = required_sequence[charms_collected]
	if type_id == expected:
		charms_collected += 1
		charm_accepted.emit(type_id, charms_collected, TOTAL_CHARMS_REQUIRED)
		if charms_collected >= TOTAL_CHARMS_REQUIRED:
			quest_completed = true
			quest_won.emit()
		return {"accepted": true, "victory": quest_completed, "collected": charms_collected}
	charm_rejected.emit(type_id)
	return {"accepted": false, "victory": false, "expected": expected}


func collect_extra_life(item_id: int) -> bool:
	var idx: int = _find_item_index(item_id)
	if idx == -1:
		return false
	var entry: Dictionary = world_items[idx]
	if not bool(entry.get("active", false)) or int(entry.get("type_id", -1)) != 7:
		return false
	entry["active"] = false
	entry["room_id"] = -1
	lives += 1
	disable_spike_ball_drop = false
	lives_changed.emit(lives)
	extra_life_gained.emit(lives)
	return true


func advance_cycle(delta: float) -> void:
	if quest_completed or game_over or delta <= 0.0:
		return
	half_day_progress += delta / maxf(half_day_duration_sec, 0.1)
	while half_day_progress >= 1.0:
		half_day_progress -= 1.0
		is_night = not is_night
		if not is_night:
			day_count += 1
			if day_count >= MAX_DAYS:
				day_count = MAX_DAYS
				half_day_progress = 0.0
				game_over = true
				cycle_updated.emit(day_count, is_night, half_day_progress)
				game_over_triggered.emit("40 DAYS ELAPSED")
				return
		var target_wulf: bool = is_night
		if target_wulf != is_wulf:
			pending_transform = true
			transform_requested.emit(target_wulf)
	cycle_updated.emit(day_count, is_night, half_day_progress)


func complete_transformation() -> bool:
	is_wulf = is_night
	pending_transform = false
	form_changed.emit(is_wulf)
	return is_wulf


func apply_player_death() -> Dictionary:
	if game_over or quest_completed:
		return {"game_over": game_over, "lives": maxi(lives, 0)}
	lives -= 1
	pending_transform = false
	is_wulf = is_night
	if lives < 0:
		lives = 0
		game_over = true
		lives_changed.emit(0)
		form_changed.emit(is_wulf)
		game_over_triggered.emit("OUT OF LIVES")
		return {"game_over": true, "lives": 0}
	lives_changed.emit(lives)
	form_changed.emit(is_wulf)
	return {"game_over": false, "lives": lives}


func get_quest_percent() -> int:
	return int(round(float(visited_rooms.size() + 2 * charms_collected) / 156.0 * 100.0))


func get_rating_label() -> String:
	var rooms_cnt: int = maxi(visited_rooms.size(), 1)
	var rating_idx: int = (((rooms_cnt - 1) >> 5) & 0x06) | int(quest_completed)
	for r_v: Variant in _ratings_cfg:
		if r_v is Dictionary and int((r_v as Dictionary).get("index", -1)) == rating_idx:
			return str((r_v as Dictionary).get("label", "POOR"))
	const FALLBACK: Array[String] = ["POOR", "AVERAGE", "FAIR", "GOOD", "EXCELLENT", "MARVELLOUS", "HERO", "ADVENTURER"]
	return FALLBACK[clampi(rating_idx, 0, FALLBACK.size() - 1)]
