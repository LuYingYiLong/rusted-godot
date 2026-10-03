## 保存单位在同步帧中可变化的状态
class_name RwUnitState
extends Resource

signal state_changed(state: RwUnitState)

const NAVIGATION_ORDER_TYPES: Array[String] = [
	"move",
	"attackMove",
	"patrol",
	"guardAt",
	"unloadAt",
	"attack",
	"repair",
	"reclaim",
	"loadInto",
	"loadUp",
	"guard",
	"touchTarget",
	"follow",
]

@export var object_id: int
@export var source_id: String
@export var unit_name: String
@export var team: String
@export var world_position: Vector2
@export var body_rotation_degrees: float
@export var turret_rotation_degrees: float
@export var weapon_rotations_degrees: PackedFloat32Array
@export var altitude: float
## 是否处于水下，未指定时按高度推断
@export var submerged: bool
@export var health: float
@export var max_health: float
## 当前护盾值
@export var shield: float
## 护盾最大值
@export var max_shield: float
## 护盾受击闪烁剩余同步帧数
@export var shield_flash_frames: int
@export var build_progress: float = 1.0
## 正在生产的队列进度，-1 表示没有活动队列
@export var production_progress: float = -1.0
@export var movement_speed: float
@export var water_movement_speed: float
@export var movement_type: String = "LAND"
@export var turn_speed: float
@export var water_turn_speed: float
@export var turn_acceleration: float
@export var movement_acceleration: float
@export var movement_deceleration: float
@export var collision_radius: float
@export var push_mass: float = 3000.0
@export var sight_range: int
@export var animation_frame: int
## 附加视觉层所用的同步帧计数
@export var visual_frame: int
@export var tech_level: int = 1
@export var is_dead: bool
@export var order_type: String
@export var order_target: Vector2
@export var order_target_id: int = -1
## 当前同步命令携带的单位动作编号
@export var order_action_id: String
## 原版攻击模式编号
@export var attack_mode: int = -1
@export var resource_balances: Dictionary

var _path_waypoints: Array[Vector2]
var _path_index: int
var _movement_velocity: float
var _turn_velocity: float
var _factory_exit_footprint: Rect2i
var _is_exiting_factory: bool
var _animation_step_frames: int
var _animation_frame_count: int
var _animation_ping_pong: bool
var _animation_speed_follows_tech_level: bool
var _animation_tick: float
var _animation_step: int
var _has_visual_clock: bool
var _submerged_below: float = -1.0


