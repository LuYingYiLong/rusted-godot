extends Resource
class_name RwUnitState
## 保存单位在同步帧中可变化的状态

signal state_changed(state: RwUnitState)

const MAX_PATH_POINTS: int = 120
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
## 原版对象的同步随机计数器
@export var random_counter: int
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
@export var is_building: bool
@export var push_mass: float = 3000.0
@export var soft_collision_on_all: int
@export var sight_range: int
@export var animation_frame: int
## 附加视觉层所用的同步帧计数
@export var visual_frame: int
@export var tech_level: int = 1
## 原版激光防御的当前充能量
@export var laser_defense_charge: float = 1.0
## 原版激光防御耗尽充能后需充满才会恢复拦截
@export var laser_defense_depleted: bool
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
## 进入目标操作范围后保留路径并逐帧减速
var navigation_stop_requested: bool
## 本帧目标操作已执行转向，移动阶段只减速，不重复转向
var operation_turn_performed_this_step: bool
## 建造尝试冷却期间保持停止导航并暂停主动转向
var operation_retry_waited_this_step: bool
## 操作阶段替换了当前命令，新目标从下一同步步开始执行
var target_order_changed_this_step: bool
## 本步移动决策使用了路径，对应原版 cK，不以残留路径点判断是否移动
var navigation_path_active: bool
## 当前路径点的主动移动累计时间，对应原版 W
var waypoint_time: float
## 持续地形阻挡的累计时间，对应原版 b，连续三个无阻挡步后归零
var terrain_blocked_time: float
## 地形阻挡后连续无阻挡的移动步数，对应原版 a
var terrain_clear_steps: int
## 旧路径因卡墙或停滞失效，下一同步步需要重新申请路径
var navigation_repath_requested: bool
## 原版普通导航路径申请冷却，对应 s，路径结束后等待归零再重新申请
var navigation_repath_timer: float
## 在移动命令目标四十一像素内累计停留的时间，对应原版 Y
var navigation_arrival_time: float
## 当前已有可攻击目标，攻击移动到达终点后仍保留命令
var navigation_attack_target_active: bool
## 原版单位自动索敌缓存的目标编号
var navigation_attack_target_id: int = -1
## 原版自动索敌冷却，对应 S
var navigation_attack_search_timer: float
## 当前追击路径使用的临时目标坐标
var navigation_attack_target_position: Vector2
## 是否正在使用自动索敌目标作为临时导航终点
var navigation_attack_override_active: bool
## 当前路径不完整，走完后保留最终命令并继续申请，对应原版 u
var navigation_path_truncated: bool
## 当前建造武器的预热量，切换命令后按原版规则冷却
var operation_charge: float
## 建造武器达到可工作状态所需的预热量
var construction_warmup_limit: float
## 建造武器每同步步的预热冷却速度
var construction_warmup_decay: float
## 上一同步步结束时建造束是否处于活动状态，对应原版 aN
var operation_visual_active: bool
## 本同步步目标操作已满足距离与角度条件
var operation_active_this_step: bool
## 本步刚完成施工，供仍持有该维修目标的单位判定工作距离
var construction_completed_this_step: bool
## 最近碰撞对象使用弱引用，避免两个 Resource 相互持有后无法释放
var collision_partner: RwUnitState:
	get:
		return _collision_partner_ref.get_ref() as RwUnitState if _collision_partner_ref != null else null
	set(value):
		_collision_partner_ref = weakref(value) if value != null else null
var collision_recent_frames: int
## 本帧发生移动、碰撞位移或空间索引初始化，允许处理缓存碰撞对
var collision_step_active: bool = true
## 新单位需要在首次同步步更新空间索引
var collision_index_dirty: bool = true
## 原版出厂后暂时忽略地形阻挡并直接追踪当前目标的剩余帧数
var factory_clearance_frames: float

