class_name RwHudLayer
extends CanvasLayer

signal minimap_position_chosen(world_position: Vector2)
signal unit_action_chosen(action_id: String, unit_ids: Array[int])
signal unit_action_cancelled(action_id: String, unit_ids: Array[int])
signal unit_group_selected(unit_ids: Array[int])

const JOIN_SCENE_UID: String = "uid://c75kjomieop5w"
const RESOURCE_LABEL_SCENE: PackedScene = preload("uid://mb863ppm1pam")
const SELECTED_UNIT_ITEM_SCENE: PackedScene = preload("uid://wh8q385lnnig")
const UNIT_ACTION_ITEM_SCENE: PackedScene = preload("uid://bmw3cmgk62apu")
const MINIMAP_REFRESH_SECONDS: float = 0.2

@onready var chat_panel: RwChatPanel = %ChatPanel
@onready var unit_description_panel: RwUnitDescriptionPanel = %UnitDescriptionPanel
@onready var resource_container: VBoxContainer = %ResourceContainer
@onready var minimap: RwMinimap = %Minimap
@onready var unit_info_container: GridContainer = %UnitInfoContainer
@onready var health_label: Label = %HealthLabel
@onready var unit_action_scroll_container: ScrollContainer = %UnitActionScrollContainer
@onready var unit_action_container: GridContainer = %UnitActionContainer
@onready var selected_unit_scroll_container: ScrollContainer = %SelectedUnitScrollContainer
@onready var selected_unit_container: GridContainer = %SelectedUnitContainer
@onready var reclaim_button: Button = %ReclaimButton
@onready var patrol_button: Button = %SetPatrolAreaButton
@onready var escort_button: Button = %EscortUnitButton

var _resource_labels: Dictionary
var _resource_catalog: RwResourceCatalog = RwResourceCatalog.create_vanilla()
var _unit_asset_provider: RwVanillaUnitAssets = RwVanillaUnitAssets.new()
var _unit_registry: RwUnitRegistry
var _unit_states: Dictionary
var _unit_visuals: Dictionary
var _players: Array[Dictionary]
var _local_slot: int = -1
var _selected_units: Array[RwUnitState]
var _selected_ids: Array[int]
var _selected_groups: Dictionary
var _focused_unit_key: String
var _minimap_refresh_timer: float
var _description_source: Control


func _ready() -> void:
	RwRoomClient.room_updated.connect(_on_room_updated)
	RwRoomClient.team_resource_changed.connect(_on_team_resource_changed)
	_clear_children(resource_container)
	_clear_dynamic_items(unit_info_container)
	_clear_dynamic_items(unit_action_container)
	_clear_children(selected_unit_container)
	_on_room_updated(RwRoomClient.settings, RwRoomClient.players, RwRoomClient.local_slot)
	_refresh_selection_details()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("send_message") and not event.is_echo():
		chat_panel.toggle_chat()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if unit_description_panel.visible:
		_update_description_position()
	_minimap_refresh_timer -= delta
	if _minimap_refresh_timer <= 0.0:
		_minimap_refresh_timer = MINIMAP_REFRESH_SECONDS
		minimap.refresh_units()
		_refresh_selection_details()


func show_status(message: String) -> void:
	chat_panel.show_status(message)


func configure_battle(map_name: String, world_size: Vector2, unit_states: Dictionary, unit_registry: RwUnitRegistry) -> String:
	_unit_states = unit_states
	_unit_registry = unit_registry
	return minimap.configure(map_name, world_size, unit_states, _players, _local_slot)


func set_fog(fog: RwFogOfWar) -> void:
	minimap.set_fog(fog)


func update_camera_view(camera_position: Vector2, camera_zoom: float, viewport_size: Vector2) -> void:
	minimap.update_view(camera_position, camera_zoom, viewport_size)


