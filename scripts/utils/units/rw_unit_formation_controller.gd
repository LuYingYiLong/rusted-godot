extends RefCounted
class_name RwUnitFormationController
## 按原版选择领队、分配槽位并推进动态跟随，编号关系避免状态对象之间形成引用环

var time_ms: int

var _units: Dictionary
var _path_grid: RwPathGrid
var _network_paths: bool


## 绑定战场单位并重置模拟时钟
func configure(units: Dictionary, path_grid: RwPathGrid, network_paths: bool) -> void:
	_units = units
	_path_grid = path_grid
	_network_paths = network_paths
	time_ms = 0


## 在每个同步步结束时更新原版的毫秒时钟
func finish_step(simulation_delta: float) -> void:
	time_ms = int(RwGameMath.float32(float(time_ms) + RwGameMath.float32(simulation_delta * 16.666666)))


## 清除当前单位的编队角色，不改变其同步命令
func detach(unit: RwUnitState) -> void:
	unit.formation_leader_id = -1
	unit.formation_is_leader = false
	unit.formation_offset = Vector2.ZERO
	unit.formation_navigation_active = false
	unit.formation_recovery = 0.0
	unit.formation_leader_age = 0
	unit.formation_path_timer = 0.0


## 根据整组平均位置计算方向，再按原版三轮距离筛选形成子队
func assign(members: Array[RwUnitState], target: Vector2, loose: bool = false) -> void:
	if members.is_empty():
		return
	var center: Vector2 = Vector2.ZERO
	for unit: RwUnitState in members:
		center += unit.world_position
	center = Vector2(RwGameMath.float32(center.x / float(members.size())), RwGameMath.float32(center.y / float(members.size())))
	var angle: float = RwGameMath.direction_degrees(center, target)
	var favored: Dictionary[int, bool]
	for unit: RwUnitState in members:
		var preferred: bool = unit.formation_is_leader and unit.formation_size > 1
		if preferred and unit.formation_size > 7 and absf(RwGameMath.signed_angle_delta(unit.formation_angle, angle)) > 80.0:
			preferred = false
		favored[unit.object_id] = preferred
		detach(unit)
		unit.formation_size = 0
		unit.formation_assigned_time = time_ms
	var assigned: Dictionary[int, bool]
	while assigned.size() < members.size():
		var leader: RwUnitState
		var nearest: float = -1.0
		for unit: RwUnitState in members:
			if assigned.has(unit.object_id):
				continue
			var distance: float = RwGameMath.float32(sqrt(RwGameMath.distance_squared(target, unit.world_position)))
			if favored[unit.object_id]:
				distance = RwGameMath.float32(distance - 160.0)
			if nearest == -1.0 or distance < nearest:
				nearest = distance
				leader = unit
		if leader == null:
			break
		leader.formation_is_leader = true
		assigned[leader.object_id] = true
		var followers: Array[RwUnitState]
		var maximum_radius: float
		for pass_index: int in 3:
			for unit: RwUnitState in members:
				if assigned.has(unit.object_id) or unit.movement_type != leader.movement_type:
					continue
				var distance: float = RwGameMath.distance_squared(unit.world_position, leader.world_position)
				if pass_index == 0 and distance > 3600.0 or pass_index == 1 and distance > 14400.0:
					continue
				if not (loose and distance < 160000.0 or distance < 40000.0 and followers.size() < 25):
					continue
				if not loose and absf(RwGameMath.float32(unit.movement_speed - leader.movement_speed)) >= RwGameMath.float32(0.4):
					continue
				followers.append(unit)
				assigned[unit.object_id] = true
				unit.formation_leader_id = leader.object_id
				maximum_radius = maxf(maximum_radius, unit.collision_radius)
		leader.formation_size = followers.size() + 1
		_assign_slots(followers, leader, maximum_radius, angle)


