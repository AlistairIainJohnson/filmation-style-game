# tools/capture_frame.gd
# Usage (NEVER pass --headless):
#   godot --path . --resolution 1280x720 -s tools/capture_frame.gd -- res://game/rooms/smoke_scene.tscn _verify/smoke.png [settle_frames]
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -s tools/capture_frame.gd -- <scene_path> <output_png> [settle_frames]")
		quit(2)
		return

	var scene_path: String = args[0]
	var out_path: String = args[1]
	var settle_frames: int = int(args[2]) if args.size() >= 3 else 15

	var abs_out_path: String = ProjectSettings.globalize_path(out_path)
	if out_path.begins_with("/") == false and out_path.begins_with("res://") == false and out_path.begins_with("user://") == false:
		abs_out_path = ProjectSettings.globalize_path("res://" + out_path)
	var out_dir: String = abs_out_path.get_base_dir()
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_err != OK:
		push_error("Failed to create output directory %s: %s" % [out_dir, error_string(mkdir_err)])
		quit(1)
		return

	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("Failed to load scene: " + scene_path)
		quit(1)
		return

	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var instance: Node = packed.instantiate()
	root.add_child(instance)

	# Allow lighting, GI, and shadow maps to settle before GPU sync
	for _i: int in range(settle_frames):
		await process_frame
	await RenderingServer.frame_post_draw

	var viewport_tex: ViewportTexture = root.get_texture()
	var img: Image = viewport_tex.get_image() if viewport_tex != null else null
	if img == null or img.is_empty():
		push_error("Empty viewport image. Do NOT invoke with --headless; use macOS Metal or xvfb-run.")
		quit(1)
		return

	var save_err: Error = img.save_png(abs_out_path)
	if save_err != OK:
		push_error("save_png failed for %s: %s" % [abs_out_path, error_string(save_err)])
		quit(1)
		return

	print("Captured %dx%d -> %s" % [img.get_width(), img.get_height(), abs_out_path])
	quit(0)
