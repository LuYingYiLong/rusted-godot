extends Control

const MIN_ZOOM: float = 0.15
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 1.2
const ZOOM_SMOOTHING: float = 12.0
const SELECTION_DRAG_PIXELS: float = 8.0
const KEYBOARD_PAN_SPEED: float = 600.0
const NAVIGATION_COLOR: Color = Color("11c608")
const BUILD_RANGE: float = 85.0
const BUILD_RETRY_FRAMES: int = 12

@onready var map_root: Node2D = %MapRoot
@onready var map_camera: Camera2D = %MapCamera
@onready var fog_sprite: Sprite2D = %FogOverlay
@onready var navigation_overlay: Node2D = %NavigationOverlay
@onready var unit_layer: Node2D = %InitialUnits
@onready var projectile_layer: RwBattleProjectileLayer = %ProjectileLayer
@onready var vfx_layer: RwBattleVfxLayer = %BattleVfxLayer
@onready var selection_overlay: Control = %SelectionOverlay
@onready var hud_layer: RwHudLayer = $HudLayer

var _panning: bool
var _selection_pressed: bool
var _selection_dragging: bool
var _selection_additive: bool
var _selection_start_screen: Vector2
var _selection_end_screen: Vector2
var _world_size: Vector2
var _map_tile_size: Vector2i
var _target_zoom: float
var _zoom_anchor_screen: Vector2
var _zoom_anchor_world: Vector2
var _last_simulated_frame: int
var _unit_states: Dictionary
var _unit_visuals: Dictionary
var _unit_registry: RwUnitRegistry
var _combat: RwBattleCombat
var _unit_orders: RwUnitOrderController
var _fog: RwFogOfWar
var _path_grid: RwPathGrid
var _mobile_unit_states: Array[RwUnitState]
var _animated_command_centers: Array[RwUnitState]
var _animated_extractors: Array[RwUnitState]
var _animated_visual_units: Array[RwUnitState]
var _selected_unit_ids: Array[int]
var _production_queues: Dictionary
var _factory_rally_points: Dictionary
var _pending_queue_cancellations: Dictionary
var _build_sites: Array[Dictionary]
var _builder_site_ids: Dictionary
var _builder_site_queues: Dictionary
var _next_build_site_id: int = 1
var _placement_action: RwUnitActionDefinition
var _placement_builder_ids: Array[int]
var _placement_preview: RwUnitVisual
var _placement_position: Vector2
var _placement_error: String
var _special_order_type: String
var _special_order_unit_ids: Array[int]
var _next_object_id: int = 1


func _ready() -> void:
	RwRoomClient.connection_changed.connect(_on_room_connection_changed)
	RwRoomClient.battle_frame_advanced.connect(_on_battle_frame_advanced)
	RwRoomClient.battle_commands_reached.connect(_on_battle_commands_reached)
	RwRoomClient.room_updated.connect(_on_room_updated)
	_on_battle_frame_advanced(RwRoomClient.battle_timeline.current_frame, RwRoomClient.battle_timeline.next_blocking_frame)
	if RwRoomClient.battle_map_info.is_empty():
		hud_layer.show_status("No start-game map received")
		return
	var map_name: String = str(RwRoomClient.battle_map_info.get("map", ""))
	var result: Dictionary = RwTmxLoader.load_skirmish_map(map_root, map_name)
	if not str(result.get("error", "")).is_empty():
		hud_layer.show_status(str(result["error"]))
		return
	var map_size: Vector2i = result["size"]
	var tile_size: Vector2i = result["tile_size"]
	_map_tile_size = tile_size
	_world_size = Vector2(map_size * tile_size)
	map_camera.position = _world_size * 0.5
	var viewport_size: Vector2 = get_viewport_rect().size
	var fit_zoom: float = minf(viewport_size.x / _world_size.x, viewport_size.y / _world_size.y)
	_target_zoom = clampf(maxf(fit_zoom, 1.0), MIN_ZOOM, MAX_ZOOM)
	map_camera.zoom = Vector2.ONE * _target_zoom
	var unit_result: Dictionary = _render_initial_units(map_name)
	if not str(unit_result.get("error", "")).is_empty():
		hud_layer.show_status(str(unit_result["error"]))
		return
	_path_grid = RwPathGrid.load_map(map_name)
	if _path_grid == null:
		hud_layer.show_status("Could not build the map movement grid")
		return
	_block_initial_structures()
	_path_grid.finalize_obstacles()
	_unit_orders = RwUnitOrderController.new()
	_unit_orders.configure(_unit_states, _unit_registry, _path_grid)
	_unit_orders.order_applied.connect(_on_unit_order_applied)
	_combat = RwBattleCombat.new()
	_combat.projectile_fired.connect(_on_projectile_fired)
	_combat.projectile_impacted.connect(projectile_layer.show_impact)
	_combat.unit_destroyed.connect(_on_combat_unit_destroyed)
	_combat.configure(_unit_states, _unit_registry, RwRoomClient.players)
	projectile_layer.set_projectiles(_combat.projectiles)
	_focus_on_local_start()
	_initialize_fog(map_size, tile_size)
	var minimap_error: String = hud_layer.configure_battle(map_name, _world_size, _unit_states, _unit_registry)
	hud_layer.set_fog(_fog)
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)
	for extractor: RwUnitState in _animated_extractors:
		RwRoomClient.battle_economy.register_extractor(extractor)
	RwRoomClient.set_initial_command_centers(unit_result["command_center_counts"])
	var warning: String = " Minimap: %s." % minimap_error if not minimap_error.is_empty() else ""
	if int(RwRoomClient.settings.get("starting_units", 1)) != 1:
		warning = " The room uses a starting-unit preset that is not simulated."
	for player: Dictionary in RwRoomClient.players:
		var starting_units_override: int = int(player.get("starting_units_override", -1))
		if starting_units_override != -1 and starting_units_override != 1:
			warning = " A player uses a starting-unit override that is not simulated."
			break
	if not warning.is_empty():
		hud_layer.show_status(warning.strip_edges())
	RwRoomClient.mark_battle_map_loaded()
	AudioManager.play_music(&"battle")


func _render_initial_units(map_name: String) -> Dictionary:
	var parsed: Dictionary = RwTmxUnitReader.read_spawns(map_name)
	if not str(parsed.get("error", "")).is_empty():
		return parsed
	_unit_registry = RwVanillaUnitDefinitions.create_registry()
	var total: int = 0
	var defined: int = 0
	var placeholder: int = 0
	var command_center_counts: Dictionary
	for spawn: Dictionary in parsed["spawns"]:
		var team: String = str(spawn["team"])
		if not _is_active_team(team):
			continue
		var source_id: String = str(spawn["source_id"])
		var unit_name: String = str(spawn["unit_name"])
		var object_id: int = _unit_states.size() + 1
		spawn["object_id"] = object_id
		var definition: RwUnitDefinition = _unit_registry.find_definition(source_id, unit_name)
		var color: Color = RwUnitTeamColors.for_team(team, RwRoomClient.players)
		var visual: RwUnitVisual = _unit_registry.create_visual(spawn, color)
		visual.set_footprint_tile_size(_map_tile_size)
		visual.set_relation(RwUnitTeamColors.relation_for_team(team, RwRoomClient.players, RwRoomClient.local_slot))
		var unit_state: RwUnitState = RwUnitState.new()
		unit_state.initialize_from_spawn(spawn, definition)
		visual.bind_state(unit_state)
		unit_layer.add_child(visual)
		_unit_states[object_id] = unit_state
		_unit_visuals[object_id] = visual
		if unit_state.movement_speed > 0.0:
			_mobile_unit_states.append(unit_state)
		if unit_name == "commandCenter":
			_animated_command_centers.append(unit_state)
			if team.is_valid_int():
				var team_slot: int = team.to_int()
				command_center_counts[team_slot] = int(command_center_counts.get(team_slot, 0)) + 1
		if RwRoomClient.battle_economy.has_unit_income(unit_state):
			_animated_extractors.append(unit_state)
		if definition != null and definition.needs_visual_ticks():
			_animated_visual_units.append(unit_state)
		total += 1
		if definition == null:
			placeholder += 1
		else:
			defined += 1
	_next_object_id = _unit_states.size() + 1
	return {
		"error": "",
		"total": total,
		"defined": defined,
		"placeholder": placeholder,
		"command_center_counts": command_center_counts,
	}


func _is_active_team(team: String) -> bool:
	if team.to_lower() == "none":
		return true
	if not team.is_valid_int():
		return false
	for player: Dictionary in RwRoomClient.players:
		if int(player.get("slot", -1)) == team.to_int() and not bool(player.get("spectator", false)):
			return true
	return false


