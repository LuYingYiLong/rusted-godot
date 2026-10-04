extends Node
## 自动加入原版房间并监测长时间联机帧推进

const BATTLE_MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"
const DEFAULT_DURATION_SECONDS: int = 1800
const DEFAULT_JOIN_TIMEOUT_SECONDS: int = 30
const DEFAULT_START_TIMEOUT_SECONDS: int = 300
const DEFAULT_STALL_TIMEOUT_SECONDS: int = 20
const SAMPLE_INTERVAL_SECONDS: int = 10
const JOIN_RETRY_INTERVAL_MS: int = 5_000
const CHECKSUM_FIELD_NAMES: Array[String] = [
	"unit_pos",
	"unit_dir",
	"unit_hp",
	"unit_id",
	"waypoints",
	"waypoint_pos",
	"team_credits",
	"unit_paths",
	"unit_count",
	"team_info",
	"team_1_credits",
	"team_2_credits",
	"team_3_credits",
	"command_center_2",
	"command_center_3",
]
const LOCAL_UNIT_CHECKSUM_FIELDS: Dictionary = {
	0: "Unit Pos",
	1: "Unit Dir",
	2: "Unit Hp",
	3: "Unit Id",
	4: "Waypoints",
	5: "Waypoints Pos",
	7: "UnitPaths",
}

var _report: FileAccess
var _started_at_ms: int
var _battle_started_at_ms: int
var _last_frame_at_ms: int
var _last_sample_at_ms: int
var _last_frame: int
var _last_join_attempt_ms: int
var _command_count: int
var _checksum_count: int
var _first_checksum_mismatch_reported: bool
var _battle_ready: bool
var _last_connection_message: String
var _waiting_for_room_restart: bool
var _battle_scene: Node
var _pending_checksum_requests: Array[Dictionary]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var address: String = OS.get_environment("RW_SOAK_ADDRESS")
	if address.is_empty():
		push_error("Set RW_SOAK_ADDRESS to the private room IP:port")
		get_tree().quit(2)
		return
	var report_path: String = OS.get_environment("RW_SOAK_REPORT_PATH")
	if report_path.is_empty():
		report_path = "user://rw_soak_report.jsonl"
	var report_directory: String = report_path.get_base_dir()
	if report_path.is_absolute_path() and not report_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(report_directory)
	_report = FileAccess.open(report_path, FileAccess.WRITE)
	if _report == null:
		push_error("Could not open soak report: %s" % report_path)
		get_tree().quit(2)
		return
	_started_at_ms = Time.get_ticks_msec()
	_last_frame_at_ms = _started_at_ms
	_last_join_attempt_ms = _started_at_ms
	RwRoomClient.connection_changed.connect(_on_connection_changed)
	RwRoomClient.game_started.connect(_on_game_started)
	RwRoomClient.battle_frame_advanced.connect(_on_battle_frame_advanced)
	RwRoomClient.battle_commands_reached.connect(_on_battle_commands_reached)
	RwRoomClient.checksum_requested.connect(_on_checksum_requested)
	_write_event("joining", {"address": address,})
	RwRoomClient.join_room(address, "GodotSoak", "")
	while true:
		await get_tree().create_timer(1.0).timeout
		var now_ms: int = Time.get_ticks_msec()
		var stop_path: String = OS.get_environment("RW_SOAK_CONTROL_PATH")
		if not stop_path.is_empty() and FileAccess.file_exists(stop_path):
			var stop_file: FileAccess = FileAccess.open(stop_path, FileAccess.READ)
			_finish(stop_file.get_as_text().strip_edges() if stop_file != null else "external_stop", now_ms)
			return
		if not RwRoomClient.is_active():
			if _waiting_for_room_restart and now_ms - _started_at_ms < _setting("RW_SOAK_START_TIMEOUT", DEFAULT_START_TIMEOUT_SECONDS) * 1000:
				if now_ms - _last_join_attempt_ms >= JOIN_RETRY_INTERVAL_MS:
					_last_join_attempt_ms = now_ms
					_write_event("rejoining", {"address": address,})
					RwRoomClient.join_room(address, "GodotSoak", "")
				continue
			_fail("Connection ended: %s" % _last_connection_message)
			return
		if RwRoomClient.is_joined():
			_waiting_for_room_restart = false
		if not RwRoomClient.is_joined() and not _waiting_for_room_restart and now_ms - _last_join_attempt_ms > _setting("RW_SOAK_JOIN_TIMEOUT", DEFAULT_JOIN_TIMEOUT_SECONDS) * 1000:
			_fail("Room join timed out: %s" % _last_connection_message)
			return
		if not _battle_ready:
			if now_ms - _started_at_ms > _setting("RW_SOAK_START_TIMEOUT", DEFAULT_START_TIMEOUT_SECONDS) * 1000:
				_fail("Expected battle did not start")
				return
			continue
		if now_ms - _last_frame_at_ms > _setting("RW_SOAK_STALL_TIMEOUT", DEFAULT_STALL_TIMEOUT_SECONDS) * 1000:
			_fail("Synchronized frame stalled at %d" % _last_frame)
			return
		if now_ms - _last_sample_at_ms >= SAMPLE_INTERVAL_SECONDS * 1000:
			_write_sample(now_ms)
			_last_sample_at_ms = now_ms
		if now_ms - _battle_started_at_ms >= _setting("RW_SOAK_DURATION", DEFAULT_DURATION_SECONDS) * 1000:
			_finish("duration_reached", now_ms)
			return