func show_selection(selected_units: Array[RwUnitState], unit_visuals: Dictionary) -> void:
	var selected_ids: Array[int] = []
	for unit_state: RwUnitState in selected_units:
		selected_ids.append(unit_state.object_id)
	if selected_ids == _selected_ids:
		_refresh_selection_details()
		return
	_selected_ids = selected_ids
	_selected_units = selected_units.duplicate()
	_unit_visuals = unit_visuals
	_selected_groups.clear()
	_focused_unit_key = ""
	for unit_state: RwUnitState in _selected_units:
		var unit_key: String = "%s:%s" % [unit_state.source_id, unit_state.unit_name]
		if not _selected_groups.has(unit_key):
			_selected_groups[unit_key] = []
		(_selected_groups[unit_key] as Array).append(unit_state)
	_render_selection()


func set_production_status(status: Dictionary) -> void:
	for child: Node in unit_action_container.get_children():
		var item: RwUnitActionItem = child as RwUnitActionItem
		if item == null:
			continue
		var entry: Dictionary = status.get(item.action_id, {})
		item.set_production_status(
			int(entry.get("count", 0)),
			float(entry.get("progress", 0.0)),
			bool(entry.get("active", false)),
		)


func _render_selection() -> void:
	_hide_description()
	_clear_dynamic_items(unit_info_container)
	_clear_dynamic_items(unit_action_container)
	_clear_children(selected_unit_container)
	unit_info_container.hide()
	unit_action_scroll_container.hide()
	selected_unit_scroll_container.hide()
	reclaim_button.hide()
	if _selected_units.is_empty():
		_refresh_selection_details()
		return
	if _selected_groups.size() > 1 and _focused_unit_key.is_empty():
		selected_unit_scroll_container.show()
		for unit_key: String in _selected_groups:
			var group: Array = _selected_groups[unit_key]
			var first_unit: RwUnitState = group[0] as RwUnitState
			var item: RwSelectedUnitItem = SELECTED_UNIT_ITEM_SCENE.instantiate() as RwSelectedUnitItem
			selected_unit_container.add_child(item)
			item.configure(unit_key, first_unit.unit_name, group.size(), _icon_for_unit(first_unit))
			item.selected.connect(_on_unit_type_selected)
			item.hovered.connect(_on_selected_item_hovered)
			item.unhovered.connect(_on_description_item_unhovered)
		_refresh_selection_details()
		return
	if _focused_unit_key.is_empty():
		_focused_unit_key = str(_selected_groups.keys()[0])
	var focused_group: Array = _selected_groups.get(_focused_unit_key, [])
	if focused_group.is_empty():
		return
	var focused_unit: RwUnitState = focused_group[0] as RwUnitState
	var definition: RwUnitDefinition = _unit_registry.find_definition(focused_unit.source_id, focused_unit.unit_name) if _unit_registry != null else null
	var info_item: RwSelectedUnitItem = SELECTED_UNIT_ITEM_SCENE.instantiate() as RwSelectedUnitItem
	unit_info_container.add_child(info_item)
	unit_info_container.move_child(info_item, 0)
	info_item.configure(_focused_unit_key, focused_unit.unit_name, focused_group.size(), _icon_for_unit(focused_unit))
	info_item.set_focused(_selected_groups.size() > 1)
	info_item.selected.connect(_on_focused_item_selected)
	info_item.hovered.connect(_on_selected_item_hovered)
	info_item.unhovered.connect(_on_description_item_unhovered)
	var can_control: bool = focused_unit.team == str(_local_slot)
	var can_move: bool = definition != null and definition.movement_speed > 0.0 and can_control
	patrol_button.visible = can_move
	escort_button.visible = can_move
	if definition != null and can_control:
		reclaim_button.visible = definition.can_reclaim
		for action: RwUnitActionDefinition in definition.build_actions:
			var action_item: RwUnitActionItem = UNIT_ACTION_ITEM_SCENE.instantiate() as RwUnitActionItem
			unit_action_container.add_child(action_item)
			action_item.configure(action, _icon_for_action(action, focused_unit.team))
			action_item.activated.connect(_on_unit_action_activated)
			action_item.cancelled.connect(_on_unit_action_cancelled)
			action_item.hovered.connect(_on_action_item_hovered)
			action_item.unhovered.connect(_on_description_item_unhovered)
	_refresh_action_affordability()
	unit_info_container.show()
	unit_action_scroll_container.show()
	_refresh_selection_details()


