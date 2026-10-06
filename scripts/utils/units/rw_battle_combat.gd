extends RwCombatContext
class_name RwBattleCombat
## 在同步帧内统一处理索敌、武器冷却、弹体飞行和伤害

## 弹体生成后发出，绘制和音效层可订阅
signal projectile_fired(projectile: RwProjectileState)
## 弹体命中后发出，可用于命中特效和音效
signal projectile_impacted(projectile: RwProjectileState, target: RwUnitState)
## 弹体触发原版临时揭雾时发出
signal projectile_fog_reveal_requested(projectile: RwProjectileState)
## 弹体从模拟列表移除时发出，表现层可保留剩余尾迹
signal projectile_finished(projectile: RwProjectileState)
## 原版激光防御命中弹体后发出
signal projectile_deflected(defense_unit: RwUnitState, projectile: RwProjectileState, destroyed: bool)
## 弹体命中后请求地图创建弹药定义指定的单位
signal projectile_unit_spawn_requested(projectile: RwProjectileState, spawn_spec: Dictionary)
## 单位首次死亡后发出，地图负责移除阻挡和更新界面
signal unit_destroyed(unit_state: RwUnitState)

## 当前仍在飞行的弹体，按发射顺序排列
var projectiles: Array[RwProjectileState]

var _unit_states: Dictionary
var _registry: RwUnitRegistry
var _players: Array[Dictionary]
var _weapon_runtime: Dictionary
var _idle_sweep_runtime: Dictionary
var _sorted_ids: Array[int]
var _sorted_ids_dirty: bool = true
var _simulation_delta: float = 1.0
var _simulation_frame: int = -1
var _global_random_seed: int
var _projectile_sequence: int


## 绑定地图单位与定义，并注册已有单位
func configure(unit_states: Dictionary, registry: RwUnitRegistry, players: Array[Dictionary]) -> void:
	_unit_states = unit_states
	_registry = registry
	_players = players.duplicate(true)
	_weapon_runtime.clear()
	_idle_sweep_runtime.clear()
	projectiles.clear()
	_projectile_sequence = 0
	_sorted_ids_dirty = true
	var unit_ids: Array[int] = _sorted_unit_ids()
	for unit_id: int in unit_ids:
		register_unit(_unit_states[unit_id] as RwUnitState)


## 更新玩家队伍与联盟关系
func set_players(players: Array[Dictionary]) -> void:
	_players = players.duplicate(true)


## 设置原版同步随机数使用的帧与种子
func set_simulation_context(frame: int, global_seed: int = 0) -> void:
	_simulation_frame = frame
	_global_random_seed = global_seed


## 注册刚生成的单位，冷却和索敌状态只属于该单位
func register_unit(unit_state: RwUnitState) -> void:
	if unit_state == null or _registry == null or _weapon_runtime.has(unit_state.object_id):
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	var runtime: Dictionary = {}
	if definition != null:
		for weapon_index: int in definition.combat_weapons.size():
			runtime[weapon_index] = {"cooldown": 0, "warmup": 0, "target_id": -1,}
	_weapon_runtime[unit_state.object_id] = runtime
	_sorted_ids_dirty = true
	if definition != null and definition.behavior != null:
		definition.behavior.on_spawned(unit_state, definition, self)


## 形态切换后重建该单位的武器冷却状态
func reset_unit(unit_state: RwUnitState) -> void:
	if unit_state == null:
		return
	_weapon_runtime.erase(unit_state.object_id)
	_idle_sweep_runtime.erase(unit_state.object_id)
	register_unit(unit_state)


## 通知单位行为已经收到同步命令
func notify_order(unit_state: RwUnitState, order_type: String, order: Dictionary = {}) -> void:
	if unit_state == null or _registry == null:
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	if definition != null and definition.behavior != null:
		definition.behavior.on_ordered(unit_state, definition, order_type, order, self)


## 检查已缓存武器目标是否仍可攻击，供攻击移动决定是否结束命令
func has_active_attack_target(unit_state: RwUnitState) -> bool:
	if unit_state == null or _registry == null:
		return false
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	if definition == null:
		return false
	var runtime: Dictionary = _weapon_runtime.get(unit_state.object_id, {})
	for weapon_index: int in definition.combat_weapons.size():
		var weapon_runtime: Dictionary = runtime.get(weapon_index, {})
		var target: RwUnitState = _unit_states.get(int(weapon_runtime.get("target_id", -1))) as RwUnitState
		if _can_target(unit_state, target, definition.combat_weapons[weapon_index]):
			return true
	return false


## 在移动前按原版攻击模式更新缓存目标与临时追击终点
func prepare_navigation_target(unit_state: RwUnitState, simulation_delta: float = 1.0) -> void:
	if unit_state == null or _registry == null:
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	if definition == null or definition.combat_weapons.is_empty():
		_clear_navigation_target(unit_state)
		return
	var attack_mode: int = unit_state.attack_mode if unit_state.attack_mode >= 0 else 1
	if attack_mode == 2 or attack_mode == 3:
		_clear_navigation_target(unit_state)
		return
	var search_range: float = _target_search_range(unit_state, definition, attack_mode)
	var target: RwUnitState = _unit_states.get(unit_state.navigation_attack_target_id) as RwUnitState
	if not _can_acquire_target(unit_state, target, definition, search_range):
		if target != null:
			unit_state.navigation_attack_target_id = -1
			target = null
	unit_state.navigation_attack_search_timer = RwGameMath.advance_speed(unit_state.navigation_attack_search_timer, 0.0, 1.0, simulation_delta)
	var effective_attack_range: float = _attack_range_for_unit(unit_state, definition)
	var target_out_of_weapon_range: bool = (
		target != null
		and unit_state.world_position.distance_squared_to(target.world_position) >= effective_attack_range * effective_attack_range
	)
	if (target == null or target_out_of_weapon_range) and unit_state.navigation_attack_search_timer == 0.0:
		unit_state.navigation_attack_search_timer = (
			20.0
			+ fmod(unit_state.world_position.x, 5.0)
			+ fmod(unit_state.world_position.y, 5.0)
		)
		target = _find_navigation_target(unit_state, definition, search_range)
		unit_state.navigation_attack_target_id = target.object_id if target != null else -1
	var can_pursue: bool = attack_mode == 0 or attack_mode == 4 or attack_mode == 5
	var should_override: bool = (
		target != null
		and can_pursue
		and RwUnitOrderController.POINT_ORDER_TYPES.has(unit_state.order_type)
		and unit_state.world_position.distance_squared_to(target.world_position) > effective_attack_range * effective_attack_range
	)
	unit_state.navigation_attack_target_active = target != null or has_active_attack_target(unit_state)
	if should_override:
		if not unit_state.navigation_attack_override_active:
			unit_state.navigation_attack_target_position = target.world_position
			unit_state.navigation_attack_override_active = true
			unit_state.navigation_repath_timer = 0.0
			unit_state.navigation_repath_requested = true
		else:
			unit_state.navigation_repath_timer = minf(unit_state.navigation_repath_timer, 90.0)
			if unit_state.navigation_repath_timer <= maxf(simulation_delta, 0.0):
				unit_state.navigation_attack_target_position = target.world_position
				unit_state.navigation_repath_requested = true
	else:
		if unit_state.navigation_attack_override_active:
			unit_state.navigation_attack_override_active = false
			unit_state.navigation_repath_requested = true
		unit_state.navigation_attack_target_position = target.world_position if target != null else Vector2.ZERO