func _block_initial_structures() -> void:
	for unit_state: RwUnitState in _unit_states.values():
		var definition: RwUnitDefinition = _unit_registry.find_definition(unit_state.source_id, unit_state.unit_name)
		if definition != null and definition.blocks_movement:
			_path_grid.block_structure(unit_state.world_position, definition.structure_footprint_min, definition.structure_footprint_max)


func _initialize_fog(map_size: Vector2i, tile_size: Vector2i) -> void:
	_fog = RwFogOfWar.new()
	var fog_mode: int = int(RwRoomClient.settings.get("fog", RwFogOfWar.Mode.LOS_FOG))
	if RwRoomClient.local_slot < 0:
		fog_mode = RwFogOfWar.Mode.NO_FOG
	_fog.configure(map_size, tile_size, fog_mode, bool(RwRoomClient.settings.get("revealed", true)))
	fog_sprite.scale = Vector2(tile_size)
	_refresh_fog_visibility()


func _refresh_fog_visibility() -> void:
	if _fog == null:
		return
	var fog_changed: bool = _fog.update_visibility(_unit_states, RwRoomClient.players, RwRoomClient.local_slot)
	fog_sprite.texture = _fog.texture
	fog_sprite.visible = _fog.texture != null
	for object_id: int in _unit_states:
		var unit_state: RwUnitState = _unit_states[object_id]
		var visual: RwUnitVisual = _unit_visuals[object_id]
		visual.visible = _fog.is_unit_visible(unit_state, RwRoomClient.local_slot)
	if fog_changed:
		hud_layer.minimap.refresh_units()


func _process(delta: float) -> void:
	if _world_size == Vector2.ZERO:
		return
	_update_keyboard_pan(delta)
	_update_smooth_zoom(delta)
	if _placement_action != null:
		_update_placement_preview()
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)
	if _selection_pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_selection(get_viewport().get_mouse_position())
	if not _selected_unit_ids.is_empty():
		navigation_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _world_size == Vector2.ZERO:
		return
	if not _special_order_type.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_special_order()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_special_order(event.position)
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_special_order()
				get_viewport().set_input_as_handled()
				return
	if _placement_action != null:
		if event is InputEventKey:
			var key_event: InputEventKey = event
			if key_event.pressed and key_event.keycode == KEY_ESCAPE:
				_cancel_placement()
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseButton:
			var placement_click: InputEventMouseButton = event
			if placement_click.pressed and placement_click.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement(placement_click.shift_pressed)
				get_viewport().set_input_as_handled()
				return
			if placement_click.pressed and placement_click.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_placement()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event
		if button_event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button_event.pressed
		elif button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				_selection_pressed = true
				_selection_dragging = false
				_selection_additive = button_event.shift_pressed
				_selection_start_screen = button_event.position
				_selection_end_screen = button_event.position
			else:
				_finish_selection(button_event.position)
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_RIGHT:
			_request_move(button_event.position)
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_queue_zoom(button_event.position, ZOOM_STEP)
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_queue_zoom(button_event.position, 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event
		if _panning:
			_pan_by_screen_delta(motion_event.relative)
		elif _selection_pressed:
			_selection_end_screen = motion_event.position
			if _selection_start_screen.distance_to(_selection_end_screen) >= SELECTION_DRAG_PIXELS:
				_selection_dragging = true
			if _selection_dragging:
				selection_overlay.queue_redraw()


func _focus_on_local_start() -> void:
	var own_centers: Array[Vector2] = []
	var own_units: Array[Vector2] = []
	for unit_state: RwUnitState in _unit_states.values():
		if unit_state.team != str(RwRoomClient.local_slot):
			continue
		own_units.append(unit_state.world_position)
		if unit_state.unit_name == "commandCenter":
			own_centers.append(unit_state.world_position)
	var start_positions: Array[Vector2] = own_centers if not own_centers.is_empty() else own_units
	if not start_positions.is_empty():
		var total: Vector2 = Vector2.ZERO
		for world_position: Vector2 in start_positions:
			total += world_position
		map_camera.position = total / float(start_positions.size())
	_clamp_camera_position()
	_zoom_anchor_screen = get_viewport_rect().size * 0.5
	_zoom_anchor_world = map_camera.position


func _queue_zoom(screen_position: Vector2, factor: float) -> void:
	_zoom_anchor_screen = screen_position
	_zoom_anchor_world = _screen_to_world(screen_position)
	_target_zoom = clampf(_target_zoom * factor, MIN_ZOOM, MAX_ZOOM)


func _update_smooth_zoom(delta: float) -> void:
	var current_zoom: float = map_camera.zoom.x
	if absf(current_zoom - _target_zoom) <= 0.0001:
		return
	var weight: float = 1.0 - exp(-ZOOM_SMOOTHING * delta)
	var next_zoom: float = lerpf(current_zoom, _target_zoom, weight)
	if absf(next_zoom - _target_zoom) <= 0.0001:
		next_zoom = _target_zoom
	map_camera.zoom = Vector2.ONE * next_zoom
	map_camera.position = _zoom_anchor_world - (_zoom_anchor_screen - get_viewport_rect().size * 0.5) / next_zoom
	_clamp_camera_position()
	_zoom_anchor_world = _screen_to_world(_zoom_anchor_screen)


func _update_keyboard_pan(delta: float) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction == Vector2.ZERO:
		return
	var displacement: Vector2 = direction * KEYBOARD_PAN_SPEED * delta / map_camera.zoom.x
	map_camera.position += displacement
	_clamp_camera_position()
	_zoom_anchor_world = _screen_to_world(_zoom_anchor_screen)


func _pan_by_screen_delta(screen_delta: Vector2) -> void:
	map_camera.position -= screen_delta / map_camera.zoom.x
	_clamp_camera_position()
	_zoom_anchor_world = _screen_to_world(_zoom_anchor_screen)


func _clamp_camera_position() -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / map_camera.zoom.x
	map_camera.position.x = _clamp_camera_axis(map_camera.position.x, _world_size.x, half_view.x)
	map_camera.position.y = _clamp_camera_axis(map_camera.position.y, _world_size.y, half_view.y)


func _clamp_camera_axis(value: float, world_extent: float, half_view_extent: float) -> float:
	if world_extent <= half_view_extent * 2.0:
		return world_extent * 0.5
	return clampf(value, half_view_extent, world_extent - half_view_extent)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return map_camera.position + (screen_position - get_viewport_rect().size * 0.5) / map_camera.zoom.x


func _world_to_screen(world_position: Vector2) -> Vector2:
	return (world_position - map_camera.position) * map_camera.zoom.x + get_viewport_rect().size * 0.5


func _draw_navigation_overlay() -> void:
	if _placement_action != null and _path_grid != null:
		var definition: RwUnitDefinition = _unit_registry.find_definition(_placement_action.target_source_id, _placement_action.target_unit_name)
		if definition != null:
			var cell: Vector2i = _path_grid.structure_anchor_cell(_placement_position, definition.structure_footprint_min, definition.structure_footprint_max)
			var placement_color: Color = Color(0.1, 1.0, 0.2, 0.3) if _placement_error.is_empty() else Color(1.0, 0.15, 0.1, 0.4)
			for y: int in range(cell.y + definition.structure_footprint_min.y, cell.y + definition.structure_footprint_max.y + 1):
				for x: int in range(cell.x + definition.structure_footprint_min.x, cell.x + definition.structure_footprint_max.x + 1):
					var rect: Rect2 = Rect2(Vector2(x, y) * Vector2(_path_grid.tile_size), Vector2(_path_grid.tile_size))
					navigation_overlay.draw_rect(rect, placement_color, true)
					navigation_overlay.draw_rect(rect, placement_color.lightened(0.3), false, 1.0)
	for object_id: int in _selected_unit_ids:
		var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if unit_state == null:
			continue
		var points: PackedVector2Array = unit_state.get_navigation_path()
		if points.size() < 2:
			continue
		navigation_overlay.draw_polyline(points, NAVIGATION_COLOR, 1.0, false)
		navigation_overlay.draw_circle(points[points.size() - 1], 2.0, NAVIGATION_COLOR)


func _draw_selection_overlay() -> void:
	if not _selection_dragging:
		return
	var selection_rect: Rect2 = Rect2(_selection_start_screen, _selection_end_screen - _selection_start_screen).abs()
	selection_overlay.draw_rect(selection_rect, Color(0.2, 1.0, 0.2, 0.1), true)
	selection_overlay.draw_rect(selection_rect.grow(-0.5), Color(0.45, 1.0, 0.45), false, 1.0, false)


func _finish_selection(screen_position: Vector2) -> void:
	if not _selection_pressed:
		return
	_selection_end_screen = screen_position
	var new_selection: Array[int] = []
	if _selection_dragging:
		var selection_rect: Rect2 = Rect2(_selection_start_screen, _selection_end_screen - _selection_start_screen).abs()
		for object_id: int in _unit_states:
			var unit_state: RwUnitState = _unit_states[object_id]
			if unit_state.is_dead or unit_state.team != str(RwRoomClient.local_slot):
				continue
			var unit_screen: Vector2 = _world_to_screen(unit_state.world_position)
			if selection_rect.has_point(unit_screen):
				new_selection.append(object_id)
	else:
		var clicked_id: int = _find_unit_at(_screen_to_world(screen_position))
		if clicked_id > 0:
			new_selection.append(clicked_id)
	_set_selection(new_selection, _selection_additive)
	_selection_pressed = false
	_selection_dragging = false
	selection_overlay.queue_redraw()


func _find_unit_at(world_position: Vector2) -> int:
	var nearest_id: int
	var nearest_distance: float = INF
	for object_id: int in _unit_states:
		var unit_state: RwUnitState = _unit_states[object_id]
		if unit_state.is_dead:
			continue
		var visual: RwUnitVisual = _unit_visuals[object_id]
		if not visual.visible:
			continue
		var hit_radius: float = maxf(visual.get_hit_radius(), 8.0 / map_camera.zoom.x)
		var distance: float = unit_state.world_position.distance_to(world_position)
		if distance < hit_radius and distance < nearest_distance:
			nearest_distance = distance
			nearest_id = object_id
	return nearest_id


func _set_selection(unit_ids: Array[int], additive: bool) -> void:
	if additive:
		for object_id: int in unit_ids + _selected_unit_ids:
			var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
			if unit_state == null or unit_state.team != str(RwRoomClient.local_slot):
				additive = false
				break
	var next_selection: Array[int] = []
	if additive:
		next_selection.append_array(_selected_unit_ids)
	for object_id: int in unit_ids:
		if not next_selection.has(object_id):
			next_selection.append(object_id)
	for object_id: int in _selected_unit_ids:
		if _unit_visuals.has(object_id):
			(_unit_visuals[object_id] as RwUnitVisual).set_selected(false)
	_selected_unit_ids = next_selection
	for object_id: int in _selected_unit_ids:
		if _unit_visuals.has(object_id):
			(_unit_visuals[object_id] as RwUnitVisual).set_selected(true)
	navigation_overlay.queue_redraw()
	_show_selection()


func _show_selection() -> void:
	var selected_units: Array[RwUnitState] = []
	for object_id: int in _selected_unit_ids:
		var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if unit_state != null:
			selected_units.append(unit_state)
	hud_layer.show_selection(selected_units, _unit_visuals)
	_refresh_production_status()


func _refresh_production_status() -> void:
	var status: Dictionary = {}
	for object_id: int in _selected_unit_ids:
		var queue: RwProductionQueue = _production_queues.get(object_id) as RwProductionQueue
		if queue == null:
			continue
		for item_index: int in queue.items.size():
			var action: RwUnitActionDefinition = queue.items[item_index]
			var entry: Dictionary = status.get(action.action_id, {"count": 0, "progress": 0.0, "active": false,})
			entry["count"] = int(entry["count"]) + 1
			if item_index == 0:
				entry["progress"] = maxf(float(entry["progress"]), queue.progress)
				entry["active"] = true
			status[action.action_id] = entry
	hud_layer.set_production_status(status)


func _on_minimap_position_chosen(world_position: Vector2) -> void:
	map_camera.position = world_position
	_clamp_camera_position()
	_zoom_anchor_world = _screen_to_world(_zoom_anchor_screen)
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)


