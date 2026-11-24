class_name PuzzleEntity3D
extends Node3D
## Base class and shared persistence/trigger contract for all Filmation puzzle entities.

const GROUP_NAME: StringName = &"puzzle_entities"

@export var entity_id: String = ""
@export var archetype: String = ""
@export var persistent: bool = true


func _ready() -> void:
	add_to_group(GROUP_NAME)


func serialize_state() -> Dictionary:
	return {
		"entity_id": entity_id,
		"archetype": archetype,
		"pos": [global_position.x, global_position.y, global_position.z]
	}


func hydrate_state(data: Dictionary) -> void:
	if data.has("pos"):
		var p: Variant = data["pos"]
		if p is Array and p.size() >= 3:
			global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))


func on_trigger_changed(_active: bool) -> void:
	pass


static func serialize_node(node: Node) -> Dictionary:
	if node.has_method("serialize_state"):
		return node.call("serialize_state") as Dictionary
	return {}


static func hydrate_node(node: Node, data: Dictionary) -> void:
	if node.has_method("hydrate_state"):
		node.call("hydrate_state", data)
