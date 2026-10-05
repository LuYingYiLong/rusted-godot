extends RefCounted
class_name RwUnitOrderController
## 在原版同步帧上应用服务器单位命令并推进路径与队列

## 单位命令实际生效后发出，供战斗行为接收
signal order_applied(unit_state: RwUnitState, order_type: String, order: Dictionary)

const TARGET_ORDER_TYPES: Array[String] = [
	"attack",
	"repair",
	"reclaim",
	"loadInto",
	"loadUp",
	"guard",
	"touchTarget",
	"follow",
]
const POINT_ORDER_TYPES: Array[String] = [
	"move",
	"attackMove",
	"patrol",
	"guardAt",
	"unloadAt",
]
const REPATH_INTERVAL_FRAMES: int = 15
const REPATH_DISTANCE: float = 16.0

var _units: Dictionary
var _registry: RwUnitRegistry
var _path_grid: RwPathGrid
var _network_paths: bool
var _pending_orders: Dictionary
var _pending_order_paths: Dictionary[int, Dictionary]
var _last_repath_frames: Dictionary
var _formation: RwUnitFormationController = RwUnitFormationController.new()


## 绑定战场单位、原版定义和导航网格
func configure(units: Dictionary, registry: RwUnitRegistry, path_grid: RwPathGrid, network_paths: bool = false) -> void:
	_units = units
	_registry = registry
	_path_grid = path_grid
	_network_paths = network_paths
	_formation.configure(units, path_grid, network_paths)
	_pending_orders.clear()
	_pending_order_paths.clear()
	_last_repath_frames.clear()


## 在服务器指定的同步帧执行一条命令
func apply_command(command: Dictionary, busy_unit_ids: Array[int] = []) -> void:
	if bool(command.get("is_system_action", false)):
		return
	var order_type: String = str(command.get("order_type", ""))
	var command_targets: Dictionary = command.get("command_targets", {})
	var team_slot: int = int(command.get("source_team", -1))
	if team_slot == -1:
		team_slot = int(command.get("team", -1))
	var allowed_mask: int = int(command.get("allowed_team_mask", 0))
	var formation_members: Array[RwUnitState]
	for object_id: int in command.get("unit_ids", []):
		var unit_state: RwUnitState = _units.get(object_id) as RwUnitState
		if unit_state == null or unit_state.is_dead or not can_apply_to_unit(unit_state, team_slot, allowed_mask):
			continue
		if int(command.get("attack_mode", -1)) >= 0:
			unit_state.apply_snapshot({"attack_mode": int(command["attack_mode"]),})
		if bool(command.get("clear_existing_orders", false)):
			_formation.detach(unit_state)
			_pending_orders.erase(object_id)
			_pending_order_paths.erase(object_id)
			unit_state.apply_order("", unit_state.world_position)
		if order_type.is_empty():
			continue
		var metadata: Dictionary = command_targets.get(object_id, {})
		var base_target: Vector2 = command.get("target", Vector2.ZERO)
		if order_type.begins_with("triggerAction") and command.get("command_target_point") is Vector2:
			base_target = command["command_target_point"]
		var target: Vector2 = metadata.get("target_position", base_target)
		var target_id: int = int(command.get("target_id", -1))
		if target_id <= 0:
			target_id = int(command.get("command_target_id", -1))
		var action_id: String = str(command.get("order_action_id", ""))
		if action_id.is_empty() and order_type.begins_with("triggerAction"):
			action_id = str(command.get("action_id", ""))
		var order: Dictionary = {
			"type": order_type,
			"target": target,
			"target_id": target_id,
			"action_id": action_id,
			"build_queue_size": int(command.get("build_queue_size", 0)),
			"force_move": bool(command.get("force_move", false)),
			"is_high_priority": bool(command.get("is_high_priority", false)),
			"path": metadata.get("path", []),
			"start_position": metadata.get("start_position", unit_state.world_position),
		}
		var should_queue: bool = bool(command.get("is_queued", false)) and not bool(command.get("is_instant_command", false))
		if should_queue and (not unit_state.order_type.is_empty() or _pending_orders.has(object_id) or busy_unit_ids.has(object_id)):
			var queue: Array[Dictionary] = []
			if _pending_orders.has(object_id):
				queue = _pending_orders[object_id]
			if bool(order["is_high_priority"]) and not queue.is_empty():
				var last_order: Dictionary = queue.back()
				var last_target: Vector2 = last_order["target"]
				if POINT_ORDER_TYPES.has(str(last_order["type"])) and last_target.distance_to(target) <= 3.0:
					queue.pop_back()
			queue.append(order)
			_pending_orders[object_id] = queue
			continue
		if unit_state.movement_speed > 0.0:
			formation_members.append(unit_state)
		else:
			_formation.detach(unit_state)
		if not should_queue:
			_pending_orders.erase(object_id)
		unit_state.navigation_arrival_time = 0.0
		if _network_paths and (POINT_ORDER_TYPES.has(order_type) or TARGET_ORDER_TYPES.has(order_type)):
			unit_state.apply_order(order_type, target, target_id, action_id)
			_pending_order_paths[object_id] = order
		else:
			_pending_order_paths.erase(object_id)
			_apply_order(unit_state, order)

	# 原版按战场对象顺序分配槽位，同距离时不使用网络命令中的编号顺序
	var ordered_members: Array[RwUnitState]
	for unit: RwUnitState in _units.values():
		if formation_members.has(unit):
			ordered_members.append(unit)
	_formation.assign(ordered_members, command.get("target", Vector2.ZERO), bool(command.get("formation_loose", command.get("order_is_queued", false))))