func _on_unit_action_chosen(action_id: String, unit_ids: Array[int]) -> void:
	if unit_ids.is_empty():
		return
	if action_id in ["reclaim", "patrol", "guard",]:
		_begin_special_order(action_id, unit_ids)
		return
	var producer: RwUnitState = _unit_states.get(unit_ids[0]) as RwUnitState
	var action: RwUnitActionDefinition = _find_action(producer, action_id)
	if action != null and action.kind == RwUnitActionDefinition.Kind.PLACE_BUILDING:
		_begin_placement(action, unit_ids)
		return
	if action == null or action.kind not in [RwUnitActionDefinition.Kind.QUEUE_UNIT, RwUnitActionDefinition.Kind.UPGRADE_UNIT, RwUnitActionDefinition.Kind.CONVERT_UNIT, RwUnitActionDefinition.Kind.QUEUE_RESOURCE,]:
		hud_layer.show_status("%s is not available in the current battle simulation" % action_id)
		return
	var valid_ids: Array[int] = []
	for object_id: int in unit_ids:
		var selected_producer: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if selected_producer != null and not selected_producer.is_dead and selected_producer.team == str(RwRoomClient.local_slot) and _find_action(selected_producer, action_id) == action and not _resource_stockpile_full(selected_producer, action):
			valid_ids.append(object_id)
	if valid_ids.is_empty():
		return
	var credit_cost: float = float(action.resource_costs.get("credits", 0.0))
	if RwRoomClient.battle_economy.get_balance(RwRoomClient.local_slot, "credits") < credit_cost:
		hud_layer.show_status("Not enough credits to queue %s" % action.display_name)
		AudioManager.play_ui(&"error")
		return
	if not RwRoomClient.send_unit_action(valid_ids, action.network_action_id):
		hud_layer.show_status("Could not send production order; check the room connection")


func _begin_special_order(order_type: String, unit_ids: Array[int]) -> void:
	_cancel_placement()
	_special_order_type = order_type
	_special_order_unit_ids.clear()
	for object_id: int in unit_ids:
		var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.team != str(RwRoomClient.local_slot):
			continue
		var definition: RwUnitDefinition = _unit_registry.find_definition(unit_state.source_id, unit_state.unit_name)
		if order_type == "reclaim" and (definition == null or not definition.can_reclaim):
			continue
		_special_order_unit_ids.append(object_id)
	if _special_order_unit_ids.is_empty():
		_cancel_special_order()
		return
	hud_layer.show_status("Choose a target for %s; right-click to cancel" % order_type)


func _confirm_special_order(screen_position: Vector2) -> void:
	var target: Vector2 = _screen_to_world(screen_position).clamp(Vector2.ZERO, _world_size)
	var target_id: int = -1
	if _special_order_type in ["reclaim", "guard",]:
		target_id = _find_unit_at(target)
		var target_state: RwUnitState = _unit_states.get(target_id) as RwUnitState
		if target_state == null or _special_order_type == "guard" and target_state.team != str(RwRoomClient.local_slot):
			hud_layer.show_status("Choose a valid unit target")
			return
		target = target_state.world_position
	if RwRoomClient.send_special_order(_special_order_unit_ids, _special_order_type, target, target_id):
		_cancel_special_order()
	else:
		hud_layer.show_status("Could not send the unit order; check the room connection")


func _cancel_special_order() -> void:
	_special_order_type = ""
	_special_order_unit_ids.clear()


func _on_unit_action_cancelled(action_id: String, unit_ids: Array[int]) -> void:
	for object_id: int in unit_ids:
		var queue: RwProductionQueue = _production_queues.get(object_id) as RwProductionQueue
		if queue == null:
			continue
		var queued_count: int = 0
		for queued_action: RwUnitActionDefinition in queue.items:
			if queued_action.action_id == action_id:
				queued_count += 1
		var pending_key: String = "%d:%s" % [object_id, action_id]
		if queued_count <= int(_pending_queue_cancellations.get(pending_key, 0)):
			continue
		var producer: RwUnitState = _unit_states.get(object_id) as RwUnitState
		var action: RwUnitActionDefinition = _find_action(producer, action_id)
		if action == null:
			continue
		if RwRoomClient.send_cancel_unit_action(object_id, action.network_action_id):
			_pending_queue_cancellations[pending_key] = int(_pending_queue_cancellations.get(pending_key, 0)) + 1
		return


