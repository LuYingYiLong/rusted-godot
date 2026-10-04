extends SceneTree
## 重放已记录的原版房间命令并定位首个联机校验差异

const BATTLE_MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"
const DEFAULT_TARGET_FRAME: int = 602

var _target_frame: int = DEFAULT_TARGET_FRAME


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var requested_frame: int = OS.get_environment("RW_REPLAY_TARGET_FRAME").to_int()
	if requested_frame > 0:
		_target_frame = requested_frame
	var report_path: String = OS.get_environment("RW_SOAK_REPORT_PATH")
	if report_path.is_empty():
		push_error("RW_SOAK_REPORT_PATH is required")
		quit(1)
		return
	var report: Dictionary = _read_report(report_path)
	if not report.has("server_fields"):
		push_error("The report has no checksum at frame %d" % _target_frame)
		quit(1)
		return
	var offline_fields: Dictionary = _replay(report["commands_by_frame"], false)
	var network_fields: Dictionary = _replay(report["commands_by_frame"], true)
	var server_fields: Dictionary = report["server_fields"]
	if OS.get_environment("RW_REPLAY_EXPECT_MAIN_MATCH") == "1":
		assert(int(network_fields["checksum"]) == int(server_fields["checksum"]))
	if _target_frame == DEFAULT_TARGET_FRAME and not (report["commands_by_frame"] as Dictionary).is_empty():
		assert(int(network_fields["UnitPaths"]) == int(server_fields["unit_paths"]))
		assert(absi(int(network_fields["checksum"]) - int(server_fields["checksum"])) < absi(int(offline_fields["checksum"]) - int(server_fields["checksum"])))
	for field: String in ["checksum", "Unit Pos", "Unit Dir", "Unit Hp", "Unit Id", "UnitPaths", "Waypoints", "Waypoints Pos",]:
		var server_key: String = field.to_snake_case()
		if field == "Waypoints Pos":
			server_key = "waypoint_pos"
		print("ONLINE_REPLAY field=%s server=%s offline=%s network=%s" % [
			field,
			server_fields.get(server_key, "missing"),
			offline_fields.get(field, "missing"),
			network_fields.get(field, "missing"),
		])
	quit(0)


func _read_report(path: String) -> Dictionary:
	var source: FileAccess = FileAccess.open(path, FileAccess.READ)
	if source == null:
		return {}
	var commands_by_frame: Dictionary = {}
	var server_fields: Dictionary = {}
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		var record: Dictionary = parsed
		var frame: int = int(record.get("frame", -1))
		if frame > _target_frame:
			continue
		if record.get("event", "") == "checksum_unit_mismatch" and frame == _target_frame:
			server_fields = record.get("server_fields", {})
			server_fields["checksum"] = int(record.get("server_checksum", 0))
		if record.get("event", "") != "commands":
			continue
		var commands: Array[Dictionary] = []
		for raw_command: Dictionary in record.get("commands", []):
			var command: Dictionary = raw_command.duplicate()
			command["target"] = _parse_vector(str(command.get("target", "")))
			var target_metadata: Dictionary = {}
			for unit_id: String in command.get("command_targets", {}):
				var metadata: Dictionary = command["command_targets"][unit_id].duplicate()
				metadata["start_position"] = _parse_vector(str(metadata.get("start_position", "")))
				metadata["target_position"] = _parse_vector(str(metadata.get("target_position", "")))
				var cells: Array[Vector2i] = []
				for cell: String in metadata.get("path", []):
					var point: Vector2 = _parse_vector(cell)
					cells.append(Vector2i(int(point.x), int(point.y)))
				metadata["path"] = cells
				target_metadata[int(unit_id)] = metadata
			command["command_targets"] = target_metadata
			commands.append(command)
		commands_by_frame[frame] = commands
	return {"commands_by_frame": commands_by_frame, "server_fields": server_fields,}


func _parse_vector(value: String) -> Vector2:
	var components: PackedStringArray = value.trim_prefix("(").trim_suffix(")").split(",")
	if components.size() != 2:
		return Vector2.ZERO
	return Vector2(components[0].strip_edges().to_float(), components[1].strip_edges().to_float())


