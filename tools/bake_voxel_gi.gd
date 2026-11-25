# tools/bake_voxel_gi.gd
# Usage (NEVER pass --headless — requires Metal/GPU renderer for VoxelGI.bake):
#   godot --path . --resolution 640x360 -s tools/bake_voxel_gi.gd [-- --kl-only | --rooms-only | --room=<id_or_stem> | --skip-existing]
extends SceneTree


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bake_voxel_gi.gd requires GPU/Metal renderer; do NOT pass --headless.")
		quit(2)
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var kl_only: bool = false
	var rooms_only: bool = false
	var skip_existing: bool = false
	var target_room: String = ""
	for arg: String in args:
		if arg == "--kl-only":
			kl_only = true
		elif arg == "--rooms-only":
			rooms_only = true
		elif arg == "--skip-existing":
			skip_existing = true
		elif arg.begins_with("--room="):
			target_room = arg.substr(7)

	for dir_res: String in ["res://data/knight_lore/voxel_gi", "res://data/rooms/voxel_gi"]:
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_res))
		if mk_err != OK:
			push_error("Failed to create GI directory %s: %s" % [dir_res, error_string(mk_err)])
			quit(1)
			return

	var start_ms: int = Time.get_ticks_msec()
	var builder := RoomBuilder.new()
	var baked_count: int = 0
	var skipped_count: int = 0

	if not rooms_only:
		var kl_data: KnightLoreData = KnightLoreData.load_default()
		if kl_data == null:
			push_error("Failed to load KnightLoreData")
			quit(1)
			return
		var kl_ids: Array[int] = kl_data.get_room_ids()
		for rid: int in kl_ids:
			if not target_room.is_empty() and target_room != str(rid):
				continue
			var out_path: String = DioramaLighting.get_knight_lore_gi_path(rid)
			if skip_existing and FileAccess.file_exists(out_path):
				skipped_count += 1
				continue
			var host := Node3D.new()
			host.name = "BakeHostKL_%03d" % rid
			root.add_child(host)
			var res: Dictionary = builder.build_knight_lore_room(host, rid, kl_data, "castle_stone_skylight", "true_isometric", true)
			await process_frame
			var lighting: DioramaLighting = res.get("lighting") as DioramaLighting
			var arch_root: Node = res.get("architecture_root") as Node
			var gi_data: VoxelGIData = lighting.bake_gi_offline(arch_root) if (lighting != null and arch_root != null) else null
			if gi_data == null:
				push_error("VoxelGI offline bake returned null for Knight Lore room %d" % rid)
				root.remove_child(host)
				host.free()
				quit(1)
				return
			var save_err: Error = ResourceSaver.save(gi_data, out_path, ResourceSaver.FLAG_COMPRESS)
			root.remove_child(host)
			host.free()
			if save_err != OK:
				push_error("Failed to save VoxelGIData %s: %s" % [out_path, error_string(save_err)])
				quit(1)
				return
			baked_count += 1
			if baked_count % 16 == 0:
				print("  Baked %d VoxelGIData resources so far (latest: %s)..." % [baked_count, out_path])

	if not kl_only:
		var rooms_dir_abs: String = ProjectSettings.globalize_path("res://data/rooms")
		var da: DirAccess = DirAccess.open(rooms_dir_abs)
		if da != null:
			var json_files: Array[String] = []
			da.list_dir_begin()
			var entry_name: String = da.get_next()
			while not entry_name.is_empty():
				if not da.current_is_dir() and entry_name.ends_with(".json"):
					json_files.append(entry_name)
				entry_name = da.get_next()
			da.list_dir_end()
			json_files.sort()

			for fname: String in json_files:
				var stem: String = fname.get_basename()
				if not target_room.is_empty() and target_room != stem:
					continue
				var json_path: String = "res://data/rooms/" + fname
				var out_path: String = DioramaLighting.get_room_json_gi_path(json_path)
				if skip_existing and FileAccess.file_exists(out_path):
					skipped_count += 1
					continue
				var host := Node3D.new()
				host.name = "BakeHost_" + stem
				root.add_child(host)
				var res: Dictionary = builder.build_room_from_path(host, json_path, "", "")
				await process_frame
				var lighting: DioramaLighting = res.get("lighting") as DioramaLighting
				var arch_root: Node = res.get("architecture_root") as Node
				var gi_data: VoxelGIData = lighting.bake_gi_offline(arch_root) if (lighting != null and arch_root != null) else null
				if gi_data == null:
					push_error("VoxelGI offline bake returned null for %s" % json_path)
					root.remove_child(host)
					host.free()
					quit(1)
					return
				var save_err: Error = ResourceSaver.save(gi_data, out_path, ResourceSaver.FLAG_COMPRESS)
				root.remove_child(host)
				host.free()
				if save_err != OK:
					push_error("Failed to save VoxelGIData %s: %s" % [out_path, error_string(save_err)])
					quit(1)
					return
				baked_count += 1

	var elapsed_sec: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
	print("Baked %d VoxelGIData resources (skipped %d) in %.2fs" % [baked_count, skipped_count, elapsed_sec])
	quit(0)