func _begin_placement(action: RwUnitActionDefinition, unit_ids: Array[int]) -> void:
	_cancel_special_order()
	var definition: RwUnitDefinition = _unit_registry.find_definition(action.target_source_id, action.target_unit_name)
	if definition == null or action.network_build_index < 0 and action.network_build_custom_name.is_empty():
		hud_layer.show_status("Building definition is unavailable")
		return
	_cancel_placement()
	_placement_builder_ids.clear()
	for object_id: int in unit_ids:
		var builder: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if builder != null and not builder.is_dead and builder.team == str(RwRoomClient.local_slot) and _find_action(builder, action.action_id) == action:
			_placement_builder_ids.append(object_id)
	if _placement_builder_ids.is_empty():
		return
	_placement_action = action
	var spawn: Dictionary = {
		"object_id": 0,
		"source_id": action.target_source_id,
		"unit_name": action.target_unit_name,
		"team": str(RwRoomClient.local_slot),
		"position": Vector2.ZERO,
	}
	var color: Color = RwUnitTeamColors.for_team(str(RwRoomClient.local_slot), RwRoomClient.players)
	_placement_preview = _unit_registry.create_visual(spawn, color)
	var preview_state: RwUnitState = RwUnitState.new()
	preview_state.initialize_from_spawn(spawn, definition)
	_placement_preview.bind_state(preview_state)
	unit_layer.add_child(_placement_preview)
	_update_placement_preview()


func _update_placement_preview() -> void:
	if _placement_action == null or _path_grid == null:
		return
	var world_position: Vector2 = _screen_to_world(get_viewport().get_mouse_position())
	var definition: RwUnitDefinition = _unit_registry.find_definition(_placement_action.target_source_id, _placement_action.target_unit_name)
	if definition == null:
		return
	_placement_position = _path_grid.snap_structure_position(world_position, definition.structure_footprint_min, definition.structure_footprint_max)
	_placement_error = _get_build_placement_error(_placement_position, definition)
	if _placement_preview != null:
		_placement_preview.state.apply_snapshot({"position": _placement_position,})
		_placement_preview.modulate = Color(0.4, 1.0, 0.5, 0.7) if _placement_error.is_empty() else Color(1.0, 0.3, 0.25, 0.7)
	navigation_overlay.queue_redraw()


func _get_build_placement_error(world_position: Vector2, definition: RwUnitDefinition) -> String:
	if _path_grid == null or definition == null:
		return "Cannot place here"
	var error: String = _path_grid.get_placement_error(world_position, definition)
	if not error.is_empty():
		return error
	var center: Vector2i = _path_grid.structure_anchor_cell(world_position, definition.structure_footprint_min, definition.structure_footprint_max)
	var footprint: Rect2i = Rect2i(center + definition.structure_footprint_min, definition.structure_footprint_max - definition.structure_footprint_min + Vector2i.ONE)
	for site: Dictionary in _build_sites:
		if bool(site.get("finished", false)):
			continue
		var site_definition: RwUnitDefinition = site["definition"]
		var site_center: Vector2i = _path_grid.structure_anchor_cell(site["position"], site_definition.structure_footprint_min, site_definition.structure_footprint_max)
		var site_footprint: Rect2i = Rect2i(site_center + site_definition.structure_footprint_min, site_definition.structure_footprint_max - site_definition.structure_footprint_min + Vector2i.ONE)
		if footprint.intersects(site_footprint):
			return "Location is reserved"
	return ""


func _confirm_placement(is_queued: bool) -> void:
	_update_placement_preview()
	if not _placement_error.is_empty():
		hud_layer.show_status(_placement_error)
		AudioManager.play_ui(&"error")
		return
	if not RwRoomClient.send_build_order(_placement_builder_ids, _placement_action.network_build_index, _placement_position, is_queued, _placement_action.network_build_custom_name):
		hud_layer.show_status("Could not send building order")
		AudioManager.play_ui(&"error")
		return
	if not is_queued:
		_cancel_placement()


func _cancel_placement() -> void:
	_placement_action = null
	_placement_builder_ids.clear()
	if is_instance_valid(_placement_preview):
		_placement_preview.queue_free()
	_placement_preview = null
	navigation_overlay.queue_redraw()


func _on_unit_group_selected(unit_ids: Array[int]) -> void:
	_set_selection(unit_ids, false)


func _request_move(screen_position: Vector2) -> void:
	if _path_grid == null:
		return
	var movable_ids: Array[int] = []
	for object_id: int in _selected_unit_ids:
		var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if unit_state != null and not unit_state.is_dead and unit_state.movement_speed > 0.0 and unit_state.team == str(RwRoomClient.local_slot):
			movable_ids.append(object_id)
	if movable_ids.is_empty():
		return
	var target: Vector2 = _screen_to_world(screen_position).clamp(Vector2.ZERO, _world_size)
	if not RwRoomClient.send_move_order(movable_ids, target):
		hud_layer.show_status("Could not send move order; check the room connection")
		AudioManager.play_ui(&"error")
		return
	AudioManager.play_ui(&"move", linear_to_db(0.2))


func _on_room_updated(_settings: Dictionary, _players: Array[Dictionary], _local_slot: int) -> void:
	if _combat != null:
		_combat.set_players(_players)
	_refresh_fog_visibility()


func _on_room_connection_changed(message: String) -> void:
	hud_layer.show_status(message)


func _on_combat_unit_destroyed(unit_state: RwUnitState) -> void:
	var definition: RwUnitDefinition = _unit_registry.find_definition(unit_state.source_id, unit_state.unit_name)
	if definition != null and definition.blocks_movement and _path_grid != null:
		_path_grid.unblock_structure(unit_state.world_position, definition.structure_footprint_min, definition.structure_footprint_max)
		_path_grid.finalize_obstacles()
	if unit_state.unit_name == "commandCenter" and unit_state.team.is_valid_int():
		RwRoomClient.battle_economy.remove_command_center(unit_state.team.to_int())
	_animated_command_centers.erase(unit_state)
	_animated_extractors.erase(unit_state)
	_animated_visual_units.erase(unit_state)
	_mobile_unit_states.erase(unit_state)
	if _unit_orders != null:
		_unit_orders.clear_pending(unit_state.object_id)
	_factory_rally_points.erase(unit_state.object_id)
	_production_queues.erase(unit_state.object_id)
	_builder_site_ids.erase(unit_state.object_id)
	_builder_site_queues.erase(unit_state.object_id)
	for site: Dictionary in _build_sites:
		if int(site["object_id"]) != unit_state.object_id or bool(site["finished"]):
			continue
		site["finished"] = true
		for builder_id: int in site["builders"]:
			_advance_builder_site_queue(builder_id, int(site["id"]))
	var visual: RwUnitVisual = _unit_visuals.get(unit_state.object_id) as RwUnitVisual
	if visual != null:
		visual.set_selected(false)
		if visual.visible:
			AudioManager.play_unit_at(&"explode", unit_state.world_position, map_camera.position)
	if _selected_unit_ids.has(unit_state.object_id):
		_selected_unit_ids.erase(unit_state.object_id)
		navigation_overlay.queue_redraw()
		_show_selection()
	hud_layer.minimap.refresh_units()


func _on_battle_frame_advanced(frame: int, _next_blocking_frame: int) -> void:
	var frame_delta: int = maxi(frame - _last_simulated_frame, 0)
	var first_frame: int = _last_simulated_frame
	_last_simulated_frame = frame
	for step: int in frame_delta:
		for unit_state: RwUnitState in _mobile_unit_states:
			if _unit_orders != null:
				_unit_orders.advance_unit(unit_state, first_frame + step, _builder_site_ids.has(unit_state.object_id))
			else:
				unit_state.advance_movement(1, _path_grid)
		for animated_unit: RwUnitState in _animated_visual_units:
			animated_unit.advance_visual_animation(1)
		_separate_mobile_units()
		_advance_service_orders()
		_advance_unit_generation(first_frame + step)
		if _combat != null:
			_combat.advance_frame(RwRoomClient.battle_timeline.step_rate)
	if frame_delta > 0:
		projectile_layer.queue_redraw()
		_refresh_fog_visibility()
		_refresh_builder_vfx(frame)
	var animation_frame: int = _command_center_frame(frame)
	for unit_state: RwUnitState in _animated_command_centers:
		if unit_state.animation_frame != animation_frame and not unit_state.is_dead:
			unit_state.apply_snapshot({"animation_frame": animation_frame,})
	if frame_delta > 0 and _selected_unit_ids.size() == 1 and frame % 10 == 0:
		_show_selection()
	elif frame_delta > 0 and frame % 10 == 0:
		_refresh_production_status()


