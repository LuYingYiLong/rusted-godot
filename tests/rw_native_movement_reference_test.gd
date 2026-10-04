extends SceneTree
## 对照 OPEN-RW 原生单位收到移动命令后的连续状态

const DEFAULT_UNIT_IDS: Array[int] = [8, 9, 23, 37,]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_NATIVE_REFERENCE")
	var output_path: String = OS.get_environment("RW_PROBE_PATH")
	assert(not reference_path.is_empty() and not output_path.is_empty())
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	assert(source != null)
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var declared_type_index: int = headers.find("declared_type")
	assert(declared_type_index >= 0)
	var unit_ids: Array[int] = DEFAULT_UNIT_IDS.duplicate()
	var selected_ids: String = OS.get_environment("RW_NATIVE_UNIT_IDS")
	if not selected_ids.is_empty():
		unit_ids.clear()
		for selected_id: String in selected_ids.split(",", false):
			unit_ids.append(selected_id.strip_edges().to_int())
	assert(not unit_ids.is_empty())
	var rows: Dictionary = {}
	var deltas: Dictionary = {}
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		var object_id: int = fields[2].to_int()
		if not unit_ids.has(object_id):
			continue
		var frame: int = fields[0].to_int()
		if not rows.has(frame):
			rows[frame] = {}
		rows[frame][object_id] = fields
		deltas[frame] = fields[1].to_float()
	var first_frame: Dictionary = rows.get(1, {})
	assert(first_frame.size() == unit_ids.size())
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var path_grid: RwPathGrid = RwPathGrid.load_map("[p2]Small_Island (2p).tmx")
	assert(path_grid != null)
	var use_godot_path: bool = OS.get_environment("RW_NATIVE_USE_GODOT_PATH") == "1"
	var units: Dictionary = {}
	var path_assigned: Dictionary = {}
	for object_id: int in unit_ids:
		var fields: PackedStringArray = first_frame[object_id]
		var declared_type: String = fields[declared_type_index]
		var effective_type: String = fields[3]
		var source_id: String = "custom" if effective_type != declared_type else "vanilla"
		var definition: RwUnitDefinition = registry.find_definition(source_id, effective_type)
		assert(definition != null, "Missing effective definition: %s" % effective_type)
		var state: RwUnitState = RwUnitState.new()
		state.initialize_from_spawn({
			"object_id": object_id,
			"source_id": source_id,
			"unit_name": effective_type,
			"team": fields[4],
			"position": Vector2(fields[5].to_float(), fields[6].to_float()),
		}, definition)
		assert(fields[13] == "move")
		state.apply_order("move", Vector2(fields[14].to_float(), fields[15].to_float()))
		units[object_id] = state
	var probe: RwBattleStateProbe = RwBattleStateProbe.new()
	var checksum_path: String = OS.get_environment("RW_NATIVE_CHECKSUM_OUTPUT")
	var checksum_output: FileAccess
	if not checksum_path.is_empty():
		checksum_output = FileAccess.open(checksum_path, FileAccess.WRITE)
		assert(checksum_output != null)
		checksum_output.store_line("frame\tid\tUnitPaths")
	var last_frame: int = rows.keys().max()
	for frame: int in range(1, last_frame + 1):
		var frame_rows: Dictionary = rows.get(frame, {})
		assert(frame_rows.size() == unit_ids.size())
		if frame >= 2:
			for object_id: int in unit_ids:
				if path_assigned.has(object_id):
					continue
				var state: RwUnitState = units[object_id]
				var fields: PackedStringArray = frame_rows[object_id]
				if fields[17].is_empty() or fields[18].is_empty():
					continue
				var target: Vector2 = Vector2(fields[14].to_float(), fields[15].to_float())
				var waypoint: Vector2 = Vector2(fields[17].to_float(), fields[18].to_float())
				var waypoints: Array[Vector2] = [waypoint,]
				if not waypoint.is_equal_approx(target):
					waypoints.append(target)
				if use_godot_path:
					waypoints = path_grid.find_path(state.world_position, target, state.movement_type)
				state.apply_move_order(target, waypoints)
				path_assigned[object_id] = true
		if frame > 2:
			for object_id: int in unit_ids:
				var state: RwUnitState = units[object_id]
				state.advance_movement(1, path_grid, deltas[frame])
		probe.capture(frame, deltas[frame], units)
		if checksum_output != null:
			for object_id: int in unit_ids:
				var checksum: Dictionary = RwGameStateChecksum.calculate_unit_fields({object_id: units[object_id],})
				checksum_output.store_line("%d\t%d\t%d" % [frame, object_id, int(checksum["UnitPaths"])])
	probe.close()
	if checksum_output != null:
		checksum_output.close()
	assert(FileAccess.file_exists(output_path))
	print("NATIVE_MOVEMENT_TRACE_WRITTEN frames=%d units=%d" % [last_frame, units.size()])
	quit()
