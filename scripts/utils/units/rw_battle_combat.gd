class_name RwBattleCombat
extends RwCombatContext
## 在同步帧内统一处理索敌、武器冷却、弹体飞行和伤害

## 弹体生成后发出，绘制和音效层可订阅
signal projectile_fired(projectile: RwProjectileState)
## 弹体命中后发出，可用于命中特效和音效
signal projectile_impacted(projectile: RwProjectileState, target: RwUnitState)
## 单位首次死亡后发出，地图负责移除阻挡和更新界面
signal unit_destroyed(unit_state: RwUnitState)

## 当前仍在飞行的弹体，按发射顺序排列
var projectiles: Array[RwProjectileState]

var _unit_states: Dictionary
var _registry: RwUnitRegistry
var _players: Array[Dictionary]
var _weapon_runtime: Dictionary
var _sorted_ids: Array[int]
var _sorted_ids_dirty: bool = true


## 绑定地图单位与定义，并注册已有单位
func configure(unit_states: Dictionary, registry: RwUnitRegistry, players: Array[Dictionary]) -> void:
	_unit_states = unit_states
	_registry = registry
	_players = players.duplicate(true)
	_weapon_runtime.clear()
	projectiles.clear()
	_sorted_ids_dirty = true
	var unit_ids: Array[int] = _sorted_unit_ids()
	for unit_id: int in unit_ids:
		register_unit(_unit_states[unit_id] as RwUnitState)


## 更新玩家队伍与联盟关系
func set_players(players: Array[Dictionary]) -> void:
	_players = players.duplicate(true)


## 注册刚生成的单位，冷却和索敌状态只属于该单位
func register_unit(unit_state: RwUnitState) -> void:
	if unit_state == null or _registry == null or _weapon_runtime.has(unit_state.object_id):
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	var runtime: Dictionary = {}
	if definition != null:
		for weapon_index: int in definition.combat_weapons.size():
			runtime[weapon_index] = 0
	_weapon_runtime[unit_state.object_id] = runtime
	_sorted_ids_dirty = true
	if definition != null and definition.behavior != null:
		definition.behavior.on_spawned(unit_state, definition, self)


## 形态切换后重建该单位的武器冷却状态
func reset_unit(unit_state: RwUnitState) -> void:
	if unit_state == null:
		return
	_weapon_runtime.erase(unit_state.object_id)
	register_unit(unit_state)


## 通知单位行为已经收到同步命令
func notify_order(unit_state: RwUnitState, order_type: String, order: Dictionary = {}) -> void:
	if unit_state == null or _registry == null:
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	if definition != null and definition.behavior != null:
		definition.behavior.on_ordered(unit_state, definition, order_type, order, self)


## 按固定顺序推进所有单位行为，然后推进弹体
func advance_frame() -> void:
	if _registry == null:
		return
	var unit_ids: Array[int] = _sorted_unit_ids()
	for unit_id: int in unit_ids:
		var unit_state: RwUnitState = _unit_states[unit_id] as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.build_progress < 1.0:
			continue
		var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
		if definition != null and definition.behavior != null:
			definition.behavior.advance_frame(unit_state, definition, self)
	_advance_projectiles()


## 为通用自动攻击行为推进一帧武器逻辑
func advance_weapons(unit_state: RwUnitState, definition: RwUnitDefinition) -> void:
	var runtime: Dictionary = _weapon_runtime.get(unit_state.object_id, {})
	for weapon_index: int in definition.combat_weapons.size():
		var weapon: RwWeaponDefinition = definition.combat_weapons[weapon_index]
		if weapon == null or weapon.projectile == null or weapon.attack_range <= 0.0:
			continue
		var cooldown: int = int(runtime.get(weapon_index, 0))
		if cooldown > 0:
			cooldown -= 1
			runtime[weapon_index] = cooldown
		var target: RwUnitState = _find_target(unit_state, weapon)
		if target == null:
			continue
		var desired_angle: float = rad_to_deg((target.world_position - unit_state.world_position).angle())
		var current_angle: float = unit_state.get_weapon_rotation(weapon.rotation_state_index)
		var _angle_difference: float = wrapf(desired_angle - current_angle, -180.0, 180.0)
		var turn_step: float = _angle_difference
		if weapon.turn_speed_degrees > 0.0:
			turn_step = clampf(_angle_difference, -weapon.turn_speed_degrees, weapon.turn_speed_degrees)
		var next_angle: float = wrapf(current_angle + turn_step, -180.0, 180.0)
		unit_state.set_weapon_rotation(weapon.rotation_state_index, next_angle)
		if cooldown > 0 or absf(wrapf(desired_angle - next_angle, -180.0, 180.0)) > weapon.aim_tolerance_degrees:
			continue
		var projectile: RwProjectileState = spawn_projectile(unit_state, target, weapon, next_angle)
		if projectile == null:
			continue
		runtime[weapon_index] = maxi(weapon.reload_frames, 1)
	_weapon_runtime[unit_state.object_id] = runtime