func _on_battle_commands_reached(_frame: int, commands: Array[Dictionary]) -> void:
	for command: Dictionary in commands:
		if bool(command.get("is_system_action", false)):
			var step_rate: float = float(command.get("game_speed_change", 0.0))
			if step_rate >= 0.1:
				RwRoomClient.battle_timeline.set_step_rate(step_rate)
			continue
		var order_type: String = str(command.get("order_type", ""))
		if order_type.is_empty():
			var action_id: String = str(command.get("action_id", ""))
			if not action_id.is_empty() and action_id != "-1":
				_apply_production_command(command)
			if command.get("rally_point") is Vector2:
				_apply_rally_point_command(command)
			if (bool(command.get("clear_existing_orders", false)) or int(command.get("attack_mode", -1)) >= 0) and _unit_orders != null:
				_unit_orders.apply_command(command)
			continue
		if order_type == "build":
			_apply_build_command(command)
			continue
		if _unit_orders == null:
			continue
		var unit_ids: Array[int] = []
		for object_id: int in command.get("unit_ids", []):
			unit_ids.append(object_id)
		var is_movement_order: bool = RwUnitOrderController.POINT_ORDER_TYPES.has(order_type)
		var target: Vector2 = command.get("target", Vector2.ZERO)
		var formation_targets: Dictionary = _formation_targets(unit_ids, target) if is_movement_order else {}
		var busy_ids: Array[int] = []
		var should_queue: bool = (bool(command.get("is_queued", false)) or bool(command.get("order_is_queued", false))) and not bool(command.get("is_instant_command", false))
		for object_id: int in unit_ids:
			var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
			if unit_state == null or not _unit_orders.can_apply_to_unit(unit_state, _command_source_team(command), int(command.get("allowed_team_mask", 0))):
				continue
			if _builder_site_ids.has(object_id):
				busy_ids.append(object_id)
			if not should_queue:
				_builder_site_ids.erase(object_id)
				_builder_site_queues.erase(object_id)
		_unit_orders.apply_command(command, formation_targets, busy_ids)
	if not _selected_unit_ids.is_empty():
		_show_selection()


## 按同步帧更新建造者的维修与回收结果
func _advance_service_orders() -> void:
	for actor: RwUnitState in _mobile_unit_states:
		if actor.is_dead or actor.order_type not in ["repair", "reclaim",]:
			continue
		var target: RwUnitState = _unit_states.get(actor.order_target_id) as RwUnitState
		if target == null or target.is_dead or actor.world_position.distance_to(target.world_position) > maxf(actor.collision_radius + target.collision_radius + 8.0, 24.0):
			continue
		var definition: RwUnitDefinition = _unit_registry.find_definition(target.source_id, target.unit_name)
		if actor.order_type == "repair":
			if actor.team == target.team and target.health < target.max_health:
				target.apply_snapshot({"health": minf(target.health + maxf(target.max_health * 0.004, 1.0), target.max_health),})
			continue
		var actor_definition: RwUnitDefinition = _unit_registry.find_definition(actor.source_id, actor.unit_name)
		if actor_definition == null or not actor_definition.can_reclaim:
			continue
		var previous_health: float = target.health
		var removed_health: float = minf(previous_health, maxf(target.max_health * 0.004, 1.0))
		var destroyed: bool = target.apply_damage(removed_health)
		if definition != null and actor.team.is_valid_int() and target.max_health > 0.0:
			var full_cost: float = float(definition.resource_costs.get("credits", 0.0))
			if full_cost <= 0.0:
				var specs: Dictionary = RwBuiltinUnitSpecs.SPECS if target.source_id == "custom" else RwNativeProductionSpecs.SPECS
				full_cost = float((specs.get(target.unit_name, {}) as Dictionary).get("price" if target.source_id == "custom" else "cost", 0.0))
			RwRoomClient.battle_economy.refund_credits(actor.team.to_int(), full_cost * 0.75 * removed_health / target.max_health * target.build_progress)
		if destroyed:
			_on_combat_unit_destroyed(target)


func _on_unit_order_applied(unit_state: RwUnitState, order_type: String, order: Dictionary) -> void:
	if _combat != null:
		_combat.notify_order(unit_state, order_type, order)


func _on_projectile_fired(projectile: RwProjectileState) -> void:
	projectile.object_id = _next_object_id
	_next_object_id += 1


func _apply_rally_point_command(command: Dictionary) -> void:
	var rally_point: Vector2 = command["rally_point"]
	var team_slot: int = _command_source_team(command)
	var allowed_mask: int = int(command.get("allowed_team_mask", 0))
	for object_id: int in command.get("unit_ids", []):
		var factory: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if factory != null and not factory.is_dead and _unit_orders != null and _unit_orders.can_apply_to_unit(factory, team_slot, allowed_mask):
			_factory_rally_points[object_id] = rally_point


func _find_action(producer: RwUnitState, action_id: String) -> RwUnitActionDefinition:
	if producer == null or _unit_registry == null:
		return null
	var definition: RwUnitDefinition = _unit_registry.find_definition(producer.source_id, producer.unit_name)
	if definition == null:
		return null
	for action: RwUnitActionDefinition in definition.build_actions:
		if action.action_id == action_id or action.network_action_id == action_id:
			if action.required_tech_level > 0 and action.required_tech_level != producer.tech_level:
				return null
			return action
	return null


func _command_source_team(command: Dictionary) -> int:
	var source_team: int = int(command.get("source_team", -1))
	return source_team if source_team != -1 else int(command.get("team", -1))


func _apply_production_command(command: Dictionary) -> void:
	var team_slot: int = _command_source_team(command)
	var allowed_mask: int = int(command.get("allowed_team_mask", 0))
	var network_action_id: String = str(command.get("action_id", ""))
	for object_id: int in command.get("unit_ids", []):
		var producer: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if producer == null or producer.is_dead or _unit_orders == null or not _unit_orders.can_apply_to_unit(producer, team_slot, allowed_mask):
			continue
		var owner_slot: int = producer.team.to_int()
		var action: RwUnitActionDefinition = _find_action(producer, network_action_id)
		if action == null or action.kind not in [RwUnitActionDefinition.Kind.QUEUE_UNIT, RwUnitActionDefinition.Kind.UPGRADE_UNIT, RwUnitActionDefinition.Kind.CONVERT_UNIT, RwUnitActionDefinition.Kind.QUEUE_RESOURCE,]:
			continue
		if bool(command.get("stop_current_action", false)):
			var pending_key: String = "%d:%s" % [object_id, action.action_id]
			_pending_queue_cancellations[pending_key] = maxi(int(_pending_queue_cancellations.get(pending_key, 0)) - 1, 0)
			var existing_queue: RwProductionQueue = _production_queues.get(object_id) as RwProductionQueue
			if existing_queue != null:
				var cancelled_action: RwUnitActionDefinition = existing_queue.cancel_one(action.action_id)
				if cancelled_action != null:
					RwRoomClient.battle_economy.refund_credits(owner_slot, float(cancelled_action.resource_costs.get("credits", 0.0)))
				_sync_production_progress(producer, existing_queue)
			continue
		var queue: RwProductionQueue = _production_queues.get(object_id) as RwProductionQueue
		if action.kind in [RwUnitActionDefinition.Kind.UPGRADE_UNIT, RwUnitActionDefinition.Kind.CONVERT_UNIT,] and queue != null:
			var already_queued: bool
			for queued_action: RwUnitActionDefinition in queue.items:
				if queued_action.action_id == action.action_id:
					already_queued = true
					break
			if already_queued:
				continue
		if _resource_stockpile_full(producer, action):
			continue
		if not RwRoomClient.battle_economy.try_spend_credits(owner_slot, float(action.resource_costs.get("credits", 0.0))):
			continue
		if queue == null:
			queue = RwProductionQueue.new()
			_production_queues[object_id] = queue
		queue.enqueue(action)
		_sync_production_progress(producer, queue)
	_refresh_production_status()


func _resource_stockpile_full(producer: RwUnitState, action: RwUnitActionDefinition) -> bool:
	if action.kind != RwUnitActionDefinition.Kind.QUEUE_RESOURCE or action.max_stockpile <= 0 or action.resource_delta.is_empty():
		return false
	var resource_id: String = str(action.resource_delta.keys()[0])
	var total: float = float(producer.resource_balances.get(resource_id, 0.0))
	var queue: RwProductionQueue = _production_queues.get(producer.object_id) as RwProductionQueue
	if queue != null:
		for queued_action: RwUnitActionDefinition in queue.items:
			total += float(queued_action.resource_delta.get(resource_id, 0.0))
	return total >= float(action.max_stockpile)


func _sync_production_progress(producer: RwUnitState, queue: RwProductionQueue) -> void:
	var progress: float = -1.0
	if queue != null and not queue.items.is_empty():
		progress = queue.progress
	producer.set_production_progress(progress)