func _finish(reason: String, now_ms: int) -> void:
	_flush_pending_checksums()
	for request: Dictionary in _pending_checksum_requests:
		_write_event("checksum_pending_at_end", {
			"frame": int(request["frame"]),
			"reason": "pending_at_end",
			"simulated_frame": _simulated_frame(),
		})
	_pending_checksum_requests.clear()
	_write_sample(now_ms)
	_write_event("transport_completed", {
		"frame": _last_frame,
		"commands": _command_count,
		"checksum_requests": _checksum_count,
		"reason": reason,
	})
	_report.close()
	get_tree().quit(0)


func _on_connection_changed(message: String) -> void:
	_last_connection_message = message
	if message.contains("A game has already been started on this server"):
		_waiting_for_room_restart = true
	_write_event("connection", {"message": message,})
	if _battle_ready and message.contains("returned to the battle room"):
		_fail("Original battle ended before the soak duration at frame %d" % _last_frame)
		return
	if message.contains("resync save"):
		_fail("Server requested a resync save, which is not implemented")


func _on_game_started() -> void:
	var map_name: String = str(RwRoomClient.battle_map_info.get("map", ""))
	var expected_map: String = OS.get_environment("RW_SOAK_EXPECT_MAP")
	if expected_map.is_empty():
		expected_map = "small island"
	if not map_name.get_file().to_lower().replace("_", " ").contains(expected_map.to_lower()):
		_fail("Unexpected map: %s" % map_name)
		return
	var minimum_players: int = _setting("RW_SOAK_MIN_PLAYERS", 0)
	var player_settings: Array[Dictionary] = []
	var active_players: int
	for player: Dictionary in RwRoomClient.players:
		if not bool(player.get("spectator", false)):
			active_players += 1
		player_settings.append({
			"slot": int(player.get("slot", -1)),
			"starting_units_override": int(player.get("starting_units_override", -1)),
			"spectator": bool(player.get("spectator", false)),
		})
	if active_players < minimum_players:
		_fail("Expected at least %d active players, found %d" % [minimum_players, active_players])
		return
	_write_event("game_started", {
		"map": map_name,
		"starting_units": int(RwRoomClient.settings.get("starting_units", 1)),
		"starting_credits": int(RwRoomClient.settings.get("credits", 0)),
		"players": player_settings,
	})
	call_deferred("_open_battle_map")


func _on_battle_frame_advanced(frame: int, _next_blocking_frame: int) -> void:
	if frame <= _last_frame:
		return
	_last_frame = frame
	_last_frame_at_ms = Time.get_ticks_msec()
	if not _pending_checksum_requests.is_empty():
		call_deferred("_flush_pending_checksums")


func _on_battle_commands_reached(frame: int, commands: Array[Dictionary]) -> void:
	_command_count += commands.size()
	_write_event("commands", {"frame": frame, "commands": commands,})


func _on_checksum_requested(frame: int, server_checksum: int, fields: Array[int]) -> void:
	_checksum_count += 1
	var request: Dictionary = {
		"frame": frame,
		"server_checksum": server_checksum,
		"fields": fields,
	}
	if not _verify_checksum(request):
		_pending_checksum_requests.append(request)
		call_deferred("_flush_pending_checksums")


func _flush_pending_checksums() -> void:
	for index: int in range(_pending_checksum_requests.size() - 1, -1, -1):
		var request: Dictionary = _pending_checksum_requests[index]
		if _verify_checksum(request):
			_pending_checksum_requests.remove_at(index)
		elif int(request["frame"]) < _simulated_frame() - RwBattleStateProbe.CHECKSUM_HISTORY_FRAMES:
			_write_event("checksum_unverified", {
				"frame": int(request["frame"]),
				"reason": "expired",
				"simulated_frame": _simulated_frame(),
			})
			_pending_checksum_requests.remove_at(index)


