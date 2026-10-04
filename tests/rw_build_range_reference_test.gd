extends SceneTree
## 对照 OPEN-RW 在 Small Island 上放置海军基地的首个同步帧

const BATTLE_MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	var sea_factory_frame: int
	for frame: int in range(1, 3241):
		match frame:
			640:
				_send_build_command(map, frame, 2, 1, -2, "extractorT1", Vector2(1010.0, 270.0))
			850:
				_send_build_command(map, frame, 4, 0, -2, "extractorT1", Vector2(1070.0, 1790.0))
			2650:
				_send_build_command(map, frame, 4, 0, 3, "", Vector2(1470.0, 1370.0))
		map.call("_on_battle_frame_advanced", frame, frame)
		if units.has(7):
			sea_factory_frame = frame
			break
	if sea_factory_frame < 3160 or sea_factory_frame > 3200:
		var builder: RwUnitState = units[4] as RwUnitState
		push_error("Sea factory appeared at frame %d; builder=%s order=%s" % [sea_factory_frame, builder.world_position, builder.order_type,])
		quit(1)
		return
	var sea_factory: RwUnitState = units[7] as RwUnitState
	assert(sea_factory.unit_name == "seaFactory")
	assert(sea_factory.build_progress < 1.0)
	var production_command: Dictionary = {
		"team": 0,
		"source_team": 0,
		"allowed_team_mask": 3,
		"unit_ids": [7,],
		"action_id": "u_attackSubmarine",
	}
	var production_commands: Array[Dictionary] = [production_command,]
	map.call("_on_battle_commands_reached", sea_factory_frame, production_commands)
	for frame: int in range(sea_factory_frame + 1, sea_factory_frame + 101):
		map.call("_on_battle_frame_advanced", frame, frame)
	var queues: Dictionary = map.get("_production_queues") as Dictionary
	var queue: RwProductionQueue = queues.get(7) as RwProductionQueue
	assert(queue != null and queue.progress == 0.0)
	assert(sea_factory.production_progress < 0.0)
	assert(units.size() == 7)
	print("BUILD_RANGE_REFERENCE_CHECK_OK frame=%d" % sea_factory_frame)
	quit(0)


func _send_build_command(map: Control, frame: int, unit_id: int, team: int, build_index: int, custom_name: String, target: Vector2) -> void:
	var command: Dictionary = {
		"team": team,
		"source_team": team,
		"allowed_team_mask": 3,
		"unit_ids": [unit_id,],
		"order_type": "build",
		"build_unit_index": build_index,
		"custom_build_unit_name": custom_name,
		"target": target,
	}
	var commands: Array[Dictionary] = [command,]
	map.call("_on_battle_commands_reached", frame, commands)