func _apply_build_command(command: Dictionary) -> void:
	var team_slot: int = _command_source_team(command)
	var allowed_mask: int = int(command.get("allowed_team_mask", 0))
	var build_index: int = int(command.get("build_unit_index", -1))
	var custom_name: String = str(command.get("custom_build_unit_name", ""))
	var unit_name: String = custom_name if build_index == -2 else RwVanillaBuildings.name_for_network_type(build_index, custom_name)
	var definition: RwUnitDefinition = _unit_registry.find_definition("custom", unit_name) if build_index == -2 else _unit_registry.find_definition("vanilla", unit_name)
	if definition == null and build_index == -2:
		unit_name = RwVanillaBuildings.name_for_network_type(build_index, custom_name)
		definition = _unit_registry.find_definition("vanilla", unit_name)
	if definition == null and build_index >= 0:
		unit_name = RwVanillaUnitCatalog.native_name(build_index)
		definition = _unit_registry.find_definition("vanilla", unit_name)
	if definition == null:
		return
	var target: Vector2 = command.get("target", Vector2.ZERO)
	var _position: Vector2 = _path_grid.snap_structure_position(target, definition.structure_footprint_min, definition.structure_footprint_max)
	var builder_ids: Array[int] = []
	var valid_actions: Array[RwUnitActionDefinition] = []
	for object_id: int in command.get("unit_ids", []):
		var builder: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if builder == null or builder.is_dead or _unit_orders == null or not _unit_orders.can_apply_to_unit(builder, team_slot, allowed_mask):
			continue
		var candidate_action: RwUnitActionDefinition = _find_action(builder, unit_name)
		if candidate_action == null and build_index == -2:
			var builder_definition: RwUnitDefinition = _unit_registry.find_definition(builder.source_id, builder.unit_name)
			if builder_definition != null:
				for available_action: RwUnitActionDefinition in builder_definition.build_actions:
					if available_action.network_build_custom_name == custom_name:
						candidate_action = available_action
						break
		if candidate_action == null or candidate_action.kind != RwUnitActionDefinition.Kind.PLACE_BUILDING:
			continue
		if valid_actions.is_empty():
			valid_actions.append(candidate_action)
		builder_ids.append(object_id)
	if builder_ids.is_empty():
		return
	var build_action: RwUnitActionDefinition = valid_actions[0]
	var site_id: int = _next_build_site_id
	_next_build_site_id += 1
	_build_sites.append({
		"id": site_id,
		"team": (_unit_states[builder_ids[0]] as RwUnitState).team.to_int(),
		"definition": definition,
		"position": _position,
		"builders": builder_ids,
		"rate": build_action.build_rate_per_frame,
		"cost": float(build_action.resource_costs.get("credits", 0.0)),
		"object_id": 0,
		"progress": 0.0,
		"created_frame": -1,
		"next_attempt_frame": 0,
		"finished": false,
	})
	for object_id: int in builder_ids:
		var builder: RwUnitState = _unit_states[object_id] as RwUnitState
		if bool(command.get("is_queued", false)) and _builder_site_ids.has(object_id):
			var pending_sites: Array = _builder_site_queues.get(object_id, [])
			pending_sites.append(site_id)
			_builder_site_queues[object_id] = pending_sites
		else:
			_builder_site_queues.erase(object_id)
			if _unit_orders != null:
				_unit_orders.clear_pending(object_id)
			_start_builder_site(builder, site_id, _position, definition)


func _find_build_approach(builder_position: Vector2, site_position: Vector2, definition: RwUnitDefinition) -> Vector2:
	var center: Vector2i = _path_grid.structure_anchor_cell(site_position, definition.structure_footprint_min, definition.structure_footprint_max)
	var minimum: Vector2i = center + definition.structure_footprint_min - Vector2i.ONE
	var maximum: Vector2i = center + definition.structure_footprint_max + Vector2i.ONE
	var best_position: Vector2 = builder_position
	var best_distance: float = INF
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			if x > minimum.x and x < maximum.x and y > minimum.y and y < maximum.y:
				continue
			var cell: Vector2i = Vector2i(x, y)
			if not _path_grid.is_passable(cell, "LAND"):
				continue
			var candidate: Vector2 = _path_grid.cell_to_world(cell)
			var distance: float = builder_position.distance_squared_to(candidate)
			if distance < best_distance:
				var path: Array[Vector2] = _path_grid.find_path(builder_position, candidate, "LAND")
				if path.is_empty() or path.back().distance_to(candidate) > 1.0:
					continue
				best_distance = distance
				best_position = candidate
	return best_position


func _start_builder_site(builder: RwUnitState, site_id: int, _position: Vector2, definition: RwUnitDefinition) -> void:
	_builder_site_ids[builder.object_id] = site_id
	if builder.world_position.distance_to(_position) <= BUILD_RANGE:
		builder.apply_order("", _position)
		return
	var approach: Vector2 = _find_build_approach(builder.world_position, _position, definition)
	builder.apply_move_order(approach, _path_grid.find_path(builder.world_position, approach, builder.movement_type))


func _advance_builder_site_queue(builder_id: int, completed_site_id: int) -> void:
	if int(_builder_site_ids.get(builder_id, -1)) != completed_site_id:
		return
	_builder_site_ids.erase(builder_id)
	var pending_sites: Array = _builder_site_queues.get(builder_id, [])
	while not pending_sites.is_empty():
		var next_site_id: int = int(pending_sites.pop_front())
		for site: Dictionary in _build_sites:
			if int(site["id"]) != next_site_id or bool(site["finished"]):
				continue
			var builder: RwUnitState = _unit_states.get(builder_id) as RwUnitState
			if builder != null and not builder.is_dead:
				_start_builder_site(builder, next_site_id, site["position"], site["definition"])
				_builder_site_queues[builder_id] = pending_sites
				return
	_builder_site_queues.erase(builder_id)


func _advance_unit_generation(frame: int) -> void:
	var active_sites: Dictionary = _builder_site_ids.duplicate()
	var actor_ids: Array[int] = []
	for factory_id: int in _production_queues:
		actor_ids.append(factory_id)
	for builder_id: int in active_sites:
		if not actor_ids.has(builder_id):
			actor_ids.append(builder_id)
	actor_ids.sort()
	for actor_id: int in actor_ids:
		if _production_queues.has(actor_id):
			_advance_factory_production(actor_id)
		if active_sites.has(actor_id):
			_advance_builder_construction(actor_id, int(active_sites[actor_id]), frame)
	for site: Dictionary in _build_sites:
		if not bool(site["finished"]) and int(site["object_id"]) == 0 and not _is_site_assigned_or_queued(int(site["id"])):
			site["finished"] = true


func _advance_builder_construction(builder_id: int, site_id: int, frame: int) -> void:
	if int(_builder_site_ids.get(builder_id, -1)) != site_id:
		return
	var builder: RwUnitState = _unit_states.get(builder_id) as RwUnitState
	if builder == null or builder.is_dead:
		_builder_site_ids.erase(builder_id)
		_builder_site_queues.erase(builder_id)
		return
	for site: Dictionary in _build_sites:
		if int(site["id"]) != site_id or bool(site["finished"]):
			continue
		var site_position: Vector2 = site["position"]
		if builder.world_position.distance_to(site_position) > BUILD_RANGE:
			return
		if builder.order_type == "move" or builder.order_type == "attackMove":
			builder.apply_order("", site_position)
		var building: RwUnitState = _unit_states.get(int(site["object_id"])) as RwUnitState
		if building == null:
			if frame < int(site["next_attempt_frame"]):
				return
			var definition: RwUnitDefinition = site["definition"]
			if not _path_grid.get_placement_error(site_position, definition).is_empty():
				site["finished"] = true
				for assigned_id: int in site["builders"]:
					_advance_builder_site_queue(assigned_id, site_id)
				return
			if not RwRoomClient.battle_economy.try_spend_credits(int(site["team"]), float(site["cost"])):
				site["next_attempt_frame"] = frame + BUILD_RETRY_FRAMES
				return
			var candidate_object_id: int = _next_object_id
			_next_object_id += 1
			building = _create_building_site(site, candidate_object_id)
			if building == null:
				return
			site["created_frame"] = frame
		if frame <= int(site["created_frame"]):
			return
		var progress: float = minf(float(site["progress"]) + float(site["rate"]), 1.0)
		site["progress"] = progress
		building.apply_snapshot({"build_progress": progress,})
		if progress >= 1.0:
			site["finished"] = true
			for assigned_id: int in site["builders"]:
				_advance_builder_site_queue(assigned_id, site_id)
			if int(site["team"]) == RwRoomClient.local_slot:
				hud_layer.show_status("Building constructed: %s (x1)" % (site["definition"] as RwUnitDefinition).display_name)
				AudioManager.play_ui(&"add")
		return


func _is_site_assigned_or_queued(site_id: int) -> bool:
	for builder_id: int in _builder_site_ids:
		if int(_builder_site_ids[builder_id]) == site_id:
			return true
	for builder_id: int in _builder_site_queues:
		if (_builder_site_queues[builder_id] as Array).has(site_id):
			return true
	return false


