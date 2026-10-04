extends Node

signal connection_changed(message: String)
signal room_updated(settings: Dictionary, players: Array[Dictionary], local_slot: int)
signal chat_received(sender: String, message: String)
signal game_started()
signal battle_frame_advanced(frame: int, next_blocking_frame: int)
signal battle_commands_reached(frame: int, commands: Array[Dictionary])
signal checksum_requested(frame: int, server_checksum: int, fields: Array[int])
signal team_resource_changed(team_slot: int, resource_id: String, balance: float, growth: float)

const CORE_VERSION: int = 176
const CORE_UNIT_CHECKSUM: int = 678359601
const DEFAULT_PORT: int = 5123
const MAX_PACKET_BYTES: int = 16_777_216
const MAX_TEAM_BLOCK_BYTES: int = 1_048_576
const MAX_CHECKSUM_FIELDS: int = 64
const CONNECT_TIMEOUT_MS: int = 7_000
const REGISTER_TIMEOUT_MS: int = 15_000
const PROTOCOL_MAGIC: String = "com.corrodinggames.rts"
const PACKAGE_NAME: String = "com.corrodinggames.rts.java"

var settings: Dictionary
var players: Array[Dictionary]
var local_slot: int = -1
var battle_map_info: Dictionary
var battle_timeline: RwBattleTimeline = RwBattleTimeline.new()
var battle_economy: RwVanillaEconomy = RwVanillaEconomy.new()
var chat_log: Array[Dictionary]

var _peer: StreamPeerTCP = StreamPeerTCP.new()
var _incoming: PackedByteArray
var _player_name: String
var _password: String
var _connection_query: String
var _client_id: String
var _server_uuid: String
var _server_version: int
var _connecting: bool
var _connected: bool
var _joined: bool
var _has_player_update: bool
var _battle_view_ready: bool
var _connect_started_at: int
var _register_started_at: int


func _ready() -> void:
	battle_timeline.frame_advanced.connect(_on_battle_frame_advanced)
	battle_timeline.commands_reached.connect(_on_battle_commands_reached)
	battle_economy.balance_changed.connect(_on_economy_balance_changed)
	var config: ConfigFile = ConfigFile.new()
	config.load("user://identity.cfg")
	_client_id = str(config.get_value("identity", "client_id", ""))
	if _client_id.is_empty():
		_client_id = Crypto.new().generate_random_bytes(16).hex_encode()
		config.set_value("identity", "client_id", _client_id)
		config.save("user://identity.cfg")


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _connecting and now - _connect_started_at > CONNECT_TIMEOUT_MS:
		_disconnect(false)
		connection_changed.emit("Timed out while connecting to the room")
		return
	if _connected and not _joined and now - _register_started_at > REGISTER_TIMEOUT_MS:
		_disconnect(false)
		connection_changed.emit("Timed out during the room handshake")
		return
	if _peer.get_status() == StreamPeerTCP.STATUS_NONE:
		if _connecting:
			connection_changed.emit("Could not connect to the room")
			_disconnect(false)
		return
	_peer.poll()
	var state: StreamPeerTCP.Status = _peer.get_status()
	if state == StreamPeerTCP.STATUS_CONNECTED and not _connected:
		_connecting = false
		_connected = true
		_register_started_at = now
		_peer.set_no_delay(true)
		connection_changed.emit("Connected; checking the vanilla protocol...")
		_send_preregister()
	elif state == StreamPeerTCP.STATUS_ERROR or state == StreamPeerTCP.STATUS_NONE:
		if _connected or _joined:
			connection_changed.emit("Connection closed")
		elif _connecting:
			connection_changed.emit("Could not connect to the room")
		_disconnect(false)
		return
	if not _connected:
		return
	if _battle_view_ready:
		battle_timeline.advance(delta)
	var available: int = _peer.get_available_bytes()
	if available <= 0:
		return
	var read_result: Array = _peer.get_data(available)
	if read_result[0] != OK:
		connection_changed.emit("Could not read room data")
		_disconnect(false)
		return
	_incoming.append_array(read_result[1])
	_read_packets()