## 编队领队的网络编号，-1 表示没有领队
var formation_leader_id: int = -1
## 是否为当前编队领队及编队规模
var formation_is_leader: bool
var formation_size: int
## 相对领队的位置偏移与整组方向角
var formation_offset: Vector2
var formation_angle: float
## 领队分配或路径停滞刷新时的模拟毫秒计时
var formation_assigned_time: int
## 当前跟随领队的编队毫秒年龄，供原版探针对照
var formation_leader_age: int
## 脱队恢复路径的重新申请倒计时及上次目标
var formation_path_timer: float
var formation_path_target: Vector2
## 脱队恢复、落后及等待领队完成的累计同步时间
var formation_recovery: float
var formation_lag: float
var formation_wait: float
## 本步编队使用虚拟导航目标，不加入单位自己的路径校验
var formation_navigation_active: bool
var formation_navigation_target: Vector2
var formation_slow_near_target: bool
## 当前路径最初生成的节点数，对应原版 v
var original_path_count: int

var _path_waypoints: Array[Vector2]
var _path_index: int
var _pending_path_waypoints: Array[Vector2]
var _pending_path_frames: float = -1.0
var _pending_path_keeps_current: bool
var _tree_type: int = 1
var _pending_direct_path: bool
var _pending_direct_waypoints: Array[Vector2]
var _movement_velocity: float
var _sliding_velocity: Vector2
var _turn_velocity: float
var _point_arrival_prepared: bool
var _collision_partner_ref: WeakRef
var _factory_exit_footprint: Rect2i
var _is_exiting_factory: bool
var _factory_exit_phase: int
var _factory_exit_final_target: Vector2
var _terrain_checked_this_step: bool
var _terrain_blocked_this_step: bool
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
	random_counter = int(spawn.get("random_counter", 0))
	source_id = str(spawn.get("source_id", ""))
	unit_name = str(spawn.get("unit_name", ""))
	if definition != null:
		construction_warmup_limit = definition.construction_warmup
		construction_warmup_decay = definition.construction_warmup_decay
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
	if unit_name == "tree":
		var variant: PackedStringArray = str(spawn.get("variant", "1")).split(".")
		_tree_type = variant[0].to_int() if not variant.is_empty() else 1
		body_rotation_degrees = RwGameMath.float32(RwGameMath.float32(world_position.y * 5.0) + RwGameMath.float32(world_position.x * 3.0))
		while body_rotation_degrees > 180.0 or body_rotation_degrees < -180.0:
			if body_rotation_degrees > 180.0:
				body_rotation_degrees = RwGameMath.float32(body_rotation_degrees - 360.0)
			if body_rotation_degrees < -180.0:
				body_rotation_degrees = RwGameMath.float32(body_rotation_degrees + 360.0)
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
	is_building = definition != null and definition.selection_shape == RwUnitDefinition.SelectionShape.RECTANGLE
	push_mass = definition.push_mass if definition != null else 3000.0
	sight_range = definition.sight_range if definition != null else 15
	tech_level = maxi(int(spawn.get("tech_level", definition.tech_level if definition != null else 1)), 1)
	laser_defense_charge = clampf(float(spawn.get("laser_defense_charge", 1.0)), 0.0, 1.0)
	laser_defense_depleted = bool(spawn.get("laser_defense_depleted", false))
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
	if snapshot.has("random_counter"):
		random_counter = int(snapshot["random_counter"])
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
	if snapshot.has("laser_defense_charge"):
		laser_defense_charge = clampf(float(snapshot["laser_defense_charge"]), 0.0, 1.0)
	if snapshot.has("laser_defense_depleted"):
		laser_defense_depleted = bool(snapshot["laser_defense_depleted"])
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


## 返回单位当前的世界速度向量
func get_world_velocity() -> Vector2:
	if movement_sliding:
		return _sliding_velocity
	return RwGameMath.direction_for_angle(body_rotation_degrees) * _movement_velocity


