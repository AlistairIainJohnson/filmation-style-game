# tools/render_audio_preview.gd
# Headless script validating that every orchestral music track, biome ambience loop,
# and acoustic SFX resource referenced by config JSON imports and loads cleanly in Godot.
extends SceneTree


func _initialize() -> void:
	print("==> Validating Orchestral Audio, Ambience & SFX Resources in Godot...")
	var audio_mgr := ZxAudioManager.new()
	root.add_child(audio_mgr)

	var score_seq := KlScoreSequencer.new(audio_mgr)
	root.add_child(score_seq)

	var amb_dir := KlAmbienceDirector.new(audio_mgr)
	root.add_child(amb_dir)
	await process_frame

	var errors: int = 0

	# 1. Verify all orchestral score cues load with valid length
	var cues: Dictionary = score_seq._score_cfg.get("cues", {}) as Dictionary
	for cue_name: Variant in cues.keys():
		var c_dict: Dictionary = cues[cue_name] as Dictionary
		var sp: String = str(c_dict.get("stream", ""))
		var st: AudioStream = ResourceLoader.load(sp) as AudioStream
		if st == null or st.get_length() <= 0.1:
			push_error("Invalid or empty orchestral cue '%s': %s" % [str(cue_name), sp])
			errors += 1
		else:
			print("  [OK] Cue '%s' -> %s (%.2fs)" % [str(cue_name), sp.get_file(), st.get_length()])

	# 2. Verify biome ambience loops and acoustics
	for biome_id: String in ["dungeon", "woodland"]:
		audio_mgr.apply_biome(biome_id, false)
		amb_dir.set_biome(biome_id)
		for is_n: bool in [false, true]:
			amb_dir.set_cycle(is_n)
			var ap: String = amb_dir.get_active_stream_path()
			var ast: AudioStream = ResourceLoader.load(ap) as AudioStream
			if ast == null or ast.get_length() <= 1.0:
				push_error("Invalid ambience loop for %s/%s: %s" % [biome_id, "night" if is_n else "day", ap])
				errors += 1
		print("  [OK] Biome '%s' acoustics + day/night ambience verified" % biome_id)

	# 3. Verify all configured SFX event streams
	var events: Dictionary = audio_mgr._soundscapes_cfg.get("sfx_events", {}) as Dictionary
	var sfx_count: int = 0
	for ev_name: Variant in events.keys():
		var ed: Dictionary = events[ev_name] as Dictionary
		var paths: Array = []
		paths.append_array(ed.get("streams", []) as Array)
		var bmap: Dictionary = ed.get("biome_streams", {}) as Dictionary
		for bk: Variant in bmap.keys():
			paths.append_array(bmap[bk] as Array)
		for sp_v: Variant in paths:
			var sp: String = str(sp_v)
			var sst: AudioStream = ResourceLoader.load(sp) as AudioStream
			if sst == null or sst.get_length() <= 0.01:
				push_error("Invalid SFX stream for '%s': %s" % [str(ev_name), sp])
				errors += 1
			else:
				sfx_count += 1
	print("  [OK] %d SFX event stream references validated" % sfx_count)
	if sfx_count < 15:
		push_error("Expected >= 15 SFX streams configured, got %d" % sfx_count)
		errors += 1

	# Clean up explicitly to prevent ObjectDB leaks
	amb_dir.queue_free()
	score_seq.queue_free()
	audio_mgr.queue_free()
	await process_frame

	if errors > 0:
		quit(1)
		return
	print("==> Audio Resource Verification Complete!")
	quit(0)