func join_room(address: String, player_name: String, password: String) -> void:
	_disconnect(false)
	var split_address: PackedStringArray = address.strip_edges().rsplit(":", true, 1)
	var host: String = split_address[0].strip_edges()
	var port: int = DEFAULT_PORT
	if split_address.size() == 2:
		port = split_address[1].to_int()
	if host.is_empty() or port < 1 or port > 65535:
		connection_changed.emit("Enter a valid IP address and port")
		return
	_begin_join(host, port, "", player_name, password)


func join_room_id(room_id: String, player_name: String, password: String) -> void:
	_disconnect(false)
	var code: String = room_id.strip_edges()
	var code_pattern: RegEx = RegEx.new()
	code_pattern.compile("^[A-Za-z0-9][A-Za-z0-9_-]{4,63}$")
	if code_pattern.search(code) == null:
		connection_changed.emit("Enter a valid vanilla room code")
		return
	var relay_host: String = "%s.relay.corrodinggames.com" % code.substr(0, 1).to_lower()
	_begin_join(relay_host, DEFAULT_PORT, code, player_name, password)


func leave_room() -> void:
	if _connected:
		var stream: StreamPeerBuffer = RwBinary.writer()
		RwBinary.write_utf(stream, "Leaving room")
		_send_packet(111, stream.data_array)
	_disconnect(true)


func send_chat(message: String, team_only: bool = false) -> void:
	if not _joined or message.strip_edges().is_empty():
		return
	var stream: StreamPeerBuffer = RwBinary.writer()
	var outgoing_message: String = message.strip_edges()
	if team_only:
		outgoing_message = "-t " + outgoing_message
	RwBinary.write_utf(stream, outgoing_message)
	stream.put_u8(0)
	_send_packet(140, stream.data_array)


func send_move_order(unit_ids: Array[int], target: Vector2) -> bool:
	if not _joined or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or battle_map_info.is_empty() or local_slot < 0 or unit_ids.is_empty():
		return false
	var payload: PackedByteArray = RwBattleCommandWriter.write_move(local_slot, unit_ids, target)
	_send_packet(20, payload)
	return true


## 向原版服务器提交巡逻、护卫或回收等目标命令
func send_special_order(unit_ids: Array[int], order_type: String, target: Vector2, target_id: int = -1) -> bool:
	if not _joined or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or battle_map_info.is_empty() or local_slot < 0 or unit_ids.is_empty():
		return false
	var payload: PackedByteArray = RwBattleCommandWriter.write_order(local_slot, unit_ids, order_type, target, target_id)
	if payload.is_empty():
		return false
	_send_packet(20, payload)
	return true


func send_unit_action(unit_ids: Array[int], action_id: String) -> bool:
	if not _joined or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or battle_map_info.is_empty() or local_slot < 0 or unit_ids.is_empty() or action_id.is_empty():
		return false
	var payload: PackedByteArray = RwBattleCommandWriter.write_action(local_slot, unit_ids, action_id)
	_send_packet(20, payload)
	return true


func send_cancel_unit_action(unit_id: int, action_id: String) -> bool:
	if not _joined or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or battle_map_info.is_empty() or local_slot < 0 or unit_id <= 0 or action_id.is_empty():
		return false
	var payload: PackedByteArray = RwBattleCommandWriter.write_action(local_slot, [unit_id,], action_id, true)
	_send_packet(20, payload)
	return true


func send_build_order(unit_ids: Array[int], unit_type_index: int, target: Vector2, is_queued: bool, custom_unit_name: String = "") -> bool:
	if not _joined or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or battle_map_info.is_empty() or local_slot < 0 or unit_ids.is_empty() or unit_type_index < 0 and custom_unit_name.is_empty():
		return false
	var payload: PackedByteArray = RwBattleCommandWriter.write_build(local_slot, unit_ids, unit_type_index, target, is_queued, custom_unit_name)
	_send_packet(20, payload)
	return true