## 为已由建造系统接收的有效单位命令分配编队，不重复应用建造命令
func assign_command_formation(command: Dictionary, active_unit_ids: Array[int]) -> void:
	var members: Array[RwUnitState]
	for unit: RwUnitState in _units.values():
		if active_unit_ids.has(unit.object_id) and not unit.is_dead and unit.movement_speed > 0.0:
			members.append(unit)
	_formation.assign(members, command.get("target", Vector2.ZERO), bool(command.get("formation_loose", command.get("order_is_queued", false))))


## 在单位的下一模拟步申请路径，保留原版共享代价缓存的请求顺序
func prepare_pending_path(unit_state: RwUnitState, simulation_delta: float = 1.0) -> void:
	unit_state.navigation_repath_timer = RwGameMath.advance_speed(unit_state.navigation_repath_timer, 0.0, 1.0, simulation_delta)
	unit_state.advance_point_order_arrival(simulation_delta)
	var needs_point_path: bool = (
		POINT_ORDER_TYPES.has(unit_state.order_type)
		and unit_state.formation_leader_id < 0
		and (unit_state.navigation_repath_timer == 0.0 or unit_state.navigation_path_truncated and unit_state.navigation_repath_timer < 450.0)
		and unit_state.get_checksum_path_points().is_empty()
		and not unit_state.has_pending_path()
		and not unit_state.is_exiting_factory()
	)
	if needs_point_path:
		unit_state.navigation_repath_requested = true
	if unit_state.navigation_repath_requested and not _pending_order_paths.has(unit_state.object_id):
		unit_state.navigation_repath_requested = false
		if not unit_state.is_dead and POINT_ORDER_TYPES.has(unit_state.order_type):
			_apply_order(unit_state, {
				"type": unit_state.order_type,
				"target": unit_state.order_target,
				"target_id": unit_state.order_target_id,
				"action_id": unit_state.order_action_id,
				"path": [],
				"start_position": unit_state.world_position,
			})
	if not _pending_order_paths.has(unit_state.object_id):
		return
	var order: Dictionary = _pending_order_paths[unit_state.object_id]
	_pending_order_paths.erase(unit_state.object_id)
	if unit_state.formation_leader_id >= 0:
		unit_state.clear_formation_path()
		order_applied.emit(unit_state, str(order["type"]), order)
		return
	if not unit_state.is_dead:
		_apply_order(unit_state, order)


## 按同步帧推进目标追踪、移动和下一条排队命令
func advance_unit(unit_state: RwUnitState, frame: int, is_busy: bool = false, simulation_delta: float = 1.0) -> void:
	if unit_state == null or unit_state.is_dead:
		return
	unit_state.navigation_stop_requested = unit_state.operation_turn_performed_this_step or unit_state.operation_retry_waited_this_step
	if TARGET_ORDER_TYPES.has(unit_state.order_type) and not unit_state.target_order_changed_this_step:
		_update_target_order(unit_state, frame)
	_formation.prepare(unit_state, simulation_delta)
	var previous_position: Vector2 = unit_state.world_position
	unit_state.advance_movement(1, _path_grid, simulation_delta)
	unit_state.collision_step_active = unit_state.collision_index_dirty or unit_state.has_active_movement_for_collision() or unit_state.world_position != previous_position
	unit_state.collision_index_dirty = false
	unit_state.operation_turn_performed_this_step = false
	unit_state.operation_retry_waited_this_step = false
	unit_state.target_order_changed_this_step = false
	if is_busy or not unit_state.order_type.is_empty() or not _pending_orders.has(unit_state.object_id):
		return
	var queue: Array[Dictionary] = _pending_orders[unit_state.object_id]
	if queue.is_empty():
		_pending_orders.erase(unit_state.object_id)
		return
	var order: Dictionary = queue.pop_front()
	unit_state.navigation_arrival_time = 0.0
	if queue.is_empty():
		_pending_orders.erase(unit_state.object_id)
	else:
		_pending_orders[unit_state.object_id] = queue
	_apply_order(unit_state, order)