## 按原版树木接触规则扣血，倒下后不再阻挡移动单位
func apply_tree_collision(unit_mass: float, contact_position: Vector2, simulation_delta: float) -> bool:
	if is_dead:
		return true
	var damage: float = RwGameMath.float32(unit_mass / 3000.0)
	damage = RwGameMath.float32(damage * max_health)
	damage = RwGameMath.float32(damage * RwGameMath.float32(0.06))
	damage = RwGameMath.float32(damage * simulation_delta)
	health = RwGameMath.float32(health - damage)
	if health <= 0.0:
		body_rotation_degrees = RwGameMath.float32(RwGameMath.direction_degrees(world_position, contact_position) + 180.0)
		fall_tree()
	state_changed.emit(self)
	return is_dead


## 建筑清场或接触伤害放倒树木，清场保持生命值并使用原版残骸位移
func fall_tree() -> void:
	if unit_name != "tree" or is_dead:
		return
	is_dead = true
	animation_frame = 2
	if _tree_type in [1, 2,]:
		world_position = RwGameMath.movement_position(world_position, body_rotation_degrees, 12.0, 1.0, 1.0)
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


## 应用同步命令并清除旧路径，保留原版停止或切换命令后的减速惯性
func apply_order(command_type: String, target: Vector2, target_id: int = -1, action_id: String = "") -> void:
	formation_navigation_active = false
	waypoint_time = 0.0
	navigation_repath_requested = false
	navigation_repath_timer = 0.0
	navigation_arrival_time = 0.0
	navigation_path_truncated = false
	original_path_count = 0
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = action_id
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_path_keeps_current = false
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	_is_exiting_factory = false
	_factory_exit_phase = 0
	state_changed.emit(self)


## 在目标操作阶段先转向再判断角度，返回本次转向前的角差
func turn_toward_operation_target(target: Vector2, simulation_delta: float) -> float:
	operation_turn_performed_this_step = true
	var target_angle: float = RwGameMath.direction_degrees(world_position, target)
	var angle_delta: float = RwGameMath.signed_angle_delta(body_rotation_degrees, target_angle)
	if absf(angle_delta) < 0.01:
		return 0.0
	var turn_state: Vector3 = RwGameMath.turn_toward(body_rotation_degrees, target_angle, _turn_velocity, turn_speed, turn_acceleration, simulation_delta)
	body_rotation_degrees = turn_state.x
	_turn_velocity = turn_state.y
	_add_weapon_rotation(turn_state.z)
	if turn_state.z != 0.0:
		state_changed.emit(self)
	return angle_delta


## 建造目标生成后转为维修目标，保留原版减速和转向惯性
func transition_to_target_order(command_type: String, target: Vector2, target_id: int) -> void:
	waypoint_time = 0.0
	navigation_repath_requested = false
	navigation_repath_timer = 0.0
	navigation_arrival_time = 0.0
	navigation_path_truncated = false
	original_path_count = 0
	target_order_changed_this_step = true
	order_type = command_type
	order_target = target
	order_target_id = target_id
	order_action_id = ""
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_path_keeps_current = false
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	state_changed.emit(self)


## 目标操作通过距离和角度判定后推进预热，返回本步是否可以工作
func advance_operation_charge(simulation_delta: float) -> bool:
	operation_active_this_step = true
	if operation_charge < construction_warmup_limit:
		operation_charge = RwGameMath.float32(operation_charge + simulation_delta)
		return false
	operation_charge = construction_warmup_limit
	return true


## 帧末按上一帧建造束状态冷却预热，再提交本帧活动状态
func finish_operation_step(simulation_delta: float) -> void:
	var current_active: bool = operation_active_this_step and order_type in ["repair", "reclaim",] and order_target_id > 0
	if not operation_visual_active or not current_active:
		operation_charge = RwGameMath.advance_speed(operation_charge, 0.0, construction_warmup_decay, simulation_delta)
	operation_visual_active = current_active
	operation_active_this_step = false


