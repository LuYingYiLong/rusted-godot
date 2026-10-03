extends SceneTree
## 检查内置武器映射和确定性的基础命中规则


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_builtin_weapons()
	_test_target_layers()
	_test_instant_and_area_damage()
	_test_guided_missile()
	_test_weapon_warmup()
	_test_idle_turret_rotation()
	_test_idle_turret_sweep()
	_test_idle_turret_step_rate()
	_test_projectile_step_rate()
	_test_native_turret_idle()
	print("BUILTIN_COMBAT_CHECK_OK")
	quit()


func _test_builtin_weapons() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var custom_tank: RwUnitDefinition = registry.find_definition("custom", "c_tank")
	var native_tank: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var anti_air: RwUnitDefinition = registry.find_definition("custom", "c_antiAirTurret")
	var interceptor: RwUnitDefinition = registry.find_definition("custom", "c_interceptor")
	var battleship: RwUnitDefinition = registry.find_definition("custom", "heavyBattleship")
	assert(custom_tank.combat_weapons.size() == 1)
	assert(native_tank.combat_weapons.size() == 1)
	assert(custom_tank.combat_weapons[0].projectile.damage == 25.0)
	assert(native_tank.combat_weapons[0].projectile.damage == 25.0)
	assert(native_tank.combat_weapons[0].reload_frames == 75)
	assert(anti_air.combat_weapons.size() > 0)
	assert(anti_air.combat_weapons[0].can_target_air)
	assert(not anti_air.combat_weapons[0].can_target_ground)
	assert(is_equal_approx(interceptor.combat_weapons[0].turn_speed_degrees, 8.0))
	assert(battleship.combat_weapons.size() > 1)
	for weapon: RwWeaponDefinition in battleship.combat_weapons:
		assert(weapon.projectile != null)
	assert(RwBuiltinCombatDefinitions._projectile_color("#551E1E96") == Color8(30, 30, 150, 85))


func _test_target_layers() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var air_definition: RwUnitDefinition = registry.find_definition("custom", "c_helicopter")
	var water_definition: RwUnitDefinition = registry.find_definition("custom", "heavySub")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var aircraft: RwUnitState = _unit(2, "custom", "c_helicopter", "2", Vector2(50.0, 0.0), air_definition)
	var ship: RwUnitState = _unit(3, "custom", "heavySub", "2", Vector2(50.0, 0.0), water_definition)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: aircraft, 3: ship,}, registry, _players())
	var weapon: RwWeaponDefinition = tank_definition.combat_weapons[0]
	assert(not bool(combat.call("_can_target", source, aircraft, weapon)))
	ship.submerged = false
	assert(bool(combat.call("_can_target", source, ship, weapon)))
	ship.submerged = true
	assert(not bool(combat.call("_can_target", source, ship, weapon)))


func _test_instant_and_area_damage() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(40.0, 0.0), tank_definition)
	var nearby: RwUnitState = _unit(3, "vanilla", "tank", "2", Vector2(55.0, 0.0), tank_definition)
	var ally: RwUnitState = _unit(4, "vanilla", "tank", "1", Vector2(45.0, 0.0), tank_definition)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: target, 3: nearby, 4: ally,}, registry, _players())
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.damage = 20.0
	projectile_definition.splash_damage = 10.0
	projectile_definition.splash_radius = 20.0
	projectile_definition.instant = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = combat.spawn_projectile(source, target, weapon, 0.0)
	assert(projectile != null)
	combat.advance_frame()
	assert(combat.projectiles.is_empty())
	assert(target.health == 180.0)
	assert(nearby.health == 200.0)
	assert(ally.health == 210.0)
	projectile_definition.damage = 0.0
	projectile_definition.area_damage_no_falloff = false
	combat.spawn_projectile_at(source, Vector2(40.0, 0.0), weapon, 0.0)
	combat.advance_frame()
	assert(is_equal_approx(target.health, 170.0))
	assert(is_equal_approx(nearby.health, 196.5))
	assert(ally.health == 210.0)


func _test_guided_missile() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var anti_air_definition: RwUnitDefinition = registry.find_definition("custom", "c_antiAirTurret")
	var aircraft_definition: RwUnitDefinition = registry.find_definition("custom", "c_helicopter")
	var source: RwUnitState = _unit(1, "custom", "c_antiAirTurret", "1", Vector2.ZERO, anti_air_definition)
	var target: RwUnitState = _unit(2, "custom", "c_helicopter", "2", Vector2(180.0, 0.0), aircraft_definition)
	source.build_progress = 1.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: target,}, registry, _players())
	var projectile_definition: RwProjectileDefinition = anti_air_definition.combat_weapons[0].projectile
	assert(projectile_definition.target_speed_per_frame == 6.0)
	assert(projectile_definition.speed_acceleration_per_frame == 0.1)
	for frame: int in 180:
		combat.advance_frame()
	assert(target.health < target.max_health)