func _replay(commands_by_frame: Dictionary, network_paths: bool) -> Dictionary:
	var room: Node = get_root().get_node("RwRoomClient")
	var players: Array[Dictionary] = [
		{"slot": 0, "name": "Host", "credits": 200000.0, "spectator": false,},
		{"slot": 1, "name": "Guest", "credits": 200000.0, "spectator": false,},
	]
	room.set("players", players)
	room.set("local_slot", 1)
	room.set("settings", {"fog": 2, "revealed": true, "starting_units": 1,})
	room.set("battle_map_info", {"map": "[p2]Small_Island (2p).tmx",})
	room.get("battle_economy").initialize(players, 1.0)
	var map: Control = (load(BATTLE_MAP_SCENE_UID) as PackedScene).instantiate() as Control
	get_root().add_child(map)
	var units: Dictionary = map.get("_unit_states") as Dictionary
	var initial_fields: Dictionary = RwGameStateChecksum.calculate_unit_fields(units)
	assert(int(initial_fields["checksum"]) == 8048350)
	var controller: RwUnitOrderController = map.get("_unit_orders") as RwUnitOrderController
	controller.configure(units, map.get("_unit_registry") as RwUnitRegistry, map.get("_path_grid") as RwPathGrid, network_paths)
	var inspect_id: int = OS.get_environment("RW_REPLAY_INSPECT_UNIT_ID").to_int()
	var inspect_frames: Dictionary = {}
	for frame_text: String in OS.get_environment("RW_REPLAY_INSPECT_FRAMES").split(",", false):
		inspect_frames[frame_text.to_int()] = true
	for frame: int in range(1, _target_frame + 1):
		map.call("_on_battle_frame_advanced", frame, frame)
		if commands_by_frame.has(frame):
			var frame_commands: Array[Dictionary] = commands_by_frame[frame]
			map.call("_on_battle_commands_reached", frame, frame_commands)
		if network_paths and inspect_frames.has(frame) and units.has(inspect_id):
			var inspected: RwUnitState = units[inspect_id] as RwUnitState
			var grid: RwPathGrid = map.get("_path_grid") as RwPathGrid
			print("ONLINE_REPLAY_INSPECT frame=%d id=%d pos=%s dir=%s build=%s order=%s path=%s push=%s factor=%s line_clear=%s source_direct=%s" % [
				frame,
				inspect_id,
				inspected.world_position,
				inspected.body_rotation_degrees,
				inspected.build_progress,
				inspected.order_type,
				inspected.get_checksum_path_points(),
				inspected.collision_push_offset,
				inspected.get("_movement_velocity"),
				grid.has_clear_line(inspected.world_position, inspected.order_target, inspected.movement_type),
				grid.has_source_direct_line(inspected.world_position, inspected.order_target, inspected.movement_type),
			])
			var clearance: PackedByteArray = grid.get("_land_clearance") as PackedByteArray
			var blocks: PackedByteArray = grid.get("_structure_blocks") as PackedByteArray
			var objects: PackedByteArray = grid.get("_object_costs") as PackedByteArray
			var static_costs: PackedInt32Array = grid.get("_land_costs") as PackedInt32Array
			var grid_output_path: String = OS.get_environment("RW_REPLAY_GRID_OUTPUT")
			if not grid_output_path.is_empty():
				var grid_output: FileAccess = FileAccess.open(grid_output_path, FileAccess.WRITE)
				assert(grid_output != null)
				grid_output.store_line("x\ty\tstatic\tbuilding\tobject\tclearance")
				for x: int in grid.size.x:
					for y: int in grid.size.y:
						var index: int = y * grid.size.x + x
						grid_output.store_line("%d\t%d\t%d\t%d\t%d\t%d" % [x, y, static_costs[index], blocks[index], objects[index] if not objects.is_empty() else 0, clearance[index],])
				grid_output.close()
			for cell_text: String in OS.get_environment("RW_REPLAY_INSPECT_CELLS").split(",", false):
				var coordinates: PackedStringArray = cell_text.split(":")
				if coordinates.size() != 2:
					continue
				var cell: Vector2i = Vector2i(coordinates[0].to_int(), coordinates[1].to_int())
				var cell_index: int = cell.y * grid.size.x + cell.x
				print("ONLINE_REPLAY_COST frame=%d cell=%s cost=%d building=%d clearance=%d" % [
					frame,
					cell,
					grid.cost_at(cell, inspected.movement_type),
					blocks[cell_index],
					clearance[cell_index],
				])
	var result: Dictionary = RwGameStateChecksum.calculate_unit_fields(units)
	var builder: RwUnitState = units[2] as RwUnitState
	print("ONLINE_REPLAY mode=%s builder_pos=%s dir=%s paths=%s" % [
		"network" if network_paths else "offline",
		builder.world_position,
		builder.body_rotation_degrees,
		builder.get_checksum_path_points(),
	])
	if network_paths and _target_frame > DEFAULT_TARGET_FRAME:
		var ids: Array[int] = []
		ids.assign(units.keys())
		ids.sort()
		for object_id: int in ids:
			var unit_state: RwUnitState = units[object_id] as RwUnitState
			print("ONLINE_REPLAY_UNIT frame=%d id=%d type=%s pos=%s dir=%s build=%s order=%s" % [
				_target_frame,
				object_id,
				unit_state.unit_name,
				unit_state.world_position,
				unit_state.body_rotation_degrees,
				unit_state.build_progress,
				unit_state.order_type,
			])
	map.free()
	return result