func apply_move_order(
	target: Vector2,
	waypoints: Array[Vector2],
	command_type: String = "move",
	target_id: int = -1,
	action_id: String = "",
	path_delay_frames: int = 0,
	command_target: Vector2 = Vector2(INF, INF)
) -> void:
	var final_target: Vector2 = target if command_target == Vector2(INF, INF) else command_target
	if order_type != command_type or order_target != final_target or order_target_id != target_id:
		navigation_arrival_time = 0.0
	waypoint_time = 0.0
	navigation_repath_requested = false
	navigation_repath_timer = 0.0
	navigation_path_truncated = false
	var clearance_active: bool = factory_clearance_frames > 0.0
	order_type = command_type
	order_target = final_target
	order_target_id = target_id
	order_action_id = action_id
	_accept_grid_path(waypoints)
	if clearance_active:
		_path_waypoints = [target,]
		_factory_exit_final_target = target
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_path_keeps_current = false
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	if path_delay_frames > 0 and not clearance_active and not _path_waypoints.is_empty():
		_pending_path_waypoints = _path_waypoints.duplicate()
		_path_waypoints.clear()
		_pending_path_frames = float(path_delay_frames + 1)
	_is_exiting_factory = clearance_active
	_factory_exit_phase = 1 if clearance_active else 0
	state_changed.emit(self)


## 申请原版建筑占地脱离路径，本步先减速，下一步使用刚生成的单点路径
func apply_source_escape_path(
	target: Vector2,
	escape_target: Vector3,
	command_type: String,
	target_id: int = -1,
	action_id: String = "",
	command_target: Vector2 = Vector2(INF, INF)
) -> void:
	var points: Array[Vector2] = [Vector2(escape_target.x, escape_target.y),]
	apply_move_order(target, points, command_type, target_id, action_id, 0, command_target)
	navigation_path_truncated = escape_target.z != 0.0
	navigation_repath_timer = 10.0 if navigation_path_truncated else 500.0
	schedule_source_direct_path(points, navigation_path_truncated)


## 设置新单位离厂目标和原版暂缓重新寻路的帧数
func apply_factory_exit(target: Vector2, factory_cell: Vector2i, footprint_min: Vector2i, footprint_max: Vector2i, path_delay: float = 0.0) -> void:
	apply_move_order(target, [target,])
	_factory_exit_footprint = Rect2i(factory_cell + footprint_min, footprint_max - footprint_min + Vector2i.ONE)
	_is_exiting_factory = true
	_factory_exit_final_target = target
	factory_clearance_frames = path_delay
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
func schedule_source_direct_path(waypoints: Array[Vector2], truncated: bool = false) -> void:
	_path_waypoints.clear()
	_path_index = 0
	_pending_direct_path = true
	_pending_direct_waypoints = waypoints.duplicate()
	navigation_path_truncated = truncated


func is_exiting_factory() -> bool:
	return _is_exiting_factory


## 返回单位是否正在主动移动，供碰撞候选计算确定主体
func has_active_movement_for_collision() -> bool:
	return _movement_velocity != 0.0 or not _sliding_velocity.is_zero_approx()


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
	if _factory_exit_phase == 1:
		return points
	for index: int in range(_path_index, _path_waypoints.size()):
		points.append(_path_waypoints[index])
	return points


## 编队跟随时清空独立路径而保留同步命令和移动惯性
func clear_formation_path() -> void:
	_path_waypoints.clear()
	_path_index = 0
	_pending_path_waypoints.clear()
	_pending_path_frames = -1.0
	_pending_path_keeps_current = false
	_pending_direct_path = false
	_pending_direct_waypoints.clear()
	waypoint_time = 0.0
	navigation_repath_requested = false
	navigation_repath_timer = 0.0
	navigation_path_truncated = false
	original_path_count = 0


## 脱队时申请领队附近的恢复路径，保持原同步命令与编队关系
func schedule_formation_recovery_path(points: Array[Vector2], delay_frames: int, direct: bool, truncated: bool = false) -> void:
	if direct:
		_path_waypoints.clear()
		_path_index = 0
		schedule_source_direct_path(points, truncated)
	elif delay_frames > 0:
		_pending_path_waypoints = points.duplicate()
		_pending_path_frames = float(delay_frames + 1)
		_pending_path_keeps_current = true
	else:
		_accept_grid_path(points)


## 编队停止时提交方向修正并保持炮口相对旋转
func apply_formation_turn(turn: Vector3) -> void:
	body_rotation_degrees = turn.x
	_turn_velocity = turn.y
	_add_weapon_rotation(turn.z)