## 按固定顺序推进所有单位行为，然后推进弹体
func advance_frame(simulation_delta: float = 1.0) -> void:
	if _registry == null:
		return
	_simulation_delta = maxf(simulation_delta, 0.0)
	var unit_ids: Array[int] = _sorted_unit_ids()
	for unit_id: int in unit_ids:
		var unit_state: RwUnitState = _unit_states[unit_id] as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.build_progress < 1.0:
			continue
		var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
		if definition != null and definition.behavior != null:
			definition.behavior.advance_frame(unit_state, definition, self)
		if definition != null:
			_advance_idle_visual_parts(unit_state, definition)
	_advance_projectile_interceptors(unit_ids)
	_advance_projectiles()


## 为通用自动攻击行为推进一帧武器逻辑
func advance_weapons(unit_state: RwUnitState, definition: RwUnitDefinition) -> void:
	var runtime: Dictionary = _weapon_runtime.get(unit_state.object_id, {})
	for weapon_index: int in definition.combat_weapons.size():
		var weapon: RwWeaponDefinition = definition.combat_weapons[weapon_index]
		if weapon == null or weapon.projectile == null or weapon.attack_range <= 0.0:
			continue
		var weapon_runtime: Dictionary = runtime.get(weapon_index, {"cooldown": 0, "warmup": 0, "target_id": -1,})
		var cooldown: float = float(weapon_runtime["cooldown"])
		if cooldown > 0.0:
			cooldown = maxf(cooldown - _simulation_delta, 0.0)
			weapon_runtime["cooldown"] = cooldown
		var target: RwUnitState = _find_target(unit_state, weapon)
		if target == null:
			weapon_runtime["target_id"] = -1
			weapon_runtime["warmup"] = 0
			runtime[weapon_index] = weapon_runtime
			continue
		if int(weapon_runtime["target_id"]) != target.object_id:
			weapon_runtime["target_id"] = target.object_id
			weapon_runtime["warmup"] = 0
		weapon_runtime["warmup"] = minf(float(weapon_runtime["warmup"]) + _simulation_delta, float(weapon.warmup_frames))
		runtime[weapon_index] = weapon_runtime
		var projectile_definition: RwProjectileDefinition = weapon.projectile_for_target(target)
		var aim_position: Vector2 = target.world_position
		if projectile_definition.instant_reuse_last_also_change_turret_aim:
			var cached_projectile: RwProjectileState = weapon_runtime.get("last_projectile") as RwProjectileState
			if cached_projectile != null and projectiles.has(cached_projectile) and not cached_projectile.remove_requested:
				aim_position += cached_projectile.current_sweep_offset
		var desired_angle: float = rad_to_deg((aim_position - unit_state.world_position).angle())
		var current_angle: float = unit_state.get_weapon_rotation(weapon.rotation_state_index)
		var _angle_difference: float = wrapf(desired_angle - current_angle, -180.0, 180.0)
		var turn_step: float = _angle_difference
		if weapon.turn_speed_degrees > 0.0:
			var turn_limit: float = weapon.turn_speed_degrees * _simulation_delta
			turn_step = clampf(_angle_difference, -turn_limit, turn_limit)
		var next_angle: float = wrapf(current_angle + turn_step, -180.0, 180.0)
		unit_state.set_weapon_rotation(weapon.rotation_state_index, next_angle)
		if cooldown > 0.0 or float(weapon_runtime["warmup"]) < float(weapon.warmup_frames) or absf(wrapf(desired_angle - next_angle, -180.0, 180.0)) > weapon.aim_tolerance_degrees:
			continue
		if unit_state.source_id == "custom":
			unit_state.random_counter = RwVanillaRandom.advance_projectile_counter(
				unit_state.random_counter,
				unit_state.object_id,
			)
		var reusable_projectile: RwProjectileState
		if projectile_definition.instant_reuse_last:
			var cached_projectile: RwProjectileState = weapon_runtime.get("last_projectile") as RwProjectileState
			if cached_projectile != null and projectiles.has(cached_projectile) and not cached_projectile.remove_requested:
				reusable_projectile = cached_projectile
		var projectile: RwProjectileState = spawn_projectile(
			unit_state,
			target,
			weapon,
			next_angle,
			projectile_definition,
			reusable_projectile,
		)
		if projectile == null:
			continue
		weapon_runtime["last_projectile"] = projectile if projectile_definition.instant_reuse_last else null
		weapon_runtime["cooldown"] = maxi(weapon.reload_frames, 1)
	_weapon_runtime[unit_state.object_id] = runtime


