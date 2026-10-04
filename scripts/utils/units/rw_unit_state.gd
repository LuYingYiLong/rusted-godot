extends Resource
class_name RwUnitState
## 保存单位在同步帧中可变化的状态

signal state_changed(state: RwUnitState)

const NAVIGATION_ORDER_TYPES: Array[String] = [
	"move",
	"build",
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
## 原版滑行模式，同步帧间保留二维速度
@export var movement_sliding: bool
## 移动方向不受当前机身角限制
@export var movement_ignores_body: bool
@export var collision_radius: float
@export var push_mass: float = 3000.0
@export var soft_collision_on_all: int
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

## 碰撞阶段累计并在下一同步帧移动阶段应用的推力
var collision_push_offset: Vector2
var collision_partner: RwUnitState
var collision_recent_frames: int

var _path_waypoints: Array[Vector2]
var _path_index: int
var _pending_path_waypoints: Array[Vector2]
var _pending_path_frames: float = -1.0
var _pending_direct_path: bool
var _pending_direct_waypoints: Array[Vector2]
var _movement_velocity: float
var _sliding_velocity: Vector2
var _turn_velocity: float
var _factory_exit_footprint: Rect2i
var _is_exiting_factory: bool
var _factory_exit_phase: int
var _factory_exit_delay: float
var _factory_exit_final_target: Vector2
var _animation_step_frames: int
var _animation_frame_count: int
var _animation_ping_pong: bool
var _animation_speed_follows_tech_level: bool
var _animation_tick: float
var _animation_step: int
var _idle_animation_start: int
var _idle_animation_end: int
var _idle_animation_step: float
var _idle_animation_ping_pong: bool
var _moving_animation_start: int
var _moving_animation_end: int
var _moving_animation_step: float
var _moving_animation_ping_pong: bool
var _active_visual_animation_mode: int = -1
var _snapshot_moving_frames: int
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
		body_rotation_degrees = definition.default_body_rotation_degrees
	var default_turret_rotation: float = 0.0 if definition != null and not definition.applies_spawn_rotation else body_rotation_degrees
	turret_rotation_degrees = float(spawn.get("turret_rotation_degrees", default_turret_rotation))
	if definition != null and definition.randomize_initial_weapon_rotation and not spawn.has("turret_rotation_degrees") and object_id > 0:
		turret_rotation_degrees = float(posmod(object_id * 1313, 360) - 180)
	weapon_rotations_degrees = PackedFloat32Array()
	var rotation_count: int = 1
	if definition != null:
		rotation_count = maxi(rotation_count, definition.weapon_state_count)
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
	soft_collision_on_all = definition.soft_collision_on_all if definition != null else 0
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
	movement_sliding = definition.movement_sliding if definition != null else false
	movement_ignores_body = definition.movement_ignores_body if definition != null else false
	collision_radius = definition.collision_radius if definition != null else 0.0
	push_mass = definition.push_mass if definition != null else 3000.0
	sight_range = definition.sight_range if definition != null else 15
	tech_level = maxi(int(spawn.get("tech_level", definition.tech_level if definition != null else 1)), 1)
	visual_frame = maxi(int(spawn.get("visual_frame", 0)), 0)
	_animation_step_frames = definition.animation_step_frames if definition != null else 0
	_animation_frame_count = definition.body_frames if definition != null else 1
	_animation_ping_pong = definition.animation_ping_pong if definition != null else false
	_animation_speed_follows_tech_level = definition.animation_speed_follows_tech_level if definition != null else false
	_idle_animation_start = definition.idle_animation_start if definition != null else 0
	_idle_animation_end = definition.idle_animation_end if definition != null else 0
	_idle_animation_step = definition.idle_animation_step if definition != null else 0.0
	_idle_animation_ping_pong = definition.idle_animation_ping_pong if definition != null else false
	_moving_animation_start = definition.moving_animation_start if definition != null else 0
	_moving_animation_end = definition.moving_animation_end if definition != null else 0
	_moving_animation_step = definition.moving_animation_step if definition != null else 0.0
	_moving_animation_ping_pong = definition.moving_animation_ping_pong if definition != null else false
	_animation_tick = 0.0
	_animation_step = 0
	_active_visual_animation_mode = -1
	_snapshot_moving_frames = 0
	_has_visual_clock = visual_profile.is_animated() if visual_profile != null else false
	health = clampf(float(spawn.get("health", max_health)), 0.0, max_health)
	state_changed.emit(self)


func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("position"):
		if world_position.distance_to(snapshot["position"]) > 0.5:
			_snapshot_moving_frames = 2
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
	if _idle_animation_step > 0.0 or _moving_animation_step > 0.0:
		is_changed = _advance_custom_visual_animation(frame_count) or is_changed
	elif _animation_step_frames > 0 and _animation_frame_count > 1:
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


func _advance_custom_visual_animation(frame_count: int) -> bool:
	var moving: bool = _movement_velocity > 0.01 or _path_index < _path_waypoints.size() or _snapshot_moving_frames > 0
	_snapshot_moving_frames = maxi(_snapshot_moving_frames - frame_count, 0)
	var mode: int = 1 if moving and _moving_animation_step > 0.0 and _moving_animation_end > _moving_animation_start else 0
	var start_frame: int = _moving_animation_start if mode == 1 else _idle_animation_start
	var end_frame: int = _moving_animation_end if mode == 1 else _idle_animation_end
	var step_frames: float = _moving_animation_step if mode == 1 else _idle_animation_step
	var ping_pong: bool = _moving_animation_ping_pong if mode == 1 else _idle_animation_ping_pong
	var is_changed: bool
	if _active_visual_animation_mode != mode:
		_active_visual_animation_mode = mode
		_animation_step = 0
		_animation_tick = step_frames
		if animation_frame != start_frame:
			animation_frame = start_frame
			is_changed = true
	if step_frames <= 0.0 or end_frame <= start_frame:
		return is_changed
	var frame_total: int = end_frame - start_frame + 1
	var cycle_length: int = frame_total * 2 - 2 if ping_pong else frame_total
	for frame: int in frame_count:
		_animation_tick -= 1.0
		if _animation_tick > 0.0:
			continue
		_animation_tick += maxf(step_frames, 0.01)
		_animation_step = (_animation_step + 1) % cycle_length
		var relative_frame: int = mini(_animation_step, cycle_length - _animation_step) if ping_pong else _animation_step
		var next_frame: int = start_frame + relative_frame
		if animation_frame != next_frame:
			animation_frame = next_frame
			is_changed = true
	return is_changed


## 应用同步命令并清除旧路径，目标单位编号可为空
func apply_order(command_type: String, target: Vector2, target_id: int = -1, action_id: String = "") -> void:
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = action_id
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	_movement_velocity = 0.0
	_turn_velocity = 0.0
	_is_exiting_factory = false
	_factory_exit_phase = 0
	state_changed.emit(self)


## 建造目标生成后转为维修目标，保留原版减速和转向惯性
func transition_to_target_order(command_type: String, target: Vector2, target_id: int) -> void:
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = ""
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	state_changed.emit(self)


func apply_move_order(target: Vector2, waypoints: Array[Vector2], command_type: String = "move", target_id: int = -1, action_id: String = "", path_delay_frames: int = 0) -> void:
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
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	if path_delay_frames > 0 and not pending_exit and not _path_waypoints.is_empty():
		_pending_path_waypoints = _path_waypoints.duplicate()
		_path_waypoints.clear()
		_pending_path_frames = float(path_delay_frames + 1)
	_is_exiting_factory = pending_exit
	_factory_exit_phase = 0
	state_changed.emit(self)


## 设置新单位离厂目标和原版暂缓重新寻路的帧数
func apply_factory_exit(target: Vector2, factory_cell: Vector2i, footprint_min: Vector2i, footprint_max: Vector2i, path_delay: float = 0.0) -> void:
	apply_move_order(target, [target,])
	_factory_exit_footprint = Rect2i(factory_cell + footprint_min, footprint_max - footprint_min + Vector2i.ONE)
	_is_exiting_factory = true
	_factory_exit_final_target = target
	_factory_exit_delay = path_delay
	_factory_exit_phase = 1 if path_delay > 0.0 else 4


## 等待原版联机预计算路径在下一帧投入使用
func defer_current_path() -> void:
	if _path_waypoints.is_empty():
		return
	_pending_path_waypoints = _path_waypoints.duplicate()
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_frames = 1.0


## 下一帧投入按命令时位置生成的原版直线路径
func schedule_source_direct_path(waypoints: Array[Vector2]) -> void:
	_path_waypoints.clear()
	_path_index = 0
	_pending_direct_path = true
	_pending_direct_waypoints = waypoints.duplicate()


func is_exiting_factory() -> bool:
	return _is_exiting_factory


func has_pending_path() -> bool:
	return _pending_path_frames >= 0.0


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


## 返回原版校验会累加的未走完路径点
func get_checksum_path_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(_path_index, _path_waypoints.size()):
		points.append(_path_waypoints[index])
	return points


func advance_movement(frame_count: int, path_grid: RwPathGrid, simulation_delta: float = 1.0) -> void:
	if frame_count <= 0 or is_dead or movement_speed <= 0.0:
		return
	var recent_collision_partner: RwUnitState = collision_partner if collision_recent_frames > 0 else null
	collision_recent_frames = maxi(collision_recent_frames - frame_count, 0)
	var factory_exit_path_started: bool
	if _factory_exit_phase == 1:
		_factory_exit_delay = maxf(_factory_exit_delay - float(frame_count) * simulation_delta, 0.0)
		if _factory_exit_delay == 0.0:
			factory_exit_path_started = true
			_factory_exit_phase = 4
			if path_grid != null and not path_grid.is_passable(path_grid.world_to_cell(world_position), movement_type):
				var exit_distance: float = minf(world_position.distance_to(_factory_exit_final_target), 60.0)
				_path_waypoints = [world_position + RwGameMath.path_direction(world_position, _factory_exit_final_target) * exit_distance,]
				_path_index = 0
				_factory_exit_phase = 2
	var factory_exit_final_started: bool = _factory_exit_phase == 3
	if factory_exit_final_started:
		_path_waypoints = [_factory_exit_final_target,]
		_path_index = 0
		_factory_exit_phase = 4
	if _pending_direct_path:
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		_pending_direct_path = false
		_path_waypoints = _pending_direct_waypoints.duplicate()
		_pending_direct_waypoints.clear()
		state_changed.emit(self)
		return
	if _pending_path_frames > 0.0:
		_pending_path_frames = maxf(_pending_path_frames - float(frame_count) * simulation_delta, 0.0)
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		return
	if _pending_path_frames == 0.0:
		_path_waypoints = _pending_path_waypoints.duplicate()
		_pending_path_waypoints.clear()
		_pending_path_frames = -1.0
		state_changed.emit(self)
	if not _is_navigation_order():
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		return
	if _path_waypoints.is_empty():
		if order_type == "build" or order_type == "repair" and order_target_id > 0:
			_advance_target_coasting(frame_count, path_grid, simulation_delta)
		else:
			_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		return
	var is_changed: bool
	for frame: int in frame_count:
		if _path_index >= _path_waypoints.size():
			if order_target_id <= 0 and order_type != "build":
				order_type = ""
			else:
				_path_waypoints.clear()
				_path_index = 0
			_is_exiting_factory = false
			_advance_idle_coasting(1, path_grid, simulation_delta)
			is_changed = true
			break
		var waypoint: Vector2 = _path_waypoints[_path_index]
		var distance: float = world_position.distance_to(waypoint)
		var collision_waypoint_radius: float = recent_collision_partner.collision_radius + 2.0 if recent_collision_partner != null else 0.0
		var collision_waypoint_blocked: bool = recent_collision_partner != null and not recent_collision_partner.is_dead and recent_collision_partner.world_position.distance_squared_to(waypoint) < collision_waypoint_radius * collision_waypoint_radius
		var is_last_waypoint: bool = _path_index == _path_waypoints.size() - 1
		var reach_distance: float = 4.0 if _factory_exit_phase == 2 else (7.0 if is_last_waypoint and order_type in ["move", "attackMove",] else (4.0 if is_last_waypoint else 16.0))
		if distance <= 1.0:
			world_position = waypoint
			_path_index += 1
			if _factory_exit_phase == 2 and _path_index >= _path_waypoints.size():
				_path_waypoints.clear()
				_path_index = 0
				_factory_exit_phase = 3
			elif _is_exiting_factory:
				_is_exiting_factory = false
				_factory_exit_phase = 0
			is_changed = true
			continue
		var on_water: bool = path_grid != null and path_grid.is_water_at(world_position)
		var current_speed: float = water_movement_speed if on_water and water_movement_speed > 0.0 else movement_speed
		var current_turn_speed: float = water_turn_speed if on_water and water_turn_speed > 0.0 else turn_speed
		var desired_angle: float = RwGameMath.direction_degrees(world_position, waypoint)
		var _angle_difference: float = wrapf(desired_angle - body_rotation_degrees, -180.0, 180.0)
		var turn_step: float
		if factory_exit_path_started or factory_exit_final_started or (is_last_waypoint and distance < reach_distance and _factory_exit_phase != 2):
			turn_step = 0.0
		elif turn_acceleration > 0.0:
			var braking_angle: float = absf(_turn_velocity) / turn_acceleration
			var requested_turn: float = signf(_angle_difference) * (turn_acceleration if absf(_angle_difference) < braking_angle else current_turn_speed)
			_turn_velocity = move_toward(_turn_velocity, requested_turn, turn_acceleration * simulation_delta)
			turn_step = _turn_velocity * simulation_delta
		else:
			turn_step = signf(_angle_difference) * current_turn_speed * simulation_delta
		if absf(turn_step) > absf(_angle_difference):
			_turn_velocity = 0.0
			turn_step = _angle_difference
		body_rotation_degrees = wrapf(body_rotation_degrees + turn_step, -180.0, 180.0)
		_add_weapon_rotation(turn_step)
		if turn_step != 0.0:
			is_changed = true
		var allowed_angle: float = 20.0
		if distance * distance > 361.0:
			allowed_angle = 46.0
		if distance * distance > 3600.0:
			allowed_angle = 89.0
		if current_turn_speed <= 1.4:
			allowed_angle = allowed_angle * 0.5 if distance * distance > 6400.0 else 17.0
		if current_turn_speed < 1.1:
			allowed_angle *= 0.7
		if movement_ignores_body:
			allowed_angle = 181.0
		var target_speed: float = 1.0 if absf(_angle_difference) <= allowed_angle and distance >= 3.0 else 0.0
		if factory_exit_path_started or factory_exit_final_started or (is_last_waypoint and distance < reach_distance):
			target_speed = 0.0
		if is_last_waypoint and target_speed > 0.0:
			if distance * distance < 324.0 and movement_deceleration < 0.13 and current_speed > 1.0:
				target_speed *= 0.5
			if distance * distance < 169.0 and movement_deceleration < 0.15 and current_speed > 0.9:
				target_speed *= 0.5
			if current_speed > 5.0:
				if distance * distance < 324.0:
					target_speed = minf(target_speed, 0.5)
				if distance * distance < 81.0:
					target_speed = minf(target_speed, 0.25)
		var next_position: Vector2
		if movement_sliding:
			_movement_velocity = target_speed
			var slide_angle: float = desired_angle if movement_ignores_body else body_rotation_degrees
			var desired_velocity: Vector2 = RwGameMath.direction_for_angle(slide_angle) * current_speed * target_speed
			var slide_acceleration: float = movement_acceleration if target_speed > 0.0 else movement_deceleration
			_advance_sliding_velocity(desired_velocity, current_speed, slide_acceleration, simulation_delta)
			next_position = world_position + _sliding_velocity * simulation_delta
		else:
			var speed_change: float = movement_acceleration if target_speed > _movement_velocity else movement_deceleration
			_movement_velocity = move_toward(_movement_velocity, target_speed, speed_change * simulation_delta)
			var movement_step: float = current_speed * _movement_velocity * simulation_delta
			next_position = world_position + RwGameMath.direction_for_angle(body_rotation_degrees) * movement_step
		if not _can_traverse(world_position, next_position, path_grid):
			if movement_sliding:
				next_position = _resolve_sliding_wall(world_position, next_position, path_grid)
			if next_position == world_position or not _can_traverse(world_position, next_position, path_grid):
				_movement_velocity = 0.0
				break
		world_position = next_position
		is_changed = true
		if distance < reach_distance or collision_waypoint_blocked:
			_path_index += 1
			if _factory_exit_phase == 2 and _path_index >= _path_waypoints.size():
				_path_waypoints.clear()
				_path_index = 0
				_factory_exit_phase = 3
			elif _path_index >= _path_waypoints.size() and order_target_id <= 0 and order_type != "build":
				order_type = ""
			if _is_exiting_factory and _factory_exit_phase != 3:
				_is_exiting_factory = false
				_factory_exit_phase = 0
	if is_changed:
		state_changed.emit(self)


func _advance_idle_coasting(frame_count: int, path_grid: RwPathGrid, simulation_delta: float) -> void:
	var is_changed: bool
	for frame: int in frame_count:
		var next_position: Vector2
		if movement_sliding:
			_movement_velocity = 0.0
			var current_speed: float = movement_speed
			if path_grid != null and path_grid.is_water_at(world_position) and water_movement_speed > 0.0:
				current_speed = water_movement_speed
			_advance_sliding_velocity(Vector2.ZERO, current_speed, movement_deceleration, simulation_delta)
			if _sliding_velocity.is_zero_approx():
				break
			next_position = world_position + _sliding_velocity * simulation_delta
		else:
			_movement_velocity = move_toward(_movement_velocity, 0.0, movement_deceleration * simulation_delta)
			if _movement_velocity <= 0.0:
				break
			var movement_step: float = movement_speed * _movement_velocity * simulation_delta
			next_position = world_position + RwGameMath.direction_for_angle(body_rotation_degrees) * movement_step
		if not _can_traverse(world_position, next_position, path_grid):
			if movement_sliding:
				next_position = _resolve_sliding_wall(world_position, next_position, path_grid)
			if next_position == world_position or not _can_traverse(world_position, next_position, path_grid):
				_movement_velocity = 0.0
				_sliding_velocity = Vector2.ZERO
				break
		world_position = next_position
		is_changed = true
	if is_changed:
		state_changed.emit(self)


func _advance_target_coasting(frame_count: int, path_grid: RwPathGrid, simulation_delta: float) -> void:
	var is_changed: bool
	for frame: int in frame_count:
		var target_angle: float = RwGameMath.direction_degrees(world_position, order_target)
		var remaining_angle: float = wrapf(target_angle - body_rotation_degrees, -180.0, 180.0)
		var current_turn_speed: float = turn_speed
		var current_speed: float = movement_speed
		if path_grid != null and path_grid.is_water_at(world_position):
			current_turn_speed = water_turn_speed if water_turn_speed > 0.0 else turn_speed
			current_speed = water_movement_speed if water_movement_speed > 0.0 else movement_speed
		var braking_angle: float = absf(_turn_velocity) / turn_acceleration if turn_acceleration > 0.0 else 0.0
		var requested_turn: float = signf(remaining_angle) * (turn_acceleration if absf(remaining_angle) < braking_angle else current_turn_speed)
		_turn_velocity = move_toward(_turn_velocity, requested_turn, turn_acceleration * simulation_delta)
		var turn_step: float = _turn_velocity * simulation_delta
		if absf(turn_step) > absf(remaining_angle):
			_turn_velocity = 0.0
			turn_step = remaining_angle
		body_rotation_degrees = wrapf(body_rotation_degrees + turn_step, -180.0, 180.0)
		_add_weapon_rotation(turn_step)
		_movement_velocity = move_toward(_movement_velocity, 0.0, movement_deceleration * simulation_delta)
		var movement_step: float = current_speed * _movement_velocity * simulation_delta
		var next_position: Vector2 = world_position + Vector2.RIGHT.rotated(deg_to_rad(body_rotation_degrees)) * movement_step
		if _can_traverse(world_position, next_position, path_grid):
			world_position = next_position
			is_changed = is_changed or movement_step > 0.0 or turn_step != 0.0
	if is_changed:
		state_changed.emit(self)


func _advance_sliding_velocity(desired_velocity: Vector2, current_speed: float, acceleration: float, simulation_delta: float) -> void:
	var distance_squared: float = _sliding_velocity.distance_squared_to(desired_velocity)
	if distance_squared > current_speed * current_speed:
		_sliding_velocity -= _sliding_velocity * 0.05 * simulation_delta
	var step: float = acceleration * 1.41 * simulation_delta
	if distance_squared < step * step:
		_sliding_velocity = desired_velocity
		return
	var direction: Vector2 = RwGameMath.path_direction(_sliding_velocity, desired_velocity)
	_sliding_velocity += direction * step


func _is_navigation_order() -> bool:
	return NAVIGATION_ORDER_TYPES.has(order_type)


func displace_from_collision(displacement: Vector2, _path_grid: RwPathGrid) -> void:
	if is_dead or displacement == Vector2.ZERO:
		return
	collision_push_offset += displacement


func note_collision(other: RwUnitState) -> void:
	collision_partner = other
	collision_recent_frames = 2



## 在下一帧移动结束后应用累计碰撞推力
func apply_collision_push(path_grid: RwPathGrid) -> void:
	if is_dead or collision_push_offset == Vector2.ZERO:
		return
	var displacement: Vector2 = Vector2(
		clampf(collision_push_offset.x, -9.0, 9.0),
		clampf(collision_push_offset.y, -9.0, 9.0),
	)
	collision_push_offset = Vector2.ZERO
	var next_position: Vector2 = world_position + displacement
	if not _can_traverse(world_position, next_position, path_grid):
		return
	world_position = next_position
	state_changed.emit(self)


func _can_traverse(start_position: Vector2, end_position: Vector2, path_grid: RwPathGrid) -> bool:
	if path_grid == null or path_grid.has_clear_line(start_position, end_position, movement_type) or path_grid.has_source_direct_line(start_position, end_position, movement_type):
		return true
	var start_cell: Vector2i = path_grid.world_to_cell(start_position)
	var end_cell: Vector2i = path_grid.world_to_cell(end_position)
	if start_cell == end_cell and not path_grid.is_passable(start_cell, movement_type):
		if not _path_waypoints.is_empty():
			var waypoint: Vector2 = _path_waypoints[mini(_path_index, _path_waypoints.size() - 1)]
			if waypoint.is_equal_approx(path_grid.cell_to_world(start_cell)):
				return true
	if not _is_exiting_factory:
		return false
	if not _factory_exit_footprint.has_point(start_cell):
		return false
	return _factory_exit_footprint.has_point(end_cell) or path_grid.is_passable(end_cell, movement_type)


func _resolve_sliding_wall(start_position: Vector2, end_position: Vector2, path_grid: RwPathGrid) -> Vector2:
	if path_grid == null:
		return end_position
	var blocked_cell: Vector2i = path_grid.world_to_cell(end_position)
	var destination_blocked: bool = not path_grid.is_passable(blocked_cell, movement_type)
	var horizontal: Vector2 = Vector2(end_position.x, start_position.y)
	if _can_traverse(start_position, horizontal, path_grid):
		if destination_blocked and end_position.y < start_position.y:
			horizontal.y = minf(start_position.y, float(blocked_cell.y + 1) * float(path_grid.tile_size.y) + 0.2)
		elif destination_blocked and end_position.y > start_position.y:
			horizontal.y = maxf(start_position.y, float(blocked_cell.y) * float(path_grid.tile_size.y) - 0.2)
		return horizontal
	var vertical: Vector2 = Vector2(start_position.x, end_position.y)
	if _can_traverse(start_position, vertical, path_grid):
		if destination_blocked and end_position.x < start_position.x:
			vertical.x = minf(start_position.x, float(blocked_cell.x + 1) * float(path_grid.tile_size.x) + 0.2)
		elif destination_blocked and end_position.x > start_position.x:
			vertical.x = maxf(start_position.x, float(blocked_cell.x) * float(path_grid.tile_size.x) - 0.2)
		return vertical
	return start_position


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