## 在整步结束后推进编队时间，命令在帧末分配时与原版时钟一致
func finish_step(simulation_delta: float) -> void:
	_formation.finish_step(simulation_delta)


## 返回原版建造重试及编队共用的模拟毫秒时钟
func get_simulation_time_ms() -> int:
	return _formation.time_ms


## 单位死亡或建筑接管时丢弃尚未执行的排队命令
func clear_pending(object_id: int) -> void:
	_pending_orders.erase(object_id)
	_pending_order_paths.erase(object_id)
	_last_repath_frames.erase(object_id)


## 返回当前战斗是否按联机同步帧释放异步路径
func uses_network_paths() -> bool:
	return _network_paths


## 检查命令所属队伍或共享控制位是否允许操作单位
func can_apply_to_unit(unit_state: RwUnitState, team_slot: int, allowed_mask: int) -> bool:
	if not unit_state.team.is_valid_int():
		return false
	var unit_team: int = unit_state.team.to_int()
	return unit_team == team_slot or unit_team >= 0 and unit_team < 16 and (allowed_mask & (1 << unit_team)) != 0


func _apply_order(unit_state: RwUnitState, order: Dictionary) -> void:
	var order_type: String = str(order["type"])
	var command_target: Vector2 = order["target"]
	var target: Vector2 = command_target
	var target_id: int = int(order["target_id"])
	var action_id: String = str(order.get("action_id", ""))
	var attack_target: RwUnitState = _units.get(unit_state.navigation_attack_target_id) as RwUnitState
	var use_attack_override: bool = (
		POINT_ORDER_TYPES.has(order_type)
		and unit_state.navigation_attack_override_active
		and attack_target != null
		and not attack_target.is_dead
	)
	if use_attack_override:
		target = attack_target.world_position
	if POINT_ORDER_TYPES.has(order_type) and unit_state.movement_speed > 0.0:
		if unit_state.factory_clearance_frames > 0.0:
			unit_state.apply_move_order(
				target,
				[target,],
				order_type,
				target_id,
				action_id,
				0,
				command_target if use_attack_override else Vector2(INF, INF)
			)
			order_applied.emit(unit_state, order_type, order)
			return
		if _path_grid != null and _path_grid.needs_source_escape(unit_state.world_position, unit_state.movement_type):
			unit_state.apply_source_escape_path(
				target,
				_path_grid.source_escape_target(unit_state.world_position, target),
				order_type,
				target_id,
				action_id,
				command_target if use_attack_override else Vector2(INF, INF)
			)
			order_applied.emit(unit_state, order_type, order)
			return
		if _path_grid != null:
			_path_grid.update_object_costs(_units, unit_state.object_id)
		var path_start: Vector2 = unit_state.world_position
		var minimum_clearance: int = 3 if unit_state.formation_is_leader and unit_state.formation_size > 1 else 0
		var uses_direct_path: bool = _path_grid != null and _path_grid.has_source_direct_line(unit_state.world_position, target, unit_state.movement_type, minimum_clearance)
		var path_cells: Array[Vector2i] = []
		for cell: Vector2i in order["path"]:
			path_cells.append(cell)
		var waypoints: Array[Vector2] = []
		var direct_waypoints: Array[Vector2] = []
		if uses_direct_path:
			direct_waypoints = _path_grid.source_direct_waypoints(unit_state.world_position, target, unit_state.movement_type, minimum_clearance)
		var used_server_path: bool
		if not use_attack_override and not uses_direct_path and _path_grid != null and not path_cells.is_empty() and path_start.distance_squared_to(order["start_position"]) < 3600.0:
			waypoints = _path_grid.path_from_cells(path_start, target, path_cells, unit_state.movement_type)
			used_server_path = not waypoints.is_empty()
		if waypoints.is_empty() and _path_grid != null and not uses_direct_path:
			waypoints = _path_grid.find_path(path_start, target, unit_state.movement_type, false, unit_state.body_rotation_degrees, true)
		var path_delay: int = 0 if used_server_path or uses_direct_path else _network_path_delay(path_start, target, unit_state)
		unit_state.apply_move_order(
			target,
			waypoints,
			order_type,
			target_id,
			action_id,
			path_delay,
			command_target if use_attack_override else Vector2(INF, INF)
		)
		unit_state.navigation_repath_timer = 500.0
		if uses_direct_path:
			unit_state.schedule_source_direct_path(direct_waypoints, _path_grid.is_source_direct_path_truncated(path_start, target, unit_state.movement_type))
		elif used_server_path and _network_paths:
			unit_state.defer_current_path()
	elif TARGET_ORDER_TYPES.has(order_type) and target_id > 0:
		var target_state: RwUnitState = _units.get(target_id) as RwUnitState
		if target_state == null or target_state.is_dead:
			return
		_issue_target_order(unit_state, order_type, target_state, action_id)
	else:
		unit_state.apply_order(order_type, target, target_id, action_id)
	order_applied.emit(unit_state, order_type, order)