func initialize_from_spawn(spawn: Dictionary, definition: RwUnitDefinition) -> void:
	object_id = int(spawn.get("object_id", 0))
	source_id = str(spawn.get("source_id", ""))
	unit_name = str(spawn.get("unit_name", ""))
	team = str(spawn.get("team", ""))
	world_position = spawn.get("position", Vector2.ZERO)
	var visual_profile: RwUnitVisualProfile = definition.visual_profile if definition != null else null
	var spawn_altitude: float = visual_profile.spawn_altitude if visual_profile != null else 0.0
	_submerged_below = visual_profile.submerged_below if visual_profile != null else -1.0
	altitude = float(spawn.get("altitude", spawn_altitude))
	submerged = bool(spawn.get("submerged", altitude < _submerged_below))
	body_rotation_degrees = float(spawn.get("rotation_degrees", 0.0))
	if definition != null and not definition.applies_spawn_rotation:
		body_rotation_degrees = 0.0
	turret_rotation_degrees = float(spawn.get("turret_rotation_degrees", body_rotation_degrees))
	weapon_rotations_degrees = PackedFloat32Array()
	var rotation_count: int = 1
	if definition != null:
		for weapon: RwUnitWeaponDefinition in definition.weapon_parts:
			if weapon != null:
				rotation_count = maxi(rotation_count, weapon.rotation_state_index + 1)
		for weapon: RwWeaponDefinition in definition.combat_weapons:
			if weapon != null:
				rotation_count = maxi(rotation_count, weapon.rotation_state_index + 1)
	for index: int in rotation_count:
		weapon_rotations_degrees.append(turret_rotation_degrees)
	if spawn.has("weapon_rotations_degrees"):
		_apply_weapon_rotations(spawn["weapon_rotations_degrees"])
	max_health = definition.max_health if definition != null else 1.0
	max_shield = maxf(definition.max_shield, 0.0) if definition != null else 0.0
	shield = clampf(float(spawn.get("shield", max_shield)), 0.0, max_shield)
	build_progress = clampf(float(spawn.get("build_progress", 1.0)), 0.0, 1.0)
	production_progress = clampf(float(spawn.get("production_progress", -1.0)), -1.0, 1.0)
	movement_speed = definition.movement_speed if definition != null else 0.0
	water_movement_speed = definition.water_movement_speed if definition != null else 0.0
	movement_type = definition.movement_type if definition != null else "LAND"
	turn_speed = definition.turn_speed if definition != null else 0.0
	water_turn_speed = definition.water_turn_speed if definition != null else 0.0
	turn_acceleration = definition.turn_acceleration if definition != null else 0.0
	movement_acceleration = definition.movement_acceleration if definition != null else 0.0
	movement_deceleration = definition.movement_deceleration if definition != null else 0.0
	collision_radius = definition.collision_radius if definition != null else 0.0
	push_mass = definition.push_mass if definition != null else 3000.0
	sight_range = definition.sight_range if definition != null else 15
	tech_level = maxi(int(spawn.get("tech_level", 1)), 1)
	visual_frame = maxi(int(spawn.get("visual_frame", 0)), 0)
	_animation_step_frames = definition.animation_step_frames if definition != null else 0
	_animation_frame_count = definition.body_frames if definition != null else 1
	_animation_ping_pong = definition.animation_ping_pong if definition != null else false
	_animation_speed_follows_tech_level = definition.animation_speed_follows_tech_level if definition != null else false
	_animation_tick = 0.0
	_animation_step = 0
	_has_visual_clock = visual_profile.is_animated() if visual_profile != null else false
	health = clampf(float(spawn.get("health", max_health)), 0.0, max_health)
	state_changed.emit(self)


func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("position"):
		world_position = snapshot["position"]
	if snapshot.has("body_rotation_degrees"):
		body_rotation_degrees = float(snapshot["body_rotation_degrees"])
	if snapshot.has("turret_rotation_degrees"):
		turret_rotation_degrees = float(snapshot["turret_rotation_degrees"])
		if weapon_rotations_degrees.is_empty():
			weapon_rotations_degrees.append(turret_rotation_degrees)
		else:
			weapon_rotations_degrees[0] = turret_rotation_degrees
	if snapshot.has("weapon_rotations_degrees"):
		_apply_weapon_rotations(snapshot["weapon_rotations_degrees"])
	if snapshot.has("altitude"):
		altitude = float(snapshot["altitude"])
		if not snapshot.has("submerged"):
			submerged = altitude < _submerged_below
	if snapshot.has("submerged"):
		submerged = bool(snapshot["submerged"])
	if snapshot.has("max_health"):
		max_health = maxf(float(snapshot["max_health"]), 0.0)
	if snapshot.has("max_shield"):
		max_shield = maxf(float(snapshot["max_shield"]), 0.0)
		shield = minf(shield, max_shield)
	if snapshot.has("shield"):
		var next_shield: float = clampf(float(snapshot["shield"]), 0.0, max_shield)
		if next_shield < shield:
			shield_flash_frames = 12
		shield = next_shield
	if snapshot.has("shield_flash_frames"):
		shield_flash_frames = maxi(int(snapshot["shield_flash_frames"]), 0)
	if snapshot.has("build_progress"):
		build_progress = clampf(float(snapshot["build_progress"]), 0.0, 1.0)
	if snapshot.has("production_progress"):
		production_progress = clampf(float(snapshot["production_progress"]), -1.0, 1.0)
	if snapshot.has("health"):
		health = clampf(float(snapshot["health"]), 0.0, max_health)
	if snapshot.has("animation_frame"):
		animation_frame = maxi(int(snapshot["animation_frame"]), 0)
	if snapshot.has("visual_frame"):
		visual_frame = maxi(int(snapshot["visual_frame"]), 0)
	if snapshot.has("tech_level"):
		tech_level = maxi(int(snapshot["tech_level"]), 1)
	if snapshot.has("resource_balances"):
		resource_balances = (snapshot["resource_balances"] as Dictionary).duplicate()
	if snapshot.has("attack_mode"):
		attack_mode = int(snapshot["attack_mode"])
	if snapshot.has("is_dead"):
		is_dead = bool(snapshot["is_dead"])
	elif health <= 0.0:
		is_dead = true
	state_changed.emit(self)


