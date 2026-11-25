class_name KnightLoreData
extends RefCounted
## Loads the pre-decoded 128-room Knight Lore JSON dataset and converts
## 8-bit Z-up coordinates (16 units = 1.0m) into room-local Godot Y-up space.

const DATA_DIR: String = "res://data/knight_lore"
const UNITS_PER_METER: float = 16.0
const ROOM_CENTER_XY: float = 128.0
const ROOM_FLOOR_Z: float = 128.0
const ROOM_WALL_HEIGHT_M: float = 6.0

static var _cached_default: KnightLoreData

var rooms_meta: Dictionary = {}
var rooms: Dictionary = {}
var special_spawns: Array = []
var room_sizes: Dictionary = {}
var backgrounds: Dictionary = {}
var entities_cfg: Dictionary = {}
var audio_cfg: Dictionary = {}
var ui_cfg: Dictionary = {}

var _sorted_room_ids: Array[int] = []


static func load_default() -> KnightLoreData:
	if _cached_default != null and not _cached_default.rooms.is_empty():
		return _cached_default
	var inst := KnightLoreData.new()
	if inst.load_from_dir(DATA_DIR):
		_cached_default = inst
	return inst


func load_from_dir(dir_path: String = DATA_DIR) -> bool:
	var rooms_doc: Dictionary = RoomBuilder.load_json_dict(dir_path.path_join("rooms.json"))
	var bgs_doc: Dictionary = RoomBuilder.load_json_dict(dir_path.path_join("backgrounds.json"))
	entities_cfg = RoomBuilder.load_json_dict(dir_path.path_join("entities.json"))
	audio_cfg = RoomBuilder.load_json_dict(dir_path.path_join("audio.json"))
	ui_cfg = RoomBuilder.load_json_dict(dir_path.path_join("strings_and_ui.json"))

	if rooms_doc.is_empty() or bgs_doc.is_empty() or entities_cfg.is_empty():
		return false

	rooms_meta = rooms_doc.get("metadata", {}) as Dictionary
	rooms = rooms_doc.get("rooms", {}) as Dictionary
	special_spawns = rooms_doc.get("special_object_spawns", []) as Array
	room_sizes = bgs_doc.get("room_sizes", {}) as Dictionary
	backgrounds = bgs_doc.get("backgrounds", {}) as Dictionary

	_sorted_room_ids.clear()
	for k: Variant in rooms.keys():
		_sorted_room_ids.append(int(str(k)))
	_sorted_room_ids.sort()
	return not rooms.is_empty()


func has_room(room_id: int) -> bool:
	return rooms.has(str(room_id))


func get_room(room_id: int) -> Dictionary:
	return rooms.get(str(room_id), {}) as Dictionary


func get_room_ids() -> Array[int]:
	return _sorted_room_ids.duplicate()


func get_room_dims_meters(room_id: int) -> Vector3:
	var room: Dictionary = get_room(room_id)
	if room.is_empty():
		return Vector3(8.0, ROOM_WALL_HEIGHT_M, 8.0)
	var half_x: float = float(room.get("half_x", 64))
	var half_y: float = float(room.get("half_y", 64))
	return Vector3((half_x * 2.0) / UNITS_PER_METER, ROOM_WALL_HEIGHT_M, (half_y * 2.0) / UNITS_PER_METER)


func is_forest_room(room_id: int) -> bool:
	var room: Dictionary = get_room(room_id)
	var bg_names: Array = room.get("background_names", []) as Array
	return bg_names.has("tree_room_size_1")


func get_background_objects(bg_id: int) -> Array:
	var entry: Dictionary = backgrounds.get(str(bg_id), {}) as Dictionary
	return entry.get("objects", []) as Array


func get_room_exits(room_id: int) -> Dictionary:
	var room: Dictionary = get_room(room_id)
	var exits: Dictionary = {}
	if room.is_empty():
		return exits

	var src_forest: bool = is_forest_room(room_id)
	for bg_name_v: Variant in (room.get("background_names", []) as Array):
		var bg_name: String = str(bg_name_v)
		if bg_name.ends_with("_base") or bg_name.contains("filler"):
			continue
		var is_high: bool = bg_name.begins_with("high_arch_")
		var is_tree: bool = bg_name.begins_with("tree_arch_")
		if not (bg_name.begins_with("arch_") or is_high or is_tree):
			continue
		var suffix: String = bg_name.right(2)
		var dir_name: String = ""
		match suffix:
			"_n":
				dir_name = "north"
			"_s":
				dir_name = "south"
			"_e":
				dir_name = "east"
			"_w":
				dir_name = "west"
		if dir_name.is_empty():
			continue
		var target_rid: int = get_neighbor_room_id(room_id, dir_name)
		var target_exists: bool = has_room(target_rid)
		var dst_forest: bool = target_exists and is_forest_room(target_rid)
		exits[dir_name] = {
			"target_room_id": target_rid,
			"high": is_high,
			"tree": is_tree,
			"target_is_forest": dst_forest,
			"biome_transition": target_exists and (src_forest != dst_forest),
			"elevation_m": 3.0 if is_high else 0.0,
			"template": bg_name
		}
	return exits


static func get_neighbor_room_id(room_id: int, dir_name: String) -> int:
	match dir_name:
		"west":
			return (room_id & 0xF0) | ((room_id - 1) & 0x0F)
		"east":
			return (room_id & 0xF0) | ((room_id + 1) & 0x0F)
		"north":
			return (room_id + 16) & 0xFF
		"south":
			return (room_id - 16) & 0xFF
	return room_id


static func kl_to_room_pos(
	kl_x: float,
	kl_y: float,
	kl_z: float,
	half_x: float = 64.0,
	half_y: float = 64.0,
	floor_z: float = ROOM_FLOOR_Z
) -> Vector3:
	return Vector3(
		(kl_x - (ROOM_CENTER_XY - half_x)) / UNITS_PER_METER,
		(kl_z - floor_z) / UNITS_PER_METER,
		((ROOM_CENTER_XY + half_y) - kl_y) / UNITS_PER_METER
	)


static func kl_size_to_meters(half_w: float, half_d: float, full_h: float) -> Vector3:
	return Vector3(
		maxf(0.05, (half_w * 2.0) / UNITS_PER_METER),
		maxf(0.05, full_h / UNITS_PER_METER),
		maxf(0.05, (half_d * 2.0) / UNITS_PER_METER)
	)


static func get_subtle_room_tint(ink_color_name: String) -> Color:
	match ink_color_name:
		"Yellow":
			return Color(1.04, 1.00, 0.91, 1.0)
		"Green":
			return Color(0.91, 1.02, 0.93, 1.0)
		"Cyan":
			return Color(0.90, 0.99, 1.04, 1.0)
		"Magenta":
			return Color(1.02, 0.93, 1.02, 1.0)
	return Color(1.0, 1.0, 1.0, 1.0)