## 按原版充能、射程和弹体条件拦截最多一枚弹体
func advance_laser_defense(unit_state: RwUnitState, _definition: RwUnitDefinition) -> void:
	var upgraded: bool = unit_state.tech_level >= 2
	var recharge_per_frame: float = 0.0004 + (0.0002 if upgraded else 0.0)
	unit_state.laser_defense_charge = minf(
		unit_state.laser_defense_charge + recharge_per_frame * _simulation_delta,
		1.0,
	)
	if unit_state.laser_defense_charge >= 1.0:
		unit_state.laser_defense_depleted = false
	if unit_state.laser_defense_depleted or unit_state.laser_defense_charge <= 0.0:
		return
	var interception_range: float = 210.0 if upgraded else 160.0
	var energy_cost: float = 0.05 if upgraded else 0.11
	var origin: Vector2 = unit_state.world_position + Vector2(0.0, -13.0)
	var range_squared: float = interception_range * interception_range
	for projectile: RwProjectileState in projectiles:
		if not _is_laser_defense_target(unit_state, projectile, origin, range_squared):
			continue
		var destroyed: bool = projectile.apply_deflection()
		unit_state.laser_defense_charge -= energy_cost
		if unit_state.laser_defense_charge < 0.0:
			unit_state.laser_defense_charge = 0.0
			unit_state.laser_defense_depleted = true
		projectile_deflected.emit(unit_state, projectile, destroyed)
		return


## 按对象编号读取单位状态
func find_unit(object_id: int) -> RwUnitState:
	return _unit_states.get(object_id) as RwUnitState


## 生成追踪目标单位的弹体并通知表现层
func spawn_projectile(
	source: RwUnitState,
	target: RwUnitState,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	projectile_override: RwProjectileDefinition = null,
	reuse_projectile: RwProjectileState = null,
) -> RwProjectileState:
	if source == null or source.is_dead or target == null or target.is_dead or weapon == null or weapon.projectile == null:
		return null
	var projectile: RwProjectileState = reuse_projectile if reuse_projectile != null else RwProjectileState.new()
	projectile.configure(
		source,
		target,
		weapon,
		angle_degrees,
		projectile_override,
		_next_projectile_seed(),
		_simulation_frame,
		_global_random_seed,
		reuse_projectile != null,
	)
	_configure_source_damage_multiplier(projectile, source)
	if reuse_projectile == null:
		projectiles.append(projectile)
	projectile_fired.emit(projectile)
	_spawn_projectile_children(projectile, projectile.definition.spawn_on_create)
	return projectile


## 生成射向地面目标的弹体并通知表现层
func spawn_projectile_at(
	source: RwUnitState,
	target_position: Vector2,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	projectile_override: RwProjectileDefinition = null,
	target_altitude: float = 0.0,
) -> RwProjectileState:
	if source == null or source.is_dead or weapon == null or weapon.projectile == null:
		return null
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure_at(
		source,
		target_position,
		weapon,
		angle_degrees,
		projectile_override,
		target_altitude,
		_next_projectile_seed(),
		_simulation_frame,
		_global_random_seed,
	)
	_configure_source_damage_multiplier(projectile, source)
	projectiles.append(projectile)
	projectile_fired.emit(projectile)
	_spawn_projectile_children(projectile, projectile.definition.spawn_on_create)
	return projectile


func _next_projectile_seed() -> int:
	_projectile_sequence += 1
	return _projectile_sequence


func _configure_source_damage_multiplier(projectile: RwProjectileState, source: RwUnitState) -> void:
	if projectile == null or projectile.definition == null or source == null:
		return
	var projectile_definition: RwProjectileDefinition = projectile.definition
	projectile.render_color = projectile_definition.visual_color
	if projectile_definition.team_color_ratio > 0.0:
		var team_color: Color = RwUnitTeamColors.for_team(source.team, _players)
		var team_ratio: float = projectile_definition.team_color_ratio
		var source_ratio: float = projectile_definition.team_color_source_ratio
		projectile.render_color = Color(
			clampf(projectile.render_color.r * source_ratio + team_color.r * team_ratio, 0.0, 1.0),
			clampf(projectile.render_color.g * source_ratio + team_color.g * team_ratio, 0.0, 1.0),
			clampf(projectile.render_color.b * source_ratio + team_color.b * team_ratio, 0.0, 1.0),
			projectile.render_color.a,
		)
	if projectile.definition.ignore_parent_shoot_damage_multiplier:
		projectile.source_damage_multiplier = 1.0
		return
	var source_definition: RwUnitDefinition = _registry.find_definition(source.source_id, source.unit_name)
	projectile.source_damage_multiplier = source_definition.shoot_damage_multiplier if source_definition != null else 1.0


## 对单位直接造成伤害并触发单位行为与死亡事件
func deal_damage(target: RwUnitState, amount: float) -> void:
	_damage_unit(target, amount)


func _sorted_unit_ids() -> Array[int]:
	if _sorted_ids_dirty or _sorted_ids.size() != _unit_states.size():
		_sorted_ids.clear()
		for unit_id: int in _unit_states:
			_sorted_ids.append(unit_id)
		_sorted_ids.sort()
		_sorted_ids_dirty = false
	return _sorted_ids


func _advance_idle_visual_parts(unit_state: RwUnitState, definition: RwUnitDefinition) -> void:
	var runtime: Dictionary = _weapon_runtime.get(unit_state.object_id, {})
	var active_indices: Dictionary = {}
	for weapon_index: int in definition.combat_weapons.size():
		var weapon: RwWeaponDefinition = definition.combat_weapons[weapon_index]
		var weapon_runtime: Dictionary = runtime.get(weapon_index, {})
		if weapon != null and int(weapon_runtime.get("target_id", -1)) >= 0:
			active_indices[weapon.rotation_state_index] = true
	for part: RwUnitWeaponDefinition in definition.weapon_parts:
		if part == null:
			continue
		if active_indices.has(part.rotation_state_index):
			var unit_runtime: Dictionary = _idle_sweep_runtime.get(unit_state.object_id, {})
			unit_runtime.erase(part.rotation_state_index)
			_idle_sweep_runtime[unit_state.object_id] = unit_runtime
			continue
		var current_angle: float = unit_state.get_weapon_rotation(part.rotation_state_index)
		if part.idle_sweep_angle_degrees > 0.0 and part.idle_sweep_speed_degrees > 0.0:
			_advance_idle_sweep(unit_state, part, current_angle)
		elif part.idle_spin_degrees != 0.0:
			unit_state.set_weapon_rotation(part.rotation_state_index, current_angle + part.idle_spin_degrees * _simulation_delta)
		elif part.reset_when_idle:
			var base_angle: float = unit_state.body_rotation_degrees
			if part.parent_part_index >= 0:
				base_angle = unit_state.get_weapon_rotation(part.parent_part_index)
			var desired_angle: float = base_angle + part.idle_direction_degrees
			var angular_delta: float = wrapf(desired_angle - current_angle, -180.0, 180.0)
			var turn_step: float = angular_delta
			if part.idle_turn_speed_degrees > 0.0:
				var turn_limit: float = part.idle_turn_speed_degrees * _simulation_delta
				turn_step = clampf(angular_delta, -turn_limit, turn_limit)
			unit_state.set_weapon_rotation(part.rotation_state_index, current_angle + turn_step)