## 在路径申请前按原版累计到达等待时间，并逐步放宽目标完成半径
func advance_point_order_arrival(simulation_delta: float) -> void:
	_point_arrival_prepared = true
	if is_dead or order_type not in ["move", "attackMove",]:
		return
	var distance_squared: float = RwGameMath.distance_squared(world_position, order_target)
	if distance_squared < 1681.0:
		navigation_arrival_time = RwGameMath.float32(navigation_arrival_time + simulation_delta)
	var radius: float = 7.0
	if navigation_arrival_time > 340.0:
		radius = 36.0
	elif navigation_arrival_time > 240.0:
		radius = 16.0
	if distance_squared < radius * radius and (order_type != "attackMove" or not navigation_attack_target_active):
		apply_order("", world_position)


func advance_movement(frame_count: int, path_grid: RwPathGrid, simulation_delta: float = 1.0) -> void:
	navigation_path_active = false
	_terrain_checked_this_step = false
	_terrain_blocked_this_step = false
	if frame_count <= 0 or is_dead or movement_speed <= 0.0:
		return
	if not _point_arrival_prepared:
		advance_point_order_arrival(float(frame_count) * simulation_delta)
	_point_arrival_prepared = false
	var recent_collision_partner: RwUnitState = collision_partner if collision_recent_frames > 0 else null
	collision_recent_frames = maxi(collision_recent_frames - frame_count, 0)
	var factory_exit_path_started: bool
	if factory_clearance_frames > 0.0:
		factory_clearance_frames = RwGameMath.advance_speed(factory_clearance_frames, 0.0, 1.0, float(frame_count) * simulation_delta)
		if _factory_exit_phase == 1 and factory_clearance_frames == 0.0:
			factory_exit_path_started = true
			_factory_exit_phase = 4
			if path_grid != null and not path_grid.is_passable(path_grid.world_to_cell(world_position), movement_type):
				var exit_distance: float = minf(world_position.distance_to(_factory_exit_final_target), 60.0)
				_path_waypoints = [world_position + RwGameMath.path_direction(world_position, _factory_exit_final_target) * exit_distance,]
				_path_index = 0
				_factory_exit_phase = 2
	# 原版在本步申请出口路径后仍使用申请前的空路径，下一步才读取新路径点
	if factory_exit_path_started:
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		state_changed.emit(self)
		return
	if _pending_direct_path:
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		_pending_direct_path = false
		_path_waypoints = _pending_direct_waypoints.duplicate()
		original_path_count = _path_waypoints.size()
		_pending_direct_waypoints.clear()
		state_changed.emit(self)
		return
	if _pending_path_frames > 0.0:
		_pending_path_frames = maxf(_pending_path_frames - float(frame_count) * simulation_delta, 0.0)
		if not _pending_path_keeps_current:
			_advance_idle_coasting(frame_count, path_grid, simulation_delta)
			return
	if _pending_path_frames == 0.0:
		_accept_grid_path(_pending_path_waypoints)
		_pending_path_waypoints.clear()
		_pending_path_frames = -1.0
		_pending_path_keeps_current = false
		state_changed.emit(self)
	if not _is_navigation_order():
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		return
	if _path_waypoints.is_empty() and not formation_navigation_active:
		# Without a path target, preserve inertia; the operation stage handles turning in range
		_advance_idle_coasting(frame_count, path_grid, simulation_delta)
		return
	var is_changed: bool
	for frame: int in frame_count:
		if _path_index >= _path_waypoints.size() and not formation_navigation_active:
			if order_type == "move" and not navigation_path_truncated:
				order_type = ""
				navigation_arrival_time = 0.0
			else:
				_path_waypoints.clear()
				_path_index = 0
			_is_exiting_factory = false
			_advance_idle_coasting(1, path_grid, simulation_delta)
			is_changed = true
			break
		var waypoint: Vector2 = formation_navigation_target if formation_navigation_active else _path_waypoints[_path_index]
		navigation_path_active = not navigation_stop_requested
		var distance: float = world_position.distance_to(waypoint)
		var collision_waypoint_radius: float = recent_collision_partner.collision_radius + 2.0 if recent_collision_partner != null else 0.0
		var collision_waypoint_blocked: bool = recent_collision_partner != null and not recent_collision_partner.is_dead and recent_collision_partner.world_position.distance_squared_to(waypoint) < collision_waypoint_radius * collision_waypoint_radius
		var is_last_waypoint: bool = not formation_navigation_active and _path_index == _path_waypoints.size() - 1
		var reach_distance: float = 4.0 if is_last_waypoint else 16.0
		if not formation_navigation_active and not navigation_stop_requested and distance <= 1.0:
			world_position = waypoint
			_path_index += 1
			waypoint_time = 0.0
			if _factory_exit_phase == 2 and _path_index >= _path_waypoints.size():
				_path_waypoints.clear()
				_path_index = 0
				_factory_exit_phase = 0
				_is_exiting_factory = false
				navigation_repath_requested = true
			elif _is_exiting_factory:
				_is_exiting_factory = false
				_factory_exit_phase = 0
			is_changed = true
			continue
		var on_water: bool = path_grid != null and path_grid.is_water_at(world_position)
		var current_speed: float = water_movement_speed if on_water and water_movement_speed > 0.0 else movement_speed
		var current_turn_speed: float = water_turn_speed if on_water and water_turn_speed > 0.0 else turn_speed
		var desired_angle: float = RwGameMath.direction_degrees(world_position, order_target if navigation_stop_requested else waypoint)
		var _angle_difference: float = RwGameMath.signed_angle_delta(body_rotation_degrees, desired_angle)
		var turn_step: float
		if operation_turn_performed_this_step or operation_retry_waited_this_step or absf(_angle_difference) < 0.01 or factory_exit_path_started:
			turn_step = 0.0
		else:
			var turn_state: Vector3 = RwGameMath.turn_toward(body_rotation_degrees, desired_angle, _turn_velocity, current_turn_speed, turn_acceleration, simulation_delta)
			body_rotation_degrees = turn_state.x
			_turn_velocity = turn_state.y
			turn_step = turn_state.z
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
		if navigation_stop_requested:
			target_speed = 0.0
		if factory_exit_path_started or (is_last_waypoint and distance < reach_distance):
			target_speed = 0.0
		if formation_navigation_active and target_speed > 0.0:
			if formation_slow_near_target:
				if distance * distance < 2500.0:
					target_speed = RwGameMath.float32(target_speed - RwGameMath.float32(0.15))
				if distance * distance < 900.0:
					target_speed = RwGameMath.float32(target_speed - RwGameMath.float32(0.15))
				if distance * distance < 225.0:
					target_speed = RwGameMath.float32(target_speed - RwGameMath.float32(0.3))
			else:
				if distance * distance > 400.0:
					target_speed = RwGameMath.float32(target_speed + RwGameMath.float32(0.2))
				if distance * distance < 49.0:
					target_speed = RwGameMath.float32(target_speed - RwGameMath.float32(0.15))
				if distance * distance < 9.0:
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
		if target_speed > 0.0:
			_advance_waypoint_time(distance * distance, simulation_delta)
		var next_position: Vector2
		var sliding_was_active: bool = _sliding_velocity != Vector2.ZERO
		if movement_sliding:
			_movement_velocity = target_speed
			var slide_angle: float = desired_angle if movement_ignores_body else body_rotation_degrees
			var desired_velocity: Vector2 = RwGameMath.direction_for_angle(slide_angle) * current_speed * target_speed
			var slide_acceleration: float = movement_acceleration if target_speed > 0.0 else movement_deceleration
			_advance_sliding_velocity(desired_velocity, current_speed, slide_acceleration, simulation_delta)
			next_position = world_position + _sliding_velocity * simulation_delta
		else:
			var speed_change: float = movement_acceleration if target_speed > _movement_velocity else movement_deceleration
			_movement_velocity = RwGameMath.advance_speed(_movement_velocity, target_speed, speed_change, simulation_delta)
			next_position = RwGameMath.movement_position(world_position, body_rotation_degrees, current_speed, _movement_velocity, simulation_delta)
		# Stock updates terrain counters only when movement, sliding inertia or collision push participates
		if _movement_velocity != 0.0 or sliding_was_active or _sliding_velocity != Vector2.ZERO:
			next_position = _resolve_terrain_movement(world_position, next_position, path_grid)
		world_position = next_position
		is_changed = true
		if not formation_navigation_active and not navigation_repath_requested and not navigation_stop_requested and (distance < reach_distance or collision_waypoint_blocked):
			_path_index += 1
			waypoint_time = 0.0
			if _factory_exit_phase == 2 and _path_index >= _path_waypoints.size():
				_path_waypoints.clear()
				_path_index = 0
				_factory_exit_phase = 0
				_is_exiting_factory = false
				# Recheck terrain and unit costs after the temporary factory exit path ends
				navigation_repath_requested = true
			elif _path_index >= _path_waypoints.size() and order_type == "move" and not navigation_path_truncated:
				order_type = ""
				navigation_arrival_time = 0.0
			if _is_exiting_factory:
				_is_exiting_factory = false
				_factory_exit_phase = 0
	if is_changed:
		state_changed.emit(self)


