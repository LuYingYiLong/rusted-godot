extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	var map: Control = load("uid://c0w7n4afw43pa").instantiate() as Control
	get_root().add_child(map)
	var command: Dictionary = {
		"team": 0,
		"source_team": 0,
		"allowed_team_mask": 3,
		"unit_ids": [2,],
		"order_type": "build",
		"build_unit_index": -2,
		"custom_build_unit_name": "extractorT1",
		"target": Vector2(1010.0, 270.0),
	}
	var commands: Array[Dictionary] = [command,]
	map.call("_on_battle_commands_reached", 740, commands)
	map.call("_on_battle_frame_advanced", 1400, 1400)
	var units: Dictionary = map.get("_unit_states")
	var extractors: int
	var extractor_id: int
	for unit: RwUnitState in units.values():
		if unit.unit_name == "extractor":
			extractors += 1
			extractor_id = unit.object_id
	assert(extractors == 1)
	var command_center: RwUnitState = units[1] as RwUnitState
	var visuals: Dictionary = map.get("_unit_visuals")
	assert((visuals[1] as RwUnitVisual).call("_get_footprint_rect") == Rect2(-30.0, -30.0, 60.0, 60.0))
	assert((visuals[extractor_id] as RwUnitVisual).call("_get_footprint_rect") == Rect2(-10.0, -30.0, 20.0, 40.0))
	var production_command: Dictionary = {
		"team": 0,
		"source_team": 0,
		"allowed_team_mask": 3,
		"unit_ids": [1,],
		"action_id": "u_builder",
	}
	var production_commands: Array[Dictionary] = [production_command,]
	map.call("_on_battle_commands_reached", 1400, production_commands)
	assert(is_equal_approx(command_center.production_progress, 0.0))
	map.call("_on_battle_frame_advanced", 1450, 1450)
	assert(command_center.production_progress > 0.0)
	production_command["stop_current_action"] = true
	map.call("_on_battle_commands_reached", 1450, production_commands)
	assert(command_center.production_progress < 0.0)
	print("SHARED_BUILD_SCENE_CHECK_OK")
	map.free()
	quit()