## 按对象编号读取单位状态
func find_unit(object_id: int) -> RwUnitState:
	return _unit_states.get(object_id) as RwUnitState


## 生成追踪目标单位的弹体并通知表现层
func spawn_projectile(
	source: RwUnitState,
	target: RwUnitState,
	weapon: RwWeaponDefinition,
	angle_degrees: float
) -> RwProjectileState:
	if source == null or source.is_dead or target == null or target.is_dead or weapon == null or weapon.projectile == null:
		return null
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, angle_degrees)
	projectiles.append(projectile)
	projectile_fired.emit(projectile)
	return projectile


## 生成射向地面目标的弹体并通知表现层
func spawn_projectile_at(
	source: RwUnitState,
	target_position: Vector2,
	weapon: RwWeaponDefinition,
	angle_degrees: float
) -> RwProjectileState:
	if source == null or source.is_dead or weapon == null or weapon.projectile == null:
		return null
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure_at(source, target_position, weapon, angle_degrees)
	projectiles.append(projectile)
	projectile_fired.emit(projectile)
	return projectile


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


func _find_target(source: RwUnitState, weapon: RwWeaponDefinition) -> RwUnitState:
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


func _can_target(source: RwUnitState, target: RwUnitState, weapon: RwWeaponDefinition) -> bool:
	if target == null or target.is_dead or target.object_id == source.object_id:
		return false
	if not _are_hostile(source.team, target.team):
		return false
	match target.movement_type:
		"AIR":
			if not weapon.can_target_air:
				return false
		"WATER":
			if not weapon.can_target_water:
				return false
		_:
			if not weapon.can_target_ground:
				return false
	var distance_squared: float = source.world_position.distance_squared_to(target.world_position)
	return (
		distance_squared <= weapon.attack_range * weapon.attack_range
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
		var target: RwUnitState = _unit_states.get(projectile.target_id) as RwUnitState
		var hit: bool = projectile.advance_frame(target)
		if hit:
			_resolve_impact(projectile, target)
			projectile_impacted.emit(projectile, target)
		if hit or projectile.remaining_frames <= 0:
			projectiles.remove_at(projectile_index)


func _resolve_impact(projectile: RwProjectileState, direct_target: RwUnitState) -> void:
	var splash_radius: float = projectile.definition.splash_radius
	if splash_radius <= 0.0:
		_damage_unit(direct_target, projectile.definition.damage)
		return
	for unit_id: int in _sorted_unit_ids():
		var candidate: RwUnitState = _unit_states[unit_id] as RwUnitState
		if candidate == null or candidate.is_dead or not _are_hostile(projectile.team, candidate.team):
			continue
		if candidate.world_position.distance_to(projectile.world_position) <= splash_radius + candidate.collision_radius:
			_damage_unit(candidate, projectile.definition.damage)


func _damage_unit(unit_state: RwUnitState, amount: float) -> void:
	if unit_state == null or unit_state.is_dead or amount <= 0.0:
		return
	var definition: RwUnitDefinition = _registry.find_definition(unit_state.source_id, unit_state.unit_name)
	var behavior: RwUnitBehavior = definition.behavior if definition != null else null
	var actual_damage: float = maxf(behavior.filter_damage(unit_state, amount, self), 0.0) if behavior != null else amount
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
	unit_destroyed.emit(unit_state)