func _refresh_selection_details() -> void:
	if _selected_units.is_empty() or _focused_unit_key.is_empty():
		return
	var group: Array = _selected_groups.get(_focused_unit_key, [])
	if group.is_empty():
		return
	var total_health: float = 0.0
	var total_max_health: float = 0.0
	for unit_state: RwUnitState in group:
		total_health += unit_state.health
		total_max_health += unit_state.max_health
	health_label.text = "%.0f/%.0f" % [total_health, total_max_health]


func _icon_for_unit(unit_state: RwUnitState) -> Texture2D:
	var visual: RwUnitVisual = _unit_visuals.get(unit_state.object_id) as RwUnitVisual
	if visual != null:
		return visual.get_icon_texture()
	return RwDrawableCatalog.load_texture("error.png")


func _icon_for_action(action: RwUnitActionDefinition, team: String) -> Texture2D:
	var team_color: Color = RwUnitTeamColors.for_team(team, _players)
	var source_texture: Texture2D = _unit_asset_provider.load_team_texture(action.icon_image, team_color)
	if source_texture == null:
		return RwDrawableCatalog.load_texture("error.png")
	if action.icon_frames <= 1:
		return source_texture
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = source_texture
	atlas.region = Rect2(Vector2.ZERO, Vector2(float(source_texture.get_width()) / float(action.icon_frames), float(source_texture.get_height())))
	return atlas


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _clear_dynamic_items(container: Node) -> void:
	for child: Node in container.get_children():
		if child is RwSelectedUnitItem or child is RwUnitActionItem:
			container.remove_child(child)
			child.queue_free()


func _refresh_action_affordability() -> void:
	var balances: Dictionary = {}
	for player: Dictionary in _players:
		if int(player.get("slot", -1)) == _local_slot:
			balances = player.get("team_resources", {})
			break
	for child: Node in unit_action_container.get_children():
		var item: RwUnitActionItem = child as RwUnitActionItem
		if item == null or item.action_definition == null:
			continue
		var is_affordable: bool = true
		for resource_id: String in item.action_definition.resource_costs:
			var cost: float = float(item.action_definition.resource_costs[resource_id])
			var balance: float = float(balances.get(resource_id, 0.0))
			if resource_id == "credits":
				balance = RwRoomClient.battle_economy.get_balance(_local_slot, resource_id)
			if balance < cost:
				is_affordable = false
				break
		item.set_affordable(is_affordable)


func _on_selected_item_hovered(item: RwSelectedUnitItem) -> void:
	var group: Array = _selected_groups.get(item.unit_key, [])
	if group.is_empty():
		return
	var unit_state: RwUnitState = group[0] as RwUnitState
	var definition: RwUnitDefinition = _unit_registry.find_definition(unit_state.source_id, unit_state.unit_name) if _unit_registry != null else null
	var unit_name: String = unit_state.unit_name
	var lines: Array[String] = []
	if definition != null:
		if not definition.display_name.is_empty():
			unit_name = definition.display_name
		if not definition.description.is_empty():
			lines.append(definition.description)
	lines.append("HP: %.0f/%.0f" % [unit_state.health, unit_state.max_health])
	if definition != null and definition.attack_range > 0.0:
		lines.append("Range: %.0f" % definition.attack_range)
	if unit_state.movement_speed > 0.0:
		lines.append("Speed: %.1f" % unit_state.movement_speed)
	_show_description(item, item.unit_texture.texture, unit_name, "\n".join(lines))


func _on_action_item_hovered(item: RwUnitActionItem) -> void:
	var action: RwUnitActionDefinition = item.action_definition
	if action == null:
		return
	var description: String = action.description
	if description.is_empty():
		var verb: String = "Build" if _focused_unit_key.ends_with(":builder") else "Produce"
		description = "%s %s" % [verb, action.display_name]
	var credit_cost: float = float(action.resource_costs.get("credits", 0.0))
	if credit_cost > 0.0:
		description += "\nCost: %.0f credits" % credit_cost
	if action.build_rate_per_frame > 0.0:
		description += "\nTime: %.1f s" % (1.0 / action.build_rate_per_frame / 60.0)
	_show_description(item, item.unit_texture.texture, action.display_name, description)