## 更新建筑生产队列进度并通知单位视觉层
func set_production_progress(value: float) -> void:
	var next_progress: float = clampf(value, -1.0, 1.0)
	if is_equal_approx(production_progress, next_progress):
		return
	production_progress = next_progress
	state_changed.emit(self)


## 读取指定炮塔的世界朝向，越界时返回主炮塔朝向
func get_weapon_rotation(index: int) -> float:
	if index >= 0 and index < weapon_rotations_degrees.size():
		return weapon_rotations_degrees[index]
	return turret_rotation_degrees


## 修改炮塔朝向并通知绘制层，角度使用世界坐标
func set_weapon_rotation(index: int, angle_degrees: float) -> void:
	if index < 0:
		return
	while weapon_rotations_degrees.size() <= index:
		weapon_rotations_degrees.append(turret_rotation_degrees)
	var normalized_angle: float = wrapf(angle_degrees, -180.0, 180.0)
	if is_equal_approx(weapon_rotations_degrees[index], normalized_angle):
		return
	weapon_rotations_degrees[index] = normalized_angle
	if index == 0:
		turret_rotation_degrees = normalized_angle
	state_changed.emit(self)


## 扣除生命值，首次死亡时返回 true
func apply_damage(amount: float) -> bool:
	if amount <= 0.0 or is_dead:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		is_dead = true
	state_changed.emit(self)
	return is_dead


## 修改护盾值，受击时短暂增强护盾贴图亮度
func set_shield(value: float) -> void:
	var next_shield: float = clampf(value, 0.0, max_shield)
	if is_equal_approx(next_shield, shield):
		return
	if next_shield < shield:
		shield_flash_frames = 12
	shield = next_shield
	state_changed.emit(self)


func advance_visual_animation(frame_count: int) -> void:
	if frame_count <= 0 or is_dead or build_progress < 1.0:
		return
	var is_changed: bool
	if _has_visual_clock:
		visual_frame += frame_count
		is_changed = true
	if shield_flash_frames > 0:
		shield_flash_frames = maxi(shield_flash_frames - frame_count, 0)
		is_changed = true
	if _animation_step_frames > 0 and _animation_frame_count > 1:
		var cycle_length: int = _animation_frame_count * 2 if _animation_ping_pong else _animation_frame_count
		for frame: int in frame_count:
			var animation_speed: float = float(tech_level) if _animation_speed_follows_tech_level else 1.0
			_animation_tick = maxf(_animation_tick - animation_speed, 0.0)
			if _animation_tick > 0.0:
				continue
			_animation_tick = float(_animation_step_frames)
			_animation_step = (_animation_step + 1) % cycle_length
			var next_frame: int = mini(_animation_step, cycle_length - 1 - _animation_step) if _animation_ping_pong else _animation_step
			if animation_frame != next_frame:
				animation_frame = next_frame
				is_changed = true
	if is_changed:
		state_changed.emit(self)


## 应用同步命令并清除旧路径，目标单位编号可为空
func apply_order(command_type: String, target: Vector2, target_id: int = -1, action_id: String = "") -> void:
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = action_id
	_path_waypoints.clear()
	_path_index = 0
	_movement_velocity = 0.0
	_turn_velocity = 0.0
	_is_exiting_factory = false
	state_changed.emit(self)


func apply_move_order(target: Vector2, waypoints: Array[Vector2], command_type: String = "move", target_id: int = -1, action_id: String = "") -> void:
	var pending_exit: bool = _is_exiting_factory and _path_index < _path_waypoints.size()
	var exit_target: Vector2 = _path_waypoints[_path_index] if pending_exit else Vector2.ZERO
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = action_id
	_path_waypoints = waypoints.duplicate()
	if pending_exit and (_path_waypoints.is_empty() or _path_waypoints[0] != exit_target):
		_path_waypoints.push_front(exit_target)
	_path_index = 0
	_is_exiting_factory = pending_exit
	state_changed.emit(self)