## 在运动和碰撞推力完成后提交本步地形阻挡计时
func finish_movement_step(simulation_delta: float) -> void:
	if not _terrain_checked_this_step:
		return
	if _terrain_blocked_this_step:
		terrain_blocked_time = RwGameMath.float32(terrain_blocked_time + simulation_delta)
		terrain_clear_steps = 0
	elif terrain_blocked_time != 0.0 and simulation_delta > 0.0:
		terrain_clear_steps += 1
		if terrain_clear_steps >= 3:
			terrain_blocked_time = 0.0


## 按原版异步路径容量接收节点，满一百二十点时保留部分路径标志
func _accept_grid_path(points: Array[Vector2]) -> void:
	_path_waypoints = points.slice(0, MAX_PATH_POINTS)
	_path_index = 0
	original_path_count = _path_waypoints.size()
	navigation_path_truncated = points.size() >= MAX_PATH_POINTS


func _advance_waypoint_time(distance_squared: float, simulation_delta: float) -> void:
	waypoint_time = RwGameMath.float32(waypoint_time + simulation_delta)
	var remaining_points: int = _path_waypoints.size() - _path_index
	if waypoint_time > 200.0 and distance_squared < 3600.0 and remaining_points >= 2:
		_path_index += 1
		remaining_points -= 1
	if (waypoint_time > 600.0 and remaining_points >= 2) or (waypoint_time > 80.0 and terrain_blocked_time > 30.0):
		_path_waypoints.clear()
		_path_index = 0
		_pending_path_waypoints.clear()
		_pending_path_frames = -1.0
		_pending_path_keeps_current = false
		_factory_exit_phase = 0
		_is_exiting_factory = false
		waypoint_time = 0.0
		navigation_repath_requested = true
		navigation_repath_timer = 0.0
		navigation_path_truncated = false
		return
	if waypoint_time > 40.0 and remaining_points >= 2:
		var next_distance_squared: float = world_position.distance_squared_to(_path_waypoints[_path_index + 1])
		if next_distance_squared < distance_squared:
			_path_index += 1


