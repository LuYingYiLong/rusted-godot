extends Control

const LOBBY_SCENE_UID: String = "uid://kbqq6run7b25"

@onready var nickname_line_edit: LineEdit = %NicknameLineEdit
@onready var room_id_line_edit: LineEdit = %RoomIDLineEdit
@onready var ip_line_edit: LineEdit = %IPLineEdit
@onready var password_line_edit: LineEdit = %PasswordLineEdit
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	RwRoomClient.name = "RwRoomClient"
	RwRoomClient.connection_changed.connect(_on_connection_changed)
	AudioManager.play_music(&"menu")
	# 自动设置语言
	var preferred_language: String = OS.get_locale_language()
	TranslationServer.set_locale(preferred_language)
	_update_join_button()


func _on_join_button_pressed() -> void:
	AudioManager.play_ui(&"click")
	var room_id: String = room_id_line_edit.text.strip_edges()
	var ip_address: String = ip_line_edit.text.strip_edges()
	if not room_id.is_empty():
		RwRoomClient.join_room_id(room_id, nickname_line_edit.text, password_line_edit.text)
	elif not ip_address.is_empty():
		RwRoomClient.join_room(ip_address, nickname_line_edit.text, password_line_edit.text)
	else:
		status_label.text = "Enter a room code or IP address"
		AudioManager.play_ui(&"error")
	_update_join_button()


func _on_input_submitted(_text: String) -> void:
	_on_join_button_pressed()


func _on_connection_changed(message: String) -> void:
	status_label.text = message
	_update_join_button()
	if RwRoomClient.is_joined():
		AudioManager.play_ui(&"add")
		get_tree().change_scene_to_file(LOBBY_SCENE_UID)


func _update_join_button() -> void:
	join_button.disabled = RwRoomClient.is_active()
