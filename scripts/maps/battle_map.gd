extends Control

const MIN_ZOOM: float = 0.15
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 1.2
const ZOOM_SMOOTHING: float = 12.0
const SELECTION_DRAG_PIXELS: float = 8.0
const KEYBOARD_PAN_SPEED: float = 600.0
const NAVIGATION_COLOR: Color = Color("11c608")

@onready var map_root: Node2D = %MapRoot
@onready var map_camera: Camera2D = %MapCamera
@onready var fog_sprite: Sprite2D = %FogOverlay
@onready var navigation_overlay: Node2D = %NavigationOverlay
@onready var unit_layer: Node2D = %InitialUnits
@onready var selection_overlay: Control = %SelectionOverlay
@onready var hud_layer: RwHudLayer = $HudLayer

var _panning: bool
var _selection_pressed: bool
var _selection_dragging: bool
var _selection_additive: bool
var _selection_start_screen: Vector2
var _selection_end_screen: Vector2
var _world_size: Vector2
var _target_zoom: float
var _zoom_anchor_screen: Vector2
var _zoom_anchor_world: Vector2
var _last_simulated_frame: int
var _unit_states: Dictionary
var _unit_visuals: Dictionary
var _unit_registry: RwUnitRegistry
var _fog: RwFogOfWar
var _path_grid: RwPathGrid
var _mobile_unit_states: Array[RwUnitState]
var _animated_command_centers: Array[RwUnitState]
var _selected_unit_ids: Array[int]


func _ready() -> void:
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
	_focus_on_local_start()
	_initialize_fog(map_size, tile_size)
	var minimap_error: String = hud_layer.configure_battle(map_name, _world_size, _unit_states, _unit_registry)
	hud_layer.set_fog(_fog)
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)
	RwRoomClient.set_initial_command_centers(unit_result["command_center_counts"])
	var warning: String = " Minimap: %s." % minimap_error if not minimap_error.is_empty() else ""
	if int(RwRoomClient.settings.get("starting_units", 1)) != 1:
		warning = " The room uses a starting-unit preset that is not simulated."
	for player: Dictionary in RwRoomClient.players:
		var starting_units_override: int = int(player.get("starting_units_override", -1))
		if starting_units_override != -1 and starting_units_override != 1:
			warning = " A player uses a starting-unit override that is not simulated."
			break
	hud_layer.show_status("Map loaded: %d initial units (%d defined, %d placeholders).%s Drag to select own units; right-click to move." % [
		int(unit_result["total"]),
		int(unit_result["defined"]),
		int(unit_result["placeholder"]),
		warning,
	])
	RwRoomClient.mark_battle_map_loaded()


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
		total += 1
		if definition == null:
			placeholder += 1
		else:
			defined += 1
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
		match unit_state.unit_name:
			"commandCenter":
				_path_grid.block_structure(unit_state.world_position, Vector2i(-1, -1), Vector2i(1, 1))
			"seaFactory":
				_path_grid.block_structure(unit_state.world_position, Vector2i(-1, -1), Vector2i(1, 2))


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
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)
	if _selection_pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_selection(get_viewport().get_mouse_position())
	if not _selected_unit_ids.is_empty():
		navigation_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _world_size == Vector2.ZERO:
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


func _on_minimap_position_chosen(world_position: Vector2) -> void:
	map_camera.position = world_position
	_clamp_camera_position()
	_zoom_anchor_world = _screen_to_world(_zoom_anchor_screen)
	hud_layer.update_camera_view(map_camera.position, map_camera.zoom.x, get_viewport_rect().size)


func _on_unit_action_chosen(action_id: String, _unit_ids: Array[int]) -> void:
	hud_layer.show_status("%s is not available in the current battle simulation" % action_id)


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


func _on_room_updated(_settings: Dictionary, _players: Array[Dictionary], _local_slot: int) -> void:
	_refresh_fog_visibility()


func _on_battle_frame_advanced(frame: int, _next_blocking_frame: int) -> void:
	var frame_delta: int = maxi(frame - _last_simulated_frame, 0)
	_last_simulated_frame = frame
	for step: int in frame_delta:
		for unit_state: RwUnitState in _mobile_unit_states:
			unit_state.advance_movement(1, _path_grid)
		_separate_mobile_units()
	if frame_delta > 0:
		_refresh_fog_visibility()
	var animation_frame: int = _command_center_frame(frame)
	for unit_state: RwUnitState in _animated_command_centers:
		if unit_state.animation_frame != animation_frame and not unit_state.is_dead:
			unit_state.apply_snapshot({"animation_frame": animation_frame,})
	if frame_delta > 0 and _selected_unit_ids.size() == 1 and frame % 10 == 0:
		_show_selection()


func _on_battle_commands_reached(_frame: int, commands: Array[Dictionary]) -> void:
	for command: Dictionary in commands:
		var order_type: String = str(command.get("order_type", ""))
		if order_type.is_empty():
			continue
		var target: Vector2 = command.get("target", Vector2.ZERO)
		var command_paths: Dictionary = command.get("paths", {})
		var unit_ids: Array[int] = []
		for object_id: int in command.get("unit_ids", []):
			unit_ids.append(object_id)
		var is_movement_order: bool = order_type == "move" or order_type == "attackMove"
		var formation_targets: Dictionary = _formation_targets(unit_ids, target) if is_movement_order else {}
		for object_id: int in unit_ids:
			var unit_state: RwUnitState = _unit_states.get(object_id) as RwUnitState
			if unit_state == null:
				continue
			if is_movement_order and _path_grid != null and unit_state.movement_speed > 0.0:
				var unit_target: Vector2 = formation_targets.get(object_id, target)
				var waypoints: Array[Vector2] = []
				if command_paths.has(object_id):
					var path_cells: Array[Vector2i] = command_paths[object_id]
					waypoints = _path_grid.path_from_cells(unit_state.world_position, unit_target, path_cells, unit_state.movement_type)
				if waypoints.is_empty():
					waypoints = _path_grid.find_path(unit_state.world_position, unit_target, unit_state.movement_type)
				unit_state.apply_move_order(unit_target, waypoints, order_type)
			else:
				unit_state.apply_order(order_type, target)
	if not _selected_unit_ids.is_empty():
		_show_selection()


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
			if second.is_dead or second.collision_radius <= 0.0:
				continue
			var first_moving: bool = first.order_type == "move" or first.order_type == "attackMove"
			var second_moving: bool = second.order_type == "move" or second.order_type == "attackMove"
			if not first_moving and not second_moving:
				continue
			var separation: Vector2 = second.world_position - first.world_position
			var distance: float = separation.length()
			var minimum_distance: float = first.collision_radius + second.collision_radius
			if distance >= minimum_distance:
				continue
			var direction: Vector2 = separation / distance if distance > 0.001 else Vector2.RIGHT
			var correction: Vector2 = direction * minf(minimum_distance - distance, 2.0)
			if first_moving and second_moving:
				first.displace_from_collision(-correction * 0.5, _path_grid)
				second.displace_from_collision(correction * 0.5, _path_grid)
			elif first_moving:
				first.displace_from_collision(-correction, _path_grid)
			else:
				second.displace_from_collision(correction, _path_grid)


func _command_center_frame(frame: int) -> int:
	if frame < 20:
		return 0
	var phase: int = posmod(frame - 20, 100)
	if phase >= 30:
		return 0
	@warning_ignore("integer_division")
	var step: int = int(phase / 5) + 1
	return step if step <= 3 else 6 - step