func _advance_idle_sweep(unit_state: RwUnitState, part: RwUnitWeaponDefinition, current_angle: float) -> void:
	var unit_runtime: Dictionary = _idle_sweep_runtime.get(unit_state.object_id, {})
	var state: Dictionary = unit_runtime.get(part.rotation_state_index, {
		"base_angle": current_angle,
		"elapsed": 0.0,
		"offset": 0.0,
		"reached": true,
		"cycle": 0,
	})
	var offset: float = float(state["offset"])
	if not bool(state["reached"]):
		var target_angle: float = float(state["base_angle"]) + offset
		var angular_delta: float = wrapf(target_angle - current_angle, -180.0, 180.0)
		var turn_limit: float = part.idle_sweep_speed_degrees * _simulation_delta
		var turn_step: float = clampf(angular_delta, -turn_limit, turn_limit)
		unit_state.set_weapon_rotation(part.rotation_state_index, current_angle + turn_step)
		if absf(angular_delta) <= turn_limit:
			state["reached"] = true
	state["elapsed"] = float(state["elapsed"]) + _simulation_delta
	if float(state["elapsed"]) > part.idle_sweep_delay:
		var cycle: int = int(state["cycle"]) + 1
		var random_range: int = maxi(ceili(part.idle_sweep_random_delay), 1)
		var random_delay: int = posmod(unit_state.object_id * 1313 + cycle * 13, random_range)
		state["elapsed"] = -float(random_delay)
		state["offset"] = -part.idle_sweep_angle_degrees if offset > 0.0 else part.idle_sweep_angle_degrees
		state["reached"] = false
		state["cycle"] = cycle
	unit_runtime[part.rotation_state_index] = state
	_idle_sweep_runtime[unit_state.object_id] = unit_runtime


func _find_target(source: RwUnitState, weapon: RwWeaponDefinition) -> RwUnitState:
	if source.attack_mode == 2 or source.attack_mode == 3:
		return null
	if (source.order_type == "attack" or source.order_type == "setPassiveTarget") and source.order_target_id > 0:
		var ordered_target: RwUnitState = _unit_states.get(source.order_target_id) as RwUnitState
		return ordered_target if _can_target(source, ordered_target, weapon) else null
	var best_target: RwUnitState
	var best_distance: float = INF
	for unit_id: int in _sorted_unit_ids():
		var candidate: RwUnitState = _unit_states[unit_id] as RwUnitState
		if not _can_target(source, candidate, weapon):
			continue
		var distance: float = source.world_position.distance_squared_to(candidate.world_position)
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	return best_target


func _find_navigation_target(source: RwUnitState, definition: RwUnitDefinition, search_range: float) -> RwUnitState:
	var best_target: RwUnitState
	var best_distance: float = INF
	var search_range_squared: float = search_range * search_range
	for unit_id: int in _sorted_unit_ids():
		var candidate: RwUnitState = _unit_states[unit_id] as RwUnitState
		if not _can_acquire_target(source, candidate, definition, search_range):
			continue
		var distance_squared: float = source.world_position.distance_squared_to(candidate.world_position)
		if distance_squared < best_distance and distance_squared < search_range_squared:
			best_distance = distance_squared
			best_target = candidate
	return best_target


func _can_acquire_target(source: RwUnitState, target: RwUnitState, definition: RwUnitDefinition, search_range: float) -> bool:
	if target == null or target.is_dead or target.object_id == source.object_id or not _are_hostile(source.team, target.team):
		return false
	if source.world_position.distance_squared_to(target.world_position) >= search_range * search_range:
		return false
	for weapon: RwWeaponDefinition in definition.combat_weapons:
		if weapon == null or weapon.attack_range_for_source(source.submerged) <= 0.0:
			continue
		if target.movement_type == "AIR" and weapon.can_target_air and (not source.submerged or weapon.can_target_air_when_submerged):
			return true
		if target.submerged and weapon.can_target_water:
			return true
		if target.movement_type != "AIR" and not target.submerged and weapon.can_target_ground:
			return true
	return false


func _target_search_range(unit_state: RwUnitState, definition: RwUnitDefinition, attack_mode: int) -> float:
	var search_range: float = _attack_range_for_unit(unit_state, definition)
	if unit_state.order_type == "attackMove":
		search_range += 20.0
		search_range = maxf(search_range, 190.0)
	elif unit_state.order_type == "patrol":
		search_range += 110.0
		search_range = maxf(search_range, 190.0)
	elif unit_state.order_type == "guardAt":
		search_range += 90.0
		search_range = maxf(search_range, 190.0)
	match attack_mode:
		0:
			search_range += 250.0
		4:
			search_range += 150.0
		5:
			search_range += 180.0
	return search_range


func _attack_range_for_unit(unit_state: RwUnitState, definition: RwUnitDefinition) -> float:
	var effective_range: float
	for weapon: RwWeaponDefinition in definition.combat_weapons:
		if weapon != null:
			effective_range = maxf(effective_range, weapon.attack_range_for_source(unit_state.submerged))
	return effective_range if effective_range > 0.0 else definition.attack_range


func _clear_navigation_target(unit_state: RwUnitState) -> void:
	if unit_state.navigation_attack_target_id >= 0 or unit_state.navigation_attack_override_active:
		unit_state.navigation_attack_target_id = -1
		unit_state.navigation_attack_override_active = false
		unit_state.navigation_attack_target_active = false
		unit_state.navigation_attack_target_position = Vector2.ZERO
		unit_state.navigation_repath_requested = true