func _update_target_order(unit_state: RwUnitState, frame: int) -> void:
	var target_state: RwUnitState = _units.get(unit_state.order_target_id) as RwUnitState
	if target_state == null or target_state.is_dead:
		unit_state.apply_order("", unit_state.world_position)
		return
	var desired_distance: float = _target_distance(unit_state, unit_state.order_type, target_state)
	if unit_state.world_position.distance_to(target_state.world_position) <= desired_distance:
		unit_state.navigation_stop_requested = true
		return
	if frame - int(_last_repath_frames.get(unit_state.object_id, -REPATH_INTERVAL_FRAMES)) < REPATH_INTERVAL_FRAMES:
		return
	if unit_state.has_pending_path():
		return
	if unit_state.get_navigation_path().is_empty() or unit_state.order_target.distance_to(target_state.world_position) > REPATH_DISTANCE:
		_last_repath_frames[unit_state.object_id] = frame
		_issue_target_order(unit_state, unit_state.order_type, target_state, unit_state.order_action_id)


func _issue_target_order(unit_state: RwUnitState, order_type: String, target_state: RwUnitState, action_id: String = "") -> void:
	var target: Vector2 = target_state.world_position
	if unit_state.movement_speed <= 0.0 or unit_state.world_position.distance_to(target) <= _target_distance(unit_state, order_type, target_state):
		unit_state.apply_order(order_type, target, target_state.object_id, action_id)
		return
	if _path_grid != null:
		_path_grid.update_object_costs(_units, unit_state.object_id)
	var goal_radius_cells: int
	if _path_grid != null:
		var desired_distance: float = _target_distance(unit_state, order_type, target_state)
		if desired_distance > 58.0:
			goal_radius_cells = maxi(0, int((desired_distance - 41.0) / (float(_path_grid.tile_size.x) * 1.414)))
	var waypoints: Array[Vector2] = _path_grid.find_path(unit_state.world_position, target, unit_state.movement_type, true, unit_state.body_rotation_degrees, true, goal_radius_cells) if _path_grid != null else []
	var path_delay: int = _network_path_delay(unit_state.world_position, target, unit_state)
	unit_state.apply_move_order(target, waypoints, order_type, target_state.object_id, action_id, path_delay)


func _network_path_delay(start: Vector2, target: Vector2, unit_state: RwUnitState) -> int:
	if not _network_paths or _path_grid == null or unit_state.is_exiting_factory():
		return 0
	var minimum_clearance: int = 3 if unit_state.formation_is_leader and unit_state.formation_size > 1 else 0
	return _path_grid.network_path_delay_frames(start, target, unit_state.movement_type, minimum_clearance)


func _target_distance(unit_state: RwUnitState, order_type: String, target_state: RwUnitState) -> float:
	if order_type == "repair" and (target_state.build_progress < 1.0 or target_state.construction_completed_this_step):
		return 85.0
	if order_type != "attack":
		return maxf(unit_state.collision_radius + target_state.collision_radius + 8.0, 24.0)
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name) if _registry != null else null
	var distance: float = definition.attack_range if definition != null else 0.0
	if definition != null:
		for weapon: RwWeaponDefinition in definition.combat_weapons:
			if weapon != null:
				distance = maxf(distance, weapon.attack_range)
	return maxf(distance - 5.0, 24.0)
