extends Node3D
## Entry scene bootstrapping WorldManager and loading the configured starting chamber.

@export var world_graph_path: String = "res://data/world_graph.json"

var room_container: Node3D


func _ready() -> void:
	room_container = Node3D.new()
	room_container.name = "RoomContainer"
	add_child(room_container)

	var wm: WorldManagerNode = get_node("/root/WorldManager") as WorldManagerNode
	wm.reset_world_state()
	wm.set_room_container(room_container)
	if not wm.load_world_manifest(world_graph_path):
		push_error("MainGame: Failed to load world manifest: " + world_graph_path)
		return

	var start_arr: Array = wm.world_config.get("start_room", [8, 8]) as Array
	var start_room := Vector2i(int(start_arr[0]), int(start_arr[1]))
	var start_spawn: String = str(wm.world_config.get("start_spawn", "north"))

	var env_room: String = OS.get_environment("FILMATION_START_ROOM")
	if not env_room.is_empty():
		var parts: PackedStringArray = env_room.split(",")
		if parts.size() == 2:
			start_room = Vector2i(int(parts[0]), int(parts[1]))
			start_spawn = ""

	wm.load_room(start_room, start_spawn)