func _simulated_frame() -> int:
	return int(_battle_scene.get("_last_simulated_frame")) if _battle_scene != null else -1


func _verify_checksum(request: Dictionary) -> bool:
	var frame: int = int(request["frame"])
	var server_checksum: int = int(request["server_checksum"])
	var fields: Array[int] = request["fields"]
	var named_fields: Dictionary = {}
	for index: int in mini(fields.size(), CHECKSUM_FIELD_NAMES.size()):
		named_fields[CHECKSUM_FIELD_NAMES[index]] = fields[index]
	var local_checksum: Dictionary = {}
	if _battle_scene != null and _battle_scene.has_method("get_unit_checksum_for_frame"):
		local_checksum = _battle_scene.call("get_unit_checksum_for_frame", frame)
	if local_checksum.is_empty():
		return false
	var differences: Dictionary = {}
	if int(local_checksum["checksum"]) != server_checksum:
		differences["checksum"] = {"server": server_checksum, "godot": local_checksum["checksum"],}
	var checked_fields: int
	for index: int in LOCAL_UNIT_CHECKSUM_FIELDS:
		if index >= fields.size():
			continue
		var name: String = LOCAL_UNIT_CHECKSUM_FIELDS[index]
		checked_fields += 1
		if int(local_checksum[name]) != fields[index]:
			differences[name] = {"server": fields[index], "godot": local_checksum[name],}
	var event_name: String = "checksum_unit_match" if differences.is_empty() else "checksum_unit_mismatch"
	var details: Dictionary = {
		"frame": frame,
		"checked_fields": checked_fields,
		"differences": differences,
		"server_checksum": server_checksum,
		"server_fields": named_fields,
		"local_checksum": local_checksum["checksum"],
		"unverified_fields": ["Team Credits", "Unit Count", "Team Info", "Team 1 Credits", "Team 2 Credits", "Team 3 Credits", "Command center2", "Command center3",],
	}
	if not differences.is_empty() and not _first_checksum_mismatch_reported:
		_first_checksum_mismatch_reported = true
		if _battle_scene != null and _battle_scene.has_method("get_unit_probe_snapshot_for_frame"):
			details["unit_snapshot"] = _battle_scene.call("get_unit_probe_snapshot_for_frame", frame)
	_write_event(event_name, details)
	return true


func _open_battle_map() -> void:
	var battle_packed: PackedScene = load(BATTLE_MAP_SCENE_UID) as PackedScene
	if battle_packed == null:
		_fail("Could not load battle scene")
		return
	_battle_scene = battle_packed.instantiate()
	get_tree().root.add_child(_battle_scene)
	call_deferred("_check_battle_map")


func _check_battle_map() -> void:
	if not bool(RwRoomClient.get("_battle_view_ready")):
		_fail("Battle scene did not finish loading")
		return
	_battle_started_at_ms = Time.get_ticks_msec()
	_last_frame_at_ms = _battle_started_at_ms
	_last_sample_at_ms = _battle_started_at_ms
	_battle_ready = true
	_write_sample(_battle_started_at_ms)


func _write_sample(now_ms: int) -> void:
	var unit_count: int
	if _battle_scene != null:
		var units: Dictionary = _battle_scene.get("_unit_states") as Dictionary
		unit_count = units.size()
	_write_event("sample", {
		"elapsed_seconds": float(now_ms - _battle_started_at_ms) / 1000.0,
		"frame": _last_frame,
		"next_blocking_frame": RwRoomClient.battle_timeline.next_blocking_frame,
		"step_rate": RwRoomClient.battle_timeline.step_rate,
		"units": unit_count,
		"commands": _command_count,
		"checksum_requests": _checksum_count,
	})


func _write_event(event_name: String, details: Dictionary) -> void:
	if _report == null:
		return
	var record: Dictionary = details.duplicate()
	record["event"] = event_name
	record["time_unix"] = Time.get_unix_time_from_system()
	_report.store_line(JSON.stringify(record))
	_report.flush()


func _fail(reason: String) -> void:
	_write_event("failed", {"reason": reason, "frame": _last_frame,})
	push_error(reason)
	if _report != null:
		_report.close()
	get_tree().quit(1)


func _setting(name: String, default_value: int) -> int:
	var value: String = OS.get_environment(name)
	return maxi(value.to_int(), 1) if not value.is_empty() else default_value
