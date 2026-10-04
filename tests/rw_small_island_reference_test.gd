extends SceneTree
## 生成 Small Island 开局 50 帧的本地状态轨迹供 OPEN-RW 对照

const MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = OS.get_environment("RW_PROBE_PATH")
	assert(not output_path.is_empty())
	var room: Node = get_root().get_node("RwRoomClient")
	var players: Array[Dictionary] = [
		{"slot": 0, "name": "Host", "credits": 4000.0, "spectator": false,},
		{"slot": 1, "name": "Guest", "credits": 4000.0, "spectator": false,},
	]
	room.set("players", players)
	room.set("local_slot", 1)
	room.set("settings", {"fog": 2, "revealed": true, "starting_units": 1,})
	room.set("battle_map_info", {"map": "[p2]Small_Island (2p).tmx",})
	room.get("battle_economy").initialize(players, 1.0)
	var map: Control = (load(MAP_SCENE_UID) as PackedScene).instantiate() as Control
	get_root().add_child(map)
	var units: Dictionary = map.get("_unit_states") as Dictionary
	assert(units.size() == 4)
	var command_center: RwUnitState = units[1] as RwUnitState
	var visuals: Dictionary = map.get("_unit_visuals") as Dictionary
	assert(is_equal_approx(command_center.body_rotation_degrees, -90.0))
	assert(is_equal_approx(command_center.turret_rotation_degrees, 0.0))
	assert(is_equal_approx((visuals[1] as RwUnitVisual).rotation_degrees, 0.0))
	var target_frame: int = maxi(OS.get_environment("RW_REFERENCE_FRAMES").to_int(), 50)
	var source_trace: String = OS.get_environment("RW_REFERENCE_COMMAND_TRACE")
	if source_trace.is_empty():
		map.call("_on_battle_frame_advanced", target_frame, target_frame)
	else:
		var replay_commands: Dictionary = _read_build_commands(source_trace)
		var frame_deltas: Dictionary = _read_frame_deltas(source_trace)
		if replay_commands.is_empty():
			push_error("Reference trace contains no build commands")
			quit(1)
			return
		for frame: int in range(1, target_frame + 1):
			if frame_deltas.has(frame):
				room.get("battle_timeline").set_step_rate(float(frame_deltas[frame]))
			map.call("_on_battle_frame_advanced", frame, target_frame)
			if replay_commands.has(frame):
				map.call("_on_battle_commands_reached", frame, replay_commands[frame])
	map.free()
	assert(FileAccess.file_exists(output_path))
	print("SMALL_ISLAND_REFERENCE_CHECK_OK")
	quit()


func _read_build_commands(path: String) -> Dictionary:
	var source: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(source != null)
	var commands_by_frame: Dictionary = {}
	var last_orders: Dictionary = {}
	source.get_line()
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields.size() < 17:
			continue
		var object_id: int = fields[2].to_int()
		var order: String = fields[13]
		var signature: String = "%s:%s:%s:%s" % [order, fields[14], fields[15], fields[16]]
		if last_orders.get(object_id, "") == signature:
			continue
		last_orders[object_id] = signature
		if order != "build" or fields[16].is_empty():
			continue
		var frame: int = fields[0].to_int()
		var team: int = fields[4].to_int()
		var command: Dictionary = {
			"team": team,
			"source_team": team,
			"allowed_team_mask": 1 << team,
			"unit_ids": [object_id,],
			"order_type": "build",
			"build_unit_index": -2,
			"custom_build_unit_name": fields[16],
			"target": Vector2(fields[14].to_float(), fields[15].to_float()),
		}
		var frame_commands: Array[Dictionary] = []
		if commands_by_frame.has(frame):
			frame_commands.assign(commands_by_frame[frame])
		frame_commands.append(command)
		commands_by_frame[frame] = frame_commands
	return commands_by_frame


func _read_frame_deltas(path: String) -> Dictionary:
	var source: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(source != null)
	var deltas: Dictionary = {}
	source.get_line()
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields.size() < 2:
			continue
		var frame: int = fields[0].to_int()
		if not deltas.has(frame):
			deltas[frame] = fields[1].to_float()
	return deltas