func is_joined() -> bool:
	return _joined


func is_active() -> bool:
	return _peer.get_status() != StreamPeerTCP.STATUS_NONE


func mark_battle_map_loaded() -> void:
	if battle_map_info.is_empty() or not _connected:
		return
	_battle_view_ready = true
	_send_client_status(true)


func set_initial_command_centers(counts: Dictionary, extractor_counts: Dictionary = {}) -> void:
	if battle_map_info.is_empty():
		return
	battle_economy.set_extractors(extractor_counts)
	battle_economy.set_command_centers(counts)
	battle_economy.advance_to(battle_timeline.current_frame)


func _begin_join(host: String, port: int, connection_query: String, player_name: String, password: String) -> void:
	_player_name = player_name.strip_edges()
	if _player_name.length() < 2 or _player_name.length() > 20:
		connection_changed.emit("Player name must contain 2 to 20 characters")
		return
	_password = password
	_connection_query = connection_query
	var error: Error = _peer.connect_to_host(host, port)
	if error != OK:
		connection_changed.emit("Connection failed: %s" % error_string(error))
		return
	_connecting = true
	_connect_started_at = Time.get_ticks_msec()
	connection_changed.emit("Connecting %s:%d…" % [host, port])


func _disconnect(report: bool) -> void:
	_peer.disconnect_from_host()
	_connecting = false
	_connected = false
	_joined = false
	_has_player_update = false
	_incoming.clear()
	settings.clear()
	players.clear()
	battle_map_info.clear()
	_battle_view_ready = false
	battle_timeline.reset()
	battle_economy.clear()
	chat_log.clear()
	local_slot = -1
	room_updated.emit(settings, players, local_slot)
	if report:
		connection_changed.emit("Has left the room")


func _read_packets() -> void:
	while _incoming.size() >= 8:
		var header: StreamPeerBuffer = RwBinary.reader(_incoming.slice(0, 8))
		var packet_length: int = header.get_32()
		var packet_type: int = header.get_32()
		if packet_length < 0 or packet_length > MAX_PACKET_BYTES:
			connection_changed.emit("The room packet length is invalid")
			_disconnect(false)
			return
		if _incoming.size() < 8 + packet_length:
			return
		var payload: PackedByteArray = _incoming.slice(8, 8 + packet_length)
		_incoming = _incoming.slice(8 + packet_length)
		_handle_packet(packet_type, payload)
		if not _connected:
			return


func _handle_packet(packet_type: int, payload: PackedByteArray) -> void:
	match packet_type:
		10:
			_read_battle_frame(payload)
		30:
			_reply_checksum_unavailable(payload)
		35:
			_battle_view_ready = false
			connection_changed.emit("Server sent a resync save; live state restore is not implemented")
		106:
			_read_server_settings(payload)
		108:
			_reply_ping(payload)
		113:
			connection_changed.emit("The room requires a password, or the password is incorrect")
			_disconnect(false)
		115:
			_read_players(payload)
		120:
			_read_start_game(payload)
		122:
			connection_changed.emit("The server returned to the battle room")
		141:
			_read_chat(payload)
		150:
			var reason: String = RwBinary.read_utf(RwBinary.reader(payload))
			connection_changed.emit("Rejected by the room: %s" % reason)
			_disconnect(false)
		161:
			_read_preregister(payload)


func _read_start_game(payload: PackedByteArray) -> void:
	if payload.size() < 7:
		connection_changed.emit("Start-game map data is incomplete")
		return
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	stream.get_u8()
	var game_mode: int = stream.get_32()
	if game_mode != 0:
		connection_changed.emit("Only stock skirmish maps are supported")
		return
	var map_name: String = RwBinary.read_utf(stream)
	if map_name.is_empty():
		connection_changed.emit("The start-game packet has no map name")
		return
	battle_map_info = {
		"mode": game_mode,
		"map": map_name,
	}
	_battle_view_ready = false
	battle_timeline.reset()
	var starting_credits: int = _starting_credits_amount(int(settings.get("credits", 0)))
	for player: Dictionary in players:
		player["credits"] = starting_credits
		var balances: Dictionary = player.get("team_resources", {}).duplicate()
		balances["credits"] = float(starting_credits)
		player["team_resources"] = balances
	battle_economy.initialize(players, float(settings.get("income_multiplier", 1.0)))
	game_started.emit()