## 在单位移动前生成领队路径前瞻目标及脱队恢复状态
func prepare(unit: RwUnitState, simulation_delta: float) -> void:
	unit.formation_navigation_active = false
	unit.formation_path_timer = RwGameMath.advance_speed(unit.formation_path_timer, 0.0, 1.0, simulation_delta)
	if unit.formation_is_leader and unit.formation_size > 1:
		var remaining: int = unit.get_checksum_path_points().size()
		var stalled_limit: float = 150.0 if unit.movement_speed > 0.5 else 300.0
		if remaining >= 2 and unit.waypoint_time > stalled_limit:
			unit.formation_assigned_time = time_ms
	if unit.formation_leader_id < 0:
		return
	var leader: RwUnitState = _units.get(unit.formation_leader_id) as RwUnitState
	if leader == null or leader.is_dead or leader.build_progress < 1.0:
		detach(unit)
		return
	if not leader.order_type.is_empty() and (leader.order_type != unit.order_type or absf(leader.order_target.x - unit.order_target.x) > 1.0 or absf(leader.order_target.y - unit.order_target.y) > 1.0):
		return
	if float(unit.get("_movement_velocity")) != 0.0:
		unit.formation_recovery = RwGameMath.advance_speed(unit.formation_recovery, 0.0, 1.0, simulation_delta)
	var age: int = time_ms - leader.formation_assigned_time
	unit.formation_leader_age = age
	var slot: Vector2 = leader.world_position + unit.formation_offset
	var distance: float = RwGameMath.distance_squared(unit.world_position, slot)
	if age > 300 or unit.terrain_blocked_time > 1.0:
		unit.formation_lag = RwGameMath.float32(unit.formation_lag + simulation_delta)
	if unit.formation_lag > 300.0 or age > 300 and distance > 250000.0 or unit.terrain_blocked_time > 1.0 and (unit.formation_recovery != 0.0 or unit.formation_lag > 10.0):
		unit.formation_recovery = 90.0
	if unit.formation_recovery != 0.0:
		var recovery_points: PackedVector2Array = leader.get_checksum_path_points()
		var recovery_target: Vector2 = recovery_points[8] if recovery_points.size() > 8 and leader.original_path_count > 2 else leader.world_position
		var recovery_radius: float = RwGameMath.float32(unit.collision_radius + leader.collision_radius + 15.0)
		if RwGameMath.distance_squared(unit.world_position, recovery_target) < RwGameMath.float32(recovery_radius * recovery_radius):
			unit.formation_recovery = 0.0
			unit.formation_lag = 0.0
		if not unit.has_pending_path():
			if not unit.get_checksum_path_points().is_empty() and (absf(unit.formation_path_target.x - recovery_target.x) > 300.0 or absf(unit.formation_path_target.y - recovery_target.y) > 300.0):
				unit.formation_path_timer = minf(unit.formation_path_timer, 30.0)
			if unit.formation_path_timer == 0.0:
				_request_recovery_path(unit, recovery_target)
		return
	# 跟随状态 aH 清空自己的路径与 W，但实际运动仍使用领队的虚拟目标
	unit.clear_formation_path()
	unit.formation_path_timer = 0.0
	var points: PackedVector2Array = leader.get_checksum_path_points()
	var desired: Vector3 = RwGameMath.formation_target(leader.world_position, unit.formation_offset, points, leader.original_path_count, age)
	unit.formation_navigation_target = Vector2(desired.x, desired.y)
	unit.formation_slow_near_target = desired.z != 0.0
	var reset_radius: float = 60.0 if unit.terrain_blocked_time <= 1.0 else 45.0
	if distance < reset_radius * reset_radius:
		unit.formation_lag = 0.0
	if leader.order_type.is_empty():
		unit.formation_wait = RwGameMath.float32(unit.formation_wait + simulation_delta)
		var finish_radius: float = 16.0
		if unit.formation_wait > 600.0:
			finish_radius = 260.0
		elif unit.formation_wait > 360.0:
			finish_radius = 140.0
		elif unit.formation_wait > 180.0:
			finish_radius = 70.0
		elif unit.formation_wait > 120.0:
			finish_radius = 50.0
		if distance < finish_radius * finish_radius:
			var angle_delta: float = RwGameMath.signed_angle_delta(unit.body_rotation_degrees, unit.formation_angle)
			var turn: Vector3 = RwGameMath.turn_toward(unit.body_rotation_degrees, unit.formation_angle, float(unit.get("_turn_velocity")), unit.turn_speed, unit.turn_acceleration, simulation_delta)
			unit.apply_formation_turn(turn)
			if absf(angle_delta) < 3.0 and unit.order_type in ["move", "attackMove",]:
				unit.apply_order("", unit.world_position)
				detach(unit)
			return
	unit.formation_navigation_active = true


