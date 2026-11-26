class_name KnightLoreHintEngine
extends RefCounted
## Procedural and config-driven hint generator for Knight Lore chambers.
## Evaluates room geometry, elevated exits, active hazards, pushable objects,
## and quest states to deliver structured tactical guidance in Melkhior's voice.

const HINTS_FILE: String = "res://data/knight_lore/room_hints.json"

static var _cached_handcrafted: Dictionary = {}
static var _hints_loaded: bool = false


static func _ensure_hints_loaded() -> void:
	if _hints_loaded:
		return
	_hints_loaded = true
	var doc: Dictionary = RoomBuilder.load_json_dict(HINTS_FILE)
	if doc.has("hints"):
		_cached_handcrafted = doc["hints"] as Dictionary


static func get_room_hint(
	room_id: int,
	kl_data: KnightLoreData,
	session: KnightLoreSession = null
) -> Dictionary:
	_ensure_hints_loaded()

	var is_cauldron: bool = (room_id == 136)
	var is_forest: bool = kl_data.is_forest_room(room_id) if kl_data != null else false
	var room_data: Dictionary = kl_data.get_room(room_id) if kl_data != null else {}
	var exits: Dictionary = kl_data.get_room_exits(room_id) if kl_data != null else {}

	var elevated_exits: Array[String] = []
	var standard_exits: Array[String] = []
	for dir_name: String in exits.keys():
		var exit_info: Dictionary = exits[dir_name] as Dictionary
		if bool(exit_info.get("high", false)):
			elevated_exits.append(dir_name.capitalize())
		else:
			standard_exits.append(dir_name.capitalize())

	var foregrounds: Array = room_data.get("foregrounds", []) as Array
	var hazards_detected: Array[String] = []
	var pushables_detected: Array[String] = []
	var has_spikes: bool = false
	var has_dropping_blocks: bool = false
	var has_collapsing: bool = false
	var has_moving_blocks: bool = false
	var has_patrols: bool = false
	var has_gargoyles: bool = false
	var has_fire: bool = false

	for fg_v: Variant in foregrounds:
		var fg: Dictionary = fg_v as Dictionary
		var tname: String = str(fg.get("type_name", ""))
		match tname:
			"chest":
				if not pushables_detected.has("Sliding Chest"):
					pushables_detected.append("Sliding Chest")
			"table":
				if not pushables_detected.has("Heavy Table"):
					pushables_detected.append("Heavy Table")
			"moveable_block":
				if not pushables_detected.has("Moveable Block"):
					pushables_detected.append("Moveable Block")
			"spike":
				has_spikes = true
				if not hazards_detected.has("Razor Spikes"):
					hazards_detected.append("Razor Spikes")
			"dropping_block", "spike_ball_fall", "spike_ball_high_fall":
				has_dropping_blocks = true
				if not hazards_detected.has("Dropping Blocks / Spiked Balls"):
					hazards_detected.append("Dropping Blocks / Spiked Balls")
			"collapsing_block":
				has_collapsing = true
				if not hazards_detected.has("Collapsing Floor Tiles"):
					hazards_detected.append("Collapsing Floor Tiles")
			"block_ew", "block_ns":
				has_moving_blocks = true
				if not pushables_detected.has("Moving Platform Block"):
					pushables_detected.append("Moving Platform Block")
			"gargoyle":
				has_gargoyles = true
				if not hazards_detected.has("Stone Gargoyles"):
					hazards_detected.append("Stone Gargoyles")
			"fire_ew", "fire_ns":
				has_fire = true
				if not hazards_detected.has("Fires"):
					hazards_detected.append("Fires")
			"guard_ew", "guard_square", "ghost", "ball_bounce", "ball_ud", "ball_ud_x", "ball_ud_y", "ball_ud_xy":
				has_patrols = true
				if not hazards_detected.has("Patrol Guardians / Bouncing Mines"):
					hazards_detected.append("Patrol Guardians / Bouncing Mines")

	var has_special_spawn: bool = false
	if kl_data != null:
		for sp_v: Variant in kl_data.special_spawns:
			var sp: Dictionary = sp_v as Dictionary
			if int(sp.get("room_id", -1)) == room_id:
				has_special_spawn = true
				break

	# Check handcrafted override
	var rid_str: String = str(room_id)
	if _cached_handcrafted.has(rid_str):
		var base: Dictionary = (_cached_handcrafted[rid_str] as Dictionary).duplicate(true)
		base["room_id"] = room_id
		base["is_cauldron"] = is_cauldron
		base["is_forest"] = is_forest
		base["elevated_exits"] = elevated_exits
		base["standard_exits"] = standard_exits
		base["hazards_detected"] = hazards_detected
		base["pushables_detected"] = pushables_detected
		base["has_special_spawn"] = has_special_spawn

		# Dynamic cauldron active charm injection
		if is_cauldron and session != null and not session.quest_completed:
			var req_type: int = session.get_next_required_charm()
			var charm_name: String = session.get_charm_name(req_type)
			base["solution"] = "Melkhior currently requires the %s! Find it across the castle and cast it into the cauldron ([Shift] to drop)." % charm_name.to_upper()
		return base

	# Procedural generation for generic chambers
	var title: String = ""
	if is_forest:
		title = "Woodland Clearing (Room %d)" % room_id
	else:
		title = "Castle Chamber (Room %d)" % room_id

	var challenge_parts: Array[String] = []
	if elevated_exits.size() > 0:
		challenge_parts.append("Elevated high archway exit on the %s wall (3.0m elevation)" % ", ".join(elevated_exits))
	if has_spikes:
		challenge_parts.append("Lethal iron floor spikes covering ground paths")
	if has_dropping_blocks:
		challenge_parts.append("Overhead dropping blocks that fall when triggered")
	if has_patrols:
		challenge_parts.append("Moving sentinels or bouncing spheres patrolling the floor")
	if has_fire:
		challenge_parts.append("Flickering flame hazards traversing the stones")
	if challenge_parts.is_empty():
		challenge_parts.append("A connecting passageway through the %s" % ("forest" if is_forest else "dungeon"))

	var challenge: String = ". ".join(challenge_parts) + "."

	var solution_parts: Array[String] = []
	if elevated_exits.size() > 0:
		if pushables_detected.size() > 0:
			solution_parts.append("Push the %s toward the elevated %s arch to build steps" % [pushables_detected[0].to_lower(), ", ".join(elevated_exits)])
		elif has_moving_blocks:
			solution_parts.append("Wait for the moving block to reach its lowest apex, jump on top, and leap into the high arch")
		else:
			solution_parts.append("Scale surrounding stone perimeters or utilize high-reach jumps to access the %s doorway" % ", ".join(elevated_exits))
	else:
		solution_parts.append("Proceed carefully toward the %s exit portals" % (", ".join(standard_exits) if standard_exits.size() > 0 else "available"))

	if pushables_detected.has("Sliding Chest"):
		solution_parts.append("Chests slide when pushed until they contact an obstacle; jump onto them to gain height")
	if has_special_spawn:
		solution_parts.append("A sacred quest charm spawns in this room — inspect high platforms and corners")

	var solution: String = ". ".join(solution_parts) + "."

	var warning_parts: Array[String] = []
	if has_spikes:
		warning_parts.append("Touching floor spikes causes instant death; stay on solid blocks")
	if has_dropping_blocks:
		warning_parts.append("Do not pause under high arches; dropping blocks fall rapidly")
	if has_collapsing:
		warning_parts.append("Collapsing tiles give way after a half-second; keep moving across them")
	if has_gargoyles:
		warning_parts.append("Gargoyles are lethal to the touch; keep your distance")
	if warning_parts.is_empty():
		warning_parts.append("Watch your footing when jumping near open room edges")

	var warning: String = ". ".join(warning_parts) + "."

	var form_synergy: String = ""
	if elevated_exits.size() > 0:
		form_synergy = "Werewolf form gains +22% jump elevation (1.65m vs 1.35m), making high ledge reaches considerably easier."
	else:
		form_synergy = "Human form provides nimble horizontal control, while Werewolf form leaps farther across open floor gaps."

	return {
		"room_id": room_id,
		"title": title,
		"challenge": challenge,
		"solution": solution,
		"warning": warning,
		"form_synergy": form_synergy,
		"is_cauldron": is_cauldron,
		"is_forest": is_forest,
		"elevated_exits": elevated_exits,
		"standard_exits": standard_exits,
		"hazards_detected": hazards_detected,
		"pushables_detected": pushables_detected,
		"has_special_spawn": has_special_spawn
	}