func _send_preregister() -> void:
	var stream: StreamPeerBuffer = RwBinary.writer()
	RwBinary.write_utf(stream, PROTOCOL_MAGIC)
	stream.put_32(4)
	stream.put_32(CORE_VERSION)
	stream.put_32(2)
	RwBinary.write_nullable_utf(stream, _connection_query, _connection_query.is_empty())
	RwBinary.write_utf(stream, _player_name)
	RwBinary.write_utf(stream, "zh")
	RwBinary.write_utf(stream, "")
	_send_packet(160, stream.data_array)


func _read_preregister(payload: PackedByteArray) -> void:
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	if RwBinary.read_utf(stream) != PROTOCOL_MAGIC:
		connection_changed.emit("The server isn't using the original protocol")
		_disconnect(false)
		return
	var format_version: int = stream.get_32()
	_server_version = stream.get_32()
	stream.get_32()
	RwBinary.read_utf(stream)
	_server_uuid = RwBinary.read_utf(stream)
	if format_version < 2 or _server_version != CORE_VERSION:
		connection_changed.emit("Only supports the original 1.15 / protocol 176; server protocol %d" % _server_version)
		_disconnect(false)
		return
	var challenge: int = stream.get_32()
	var color: int = stream.get_32()
	stream.get_32()
	_send_registration(challenge, color)


func _send_registration(challenge: int, color: int) -> void:
	var stream: StreamPeerBuffer = RwBinary.writer()
	RwBinary.write_utf(stream, PROTOCOL_MAGIC)
	stream.put_32(5)
	stream.put_32(CORE_VERSION)
	stream.put_32(CORE_VERSION)
	RwBinary.write_utf(stream, _player_name)
	RwBinary.write_nullable_utf(stream, _password.sha256_text().to_upper(), _password.is_empty())
	RwBinary.write_utf(stream, PACKAGE_NAME)
	RwBinary.write_utf(stream, (_client_id + _server_uuid).sha256_text().to_upper())
	stream.put_32(CORE_UNIT_CHECKSUM)
	RwBinary.write_utf(stream, _integrity_response(challenge))
	RwBinary.write_utf(stream, "#%06X" % (color & 0xFFFFFF))
	_send_packet(110, stream.data_array)
	connection_changed.emit("Joining the room...")