func apply_factory_exit(target: Vector2, factory_cell: Vector2i, footprint_min: Vector2i, footprint_max: Vector2i) -> void:
	apply_move_order(target, [target,])
	_factory_exit_footprint = Rect2i(factory_cell + footprint_min, footprint_max - footprint_min + Vector2i.ONE)
	_is_exiting_factory = true


func is_exiting_factory() -> bool:
	return _is_exiting_factory


func get_factory_exit_target() -> Vector2:
	if not _is_exiting_factory or _path_index >= _path_waypoints.size():
		return world_position
	return _path_waypoints[_path_index]


func get_navigation_path() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if is_dead or not _is_navigation_order():
		return points
	if _path_index >= _path_waypoints.size():
		return points
	points.append(world_position)
	for index: int in range(_path_index, _path_waypoints.size()):
		points.append(_path_waypoints[index])
	return points


func advance_movement(frame_count: int, path_grid: RwPathGrid) -> void:
	if frame_count <= 0 or is_dead or movement_speed <= 0.0 or not _is_navigation_order():
		return
	if _path_waypoints.is_empty():
		return
	var is_changed: bool
	for frame: int in frame_count:
		if _path_index >= _path_waypoints.size():
			if order_target_id <= 0:
				order_type = ""
			else:
				_path_waypoints.clear()
				_path_index = 0
			_movement_velocity = 0.0
			_is_exiting_factory = false
			is_changed = true
			break
		var waypoint: Vector2 = _path_waypoints[_path_index]
		var distance: float = world_position.distance_to(waypoint)
		if distance <= 1.0:
			world_position = waypoint
			_path_index += 1
			if _is_exiting_factory:
				_is_exiting_factory = false
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
		_add_weapon_rotation(turn_step)
		if turn_step != 0.0:
			is_changed = true
		var remaining_angle: float = absf(wrapf(desired_angle - body_rotation_degrees, -180.0, 180.0))
		var alignment: float = clampf(1.0 - remaining_angle / 90.0, 0.0, 1.0)
		var target_speed: float = minf(current_speed * alignment, distance)
		var speed_change: float = movement_acceleration if target_speed > _movement_velocity else movement_deceleration
		_movement_velocity = move_toward(_movement_velocity, target_speed, speed_change)
		var next_position: Vector2 = world_position.move_toward(waypoint, _movement_velocity)
		if not _can_traverse(world_position, next_position, path_grid):
			_movement_velocity = 0.0
			break
		world_position = next_position
		is_changed = true
	if is_changed:
		state_changed.emit(self)


func _is_navigation_order() -> bool:
	return NAVIGATION_ORDER_TYPES.has(order_type)


func displace_from_collision(displacement: Vector2, path_grid: RwPathGrid) -> void:
	if is_dead or displacement == Vector2.ZERO:
		return
	var next_position: Vector2 = world_position + displacement
	if not _can_traverse(world_position, next_position, path_grid):
		return
	world_position = next_position
	state_changed.emit(self)


func _can_traverse(start_position: Vector2, end_position: Vector2, path_grid: RwPathGrid) -> bool:
	if path_grid == null or path_grid.has_clear_line(start_position, end_position, movement_type):
		return true
	if not _is_exiting_factory:
		return false
	var start_cell: Vector2i = path_grid.world_to_cell(start_position)
	if not _factory_exit_footprint.has_point(start_cell):
		return false
	var end_cell: Vector2i = path_grid.world_to_cell(end_position)
	return _factory_exit_footprint.has_point(end_cell) or path_grid.is_passable(end_cell, movement_type)


func _apply_weapon_rotations(values: Variant) -> void:
	if not values is Array and not values is PackedFloat32Array:
		return
	if weapon_rotations_degrees.is_empty():
		weapon_rotations_degrees.append(turret_rotation_degrees)
	for index: int in mini(values.size(), weapon_rotations_degrees.size()):
		weapon_rotations_degrees[index] = float(values[index])
	turret_rotation_degrees = weapon_rotations_degrees[0]


func _add_weapon_rotation(amount: float) -> void:
	if amount == 0.0:
		return
	for index: int in weapon_rotations_degrees.size():
		weapon_rotations_degrees[index] = wrapf(weapon_rotations_degrees[index] + amount, -180.0, 180.0)
	turret_rotation_degrees = weapon_rotations_degrees[0]
