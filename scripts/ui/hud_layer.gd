class_name RwHudLayer
extends CanvasLayer

const JOIN_SCENE_UID: String = "uid://c75kjomieop5w"
const RESOURCE_LABEL_SCENE: PackedScene = preload("uid://mb863ppm1pam")
const SELECTED_UNIT_ITEM_SCENE: PackedScene = preload("uid://mb863ppm1pam")
const UNIT_ACTION_ITEM_SCENE: PackedScene = preload("uid://wh8q385lnnig")

@onready var message_label: RichTextLabel = %MessageLabel
@onready var unit_info_label: Label = %UnitInfoLabel
@onready var chat_history: RichTextLabel = %ChatHistory
@onready var chat_input: LineEdit = %ChatInput
@onready var send_button: Button = %SendButton
@onready var resource_container: VBoxContainer = %ResourceContainer

var _chat_lines: Array[String]
var _resource_labels: Dictionary
var _resource_catalog: RwResourceCatalog = RwResourceCatalog.create_vanilla()


func _ready() -> void:
	RwRoomClient.connection_changed.connect(_on_connection_changed)
	RwRoomClient.room_updated.connect(_on_room_updated)
	RwRoomClient.chat_received.connect(_on_chat_received)
	RwRoomClient.team_resource_changed.connect(_on_team_resource_changed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	send_button.pressed.connect(_on_send_button_pressed)
	var credits_label: RwResourceLabel = resource_container.get_node("ResourceLabel") as RwResourceLabel
	_resource_labels[credits_label.resource_id] = credits_label
	for entry: Dictionary in RwRoomClient.chat_log:
		_on_chat_received(str(entry.get("sender", "System")), str(entry.get("message", "")))
	_on_room_updated(RwRoomClient.settings, RwRoomClient.players, RwRoomClient.local_slot)


func show_status(message: String) -> void:
	message_label.text = message


func show_selected_unit(unit_state: RwUnitState, relation_name: String = "") -> void:
	if unit_state == null:
		unit_info_label.text = "Select a unit or drag to select your units"
		return
	var order_text: String = " · Order: %s" % unit_state.order_type if not unit_state.order_type.is_empty() else ""
	unit_info_label.text = "%s · %s #%d · Team %s · HP %.0f/%.0f · (%.0f, %.0f)%s" % [
		relation_name,
		unit_state.unit_name,
		unit_state.object_id,
		unit_state.team,
		unit_state.health,
		unit_state.max_health,
		unit_state.world_position.x,
		unit_state.world_position.y,
		order_text,
	]


func show_selected_count(count: int) -> void:
	unit_info_label.text = "%d own units selected · Right-click the map to move" % count


func _on_leave_button_pressed() -> void:
	RwRoomClient.leave_room()
	get_tree().change_scene_to_file(JOIN_SCENE_UID)


func _on_connection_changed(message: String) -> void:
	message_label.append_text("\n%s" % message)
	_update_chat_availability()


func _on_room_updated(_settings: Dictionary, players: Array[Dictionary], local_slot: int) -> void:
	_update_chat_availability()
	for player: Dictionary in players:
		if int(player.get("slot", -1)) != local_slot:
			continue
		var balances: Dictionary = player.get("team_resources", {})
		for resource_id: String in balances:
			_set_resource_balance(
				resource_id,
				float(balances[resource_id]),
				RwRoomClient.battle_economy.get_income_rate(local_slot, resource_id)
			)
		return
	_set_resource_balance("credits", 0.0, 0.0)


func _on_team_resource_changed(team_slot: int, resource_id: String, balance: float, growth: float) -> void:
	if team_slot == RwRoomClient.local_slot:
		_set_resource_balance(resource_id, balance, growth)


func _on_chat_received(sender: String, message: String) -> void:
	_chat_lines.append("%s: %s" % [sender, message])
	if _chat_lines.size() > 80:
		_chat_lines.remove_at(0)
	chat_history.text = "\n".join(_chat_lines)


func _on_chat_submitted(_text: String) -> void:
	_on_send_button_pressed()


func _on_send_button_pressed() -> void:
	var message: String = chat_input.text.strip_edges()
	if message.is_empty() or not RwRoomClient.is_joined():
		return
	RwRoomClient.send_chat(message)
	chat_input.clear()


func _update_chat_availability() -> void:
	chat_input.editable = RwRoomClient.is_joined()
	send_button.disabled = not RwRoomClient.is_joined()


func _set_resource_balance(resource_id: String, balance: float, growth: float) -> void:
	var definition: RwResourceDefinition = _resource_catalog.find_definition(resource_id)
	if definition == null or not definition.display_in_hud:
		return
	var label: RwResourceLabel = _resource_labels.get(resource_id) as RwResourceLabel
	if label == null:
		label = RESOURCE_LABEL_SCENE.instantiate() as RwResourceLabel
		label.resource_id = resource_id
		label.display_rounded_down = definition.display_rounded_down
		resource_container.add_child(label)
		_resource_labels[resource_id] = label
	label.set_values(balance, growth)