func _read_server_settings(payload: PackedByteArray) -> void:
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	RwBinary.read_utf(stream)
	stream.get_32()
	settings["mode"] = stream.get_32()
	settings["map"] = RwBinary.read_utf(stream)
	settings["credits"] = stream.get_32()
	settings["fog"] = stream.get_32()
	settings["revealed"] = stream.get_u8() != 0
	settings["ai_difficulty"] = stream.get_32()
	var settings_version: int = stream.get_u8()
	stream.get_u8()
	stream.get_u8()
	if settings_version >= 1:
		settings["unit_cap"] = stream.get_32()
		settings["max_unit_cap"] = stream.get_32()
	if settings_version >= 2:
		settings["starting_units"] = stream.get_32()
		settings["income_multiplier"] = stream.get_float()
		settings["no_nukes"] = stream.get_u8() != 0
		stream.get_u8()
	if settings_version >= 3 and stream.get_u8() != 0:
		var block_name: String = RwBinary.read_utf(stream)
		var block_length: int = stream.get_32()
		if block_name != "customUnits" or block_length < 0 or block_length > MAX_TEAM_BLOCK_BYTES or block_length > stream.get_available_bytes():
			connection_changed.emit("Custom unit data is invalid")
			_disconnect(false)
			return
		var block_result: Array = stream.get_data(block_length)
		var unit_block: StreamPeerBuffer = RwBinary.reader(block_result[1])
		unit_block.get_32()
		var custom_unit_count: int = unit_block.get_32()
		if custom_unit_count != RwVanillaUnits.HASHES.size():
			connection_changed.emit("The room unit list doesn't match the original 1.15 version")
			_disconnect(false)
			return
		for index: int in custom_unit_count:
			var unit_name: String = RwBinary.read_utf(unit_block)
			var unit_hash: int = unit_block.get_32()
			unit_block.get_u8()
			var mod_name: String = RwBinary.read_nullable_utf(unit_block)
			var steam_id: int = unit_block.get_64()
			unit_block.get_64()
			if not RwVanillaUnits.HASHES.has(unit_name) or RwVanillaUnits.HASHES[unit_name] != unit_hash or not mod_name.is_empty() or steam_id != 0:
				connection_changed.emit("The room contains non-original units: %s" % unit_name)
				_disconnect(false)
				return
	settings["vanilla"] = true
	if _has_player_update:
		_confirm_join()
	room_updated.emit(settings, players, local_slot)


func _read_players(payload: PackedByteArray) -> void:
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	local_slot = stream.get_32()
	var partial_update: bool = stream.get_u8() != 0
	var slot_count: int = stream.get_32()
	var block_name: String = RwBinary.read_utf(stream)
	var block_length: int = stream.get_32()
	if block_name != "teams" or block_length < 0 or block_length > MAX_TEAM_BLOCK_BYTES or block_length > stream.get_available_bytes():
		connection_changed.emit("Player list data is invalid")
		return
	var block_result: Array = stream.get_data(block_length)
	var compressed: PackedByteArray = block_result[1]
	var team_bytes: PackedByteArray = compressed.decompress_dynamic(MAX_TEAM_BLOCK_BYTES, FileAccess.COMPRESSION_GZIP)
	if team_bytes.is_empty() or slot_count < 0 or slot_count > 100:
		connection_changed.emit("Can't unzip the player list")
		return
	var teams: StreamPeerBuffer = RwBinary.reader(team_bytes)
	var updated_players: Array[Dictionary] = []
	for slot: int in slot_count:
		if teams.get_u8() == 0:
			continue
		var is_ai: bool = teams.get_32() == 1
		if partial_update:
			var previous: Dictionary = _find_player(slot)
			teams.get_u8()
			previous["ping"] = teams.get_32()
			previous["connected"] = teams.get_u8() != 0
			previous["network_active"] = teams.get_u8() != 0
			updated_players.append(previous)
		else:
			updated_players.append(_read_full_player(teams, slot, is_ai))
	players = updated_players
	_read_player_settings_footer(stream)
	if not battle_map_info.is_empty():
		battle_economy.set_income_multiplier(float(settings.get("income_multiplier", 1.0)))
		if _battle_view_ready and not partial_update:
			for player: Dictionary in updated_players:
				battle_economy.reconcile_credits(int(player["slot"]), float(player["credits"]))
	if not _has_player_update:
		_has_player_update = true
		_send_client_status()
		if not bool(settings.get("vanilla", false)):
			connection_changed.emit("Checking original unit list…")
	if bool(settings.get("vanilla", false)):
		_confirm_join()
	room_updated.emit(settings, players, local_slot)