func _advance_idle_coasting(frame_count: int, path_grid: RwPathGrid, simulation_delta: float) -> void:
	var is_changed: bool
	for frame: int in frame_count:
		var next_position: Vector2
		if movement_sliding:
			_movement_velocity = 0.0
			if _sliding_velocity == Vector2.ZERO:
				break
			var current_speed: float = movement_speed
			if path_grid != null and path_grid.is_water_at(world_position) and water_movement_speed > 0.0:
				current_speed = water_movement_speed
			_advance_sliding_velocity(Vector2.ZERO, current_speed, movement_deceleration, simulation_delta)
			next_position = world_position + _sliding_velocity * simulation_delta
		else:
			_movement_velocity = RwGameMath.advance_speed(_movement_velocity, 0.0, movement_deceleration, simulation_delta)
			if _movement_velocity <= 0.0:
				break
			next_position = RwGameMath.movement_position(world_position, body_rotation_degrees, movement_speed, _movement_velocity, simulation_delta)
		next_position = _resolve_terrain_movement(world_position, next_position, path_grid)
		world_position = next_position
		is_changed = true
	if is_changed:
		state_changed.emit(self)


func _advance_sliding_velocity(desired_velocity: Vector2, current_speed: float, acceleration: float, simulation_delta: float) -> void:
	_sliding_velocity = RwGameMath.sliding_velocity(_sliding_velocity, desired_velocity, current_speed, acceleration, simulation_delta)


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
	collision_step_active = true
	var displacement: Vector2 = Vector2(
		clampf(collision_push_offset.x, -9.0, 9.0),
		clampf(collision_push_offset.y, -9.0, 9.0),
	)
	collision_push_offset = Vector2.ZERO
	var next_position: Vector2 = world_position + displacement
	world_position = _resolve_terrain_movement(world_position, next_position, path_grid)
	state_changed.emit(self)


