class_name RwUnitState
extends Resource

signal state_changed(state: RwUnitState)

@export var object_id: int
@export var source_id: String
@export var unit_name: String
@export var team: String
@export var world_position: Vector2
@export var body_rotation_degrees: float
@export var turret_rotation_degrees: float
@export var altitude: float
@export var health: float
@export var max_health: float
@export var movement_speed: float
@export var water_movement_speed: float
@export var movement_type: String = "LAND"
@export var turn_speed: float
@export var water_turn_speed: float
@export var turn_acceleration: float
@export var movement_acceleration: float
@export var movement_deceleration: float
@export var collision_radius: float
@export var sight_range: int
@export var animation_frame: int
@export var is_dead: bool
@export var order_type: String
@export var order_target: Vector2
@export var resource_balances: Dictionary

var _path_waypoints: Array[Vector2]
var _path_index: int
var _movement_velocity: float
var _turn_velocity: float


func initialize_from_spawn(spawn: Dictionary, definition: RwUnitDefinition) -> void:
	object_id = int(spawn.get("object_id", 0))
	source_id = str(spawn.get("source_id", ""))
	unit_name = str(spawn.get("unit_name", ""))
	team = str(spawn.get("team", ""))
	world_position = spawn.get("position", Vector2.ZERO)
	body_rotation_degrees = float(spawn.get("rotation_degrees", 0.0))
	if definition != null and not definition.applies_spawn_rotation:
		body_rotation_degrees = 0.0
	max_health = definition.max_health if definition != null else 1.0
	movement_speed = definition.movement_speed if definition != null else 0.0
	water_movement_speed = definition.water_movement_speed if definition != null else 0.0
	movement_type = definition.movement_type if definition != null else "LAND"
	turn_speed = definition.turn_speed if definition != null else 0.0
	water_turn_speed = definition.water_turn_speed if definition != null else 0.0
	turn_acceleration = definition.turn_acceleration if definition != null else 0.0
	movement_acceleration = definition.movement_acceleration if definition != null else 0.0
	movement_deceleration = definition.movement_deceleration if definition != null else 0.0
	collision_radius = definition.collision_radius if definition != null else 0.0
	sight_range = definition.sight_range if definition != null else 15
	health = max_health
	state_changed.emit(self)


func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("position"):
		world_position = snapshot["position"]
	if snapshot.has("body_rotation_degrees"):
		body_rotation_degrees = float(snapshot["body_rotation_degrees"])
	if snapshot.has("turret_rotation_degrees"):
		turret_rotation_degrees = float(snapshot["turret_rotation_degrees"])
	if snapshot.has("altitude"):
		altitude = float(snapshot["altitude"])
	if snapshot.has("max_health"):
		max_health = maxf(float(snapshot["max_health"]), 0.0)
	if snapshot.has("health"):
		health = clampf(float(snapshot["health"]), 0.0, max_health)
	if snapshot.has("animation_frame"):
		animation_frame = maxi(int(snapshot["animation_frame"]), 0)
	if snapshot.has("resource_balances"):
		resource_balances = (snapshot["resource_balances"] as Dictionary).duplicate()
	if snapshot.has("is_dead"):
		is_dead = bool(snapshot["is_dead"])
	elif health <= 0.0:
		is_dead = true
	state_changed.emit(self)


func apply_order(command_type: String, target: Vector2) -> void:
	order_type = command_type
	order_target = target
	_path_waypoints.clear()
	_path_index = 0
	state_changed.emit(self)


func apply_move_order(target: Vector2, waypoints: Array[Vector2], command_type: String = "move") -> void:
	order_type = command_type
	order_target = target
	_path_waypoints = waypoints.duplicate()
	_path_index = 0
	state_changed.emit(self)


func get_navigation_path() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if is_dead or (order_type != "move" and order_type != "attackMove"):
		return points
	if _path_index >= _path_waypoints.size():
		return points
	points.append(world_position)
	for index: int in range(_path_index, _path_waypoints.size()):
		points.append(_path_waypoints[index])
	return points


func advance_movement(frame_count: int, path_grid: RwPathGrid) -> void:
	if frame_count <= 0 or is_dead or movement_speed <= 0.0 or (order_type != "move" and order_type != "attackMove"):
		return
	if _path_waypoints.is_empty():
		return
	var is_changed: bool
	for frame: int in frame_count:
		if _path_index >= _path_waypoints.size():
			order_type = ""
			_movement_velocity = 0.0
			is_changed = true
			break
		var waypoint: Vector2 = _path_waypoints[_path_index]
		var distance: float = world_position.distance_to(waypoint)
		if distance <= 1.0:
			world_position = waypoint
			_path_index += 1
			is_changed = true
			continue
		var on_water: bool = path_grid != null and path_grid.is_water_at(world_position)
		var current_speed: float = water_movement_speed if on_water and water_movement_speed > 0.0 else movement_speed
		var current_turn_speed: float = water_turn_speed if on_water and water_turn_speed > 0.0 else turn_speed
		var desired_angle: float = rad_to_deg((waypoint - world_position).angle())
		var _angle_difference: float = wrapf(desired_angle - body_rotation_degrees, -180.0, 180.0)
		var requested_turn: float = signf(_angle_difference) * current_turn_speed
		_turn_velocity = move_toward(_turn_velocity, requested_turn, turn_acceleration)
		var turn_step: float = minf(absf(_turn_velocity), absf(_angle_difference)) * signf(_angle_difference)
		body_rotation_degrees = wrapf(body_rotation_degrees + turn_step, -180.0, 180.0)
		var remaining_angle: float = absf(wrapf(desired_angle - body_rotation_degrees, -180.0, 180.0))
		var alignment: float = clampf(1.0 - remaining_angle / 90.0, 0.0, 1.0)
		var target_speed: float = minf(current_speed * alignment, distance)
		var speed_change: float = movement_acceleration if target_speed > _movement_velocity else movement_deceleration
		_movement_velocity = move_toward(_movement_velocity, target_speed, speed_change)
		var next_position: Vector2 = world_position.move_toward(waypoint, _movement_velocity)
		if path_grid != null and not path_grid.has_clear_line(world_position, next_position, movement_type):
			_movement_velocity = 0.0
			break
		world_position = next_position
		is_changed = true
	if is_changed:
		state_changed.emit(self)


func displace_from_collision(displacement: Vector2, path_grid: RwPathGrid) -> void:
	if is_dead or displacement == Vector2.ZERO:
		return
	var next_position: Vector2 = world_position + displacement
	if path_grid != null and not path_grid.has_clear_line(world_position, next_position, movement_type):
		return
	world_position = next_position
	state_changed.emit(self)