func _can_target(source: RwUnitState, target: RwUnitState, weapon: RwWeaponDefinition) -> bool:
	if target == null or target.is_dead or target.object_id == source.object_id:
		return false
	if not _are_hostile(source.team, target.team):
		return false
	if target.movement_type == "AIR":
		if not weapon.can_target_air or source.submerged and not weapon.can_target_air_when_submerged:
			return false
	elif target.submerged:
		if not weapon.can_target_water:
			return false
	elif not weapon.can_target_ground:
		return false
	var distance_squared: float = source.world_position.distance_squared_to(target.world_position)
	var attack_range: float = weapon.attack_range_for_source(source.submerged)
	return (
		distance_squared <= attack_range * attack_range
		and distance_squared >= weapon.minimum_range * weapon.minimum_range
	)


func _are_hostile(first_team: String, second_team: String) -> bool:
	if not first_team.is_valid_int() or not second_team.is_valid_int() or first_team == second_team:
		return false
	var first_alliance: int = -1
	var second_alliance: int = -2
	for player: Dictionary in _players:
		var slot: int = int(player.get("slot", -1))
		if slot == first_team.to_int():
			first_alliance = int(player.get("color", -1))
		elif slot == second_team.to_int():
			second_alliance = int(player.get("color", -2))
	return first_alliance < 0 or second_alliance < 0 or first_alliance != second_alliance


func _advance_projectiles() -> void:
	for projectile_index: int in range(projectiles.size() - 1, -1, -1):
		var projectile: RwProjectileState = projectiles[projectile_index]
		if projectile.remove_requested:
			projectile_finished.emit(projectile)
			projectiles.remove_at(projectile_index)
			continue
		var target: RwUnitState = _unit_states.get(projectile.target_id) as RwUnitState
		if projectile.target_id > 0 and (target == null or target.is_dead):
			projectile.mark_target_lost()
		if not projectile.has_impacted and projectile.target_lost and projectile.definition != null and projectile.definition.retarget_on_target_loss:
			var replacement_target: RwUnitState = _find_projectile_retarget(projectile)
			if replacement_target != null:
				projectile.retarget(replacement_target)
				target = replacement_target
		if not projectile.has_impacted and projectile.definition != null and projectile.definition.retarget_in_flight and not projectile.target_lost:
			projectile.retarget_search_timer = maxf(projectile.retarget_search_timer - _simulation_delta, 0.0)
			if projectile.retarget_search_timer == 0.0:
				projectile.retarget_search_timer = maxf(projectile.definition.retarget_in_flight_search_delay, 1.0)
				var in_flight_target: RwUnitState = _find_projectile_retarget(
					projectile,
					projectile.definition.retarget_in_flight_search_range,
					projectile.definition.retarget_in_flight_lead_distance,
				)
				if in_flight_target != null and in_flight_target.object_id != projectile.target_id:
					projectile.retarget(in_flight_target)
					target = in_flight_target
		var was_impacted: bool = projectile.has_impacted
		var parent: RwUnitState = _unit_states.get(projectile.owner_id) as RwUnitState
		var hit: bool = projectile.advance_frame(target, _simulation_delta, parent)
		if projectile.should_reveal_fog_this_frame(hit):
			projectile.fog_reveal_triggered = true
			projectile_fog_reveal_requested.emit(projectile)
		if projectile.remove_requested:
			projectile_finished.emit(projectile)
			projectiles.remove_at(projectile_index)
			continue
		if was_impacted and _has_area_expansion(projectile):
			_advance_area_expansion(projectile)
		var expired: bool = projectile.remaining_frames <= 0.0
		if hit and not projectile.has_impacted:
			projectile.has_impacted = true
			_resolve_impact(projectile, target)
			projectile_impacted.emit(projectile, target)
		var area_expansion_active: bool = _has_area_expansion(projectile)
		if expired:
			if not projectile.has_impacted and projectile.definition != null and projectile.definition.explode_on_end_of_life:
				projectile.has_impacted = true
				_resolve_impact(projectile, target)
				projectile_impacted.emit(projectile, target)
				area_expansion_active = _has_area_expansion(projectile)
			if not area_expansion_active:
				_spawn_terminal_projectiles(projectile)
				projectile_finished.emit(projectile)
				projectiles.remove_at(projectile_index)
		elif hit and projectile.definition.spawn_on_end_of_life.is_empty() and not area_expansion_active and not projectile.definition.instant_reuse_last:
			projectile_finished.emit(projectile)
			projectiles.remove_at(projectile_index)
		elif was_impacted and projectile.definition.spawn_on_end_of_life.is_empty() and not area_expansion_active and not projectile.definition.instant_reuse_last:
			projectile_finished.emit(projectile)
			projectiles.remove_at(projectile_index)


func _advance_projectile_interceptors(unit_ids: Array[int]) -> void:
	for unit_id: int in unit_ids:
		var unit_state: RwUnitState = _unit_states[unit_id] as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.build_progress < 1.0:
			continue
		var unit_definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
		if unit_definition == null:
			continue
		for interceptor: RwProjectileInterceptorDefinition in unit_definition.projectile_interceptors:
			if interceptor == null or interceptor.projectile == null or not _can_pay_interceptor_cost(unit_state, interceptor):
				continue
			var target_projectile: RwProjectileState
			for candidate: RwProjectileState in projectiles:
				if not _is_valid_interceptor_target(unit_state, interceptor, candidate):
					continue
				target_projectile = candidate
			if target_projectile == null:
				continue
			var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
			weapon.projectile = interceptor.projectile
			weapon.muzzle_offset = interceptor.muzzle_offset
			weapon.shoot_sound_name = interceptor.shoot_sound_name
			weapon.shoot_sound_volume = interceptor.shoot_sound_volume
			weapon.shoot_flame = interceptor.shoot_flame
			weapon.shoot_light_color = interceptor.shoot_light_color
			weapon.reload_frames = 1
			var firing_angle: float = rad_to_deg((target_projectile.world_position - unit_state.world_position).angle())
			var interceptor_projectile: RwProjectileState = spawn_projectile_at(
				unit_state,
				target_projectile.world_position,
				weapon,
				firing_angle,
				interceptor.projectile,
				target_projectile.height,
			)
			if interceptor_projectile == null:
				continue
			interceptor_projectile.intercept_target_projectile = target_projectile
			_consume_interceptor_cost(unit_state, interceptor)