func _refresh_builder_vfx(frame: int) -> void:
	var beams: Dictionary = {}
	for builder_id: int in _builder_site_ids:
		var builder: RwUnitState = _unit_states.get(builder_id) as RwUnitState
		var builder_visual: RwUnitVisual = _unit_visuals.get(builder_id) as RwUnitVisual
		if builder == null or builder.is_dead or builder_visual == null or not builder_visual.visible:
			continue
		var site_id: int = int(_builder_site_ids[builder_id])
		for site: Dictionary in _build_sites:
			if int(site["id"]) != site_id or bool(site["finished"]):
				continue
			var building: RwUnitState = _unit_states.get(int(site["object_id"])) as RwUnitState
			if building == null or building.is_dead or builder.world_position.distance_to(building.world_position) > BUILD_RANGE:
				break
			beams[builder_id] = {
				"origin": builder.world_position,
				"target": building.world_position,
				"radius": building.collision_radius,
			}
			break
	vfx_layer.set_builder_beams(beams, frame)


func _create_building_site(site: Dictionary, object_id: int) -> RwUnitState:
	var definition: RwUnitDefinition = site["definition"]
	var spawn: Dictionary = {
		"object_id": object_id,
		"source_id": definition.source_id,
		"unit_name": definition.unit_name,
		"team": str(site["team"]),
		"position": site["position"],
		"build_progress": 0.0,
	}
	var color: Color = RwUnitTeamColors.for_team(str(site["team"]), RwRoomClient.players)
	var visual: RwUnitVisual = _unit_registry.create_visual(spawn, color)
	visual.set_footprint_tile_size(_map_tile_size)
	visual.set_relation(RwUnitTeamColors.relation_for_team(str(site["team"]), RwRoomClient.players, RwRoomClient.local_slot))
	var building: RwUnitState = RwUnitState.new()
	building.initialize_from_spawn(spawn, definition)
	visual.bind_state(building)
	unit_layer.add_child(visual)
	_unit_states[building.object_id] = building
	_unit_visuals[building.object_id] = visual
	if _combat != null:
		_combat.register_unit(building)
	site["object_id"] = building.object_id
	if RwRoomClient.battle_economy.has_unit_income(building):
		_animated_extractors.append(building)
		RwRoomClient.battle_economy.register_extractor(building)
	if definition.needs_visual_ticks():
		_animated_visual_units.append(building)
	_path_grid.block_structure(building.world_position, definition.structure_footprint_min, definition.structure_footprint_max)
	_path_grid.finalize_obstacles()
	hud_layer.minimap.refresh_units()
	return building


func _advance_factory_production(factory_id: int) -> void:
	var factory: RwUnitState = _unit_states.get(factory_id) as RwUnitState
	if factory == null or factory.is_dead:
		_production_queues.erase(factory_id)
		return
	var queue: RwProductionQueue = _production_queues[factory_id] as RwProductionQueue
	for action: RwUnitActionDefinition in queue.advance(1):
		if action.kind == RwUnitActionDefinition.Kind.UPGRADE_UNIT:
			_complete_unit_upgrade(factory, action)
		elif action.kind == RwUnitActionDefinition.Kind.CONVERT_UNIT:
			_complete_unit_conversion(factory, action)
		elif action.kind == RwUnitActionDefinition.Kind.QUEUE_RESOURCE:
			_complete_resource_action(factory, action)
		else:
			_spawn_produced_unit(factory, action)
	var current_state: RwUnitState = _unit_states.get(factory_id) as RwUnitState
	if current_state != null:
		_sync_production_progress(current_state, queue)


## 将弹药等单位库存写回状态，供后续特殊动作使用
func _complete_resource_action(unit_state: RwUnitState, action: RwUnitActionDefinition) -> void:
	var balances: Dictionary = unit_state.resource_balances.duplicate()
	for resource_id: String in action.resource_delta:
		balances[resource_id] = float(balances.get(resource_id, 0.0)) + float(action.resource_delta[resource_id])
	unit_state.apply_snapshot({"resource_balances": balances,})


func _complete_unit_upgrade(unit_state: RwUnitState, action: RwUnitActionDefinition) -> void:
	if unit_state.tech_level != action.required_tech_level:
		return
	var added_health: float
	if unit_state.unit_name == "extractor":
		added_health = 200.0 if action.result_tech_level == 2 else 1000.0
	unit_state.apply_snapshot({
		"tech_level": action.result_tech_level,
		"max_health": unit_state.max_health + added_health,
		"health": unit_state.health + added_health,
	})
	if _selected_unit_ids.has(unit_state.object_id):
		hud_layer.refresh_selected_unit_actions()
		_refresh_production_status()


## 保留网络对象编号和相对生命值，将形态切换到目标单位定义
func _complete_unit_conversion(old_state: RwUnitState, action: RwUnitActionDefinition) -> void:
	var definition: RwUnitDefinition = _unit_registry.find_definition(action.target_source_id, action.target_unit_name)
	if definition == null or old_state.source_id == action.target_source_id and old_state.unit_name == action.target_unit_name:
		return
	var previous_definition: RwUnitDefinition = _unit_registry.find_definition(old_state.source_id, old_state.unit_name)
	var object_id: int = old_state.object_id
	if previous_definition != null and previous_definition.blocks_movement and _path_grid != null:
		_path_grid.unblock_structure(old_state.world_position, previous_definition.structure_footprint_min, previous_definition.structure_footprint_max)
	if RwRoomClient.battle_economy.has_unit_income(old_state):
		RwRoomClient.battle_economy.unregister_extractor(object_id)
	_animated_command_centers.erase(old_state)
	_animated_extractors.erase(old_state)
	_animated_visual_units.erase(old_state)
	_mobile_unit_states.erase(old_state)
	if _unit_orders != null:
		_unit_orders.clear_pending(object_id)
	var health_ratio: float = old_state.health / old_state.max_health if old_state.max_health > 0.0 else 1.0
	var shield_ratio: float = old_state.shield / old_state.max_shield if old_state.max_shield > 0.0 else 1.0
	var spawn: Dictionary = {
		"object_id": object_id,
		"source_id": action.target_source_id,
		"unit_name": action.target_unit_name,
		"team": old_state.team,
		"position": old_state.world_position,
		"rotation_degrees": old_state.body_rotation_degrees,
		"turret_rotation_degrees": old_state.turret_rotation_degrees,
		"health": definition.max_health * health_ratio,
		"shield": definition.max_shield * shield_ratio,
	}
	var replacement: RwUnitState = RwUnitState.new()
	replacement.initialize_from_spawn(spawn, definition)
	var color: Color = RwUnitTeamColors.for_team(old_state.team, RwRoomClient.players)
	var visual: RwUnitVisual = _unit_registry.create_visual(spawn, color)
	visual.set_footprint_tile_size(_map_tile_size)
	visual.set_relation(RwUnitTeamColors.relation_for_team(old_state.team, RwRoomClient.players, RwRoomClient.local_slot))
	visual.bind_state(replacement)
	var previous_visual: RwUnitVisual = _unit_visuals.get(object_id) as RwUnitVisual
	if previous_visual != null:
		previous_visual.queue_free()
	unit_layer.add_child(visual)
	_unit_states[object_id] = replacement
	_unit_visuals[object_id] = visual
	if _combat != null:
		_combat.reset_unit(replacement)
	if replacement.movement_speed > 0.0:
		_mobile_unit_states.append(replacement)
	if definition.needs_visual_ticks():
		_animated_visual_units.append(replacement)
	if RwRoomClient.battle_economy.has_unit_income(replacement):
		_animated_extractors.append(replacement)
		RwRoomClient.battle_economy.register_extractor(replacement)
	if definition.blocks_movement and _path_grid != null:
		_path_grid.block_structure(replacement.world_position, definition.structure_footprint_min, definition.structure_footprint_max)
	if _path_grid != null:
		_path_grid.finalize_obstacles()
	visual.set_selected(_selected_unit_ids.has(object_id))
	hud_layer.minimap.refresh_units()
	if _selected_unit_ids.has(object_id):
		_show_selection()


