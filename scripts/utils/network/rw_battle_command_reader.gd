extends RefCounted
class_name RwBattleCommandReader
## 读取原版同步帧中的命令和每单位目标数据

const MAX_COMMANDS: int = 512
const MAX_COMMAND_BYTES: int = 1_048_576
const MAX_SELECTED_UNITS: int = 10_000
const MAX_COMMAND_TARGETS: int = 10_000
const MAX_PATH_BYTES: int = 1_048_576
const MAX_PATH_POINTS: int = 160_000
const COMMAND_TYPES: Array[String] = [
	"move",
	"attack",
	"build",
	"repair",
	"loadInto",
	"unloadAt",
	"reclaim",
	"attackMove",
	"loadUp",
	"patrol",
	"guard",
	"guardAt",
	"touchTarget",
	"follow",
	"triggerAction",
	"triggerActionWhenInRange",
	"setPassiveTarget",
]


static func read_frame_packet(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 8:
		return {"error": "Sync frame header is incomplete",}
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	var next_frame: int = stream.get_32()
	var count: int = stream.get_32()
	if next_frame < 0 or count < 0 or count > MAX_COMMANDS:
		return {"error": "Sync frame header is invalid",}
	var commands: Array[Dictionary] = []
	for index: int in count:
		if stream.get_available_bytes() < 6:
			return {"error": "Sync command block is incomplete",}
		var block_name: String = RwBinary.read_utf(stream)
		var block_length: int = stream.get_32()
		if block_name != "c" or block_length < 0 or block_length > MAX_COMMAND_BYTES or block_length > stream.get_available_bytes():
			return {"error": "Sync command block is invalid",}
		var block_result: Array = stream.get_data(block_length)
		if block_result[0] != OK:
			return {"error": "Could not read sync command block",}
		var command: Dictionary = _read_command(block_result[1])
		if not str(command.get("error", "")).is_empty():
			return command
		commands.append(command)
	if stream.get_available_bytes() != 0:
		return {"error": "Sync frame contains unexpected trailing data",}
	return {"error": "", "next_blocking_frame": next_frame, "commands": commands,}


static func _read_command(data: PackedByteArray) -> Dictionary:
	var stream: StreamPeerBuffer = RwBinary.reader(data)
	if stream.get_available_bytes() < 2:
		return {"error": "Command body is incomplete",}
	var team: int = stream.get_8()
	var has_order: bool = stream.get_u8() != 0
	var order_type: String
	var build_unit_index: int = -1
	var custom_build_unit_name: String
	var target: Vector2
	var target_id: int = -1
	var build_queue_size: int
	var attack_move_range: float
	var max_waypoint_surviving_time: float
	var order_is_repeating: bool
	var formation_loose: bool
	var force_move: bool
	var order_action_id: String
	if has_order:
		if stream.get_available_bytes() < 8:
			return {"error": "Unit order is incomplete",}
		var type_index: int = stream.get_32()
		build_unit_index = stream.get_32()
		if build_unit_index == -2:
			custom_build_unit_name = RwBinary.read_utf(stream)
		if stream.get_available_bytes() < 29:
			return {"error": "Unit order target is incomplete",}
		target = Vector2(stream.get_float(), stream.get_float())
		target_id = stream.get_64()
		build_queue_size = stream.get_8()
		attack_move_range = stream.get_float()
		max_waypoint_surviving_time = stream.get_float()
		order_is_repeating = stream.get_u8() != 0
		formation_loose = stream.get_u8() != 0
		force_move = stream.get_u8() != 0
		order_action_id = RwBinary.read_nullable_utf(stream)
		if type_index >= 0 and type_index < COMMAND_TYPES.size():
			order_type = COMMAND_TYPES[type_index]
	if stream.get_available_bytes() < 16:
		return {"error": "Command selection is incomplete",}
	var is_queued: bool = stream.get_u8() != 0
	var stop_current_action: bool = stream.get_u8() != 0
	stream.get_32()
	var attack_mode: int = stream.get_32()
	var rally_point: Variant
	if stream.get_u8() != 0:
		if stream.get_available_bytes() < 8:
			return {"error": "Command rally point is incomplete",}
		rally_point = Vector2(stream.get_float(), stream.get_float())
	var clear_existing_orders: bool = stream.get_u8() != 0
	var selection_count: int = stream.get_32()
	if selection_count < 0 or selection_count > MAX_SELECTED_UNITS or stream.get_available_bytes() < selection_count * 8:
		return {"error": "Command selection is invalid",}
	var unit_ids: Array[int] = []
	for index: int in selection_count:
		unit_ids.append(stream.get_64())
	if stream.get_available_bytes() < 2:
		return {"error": "Command target header is incomplete",}
	var source_team: int = -1
	if stream.get_u8() != 0:
		if stream.get_available_bytes() < 1:
			return {"error": "Command source team is incomplete",}
		source_team = stream.get_8()
	var command_target_point: Variant
	if stream.get_u8() != 0:
		if stream.get_available_bytes() < 8:
			return {"error": "Command target point is incomplete",}
		command_target_point = Vector2(stream.get_float(), stream.get_float())
	if stream.get_available_bytes() < 17:
		return {"error": "Command metadata is incomplete",}
	var command_target_id: int = stream.get_64()
	var action_id: String = RwBinary.read_utf(stream)
	var is_instant_command: bool = stream.get_u8() != 0
	var allowed_team_mask: int = stream.get_u16()
	var is_system_action: bool = stream.get_u8() != 0
	var game_speed_change: float
	var system_float: float
	var system_action_type: int
	if is_system_action:
		if stream.get_available_bytes() < 13:
			return {"error": "System action is incomplete",}
		stream.get_u8()
		game_speed_change = stream.get_float()
		system_float = stream.get_float()
		system_action_type = stream.get_32()
	if stream.get_available_bytes() < 4:
		return {"error": "Command target count is incomplete",}
	var target_count: int = stream.get_32()
	if target_count < 0 or target_count > MAX_COMMAND_TARGETS:
		return {"error": "Command target count is invalid",}
	var paths: Dictionary = {}
	var command_targets: Dictionary = {}
	for index: int in target_count:
		var target_result: Dictionary = _read_command_target(stream)
		if not str(target_result.get("error", "")).is_empty():
			return target_result
		var path_points: Array[Vector2i] = target_result["path"]
		command_targets[int(target_result["unit_id"])] = target_result
		if not path_points.is_empty():
			paths[int(target_result["unit_id"])] = path_points
	if stream.get_available_bytes() < 1:
		return {"error": "Command priority flag is incomplete",}
	var is_high_priority: bool = stream.get_u8() != 0
	if stream.get_available_bytes() != 0:
		return {"error": "Command contains unexpected trailing data",}
	return {
		"error": "",
		"team": team,
		"order_type": order_type,
		"build_unit_index": build_unit_index,
		"custom_build_unit_name": custom_build_unit_name,
		"action_id": action_id,
		"is_queued": is_queued,
		"stop_current_action": stop_current_action,
		"target": target,
		"target_id": target_id,
		"build_queue_size": build_queue_size,
		"attack_move_range": attack_move_range,
		"max_waypoint_surviving_time": max_waypoint_surviving_time,
		"order_is_repeating": order_is_repeating,
		"formation_loose": formation_loose,
		"force_move": force_move,
		"order_action_id": order_action_id,
		"unit_ids": unit_ids,
		"paths": paths,
		"command_targets": command_targets,
		"attack_mode": attack_mode,
		"rally_point": rally_point,
		"clear_existing_orders": clear_existing_orders,
		"source_team": source_team,
		"command_target_point": command_target_point,
		"command_target_id": command_target_id,
		"is_instant_command": is_instant_command,
		"allowed_team_mask": allowed_team_mask,
		"is_system_action": is_system_action,
		"game_speed_change": game_speed_change,
		"system_float": system_float,
		"system_action_type": system_action_type,
		"is_high_priority": is_high_priority,
	}


static func _read_command_target(stream: StreamPeerBuffer) -> Dictionary:
	if stream.get_available_bytes() < 33:
		return {"error": "Command target is incomplete",}
	var unit_id: int = stream.get_64()
	var start_position: Vector2 = Vector2(stream.get_float(), stream.get_float())
	var target_position: Vector2 = Vector2(stream.get_float(), stream.get_float())
	var created_tick: int = stream.get_32()
	var movement_type: int = stream.get_32()
	var path_points: Array[Vector2i] = []
	if stream.get_u8() != 0:
		if stream.get_available_bytes() < 1:
			return {"error": "Command path flag is incomplete",}
		if stream.get_u8() != 0:
			if stream.get_available_bytes() < 6:
				return {"error": "Compressed command path is incomplete",}
			var block_name: String = RwBinary.read_utf(stream)
			var block_size: int = stream.get_32()
			if block_name != "p" or block_size < 0 or block_size > MAX_COMMAND_BYTES or block_size > stream.get_available_bytes():
				return {"error": "Compressed command path is invalid",}
			var block_result: Array = stream.get_data(block_size)
			var decompressed: PackedByteArray = (block_result[1] as PackedByteArray).decompress_dynamic(MAX_PATH_BYTES, FileAccess.COMPRESSION_GZIP)
			if decompressed.size() < 4:
				return {"error": "Could not decompress command path",}
			var path_stream: StreamPeerBuffer = RwBinary.reader(decompressed)
			var point_count: int = path_stream.get_32()
			if point_count < 0 or point_count > MAX_PATH_POINTS or point_count > 0 and path_stream.get_available_bytes() < 4:
				return {"error": "Compressed command path count is invalid",}
			if point_count > 0:
				var cell: Vector2i = Vector2i(path_stream.get_16(), path_stream.get_16())
				path_points.append(cell)
				for index: int in range(1, point_count):
					if path_stream.get_available_bytes() < 1:
						return {"error": "Compressed command path points are incomplete",}
					var delta: int = path_stream.get_u8()
					if delta < 128:
						cell += Vector2i((delta & 3) - 1, ((delta & 12) >> 2) - 1)
					else:
						if path_stream.get_available_bytes() < 4:
							return {"error": "Compressed command path jump is incomplete",}
						cell = Vector2i(path_stream.get_16(), path_stream.get_16())
					path_points.append(cell)
	return {
		"error": "",
		"unit_id": unit_id,
		"start_position": start_position,
		"target_position": target_position,
		"created_tick": created_tick,
		"movement_type": movement_type,
		"path": path_points,
	}