func _is_valid_interceptor_target(
	unit_state: RwUnitState,
	interceptor: RwProjectileInterceptorDefinition,
	candidate: RwProjectileState,
) -> bool:
	if candidate == null or candidate.definition == null or candidate.remaining_frames <= 0.0 or candidate.remove_requested:
		return false
	if candidate.height <= interceptor.projectile_over_height:
		return false
	var has_matching_tag: bool
	for tag: String in interceptor.projectile_tags:
		if candidate.definition.tags.has(tag):
			has_matching_tag = true
			break
	if not has_matching_tag:
		return false
	var projectile_range_squared: float = interceptor.projectile_under_distance * interceptor.projectile_under_distance
	if unit_state.world_position.distance_squared_to(candidate.world_position) >= projectile_range_squared:
		return false
	if (
		interceptor.target_ground_under_distance >= 0.0
		and unit_state.world_position.distance_squared_to(candidate.target_position)
		>= interceptor.target_ground_under_distance * interceptor.target_ground_under_distance
	):
		return false
	var target_owner: RwUnitState = _unit_states.get(candidate.owner_id) as RwUnitState
	if target_owner != null and not _are_hostile(unit_state.team, target_owner.team):
		return false
	for existing_projectile: RwProjectileState in projectiles:
		if existing_projectile.intercept_target_projectile == candidate:
			return false
	return true


func _is_laser_defense_target(
	unit_state: RwUnitState,
	projectile: RwProjectileState,
	origin: Vector2,
	range_squared: float,
) -> bool:
	if (
		projectile == null
		or projectile.definition == null
		or projectile.definition.instant
		or projectile.definition.deflection_power < 0.5
		or projectile.remaining_frames <= 0.0
		or projectile.remove_requested
		or projectile.height < -1.0
	):
		return false
	if not (projectile.elapsed_frames > 7.0 or projectile.elapsed_frames > 2.0 and projectile.velocity.length() > 8.0):
		return false
	if origin.distance_squared_to(projectile.world_position) >= range_squared:
		return false
	var target: RwUnitState = _unit_states.get(projectile.target_id) as RwUnitState
	if target != null and _are_allied(unit_state.team, target.team):
		return true
	var owner: RwUnitState = _unit_states.get(projectile.owner_id) as RwUnitState
	var owner_team: String = owner.team if owner != null else projectile.team
	return _are_hostile(unit_state.team, owner_team)


func _are_allied(first_team: String, second_team: String) -> bool:
	if first_team == second_team:
		return true
	if not first_team.is_valid_int() or not second_team.is_valid_int():
		return false
	var first_alliance: int = -1
	var second_alliance: int = -2
	for player: Dictionary in _players:
		var slot: int = int(player.get("slot", -1))
		if slot == first_team.to_int():
			first_alliance = int(player.get("color", -1))
		elif slot == second_team.to_int():
			second_alliance = int(player.get("color", -2))
	return first_alliance >= 0 and first_alliance == second_alliance


func _can_pay_interceptor_cost(
	unit_state: RwUnitState,
	interceptor: RwProjectileInterceptorDefinition,
) -> bool:
	for resource_name: String in interceptor.resource_usage:
		var resource_cost: float = float(interceptor.resource_usage[resource_name])
		if resource_cost > float(unit_state.resource_balances.get(resource_name, 0.0)):
			return false
	return true


func _consume_interceptor_cost(
	unit_state: RwUnitState,
	interceptor: RwProjectileInterceptorDefinition,
) -> void:
	for resource_name: String in interceptor.resource_usage:
		var balance: float = float(unit_state.resource_balances.get(resource_name, 0.0))
		unit_state.resource_balances[resource_name] = maxf(balance - float(interceptor.resource_usage[resource_name]), 0.0)


func _spawn_terminal_projectiles(parent: RwProjectileState) -> void:
	if parent == null or parent.definition == null or parent.weapon_definition == null:
		return
	_spawn_projectile_children(parent, parent.definition.spawn_on_end_of_life)