func _test_weapon_warmup() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var turret_definition: RwUnitDefinition = registry.find_definition("custom", "c_turret_t1_lightning")
	var target_definition: RwUnitDefinition = registry.find_definition("custom", "c_tank")
	var turret: RwUnitState = _unit(1, "custom", "c_turret_t1_lightning", "1", Vector2.ZERO, turret_definition)
	var target: RwUnitState = _unit(2, "custom", "c_tank", "2", Vector2(100.0, 0.0), target_definition)
	turret.build_progress = 1.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: turret, 2: target,}, registry, _players())
	assert(turret_definition.combat_weapons[0].warmup_frames == 30)
	for frame: int in 29:
		combat.advance_frame()
	assert(target.health == target.max_health)
	combat.advance_frame()
	assert(target.health < target.max_health)


func _test_idle_turret_rotation() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var turret_definition: RwUnitDefinition = registry.find_definition("custom", "c_turret_t1_lightning")
	var turret: RwUnitState = _unit(1, "custom", "c_turret_t1_lightning", "1", Vector2.ZERO, turret_definition)
	turret.build_progress = 1.0
	assert(is_equal_approx(turret_definition.weapon_parts[0].idle_spin_degrees, 0.8))
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: turret,}, registry, _players())
	combat.advance_frame()
	assert(is_equal_approx(turret.get_weapon_rotation(0), 0.8))
	combat.advance_frame()
	assert(is_equal_approx(turret.get_weapon_rotation(0), 1.6))
	var anti_air_definition: RwUnitDefinition = registry.find_definition("custom", "c_antiAirTurretT2")
	var anti_air: RwUnitState = _unit(2, "custom", "c_antiAirTurretT2", "1", Vector2.ZERO, anti_air_definition)
	anti_air.build_progress = 1.0
	assert(is_equal_approx(anti_air_definition.weapon_parts[0].idle_spin_degrees, 0.8))
	combat.configure({2: anti_air,}, registry, _players())
	combat.advance_frame()
	assert(is_equal_approx(anti_air.get_weapon_rotation(0), 0.8))


func _test_idle_turret_sweep() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("custom", "c_turret_t1")
	var turret: RwUnitState = _unit(9, "custom", "c_turret_t1", "1", Vector2.ZERO, definition)
	turret.build_progress = 1.0
	assert(is_equal_approx(definition.weapon_parts[0].idle_sweep_angle_degrees, 20.0))
	assert(is_equal_approx(definition.weapon_parts[0].idle_sweep_delay, 210.0))
	var initial_angle: float = turret.get_weapon_rotation(0)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({9: turret,}, registry, _players())
	for frame: int in 211:
		combat.advance_frame()
	assert(is_equal_approx(turret.get_weapon_rotation(0), initial_angle))
	combat.advance_frame()
	assert(is_equal_approx(turret.get_weapon_rotation(0), initial_angle + 0.2))


func _test_native_turret_idle() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("vanilla", "turret")
	var turret: RwUnitState = _unit(1, "vanilla", "turret", "1", Vector2.ZERO, definition)
	turret.build_progress = 1.0
	assert(turret.get_weapon_rotation(0) != 0.0)
	var original_angle: float = turret.get_weapon_rotation(0)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: turret,}, registry, _players())
	combat.advance_frame()
	assert(is_equal_approx(turret.get_weapon_rotation(0), original_angle))
	var anti_air_definition: RwUnitDefinition = registry.find_definition("vanilla", "antiAirTurret")
	var anti_air: RwUnitState = _unit(2, "vanilla", "antiAirTurret", "1", Vector2.ZERO, anti_air_definition)
	anti_air.build_progress = 1.0
	assert(is_equal_approx(anti_air_definition.weapon_parts[0].idle_spin_degrees, 0.6))
	var anti_air_angle: float = anti_air.get_weapon_rotation(0)
	combat.configure({2: anti_air,}, registry, _players())
	combat.advance_frame()
	assert(is_equal_approx(anti_air.get_weapon_rotation(0), anti_air_angle + 0.6))


func _test_idle_turret_step_rate() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("custom", "c_antiAirTurret")
	var turret: RwUnitState = _unit(7, "custom", "c_antiAirTurret", "1", Vector2.ZERO, definition)
	turret.build_progress = 1.0
	var initial_angle: float = turret.get_weapon_rotation(0)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({7: turret,}, registry, _players())
	for frame: int in 10:
		combat.advance_frame(2.0)
	assert(is_equal_approx(turret.get_weapon_rotation(0), initial_angle + 16.0))


func _test_projectile_step_rate() -> void:
	var definition: RwUnitDefinition = RwVanillaUnitDefinitions.create_registry().find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(8, "vanilla", "tank", "1", Vector2.ZERO, definition)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 2.0
	projectile_definition.lifetime_frames = 10
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure_at(source, Vector2(100.0, 0.0), weapon, 0.0)
	var origin: Vector2 = projectile.world_position
	assert(not projectile.advance_frame(null, 2.0))
	assert(is_equal_approx(projectile.world_position.x - origin.x, 4.0))
	assert(is_equal_approx(projectile.remaining_frames, 8.0))


func _unit(
	object_id: int,
	source_id: String,
	unit_name: String,
	team: String,
	position: Vector2,
	definition: RwUnitDefinition
) -> RwUnitState:
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.initialize_from_spawn({
		"object_id": object_id,
		"source_id": source_id,
		"unit_name": unit_name,
		"team": team,
		"position": position,
		"build_progress": 0.5,
	}, definition)
	return unit_state


func _players() -> Array[Dictionary]:
	return [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
