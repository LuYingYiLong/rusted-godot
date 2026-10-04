extends SceneTree
## 重放同一局原版 AI 命令并输出各校验帧的数值差异，避免随机开局影响迁移前后比较

const BATTLE_MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"

var _game_started: Dictionary
var _commands: Dictionary[int, Array]
var _checksums: Dictionary[int, Dictionary]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: FileAccess = FileAccess.open(OS.get_environment("RW_SOAK_REPORT_PATH"), FileAccess.READ)
	if source == null:
		push_error("RW_SOAK_REPORT_PATH must point to a recorded vanilla AI room")
		quit(2)
		return
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		var record: Dictionary = parsed
		var frame: int = int(record.get("frame", -1))
		match str(record.get("event", "")):
			"game_started":
				_game_started = record
			"commands":
				var commands: Array[Dictionary] = []
				for command: Dictionary in record["commands"]:
					commands.append(_parse_command(command))
				_commands[frame] = commands
			"checksum_unit_match", "checksum_unit_mismatch":
				_checksums[frame] = record
	if _game_started.is_empty() or _checksums.is_empty() or not _checksums.has(0):
		push_error("Recorded room is missing initial state or checksums")
		quit(2)
		return
	var room: Node = get_root().get_node("RwRoomClient")
	var players: Array[Dictionary] = []
	for player: Dictionary in _game_started["players"]:
		var copy: Dictionary = player.duplicate()
		copy["credits"] = 4000.0
		copy["name"] = "Replay %d" % int(copy["slot"])
		players.append(copy)
	room.set("players", players)
	room.set("local_slot", players.size() - 1)
	room.set("settings", {"fog": 2, "revealed": true, "starting_units": int(_game_started["starting_units"]),})
	room.set("battle_map_info", {"map": str(_game_started["map"]).get_file(),})
	room.get("battle_economy").initialize(players, 1.0)
	var map: Control = (load(BATTLE_MAP_SCENE_UID) as PackedScene).instantiate() as Control
	get_root().add_child(map)
	var units: Dictionary = map.get("_unit_states")
	var controller: RwUnitOrderController = map.get("_unit_orders") as RwUnitOrderController
	controller.configure(units, map.get("_unit_registry") as RwUnitRegistry, map.get("_path_grid") as RwPathGrid, true)
	var checksum_frames: Array[int] = []
	checksum_frames.assign(_checksums.keys())
	checksum_frames.sort()
	var result: Array[Dictionary] = [_compare(0, units),]
	if not (result[0]["differences"] as Dictionary).is_empty():
		push_error("Recorded initial unit state could not be reproduced")
		quit(1)
		return
	for frame: int in range(1, checksum_frames.back() + 1):
		map.call("_on_battle_frame_advanced", frame, frame)
		if _commands.has(frame):
			var commands: Array[Dictionary] = []
			commands.assign(_commands[frame])
			map.call("_on_battle_commands_reached", frame, commands)
		if _checksums.has(frame):
			result.append(_compare(frame, units))
	var output_path: String = OS.get_environment("RW_REPLAY_OUTPUT_PATH")
	if not output_path.is_empty():
		var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		assert(output != null)
		output.store_string(JSON.stringify(result, "\t"))
	var matched: int
	for record: Dictionary in result:
		if (record["differences"] as Dictionary).is_empty():
			matched += 1
	print("RW115_AI_REPLAY checksums=%d matched=%d map=%s" % [result.size(), matched, _game_started["map"],])
	map.queue_free()
	quit(0 if matched == result.size() or OS.get_environment("RW_REPLAY_ALLOW_DIFFERENCES") == "1" else 1)


func _compare(frame: int, units: Dictionary) -> Dictionary:
	var local_fields: Dictionary = RwGameStateChecksum.calculate_unit_fields(units)
	var record: Dictionary = _checksums[frame]
	var server_fields: Dictionary = (record["server_fields"] as Dictionary).duplicate()
	server_fields["checksum"] = int(record["server_checksum"])
	var differences: Dictionary = {}
	for field: String in local_fields:
		var key: String = "waypoint_pos" if field == "Waypoints Pos" else field.to_snake_case()
		if int(local_fields[field]) != int(server_fields[key]):
			differences[field] = {"local": local_fields[field], "server": server_fields[key], "delta": int(local_fields[field]) - int(server_fields[key]),}
	var result: Dictionary = {"frame": frame, "differences": differences, "local_fields": local_fields,}
	print("RW115_AI_REPLAY_FRAME ", JSON.stringify(result))
	return result


func _parse_command(raw: Dictionary) -> Dictionary:
	var command: Dictionary = raw.duplicate(true)
	command["target"] = _parse_vector(str(command["target"]))
	for key: String in ["rally_point", "command_target_point",]:
		if command.get(key) is String:
			command[key] = _parse_vector(command[key])
	var targets: Dictionary = {}
	for unit_id: String in command.get("command_targets", {}):
		var metadata: Dictionary = command["command_targets"][unit_id]
		metadata["start_position"] = _parse_vector(str(metadata["start_position"]))
		metadata["target_position"] = _parse_vector(str(metadata["target_position"]))
		var cells: Array[Vector2i] = []
		for cell: String in metadata.get("path", []):
			cells.append(Vector2i(_parse_vector(cell)))
		metadata["path"] = cells
		targets[int(unit_id)] = metadata
	command["command_targets"] = targets
	return command


func _parse_vector(value: String) -> Vector2:
	var components: PackedStringArray = value.trim_prefix("(").trim_suffix(")").split(",")
	if components.size() != 2:
		return Vector2.ZERO
	return Vector2(components[0].strip_edges().to_float(), components[1].strip_edges().to_float())