func _spawn_produced_unit(factory: RwUnitState, action: RwUnitActionDefinition) -> void:
	var definition: RwUnitDefinition = _unit_registry.find_definition(action.target_source_id, action.target_unit_name)
	if definition == null:
		return
	var factory_definition: RwUnitDefinition = _unit_registry.find_definition(factory.source_id, factory.unit_name)
	var exit_move_away: float = factory_definition.factory_exit_move_away if factory_definition != null else 70.0
	var exit_offset: Vector2 = factory_definition.factory_exit_offset if factory_definition != null else Vector2(0.0, 9.0)
	var exit_position: Vector2 = _find_factory_exit(factory.world_position, definition.movement_type, exit_move_away)
	var spawn_position: Vector2 = factory.world_position + exit_offset
	if factory.unit_name == "seaFactory":
		spawn_position.y = maxf(spawn_position.y, factory.world_position.y - 20.0 + definition.collision_radius)
	var spawn: Dictionary = {
		"object_id": _next_object_id,
		"source_id": action.target_source_id,
		"unit_name": action.target_unit_name,
		"team": factory.team,
		"position": spawn_position,
		"rotation_degrees": 90.0,
	}
	_next_object_id += 1
	var team_color: Color = RwUnitTeamColors.for_team(factory.team, RwRoomClient.players)
	var visual: RwUnitVisual = _unit_registry.create_visual(spawn, team_color)
	visual.set_footprint_tile_size(_map_tile_size)
	visual.set_relation(RwUnitTeamColors.relation_for_team(factory.team, RwRoomClient.players, RwRoomClient.local_slot))
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.initialize_from_spawn(spawn, definition)
	if unit_state.movement_speed > 0.0 and factory_definition != null:
		var factory_cell: Vector2i = _path_grid.structure_anchor_cell(factory.world_position, factory_definition.structure_footprint_min, factory_definition.structure_footprint_max) if _path_grid != null else Vector2i.ZERO
		unit_state.apply_factory_exit(
			exit_position,
			factory_cell,
			factory_definition.structure_footprint_min,
			factory_definition.structure_footprint_max,
		)
	visual.bind_state(unit_state)
	unit_layer.add_child(visual)
	_unit_states[unit_state.object_id] = unit_state
	_unit_visuals[unit_state.object_id] = visual
	if _combat != null:
		_combat.register_unit(unit_state)
	if unit_state.movement_speed > 0.0:
		_mobile_unit_states.append(unit_state)
	if definition.needs_visual_ticks():
		_animated_visual_units.append(unit_state)
	if RwRoomClient.battle_economy.has_unit_income(unit_state):
		_animated_extractors.append(unit_state)
		RwRoomClient.battle_economy.register_extractor(unit_state)
	if _unit_orders != null and _factory_rally_points.has(factory.object_id):
		_unit_orders.apply_command({
			"team": factory.team.to_int(),
			"order_type": "move",
			"target": _factory_rally_points[factory.object_id],
			"unit_ids": [unit_state.object_id,],
			"is_queued": true,
		})
	_refresh_fog_visibility()
	hud_layer.minimap.refresh_units()
	if factory.team == str(RwRoomClient.local_slot):
		hud_layer.show_status("Unit created: %s (x1)" % action.display_name)
		AudioManager.play_ui(&"add")


func _find_factory_exit(factory_position: Vector2, movement_type: String, exit_distance: float) -> Vector2:
	if _path_grid == null:
		return factory_position + Vector2(0.0, exit_distance)
	var preferred_position: Vector2 = factory_position + Vector2(0.0, exit_distance)
	if _path_grid.is_passable(_path_grid.world_to_cell(preferred_position), movement_type):
		return preferred_position
	var center: Vector2i = _path_grid.world_to_cell(factory_position)
	var first_distance: int = maxi(2, ceili(exit_distance / float(_path_grid.tile_size.y)))
	for distance: int in range(first_distance, first_distance + 6):
		var center_exit: Vector2i = center + Vector2i(0, distance)
		if _path_grid.is_passable(center_exit, movement_type):
			return _path_grid.cell_to_world(center_exit)
		for lateral: int in range(1, distance + 1):
			for direction: int in [1, -1,]:
				var side_exit: Vector2i = center + Vector2i(lateral * direction, distance)
				if _path_grid.is_passable(side_exit, movement_type):
					return _path_grid.cell_to_world(side_exit)
	return preferred_position


func _formation_targets(unit_ids: Array[int], target: Vector2) -> Dictionary:
	var groups: Dictionary = {}
	var formation_targets: Dictionary = {}
	for object_id: int in unit_ids:
		var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.movement_speed <= 0.0:
			continue
		if not groups.has(unit_state.movement_type):
			groups[unit_state.movement_type] = []
		(groups[unit_state.movement_type] as Array).append(object_id)
	for movement_type: String in groups:
		var members: Array[int] = []
		for object_id: int in groups[movement_type]:
			members.append(object_id)
		if members.size() <= 1:
			continue
		members.sort()
		var leader_id: int = members[0]
		var leader_distance: float = INF
		var center: Vector2 = Vector2.ZERO
		var radius: float = 0.0
		for object_id: int in members:
			var unit_state: RwUnitState = _unit_states[object_id]
			var distance: float = unit_state.world_position.distance_squared_to(target)
			if distance < leader_distance:
				leader_distance = distance
				leader_id = object_id
			center += unit_state.world_position
			radius = maxf(radius, unit_state.collision_radius)
		center /= float(members.size())
		var direction: float = (target - center).angle()
		var spacing: float = 2.0 + 3.0 * radius
		var leader: RwUnitState = _unit_states[leader_id]
		members.erase(leader_id)
		for slot_index: int in members.size():
			@warning_ignore("integer_division")
			var row: int = int(slot_index / 6)
			@warning_ignore("integer_division")
			var column: int = int((slot_index % 6) / 2) + 1
			var side: float = -1.0 if slot_index % 2 == 0 else 1.0
			var offset: Vector2 = Vector2(-float(row) * spacing, side * float(column) * spacing).rotated(direction)
			var slot_position: Vector2 = leader.world_position + offset
			var nearest_id: int = members[0]
			var nearest_distance: float = INF
			for object_id: int in members:
				var candidate: RwUnitState = _unit_states[object_id]
				var distance: float = candidate.world_position.distance_squared_to(slot_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_id = object_id
			formation_targets[nearest_id] = (target + offset).clamp(Vector2.ZERO, _world_size)
			members.erase(nearest_id)
			if members.is_empty():
				break
	return formation_targets


func _separate_mobile_units() -> void:
	for first_index: int in _mobile_unit_states.size():
		var first: RwUnitState = _mobile_unit_states[first_index]
		if first.is_dead or first.collision_radius <= 0.0:
			continue
		for second_index: int in range(first_index + 1, _mobile_unit_states.size()):
			var second: RwUnitState = _mobile_unit_states[second_index]
			if second.is_dead or second.collision_radius <= 0.0 or first.team != second.team:
				continue
			var separation: Vector2 = second.world_position - first.world_position
			var minimum_distance: float = first.collision_radius + second.collision_radius
			if separation.length_squared() >= minimum_distance * minimum_distance:
				continue
			var distance: float = separation.length()
			if first.is_exiting_factory() != second.is_exiting_factory() and absf(separation.x) < 0.01 and absf(separation.y) > 0.01:
				separation.x = 2.0 if first.object_id < second.object_id else -2.0
			var direction: Vector2 = separation.normalized() if separation.length_squared() > 0.000001 else Vector2.RIGHT
			var overlap: float = minimum_distance - distance
			var priority: int = maxi(first.soft_collision_on_all, second.soft_collision_on_all)
			var push_distance: float = overlap / float(priority) if priority > 0 else overlap
			push_distance *= 0.95
			if push_distance > 1.0:
				push_distance *= 0.7
			if push_distance > 3.0:
				push_distance = 3.0 + (push_distance - 3.0) * 0.7
			if push_distance > 6.0:
				push_distance = 6.0 + (push_distance - 6.0) * 0.7
			if push_distance > 10.0:
				push_distance = 10.0 + (push_distance - 10.0) * 0.7
			var first_mass: float = maxf(first.push_mass, 1.0)
			var second_mass: float = maxf(second.push_mass, 1.0)
			if first.team == second.team:
				var first_moving: bool = first.order_type == "move" or first.order_type == "attackMove"
				var second_moving: bool = second.order_type == "move" or second.order_type == "attackMove"
				if first_moving and not second_moving:
					second_mass *= 1.7
				elif second_moving and not first_moving:
					first_mass *= 1.7
			var correction: Vector2 = direction * push_distance
			first.displace_from_collision(-correction * second_mass / (first_mass + second_mass), _path_grid)
			second.displace_from_collision(correction * first_mass / (first_mass + second_mass), _path_grid)


func _command_center_frame(frame: int) -> int:
	if frame < 20:
		return 0
	var phase: int = posmod(frame - 20, 100)
	if phase >= 30:
		return 0
	@warning_ignore("integer_division")
	var step: int = int(phase / 5) + 1
	return step if step <= 3 else 6 - step