func _request_recovery_path(unit: RwUnitState, target: Vector2) -> void:
	if _path_grid == null:
		return
	unit.formation_path_timer = 700.0
	unit.formation_path_target = target
	_path_grid.update_object_costs(_units, unit.object_id)
	var direct: bool = _path_grid.has_source_direct_line(unit.world_position, target, unit.movement_type)
	var points: Array[Vector2]
	if direct:
		points = _path_grid.source_direct_waypoints(unit.world_position, target, unit.movement_type)
	else:
		points = _path_grid.find_path(unit.world_position, target, unit.movement_type, false, unit.body_rotation_degrees, true)
	var delay: int = _path_grid.network_path_delay_frames(unit.world_position, target, unit.movement_type) if _network_paths and not direct else 0
	var truncated: bool = direct and _path_grid.is_source_direct_path_truncated(unit.world_position, target, unit.movement_type)
	unit.schedule_formation_recovery_path(points, delay, direct, truncated)


func _assign_slots(followers: Array[RwUnitState], leader: RwUnitState, radius: float, angle: float) -> void:
	var slots: Array[Vector2]
	slots.assign(RwGameMath.formation_offsets(followers.size(), radius, angle))
	var assigned: Dictionary[int, float]
	var pending: Array[RwUnitState] = followers.duplicate()
	while not pending.is_empty():
		var farthest: RwUnitState
		var farthest_distance: float = -1.0
		var chosen_slot: int = -1
		for unit: RwUnitState in pending:
			var nearest_distance: float = -1.0
			var nearest_slot: int = -1
			for index: int in slots.size():
				var distance: float = RwGameMath.distance_squared(unit.world_position, leader.world_position + slots[index])
				if nearest_distance == -1.0 or distance < nearest_distance:
					nearest_distance = distance
					nearest_slot = index
			if nearest_distance > farthest_distance:
				farthest_distance = nearest_distance
				farthest = unit
				chosen_slot = nearest_slot
		farthest.formation_offset = slots[chosen_slot]
		farthest.formation_angle = angle
		farthest.formation_size = followers.size() + 1
		assigned[farthest.object_id] = farthest_distance
		slots.remove_at(chosen_slot)
		pending.erase(farthest)
	var exchanged: Dictionary[int, bool]
	while true:
		var farthest: RwUnitState
		var maximum: float
		for unit: RwUnitState in followers:
			var distance: float = assigned[unit.object_id]
			if not exchanged.has(unit.object_id) and distance > 100.0 and (farthest == null or distance > maximum):
				farthest = unit
				maximum = distance
		if farthest == null:
			return
		exchanged[farthest.object_id] = true
		var partner: RwUnitState
		var best_gain: int
		for unit: RwUnitState in followers:
			if unit == farthest or assigned[unit.object_id] <= 0.0:
				continue
			var previous: int = int(floor(RwGameMath.float32(sqrt(float(int(maximum)))) + 0.5)) + int(floor(RwGameMath.float32(sqrt(float(int(assigned[unit.object_id])))) + 0.5))
			var next: int = RwGameMath.rounded_distance(farthest.world_position, leader.world_position + unit.formation_offset) + RwGameMath.rounded_distance(unit.world_position, leader.world_position + farthest.formation_offset)
			if next - previous < best_gain:
				best_gain = next - previous
				partner = unit
		if partner != null:
			var previous_offset: Vector2 = farthest.formation_offset
			farthest.formation_offset = partner.formation_offset
			partner.formation_offset = previous_offset
			assigned[farthest.object_id] = RwGameMath.distance_squared(farthest.world_position, leader.world_position + farthest.formation_offset)
			assigned[partner.object_id] = RwGameMath.distance_squared(partner.world_position, leader.world_position + partner.formation_offset)