func _can_traverse(start_position: Vector2, end_position: Vector2, path_grid: RwPathGrid) -> bool:
	if path_grid == null or factory_clearance_frames > 0.0:
		return true
	var start_cell: Vector2i = path_grid.world_to_cell(start_position)
	var end_cell: Vector2i = path_grid.world_to_cell(end_position)
	if start_cell == end_cell or path_grid.is_passable(end_cell, movement_type):
		return true
	# 原版只在跨格时检查碰撞，起点被新建筑覆盖时允许沿可通行地形脱离占地
	return not path_grid.is_passable(start_cell, movement_type) and path_grid.terrain_cost_at(end_cell, movement_type) >= 0


## 按原版跨格碰撞保留速度，并依次检查斜向阻挡与目标格边缘
func _resolve_terrain_movement(start_position: Vector2, end_position: Vector2, path_grid: RwPathGrid) -> Vector2:
	_terrain_checked_this_step = true
	if _can_traverse(start_position, end_position, path_grid):
		return end_position
	_terrain_blocked_this_step = true
	var start_cell: Vector2i = path_grid.world_to_cell(start_position)
	var end_cell: Vector2i = path_grid.world_to_cell(end_position)
	if start_cell.x != end_cell.x and start_cell.y != end_cell.y:
		var vertical_cell: Vector2i = Vector2i(start_cell.x, end_cell.y)
		var horizontal_cell: Vector2i = Vector2i(end_cell.x, start_cell.y)
		var vertical_blocked: bool = not path_grid.is_passable(vertical_cell, movement_type)
		var horizontal_blocked: bool = not path_grid.is_passable(horizontal_cell, movement_type)
		if vertical_blocked and horizontal_blocked:
			return start_position
		if vertical_blocked:
			var vertical_slide: Vector3 = _terrain_slide_position(start_position, end_position, vertical_cell, path_grid)
			if vertical_slide.z != 0.0:
				return Vector2(vertical_slide.x, vertical_slide.y)
		if horizontal_blocked:
			var horizontal_slide: Vector3 = _terrain_slide_position(start_position, end_position, horizontal_cell, path_grid)
			if horizontal_slide.z != 0.0:
				return Vector2(horizontal_slide.x, horizontal_slide.y)
	var slide: Vector3 = _terrain_slide_position(start_position, end_position, end_cell, path_grid)
	return Vector2(slide.x, slide.y) if slide.z != 0.0 else start_position


func _terrain_slide_position(start_position: Vector2, end_position: Vector2, blocked_cell: Vector2i, path_grid: RwPathGrid) -> Vector3:
	var open_neighbors: int
	var neighbors: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,]
	for index: int in neighbors.size():
		if path_grid.is_passable(blocked_cell + neighbors[index], movement_type):
			open_neighbors |= 1 << index
	return RwGameMath.terrain_slide_position(start_position, end_position, Vector2(path_grid.tile_size), Vector2(blocked_cell), open_neighbors)


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