func _read_player_settings_footer(stream: StreamPeerBuffer) -> void:
	if stream.get_available_bytes() < 14:
		return
	settings["fog"] = stream.get_32()
	settings["credits"] = stream.get_32()
	settings["revealed"] = stream.get_u8() != 0
	settings["ai_difficulty"] = stream.get_32()
	var settings_version: int = stream.get_u8()
	if settings_version >= 1 and stream.get_available_bytes() >= 8:
		settings["unit_cap"] = stream.get_32()
		settings["max_unit_cap"] = stream.get_32()
	if settings_version >= 2 and stream.get_available_bytes() >= 10:
		settings["starting_units"] = stream.get_32()
		settings["income_multiplier"] = stream.get_float()
		settings["no_nukes"] = stream.get_u8() != 0
		stream.get_u8()
	if settings_version >= 3 and stream.get_available_bytes() >= 1:
		stream.get_u8()
	if settings_version >= 4 and stream.get_available_bytes() >= 1:
		settings["shared_control"] = stream.get_u8() != 0
	if settings_version >= 5 and stream.get_available_bytes() >= 1:
		settings["game_paused"] = stream.get_u8() != 0


func _confirm_join() -> void:
	if _joined:
		return
	_joined = true
	connection_changed.emit("Entered a vanilla non-mod room")


func _read_full_player(stream: StreamPeerBuffer, slot: int, is_ai: bool) -> Dictionary:
	stream.get_8()
	var credits: int = stream.get_32()
	var balances: Dictionary = _find_player(slot).get("team_resources", {}).duplicate()
	balances["credits"] = float(credits)
	var color: int = stream.get_32()
	var _name: String = RwBinary.read_nullable_utf(stream)
	stream.get_u8()
	var network_id: int = stream.get_32()
	stream.get_64()
	var ai_flag: bool = stream.get_u8() != 0
	var spectator: bool = color == -3
	var ping: int = stream.get_32()
	var sort_index: int = stream.get_32()
	stream.get_u8()
	var connected: bool = stream.get_u8() != 0
	var network_active: bool = stream.get_u8() != 0
	stream.get_u8()
	stream.get_u8()
	stream.get_32()
	RwBinary.read_nullable_utf(stream)
	var host_flag: int = stream.get_32()
	RwBinary.read_nullable_int(stream)
	var starting_units_override: int = RwBinary.read_nullable_int(stream)
	RwBinary.read_nullable_int(stream)
	RwBinary.read_nullable_int(stream)
	var assigned_color: int = stream.get_32()
	return {
		"slot": slot,
		"name": _name,
		"credits": credits,
		"team_resources": balances,
		"ai": is_ai or ai_flag,
		"color": color,
		"spectator": spectator,
		"ping": ping,
		"sort_index": sort_index,
		"connected": connected,
		"network_active": network_active,
		"network_id": network_id,
		"host": host_flag != 0,
		"assigned_color": assigned_color,
		"starting_units_override": starting_units_override,
	}


func _find_player(slot: int) -> Dictionary:
	for player: Dictionary in players:
		if player["slot"] == slot:
			return player.duplicate()
	return {
		"slot": slot,
		"name": "Player %d" % (slot + 1),
		"ai": false,
		"spectator": false,
	}


func _read_chat(payload: PackedByteArray) -> void:
	var stream: StreamPeerBuffer = RwBinary.reader(payload)
	var message: String = RwBinary.read_utf(stream)
	var version: int = stream.get_u8()
	var sender: String = RwBinary.read_nullable_utf(stream)
	stream.get_32()
	if version >= 3:
		stream.get_32()
	var display_sender: String = sender if not sender.is_empty() else "System"
	chat_log.append({"sender": display_sender, "message": message,})
	if chat_log.size() > 80:
		chat_log.remove_at(0)
	chat_received.emit(display_sender, message)


func _reply_ping(payload: PackedByteArray) -> void:
	var incoming: StreamPeerBuffer = RwBinary.reader(payload)
	var timestamp: int = incoming.get_64()
	var reply: StreamPeerBuffer = RwBinary.writer()
	reply.put_64(timestamp)
	reply.put_u8(1)
	reply.put_u8(60)
	_send_packet(109, reply.data_array)


func _send_client_status(game_view_running: bool = false) -> void:
	var stream: StreamPeerBuffer = RwBinary.writer()
	stream.put_u8(0)
	stream.put_u8(1 if game_view_running else 0)
	_send_packet(112, stream.data_array)


