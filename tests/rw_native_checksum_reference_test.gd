extends SceneTree
## 对照 OPEN-RW 连续同步帧中的单位字段和主校验值


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_NATIVE_REFERENCE")
	var checksum_path: String = OS.get_environment("RW_CHECKSUM_REFERENCE")
	assert(not reference_path.is_empty() and not checksum_path.is_empty())
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	var checksum_source: FileAccess = FileAccess.open(checksum_path, FileAccess.READ)
	assert(source != null and checksum_source != null)
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var speed_index: int = headers.find("speed")
	assert(speed_index >= 0)
	var max_frame: int = maxi(OS.get_environment("RW_CHECKSUM_FRAMES").to_int(), 100)
	var units_by_frame: Dictionary = {}
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		var frame: int = fields[0].to_int()
		if frame > max_frame:
			break
		if fields[speed_index].is_empty():
			continue
		var state: RwUnitState = RwUnitState.new()
		state.object_id = fields[2].to_int()
		state.world_position = Vector2(fields[5].to_float(), fields[6].to_float())
		state.body_rotation_degrees = fields[9].to_float()
		state.health = fields[11].to_float()
		state.order_type = fields[13]
		if not state.order_type.is_empty():
			state.order_target = Vector2(fields[14].to_float(), fields[15].to_float())
		if not units_by_frame.has(frame):
			units_by_frame[frame] = {}
		units_by_frame[frame][state.object_id] = state
	var checksum_headers: PackedStringArray = checksum_source.get_line().split("\t", true)
	var checked_frames: int
	var checked_units: int
	while not checksum_source.eof_reached():
		var line: String = checksum_source.get_line()
		if line.is_empty():
			continue
		var expected: PackedStringArray = line.split("\t", true)
		var frame: int = expected[0].to_int()
		if frame > max_frame:
			break
		var units: Dictionary = units_by_frame.get(frame, {})
		if units.is_empty():
			printerr("Missing checksum fixture frame %d" % frame)
			quit(1)
			return
		var actual: Dictionary = RwGameStateChecksum.calculate_unit_fields(units)
		for field_name: String in actual:
			if field_name == "UnitPaths" and frame > 1:
				continue
			var column: int = checksum_headers.find(field_name)
			assert(column >= 0)
			if int(actual[field_name]) != expected[column].to_int():
				printerr("Checksum mismatch frame=%d %s: expected=%s actual=%s" % [frame, field_name, expected[column], actual[field_name]])
				quit(1)
				return
		checked_frames += 1
		checked_units = units.size()
	assert(checked_frames == max_frame)
	print("NATIVE_CHECKSUM_REFERENCE_CHECK_OK frames=%d units=%d" % [checked_frames, checked_units])
	quit()