func _spawn_projectile_children(parent: RwProjectileState, spawn_specs: Array[Dictionary]) -> void:
	if parent == null or parent.definition == null or parent.weapon_definition == null or spawn_specs.is_empty():
		return
	var source: RwUnitState = _unit_states.get(parent.owner_id) as RwUnitState
	if source == null:
		return
	var target: RwUnitState = _unit_states.get(parent.target_id) as RwUnitState
	if target != null and target.is_dead:
		target = null
	var spawned_count: int = 0
	var candidate_index: int = 0
	for spawn_spec: Dictionary in spawn_specs:
		var child_definition: RwProjectileDefinition = spawn_spec.get("projectile_definition") as RwProjectileDefinition
		if child_definition == null:
			continue
		var maximum_count: int = max(int(spawn_spec.get("max_spawn_limit", 2147483647)), 0)
		var requested_count: int = max(int(spawn_spec.get("count", 1)), 0)
		var spawn_chance: float = float(spawn_spec.get("spawn_chance", 1.0))
		var recursion_limit: int = int(spawn_spec.get("recursion_limit", 3))
		for _child_index: int in requested_count:
			candidate_index += 1
			if spawn_chance < 1.0 and _unit_random_range(source, 0.0, 1.0, candidate_index) > spawn_chance:
				continue
			if spawned_count >= maximum_count or parent.recursion_depth > recursion_limit:
				continue
			var seed: int = _next_projectile_seed()
			var child_weapon: RwWeaponDefinition = parent.weapon_definition.duplicate() as RwWeaponDefinition
			child_weapon.projectile = child_definition
			var parent_angle: float = deg_to_rad(parent.heading_degrees)
			var angle_degrees: float = rad_to_deg(parent_angle) + float(spawn_spec.get("offset_dir", 0.0))
			var random_direction: float = float(spawn_spec.get("offset_random_dir", 0.0))
			if random_direction != 0.0:
				angle_degrees += _unit_random_range(source, -random_direction, random_direction, candidate_index * 4 + 3)
			var absolute_offset: Vector2 = Vector2(
				float(spawn_spec.get("offset_x", 0.0)),
				float(spawn_spec.get("offset_y", 0.0)),
			)
			var relative_offset: Vector2 = Vector2(
				float(spawn_spec.get("offset_y_relative", 0.0)),
				float(spawn_spec.get("offset_x_relative", 0.0)),
			).rotated(parent_angle)
			var random_offset: Vector2 = Vector2.ZERO
			var random_x: float = float(spawn_spec.get("offset_random_x", 0.0))
			if random_x != 0.0:
				random_offset.x = _unit_random_range(source, -random_x, random_x, candidate_index * 2 + 1)
			var random_y: float = float(spawn_spec.get("offset_random_y", 0.0))
			if random_y != 0.0:
				random_offset.y = _unit_random_range(source, -random_y, random_y, candidate_index * 3 + 2)
			var child_position: Vector2 = parent.world_position + absolute_offset + relative_offset + random_offset
			var child: RwProjectileState = RwProjectileState.new()
			if target != null:
				child.configure(
					source,
					target,
					child_weapon,
					angle_degrees,
					child_definition,
					seed,
					_simulation_frame,
					_global_random_seed,
					false,
					child_position,
					true,
				)
			else:
				child.configure_at(
					source,
					child_position,
					child_weapon,
					angle_degrees,
					child_definition,
					parent.height,
					seed,
					_simulation_frame,
					_global_random_seed,
				)
			_configure_source_damage_multiplier(child, source)
			child.world_position = child_position
			child.origin_position = child_position
			child.height = parent.height + float(spawn_spec.get("offset_height", 0.0))
			child.recursion_depth = parent.recursion_depth + 1
			projectiles.append(child)
			projectile_fired.emit(child)
			spawned_count += 1
			_spawn_projectile_children(child, child_definition.spawn_on_create)


func _unit_random_range(source: RwUnitState, minimum: float, maximum: float, stream: int) -> float:
	var minimum_milli: int = int(minimum * 1000.0)
	var maximum_milli: int = int(maximum * 1000.0)
	var value: int = RwVanillaRandom.unit_range(
		minimum_milli,
		maximum_milli,
		source.object_id,
		source.world_position,
		source.random_counter,
		_simulation_frame,
		_global_random_seed,
		stream,
	)
	return float(value) * 0.001


