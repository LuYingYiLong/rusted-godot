extends Control

const JOIN_SCENE_UID: String = "uid://c75kjomieop5w"
const BATTLE_MAP_SCENE_UID: String = "uid://c0w7n4afw43pa"

@onready var info_label: RichTextLabel = %InfoLabel
@onready var status_label: Label = %StatusLabel
@onready var chat_history: RichTextLabel = %ChatHistory
@onready var chat_input: LineEdit = %ChatInput
@onready var send_button: Button = %SendButton


func _ready() -> void:
	RwRoomClient.connection_changed.connect(_on_connection_changed)
	RwRoomClient.room_updated.connect(_on_room_updated)
	RwRoomClient.chat_received.connect(_on_chat_received)
	RwRoomClient.game_started.connect(_on_game_started)
	_on_room_updated(RwRoomClient.settings, RwRoomClient.players, RwRoomClient.local_slot)
	_refresh_actions()
	status_label.text = "Joined a vanilla room"


func _on_exit_button_pressed() -> void:
	AudioManager.play_ui(&"click")
	if RwRoomClient != null:
		RwRoomClient.leave_room()
	get_tree().change_scene_to_file(JOIN_SCENE_UID)


func _on_send_button_pressed() -> void:
	var message: String = chat_input.text.strip_edges()
	if message.is_empty() or not RwRoomClient.is_joined():
		return
	RwRoomClient.send_chat(message)
	chat_input.clear()


func _on_chat_submitted(_text: String) -> void:
	_on_send_button_pressed()


func _on_connection_changed(message: String) -> void:
	status_label.text = message
	_refresh_actions()


func _on_room_updated(settings: Dictionary, players: Array[Dictionary], local_slot: int) -> void:
	var lines: Array[String] = [
		"Map: %s" % str(settings.get("map", "Waiting for map info...")),
		"Starting Credits: %s" % str(settings.get("credits", "--")),
		"Current seat: %s" % (str(local_slot + 1) if local_slot >= 0 else "--"),
		"",
		"Player seat",
	]
	for player: Dictionary in players:
		var display_name: String = str(player.get("name", ""))
		if display_name.is_empty():
			display_name = "AI" if bool(player.get("ai", false)) else "Player"
		var badges: String = ""
		if bool(player.get("host", false)):
			badges += " · Host"
		if bool(player.get("spectator", false)):
			badges += " · Spectator"
		if bool(player.get("ai", false)):
			badges += " · AI"
		if int(player.get("slot", -1)) == local_slot:
			badges += " · Me"
		lines.append("%02d  %s%s" % [int(player.get("slot", 0)) + 1, display_name, badges])
	info_label.text = "\n".join(lines)
	_refresh_actions()


func _on_chat_received(sender: String, message: String) -> void:
	chat_history.append_text("%s: %s\n" % [sender, message])
	AudioManager.play_ui(&"message")


func _on_game_started() -> void:
	AudioManager.play_music(&"battle")
	get_tree().change_scene_to_file(BATTLE_MAP_SCENE_UID)


func _refresh_actions() -> void:
	if RwRoomClient == null:
		return
	send_button.disabled = not RwRoomClient.is_joined()
	chat_input.editable = RwRoomClient.is_joined()