func _on_description_item_unhovered(item: Control) -> void:
	if _description_source == item:
		_hide_description()


func _show_description(source: Control, icon: Texture2D, unit_name: String, description: String) -> void:
	_description_source = source
	unit_description_panel.configure(icon, unit_name, description)
	unit_description_panel.show()
	unit_description_panel.reset_size()
	_update_description_position()


func _hide_description() -> void:
	_description_source = null
	unit_description_panel.hide()


func _update_description_position() -> void:
	if not is_instance_valid(_description_source):
		_hide_description()
		return
	var mouse_y: float = get_viewport().get_mouse_position().y
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var max_y: float = maxf(0.0, viewport_height - unit_description_panel.size.y)
	var action_left: float = unit_action_container.get_global_rect().position.x
	unit_description_panel.global_position = Vector2(
		action_left - unit_description_panel.size.x,
		clampf(mouse_y, 0.0, max_y),
	)


func _on_unit_type_selected(unit_key: String) -> void:
	var group: Array = _selected_groups.get(unit_key, [])
	if group.is_empty():
		return
	var unit_ids: Array[int] = []
	for unit_state: RwUnitState in group:
		unit_ids.append(unit_state.object_id)
	unit_group_selected.emit(unit_ids)


func _on_focused_item_selected(_unit_key: String) -> void:
	if _selected_groups.size() > 1:
		_focused_unit_key = ""
		_render_selection()


func _on_unit_action_activated(action_id: String) -> void:
	_emit_focused_action(action_id)


func _on_unit_action_cancelled(action_id: String) -> void:
	var group: Array = _selected_groups.get(_focused_unit_key, [])
	var unit_ids: Array[int] = []
	for unit_state: RwUnitState in group:
		unit_ids.append(unit_state.object_id)
	if not unit_ids.is_empty():
		unit_action_cancelled.emit(action_id, unit_ids)


func _on_reclaim_button_pressed() -> void:
	_emit_focused_action("reclaim")


func _on_patrol_button_pressed() -> void:
	_emit_focused_action("patrol")


func _on_escort_button_pressed() -> void:
	_emit_focused_action("guard")


func _emit_focused_action(action_id: String) -> void:
	var group: Array = _selected_groups.get(_focused_unit_key, [])
	var unit_ids: Array[int] = []
	for unit_state: RwUnitState in group:
		unit_ids.append(unit_state.object_id)
	if not unit_ids.is_empty():
		unit_action_chosen.emit(action_id, unit_ids)


func _on_minimap_position_chosen(world_position: Vector2) -> void:
	minimap_position_chosen.emit(world_position)


func _on_leave_button_pressed() -> void:
	RwRoomClient.leave_room()
	get_tree().change_scene_to_file(JOIN_SCENE_UID)


func _on_room_updated(_settings: Dictionary, players: Array[Dictionary], local_slot: int) -> void:
	_players = players
	_local_slot = local_slot
	minimap.update_team_view(players, local_slot)
	for player: Dictionary in players:
		if int(player.get("slot", -1)) != local_slot:
			continue
		var balances: Dictionary = player.get("team_resources", {})
		if balances.is_empty():
			_set_resource_balance("credits", 0.0, RwRoomClient.battle_economy.get_income_rate(local_slot, "credits"))
		for resource_id: String in balances:
			_set_resource_balance(
				resource_id,
				float(balances[resource_id]),
				RwRoomClient.battle_economy.get_income_rate(local_slot, resource_id),
			)
		_refresh_action_affordability()
		return
	_set_resource_balance("credits", 0.0, 0.0)
	_refresh_action_affordability()


func _on_team_resource_changed(team_slot: int, resource_id: String, balance: float, growth: float) -> void:
	if team_slot == RwRoomClient.local_slot:
		_set_resource_balance(resource_id, balance, growth)
		_refresh_action_affordability()


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
