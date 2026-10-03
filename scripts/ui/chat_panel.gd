class_name RwChatPanel
extends PanelContainer

const MAX_MESSAGE_LINES: int = 80
const PREVIEW_MESSAGE_LINES: int = 8

@onready var main_panel: VBoxContainer = $VBoxContainer
@onready var message_label: RichTextLabel = %MessageLabel
@onready var team_check_button: CheckButton = %TeamCheckButton
@onready var line_edit: LineEdit = %LineEdit
@onready var send_button: Button = %SendButton
@onready var preview_message_label: RichTextLabel = %PreviewMessageLabel
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var _message_lines: Array[String]


func _ready() -> void:
	RwRoomClient.chat_received.connect(_on_chat_received)
	RwRoomClient.connection_changed.connect(_on_connection_changed)
	RwRoomClient.room_updated.connect(_on_room_updated)
	for entry: Dictionary in RwRoomClient.chat_log:
		_append_message(str(entry.get("sender", "System")), str(entry.get("message", "")), false)
	_update_availability()


func toggle_chat() -> void:
	if main_panel.visible:
		submit_or_hide()
		return
	animation_player.stop()
	preview_message_label.hide()
	show()
	main_panel.show()
	line_edit.grab_focus()


func submit_or_hide() -> void:
	var message: String = line_edit.text.strip_edges()
	if not message.is_empty():
		RwRoomClient.send_chat(message, team_check_button.button_pressed)
		line_edit.clear()
	line_edit.release_focus()
	main_panel.hide()
	hide()


func append_message(sender: String, message: String) -> void:
	_append_message(sender, message, true)


func show_status(message: String) -> void:
	append_message("System", message)


func _append_message(sender: String, message: String, show_preview: bool) -> void:
	_message_lines.append("%s: %s" % [sender, message])
	if _message_lines.size() > MAX_MESSAGE_LINES:
		_message_lines.remove_at(0)
	message_label.clear()
	message_label.add_text("\n".join(_message_lines))
	if show_preview and not main_panel.visible:
		var preview_lines: Array[String] = []
		for index: int in range(maxi(_message_lines.size() - PREVIEW_MESSAGE_LINES, 0), _message_lines.size()):
			preview_lines.append(_message_lines[index])
		preview_message_label.clear()
		preview_message_label.add_text("\n".join(preview_lines))
		show()
		animation_player.stop()
		animation_player.play("preview")


func _update_availability() -> void:
	line_edit.editable = RwRoomClient.is_joined()
	send_button.disabled = not RwRoomClient.is_joined()


func _on_chat_received(sender: String, message: String) -> void:
	append_message(sender, message)


func _on_connection_changed(message: String) -> void:
	show_status(message)
	_update_availability()


func _on_room_updated(_settings: Dictionary, _players: Array[Dictionary], _local_slot: int) -> void:
	_update_availability()


func _on_text_submitted(_text: String) -> void:
	submit_or_hide()


func _on_preview_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"preview" and not main_panel.visible:
		hide()