func _find_projectile_retarget(
	projectile: RwProjectileState,
	search_range: float = -1.0,
	lead_distance: float = -1.0,
) -> RwUnitState:
	var source: RwUnitState = _unit_states.get(projectile.owner_id) as RwUnitState
	var projectile_definition: RwProjectileDefinition = projectile.definition
	var weapon: RwWeaponDefinition = projectile.weapon_definition
	if source == null or projectile_definition == null or weapon == null:
		return null
	var resolved_range: float = projectile_definition.target_loss_retarget_range if search_range <= 0.0 else search_range
	var resolved_lead: float = (
		projectile_definition.target_loss_retarget_lead_distance
		if lead_distance < 0.0
		else lead_distance
	)
	var search_range_squared: float = resolved_range * resolved_range
	var best_distance_squared: float = search_range_squared
	var best_target: RwUnitState
	var preferred_target_id: int = source.order_target_id
	if preferred_target_id <= 0 and source.navigation_attack_target_id > 0:
		preferred_target_id = source.navigation_attack_target_id
	var search_origin: Vector2 = projectile.world_position + projectile.velocity.normalized() * resolved_lead
	for unit_id: int in _sorted_unit_ids():
		var candidate: RwUnitState = _unit_states[unit_id] as RwUnitState
		if candidate == null or candidate.is_dead or candidate.object_id == source.object_id or not _are_hostile(source.team, candidate.team):
			continue
		if candidate.movement_type == "AIR" and not weapon.can_target_air:
			continue
		if candidate.submerged and not weapon.can_target_water:
			continue
		if candidate.movement_type != "AIR" and not candidate.submerged and not weapon.can_target_ground:
			continue
		var distance_squared: float = search_origin.distance_squared_to(candidate.world_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_target = candidate
		if candidate.object_id == preferred_target_id and distance_squared < search_range_squared:
			return candidate
	return best_target


func _resolve_impact(projectile: RwProjectileState, direct_target: RwUnitState) -> void:
	var definition: RwProjectileDefinition = projectile.definition
	if definition == null:
		return
	var intercepted_projectile: RwProjectileState = projectile.intercept_target_projectile
	if intercepted_projectile != null and not intercepted_projectile.remove_requested:
		if definition.intercept_projectile_remove_target_life_only:
			intercepted_projectile.remaining_frames = 0.0
		else:
			intercepted_projectile.remove_requested = true
	var source: RwUnitState = _unit_states.get(projectile.owner_id) as RwUnitState
	projectile.hit_shield = direct_target != null and direct_target.shield > 10.0
	if definition.teleport_source and source != null:
		source.world_position = projectile.world_position
	if definition.convert_hit_to_source_team and source != null and direct_target != null:
		direct_target.team = source.team
	_spawn_projectile_children(projectile, definition.spawn_on_explode)
	for spawn_spec: Dictionary in definition.spawn_units_on_explode:
		projectile_unit_spawn_requested.emit(projectile, spawn_spec)
	if not definition.target_ground and definition.damage > 0.0 and direct_target != null:
		_damage_unit(
			direct_target,
			definition.damage * projectile.source_damage_multiplier,
			definition,
			projectile.world_position,
			projectile.velocity.angle(),
		)
	if definition.area_expand_time > 0.0:
		projectile.area_expansion_elapsed_frames = minf(_simulation_delta, definition.area_expand_time)
		_apply_splash_damage(projectile, projectile.area_expansion_elapsed_frames / definition.area_expand_time)
	else:
		_apply_splash_damage(projectile, 1.0)


func _has_area_expansion(projectile: RwProjectileState) -> bool:
	return (
		projectile != null
		and projectile.has_impacted
		and projectile.definition != null
		and projectile.definition.area_expand_time > 0.0
		and projectile.area_expansion_elapsed_frames < projectile.definition.area_expand_time
	)


func _advance_area_expansion(projectile: RwProjectileState) -> void:
	var definition: RwProjectileDefinition = projectile.definition
	projectile.area_expansion_elapsed_frames = minf(
		projectile.area_expansion_elapsed_frames + _simulation_delta,
		definition.area_expand_time,
	)
	_apply_splash_damage(projectile, projectile.area_expansion_elapsed_frames / definition.area_expand_time)


func _apply_splash_damage(projectile: RwProjectileState, expansion_progress: float) -> void:
	var definition: RwProjectileDefinition = projectile.definition
	var splash_radius: float = definition.splash_radius
	var splash_damage: float = definition.splash_damage
	if splash_radius <= 0.0 or splash_damage <= 0.0:
		return
	var current_radius: float = splash_radius * clampf(expansion_progress, 0.0, 1.0)
	for unit_id: int in _sorted_unit_ids():
		var candidate: RwUnitState = _unit_states[unit_id] as RwUnitState
		if definition.area_expand_time > 0.0 and projectile.area_damaged_unit_ids.has(candidate.object_id):
			continue
		if not _can_receive_splash(projectile, candidate, definition):
			continue
		var distance: float = candidate.world_position.distance_to(projectile.world_position)
		if definition.area_radius_from_edge:
			distance = maxf(distance - candidate.collision_radius, 0.0)
		if distance > current_radius or distance < definition.area_minimum_distance:
			continue
		var damage_factor: float = 1.0
		if not definition.area_damage_no_falloff:
			damage_factor = clampf(1.1 - distance / splash_radius, 0.0, 1.0)
		_damage_unit(
			candidate,
			splash_damage * projectile.source_damage_multiplier * damage_factor,
			definition,
			projectile.world_position,
			projectile.velocity.angle(),
		)
		if definition.area_expand_time > 0.0:
			projectile.area_damaged_unit_ids[candidate.object_id] = true


func _can_receive_splash(
	projectile: RwProjectileState,
	candidate: RwUnitState,
	definition: RwProjectileDefinition,
) -> bool:
	if candidate == null or candidate.is_dead:
		return false
	var hostile: bool = _are_hostile(projectile.team, candidate.team)
	var same_player: bool = projectile.team == candidate.team
	if definition.friendly_fire_mode == "only-ignore-enemy":
		if hostile:
			return false
	elif not definition.friendly_fire and not hostile:
		return false
	elif definition.friendly_fire and not same_player and not hostile:
		return false
	if not definition.area_hit_air_and_land_at_same_time:
		var impact_is_air: bool = projectile.height >= 5.0
		if (candidate.movement_type == "AIR") != impact_is_air:
			return false
	var underwater: bool = candidate.submerged or candidate.altitude < -5.0
	if underwater and projectile.height >= -2.0 and not definition.area_hit_underwater_always:
		return false
	return true


func _damage_unit(
	unit_state: RwUnitState,
	amount: float,
	projectile_definition: RwProjectileDefinition = null,
	impact_position: Vector2 = Vector2.ZERO,
	impact_angle: float = 0.0,
) -> void:
	if unit_state == null or unit_state.is_dead or amount <= 0.0:
		return
	var resolved_damage: float = amount
	var projectile_shield_handled: bool
	if projectile_definition != null:
		if unit_state.is_building:
			resolved_damage *= projectile_definition.building_damage_multiplier
		if unit_state.movement_type == "AIR":
			resolved_damage *= projectile_definition.air_damage_multiplier
		if unit_state.build_progress < 1.0:
			resolved_damage *= 1.75
		var shield_before: float = unit_state.shield
		if shield_before > 0.0:
			projectile_shield_handled = true
			var shield_damage: float = resolved_damage * projectile_definition.shield_damage_multiplier
			unit_state.set_shield(maxf(shield_before - shield_damage, 0.0))
			if shield_before < shield_damage:
				resolved_damage -= shield_before * projectile_definition.shield_deflection_multiplier
			else:
				resolved_damage *= 1.0 - projectile_definition.shield_deflection_multiplier
		resolved_damage *= projectile_definition.hull_damage_multiplier
		resolved_damage *= projectile_definition.global_damage_multiplier
		_apply_projectile_push(unit_state, projectile_definition, impact_position, impact_angle)
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	var behavior: RwUnitBehavior = definition.behavior if definition != null else null
	var filtered_damage: float = resolved_damage
	if behavior != null:
		if projectile_definition != null:
			filtered_damage = behavior.filter_projectile_damage(
				unit_state,
				resolved_damage,
				projectile_definition,
				self,
				projectile_shield_handled,
			)
		else:
			filtered_damage = behavior.filter_damage(unit_state, resolved_damage, self)
	var actual_damage: float = maxf(filtered_damage, 0.0)
	var previous_health: float = unit_state.health
	var was_destroyed: bool = unit_state.apply_damage(actual_damage)
	if unit_state.health >= previous_health:
		return
	if behavior != null:
		behavior.on_damaged(unit_state, previous_health - unit_state.health, self)
	if not was_destroyed:
		return
	if definition != null and definition.behavior != null:
		definition.behavior.on_destroyed(unit_state, definition, self)
	_weapon_runtime.erase(unit_state.object_id)
	_idle_sweep_runtime.erase(unit_state.object_id)
	unit_destroyed.emit(unit_state)


func _apply_projectile_push(
	unit_state: RwUnitState,
	projectile_definition: RwProjectileDefinition,
	impact_position: Vector2,
	impact_angle: float,
) -> void:
	if unit_state.is_building or projectile_definition.push_force <= 0.0 and projectile_definition.push_velocity <= 0.0:
		return
	var push_direction: Vector2 = unit_state.world_position - impact_position
	if push_direction.length_squared() > 100.0:
		push_direction = push_direction.normalized()
	else:
		push_direction = Vector2.RIGHT.rotated(impact_angle)
	var push_amount: float = projectile_definition.push_velocity + projectile_definition.push_force / maxf(unit_state.push_mass, 1.0)
	unit_state.collision_push_offset += push_direction * push_amount