func _read_battle_frame(payload: PackedByteArray) -> void:
	if battle_map_info.is_empty():
		return
	var error: String = battle_timeline.receive_sync_packet(payload)
	if not error.is_empty():
		connection_changed.emit(error)


func _reply_checksum_unavailable(payload: PackedByteArray) -> void:
	if payload.size() < 12 or battle_map_info.is_empty():
		return
	var source: StreamPeerBuffer = RwBinary.reader(payload)
	var checksum_frame: int = source.get_32()
	var server_checksum: int = source.get_64()
	var fields: Array[int] = []
	if source.get_available_bytes() >= 4:
		var count: int = source.get_32()
		if count >= 0 and count <= MAX_CHECKSUM_FIELDS and source.get_available_bytes() >= count * 8:
			for index: int in count:
				fields.append(source.get_64())
	checksum_requested.emit(checksum_frame, server_checksum, fields)
	var response: StreamPeerBuffer = RwBinary.writer()
	response.put_u8(0)
	response.put_32(checksum_frame)
	response.put_32(-1)
	response.put_u8(0)
	_send_packet(31, response.data_array)


func _starting_credits_amount(preset: int) -> int:
	var values: Array[int] = [4000, 0, 1000, 2000, 5000, 10000, 50000, 100000, 200000,]
	if preset >= 0 and preset < values.size():
		return values[preset]
	return 999


func _on_battle_frame_advanced(frame: int, next_blocking_frame: int) -> void:
	battle_economy.advance_to(frame)
	battle_frame_advanced.emit(frame, next_blocking_frame)


func _on_economy_balance_changed(team_slot: int, resource_id: String, balance: float, growth: float) -> void:
	for player: Dictionary in players:
		if int(player.get("slot", -1)) != team_slot:
			continue
		var balances: Dictionary = player.get("team_resources", {})
		balances[resource_id] = balance
		player["team_resources"] = balances
		if resource_id == "credits":
			player["credits"] = floori(balance)
		break
	team_resource_changed.emit(team_slot, resource_id, balance, growth)


func _on_battle_commands_reached(frame: int, commands: Array[Dictionary]) -> void:
	battle_commands_reached.emit(frame, commands)


func _send_packet(packet_type: int, payload: PackedByteArray) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var packet: StreamPeerBuffer = RwBinary.writer()
	packet.put_32(payload.size())
	packet.put_32(packet_type)
	packet.put_data(payload)
	var error: Error = _peer.put_data(packet.data_array)
	if error != OK:
		connection_changed.emit("Failed to send room data: %s" % error_string(error))
		_disconnect(false)


func _integrity_response(_seed: int) -> String:
	var credit_values: Array[int] = [4000, 0, 1000, 2000, 5000, 10000, 50000, 100000, 200000,]
	var response: String = "c:%dm:%d" % [_seed, _signed_32(_seed * 87 + 24)]
	for index: int in credit_values.size():
		var amount: int = credit_values[index]
		var value: int
		if index == 0:
			value = _signed_32(amount * 11 * _seed)
		elif index == 1 or index == 3 or index == 5:
			value = _signed_32(amount * (index + 11) + _seed)
		else:
			value = _signed_32(amount * (index + 11) * _seed)
		response += "%d:%d" % [index, value]
	response += "t1:%s" % _java_double_integer(44000 * _seed)
	response += "d:%d" % _signed_32(5 * _seed)
	return response


func _java_double_integer(value: int) -> String:
	var digits: String = str(value)
	if value < 10_000_000:
		return digits + ".0"
	var fraction: String = digits.substr(1)
	while fraction.ends_with("0"):
		fraction = fraction.substr(0, fraction.length() - 1)
	if fraction.is_empty():
		fraction = "0"
	return "%s.%sE%d" % [digits.substr(0, 1), fraction, digits.length() - 1]


func _signed_32(value: int) -> int:
	return posmod(value + 2147483648, 4294967296) - 2147483648
