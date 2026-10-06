extends SceneTree
## 检查内置武器映射和确定性的基础命中规则

var _projectile_spawn_requests: Array[Dictionary]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_server_random_seed_packet()
	_test_vanilla_synchronized_random()
	_test_projectile_factory_phase_and_muzzle()
	_test_projectile_delay_sweep_and_parent_motion()
	_test_instant_projectile_reuse()
	_test_instant_reuse_changes_turret_aim()
	_test_builtin_weapons()
	_test_target_layers()
	_test_instant_and_area_damage()
	_test_guided_missile()
	_test_weapon_warmup()
	_test_idle_turret_rotation()
	_test_idle_turret_sweep()
	_test_idle_turret_step_rate()
	_test_projectile_step_rate()
	_test_projectile_split_on_expiry()
	_test_synchronized_projectile_child_spawn()
	_test_tank_projectile_collision_after_movement()
	_test_native_building_projectile_radius()
	_test_expanding_projectile_area_damage()
	_test_projectile_turn_speed_when_near()
	_test_projectile_unit_spawn()
	_test_projectile_interception()
	_test_projectile_initial_velocity_axes()
	_test_ground_target_snapshot_and_lead()
	_test_native_turret_idle()
	print("BUILTIN_COMBAT_CHECK_OK")
	quit()


func _test_server_random_seed_packet() -> void:
	var room_client: Node = root.get_node("RwRoomClient")
	var stream: StreamPeerBuffer = RwBinary.writer()
	RwBinary.write_utf(stream, "com.corrodinggames.rts")
	stream.put_32(176)
	stream.put_32(0)
	RwBinary.write_utf(stream, "Small Island (2p)")
	stream.put_32(0)
	stream.put_32(0)
	stream.put_u8(1)
	stream.put_32(1)
	stream.put_u8(8)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_32(1000)
	stream.put_32(1000)
	stream.put_32(1)
	stream.put_float(1.0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_u8(0)
	stream.put_32(123456789)
	room_client.call("_read_server_settings", stream.data_array)
	var settings: Dictionary = room_client.get("settings")
	assert(int(settings.get("random_seed", 0)) == 123456789)
	assert(RwVanillaRandom.unit_range(0, 1000, 42, Vector2(100.0, 200.0), 7, 1, 123456789, 2) == 129)


func _test_vanilla_synchronized_random() -> void:
	assert(RwVanillaRandom.unit_range(-3000, 3000, 42, Vector2(100.0, 200.0), 7, 1, 0, 2) == 343)
	assert(RwVanillaRandom.unit_range(-3000, 3000, 42, Vector2(100.0, 200.0), 7, 1, 0, 7) == -1312)
	assert(RwVanillaRandom.advance_projectile_counter(50, 42) == 93)
	var source: RwUnitState = _unit(42, "custom", "c_tank", "1", Vector2(100.0, 200.0), null)
	source.random_counter = 50
	var target: RwUnitState = _unit(43, "vanilla", "tank", "2", Vector2(500.0, 500.0), null)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.target_ground = true
	projectile_definition.target_ground_spread = 30.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0, null, 1, 1, 0)
	assert(is_equal_approx(projectile.source_random_phase, 0.174))
	assert(is_equal_approx(projectile.target_position.x, 521.95))
	assert(is_equal_approx(projectile.target_position.y, 505.4))
	assert(source.random_counter == 51)
	var coordinate_source: RwUnitState = _unit(42, "custom", "customTank", "1", Vector2(100.0, 200.0), null)
	coordinate_source.random_counter = 50
	var coordinate_projectile: RwProjectileState = RwProjectileState.new()
	coordinate_projectile.configure_at(coordinate_source, Vector2(500.0, 500.0), weapon, 0.0, null, 0.0, 1, 1, 0)
	var expected_x: float = RwGameMath.float32(
		500.0
		+ float(RwVanillaRandom.unit_range(-3000, 3000, 42, Vector2(100.0, 200.0), 51, 1, 0, 2)) / 100.0
	)
	var expected_counter: int = int(RwGameMath.float32(51.0 + expected_x))
	var expected_y: float = RwGameMath.float32(
		500.0
		+ float(
			RwVanillaRandom.unit_range(-3000, 3000, 42, Vector2(100.0, 200.0), expected_counter, 1, 0, 3)
		) / 100.0
	)
	expected_counter = int(RwGameMath.float32(float(expected_counter) + expected_y))
	assert(coordinate_projectile.target_position.distance_to(Vector2(expected_x, expected_y)) < 0.001)
	assert(coordinate_source.random_counter == expected_counter)
	var firing_definition: RwUnitDefinition = RwUnitDefinition.new()
	var speed_projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	speed_projectile_definition.speed_per_frame = 100.0
	speed_projectile_definition.speed_spread = 30.0
	var speed_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	speed_weapon.projectile = speed_projectile_definition
	speed_weapon.attack_range = 1000.0
	speed_weapon.turn_speed_degrees = 0.0
	speed_weapon.aim_tolerance_degrees = 180.0
	firing_definition.combat_weapons.append(speed_weapon)
	var firing_source: RwUnitState = _unit(42, "custom", "testUnit", "1", Vector2(100.0, 200.0), firing_definition)
	firing_source.random_counter = 50
	firing_source.build_progress = 1.0
	var firing_target: RwUnitState = _unit(43, "vanilla", "testTarget", "2", Vector2(500.0, 200.0), null)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({42: firing_source, 43: firing_target,}, RwVanillaUnitDefinitions.create_registry(), _players())
	combat.set_simulation_context(1)
	combat.advance_weapons(firing_source, firing_definition)
	assert(firing_source.random_counter == 94)
	assert(combat.projectiles.size() == 1)
	assert(is_equal_approx(combat.projectiles[0].source_random_phase, 0.66))
	assert(is_equal_approx(combat.projectiles[0].velocity.length(), 72.45))


func _test_projectile_factory_phase_and_muzzle() -> void:
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	weapon.muzzle_offset = Vector2(4.0, 0.0)
	var source: RwUnitState = _unit(42, "vanilla", "tank", "1", Vector2(100.0, 200.0), null)
	var target: RwUnitState = _unit(43, "vanilla", "tank", "2", Vector2(500.0, 200.0), null)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 90.0, null, 1, 1, 0)
	assert(is_equal_approx(projectile.source_random_phase, 0.074))
	assert(source.random_counter == 1)
	assert(projectile.origin_position.distance_to(Vector2(100.0, 204.0)) < 0.001)


func _test_projectile_delay_sweep_and_parent_motion() -> void:
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 0.0
	projectile_definition.delayed_start_frames = 2.0
	projectile_definition.sweep_offset_from_target_radius = 0.4
	projectile_definition.move_with_parent = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	weapon.muzzle_offset = Vector2(4.0, 0.0)
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, null)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(100.0, 0.0), null)
	target.collision_radius = 10.0
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	projectile.source_random_phase = 0.25
	var sweep_offset: Vector2 = projectile.call("_calculate_sweep_offset", target, 0.0)
	assert(sweep_offset.distance_to(Vector2(4.0, 4.0)) < 0.001)
	assert(projectile.advance_frame(target, 1.0, source) == false)
	assert(projectile.world_position == Vector2(4.0, 0.0))
	source.world_position = Vector2(10.0, 0.0)
	assert(projectile.advance_frame(target, 1.0, source) == false)
	assert(projectile.world_position == Vector2(14.0, 0.0))
	assert(projectile.elapsed_frames == 1.0)
	assert(projectile.remaining_frames == projectile_definition.lifetime_frames - 1.0)
	projectile.has_impacted = true
	source.world_position = Vector2(20.0, 0.0)
	assert(projectile.advance_frame(target, 1.0, source) == false)
	assert(projectile.world_position == Vector2(24.0, 0.0))


func _test_instant_projectile_reuse() -> void:
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.damage = 20.0
	projectile_definition.instant = true
	projectile_definition.instant_reuse_last = true
	projectile_definition.lifetime_frames = 15
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	weapon.attack_range = 500.0
	weapon.reload_frames = 1
	weapon.aim_tolerance_degrees = 180.0
	var unit_definition: RwUnitDefinition = RwUnitDefinition.new()
	unit_definition.combat_weapons.append(weapon)
	var source: RwUnitState = _unit(1, "vanilla", "beam", "1", Vector2.ZERO, unit_definition)
	source.build_progress = 1.0
	var target: RwUnitState = _unit(2, "vanilla", "target", "2", Vector2(100.0, 0.0), null)
	target.max_health = 200.0
	target.health = 200.0
	target.build_progress = 1.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: target,}, RwVanillaUnitDefinitions.create_registry(), _players())
	combat.set_simulation_context(1)
	combat.advance_weapons(source, unit_definition)
	var first_projectile: RwProjectileState = combat.projectiles[0]
	var initial_phase: float = first_projectile.source_random_phase
	combat.advance_frame()
	assert(first_projectile.has_impacted)
	combat.advance_weapons(source, unit_definition)
	assert(combat.projectiles.size() == 1)
	assert(combat.projectiles[0] == first_projectile)
	assert(not first_projectile.has_impacted)
	assert(first_projectile.source_random_phase == initial_phase)
	assert(source.random_counter == 1)
	combat.advance_frame()
	assert(is_equal_approx(target.health, target.max_health - 40.0))


func _test_instant_reuse_changes_turret_aim() -> void:
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 0.0
	projectile_definition.lifetime_frames = 60
	projectile_definition.instant_reuse_last = true
	projectile_definition.instant_reuse_last_also_change_turret_aim = true
	projectile_definition.sweep_offset = 12.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	weapon.attack_range = 500.0
	weapon.reload_frames = 1
	weapon.aim_tolerance_degrees = 180.0
	var unit_definition: RwUnitDefinition = RwUnitDefinition.new()
	unit_definition.combat_weapons.append(weapon)
	var source: RwUnitState = _unit(1, "vanilla", "turret", "1", Vector2.ZERO, unit_definition)
	var target: RwUnitState = _unit(2, "vanilla", "target", "2", Vector2(100.0, 0.0), null)
	target.build_progress = 1.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: target,}, RwVanillaUnitDefinitions.create_registry(), _players())
	combat.set_simulation_context(1)
	combat.advance_weapons(source, unit_definition)
	var projectile: RwProjectileState = combat.projectiles[0]
	projectile.source_random_phase = 0.25
	combat.advance_frame()
	assert(projectile.current_sweep_offset.distance_to(Vector2(12.0, 12.0)) < 0.01)
	combat.advance_weapons(source, unit_definition)
	var expected_angle: float = rad_to_deg((target.world_position + Vector2(12.0, 12.0)).angle())
	assert(is_equal_approx(source.get_weapon_rotation(0), expected_angle))


func _test_builtin_weapons() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var custom_tank: RwUnitDefinition = registry.find_definition("custom", "c_tank")
	var native_tank: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var anti_air: RwUnitDefinition = registry.find_definition("custom", "c_antiAirTurret")
	var interceptor: RwUnitDefinition = registry.find_definition("custom", "c_interceptor")
	var anti_nuke: RwUnitDefinition = registry.find_definition("vanilla", "AntiNukeLaucher")
	var battleship: RwUnitDefinition = registry.find_definition("custom", "heavyBattleship")
	assert(custom_tank.combat_weapons.size() == 1)
	assert(native_tank.combat_weapons.size() == 1)
	assert(custom_tank.combat_weapons[0].projectile.damage == 25.0)
	assert(native_tank.combat_weapons[0].projectile.damage == 25.0)
	assert(native_tank.combat_weapons[0].projectile.speed_per_frame == 5.0)
	assert(is_zero_approx(native_tank.combat_weapons[0].muzzle_distance))
	assert(native_tank.combat_weapons[0].reload_frames == 75)
	var heavy_missile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile("heavyMissileShip", "3")
	assert(heavy_missile.wobble_frequency == 48.0, "RWX time suffixes must convert seconds to 60 Hz frames")
	assert(heavy_missile.altitude_descent_range == 20.0)
	var nuke_profile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile("nukeLauncherC", "nukeProjectile")
	assert(nuke_profile.area_expand_time == 75.0, "areaExpandTime is a frame count, not a seconds-suffixed time")
	assert(anti_air.combat_weapons.size() > 0)
	assert(anti_air.combat_weapons[0].can_target_air)
	assert(not anti_air.combat_weapons[0].can_target_ground)
	assert(anti_nuke.projectile_interceptors.size() == 1)
	assert(anti_nuke.projectile_interceptors[0].projectile_tags == ["nuke"])
	assert(anti_nuke.projectile_interceptors[0].projectile.splash_damage == 100.0)
	assert(float(anti_nuke.projectile_interceptors[0].resource_usage["ammo"]) == 1.0)
	assert(is_equal_approx(interceptor.combat_weapons[0].turn_speed_degrees, 0.0))
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
	assert(is_equal_approx(target.health, 157.5))
	assert(is_equal_approx(nearby.health, 203.875))
	assert(ally.health == 210.0)
	projectile_definition.damage = 0.0
	projectile_definition.area_damage_no_falloff = false
	combat.spawn_projectile_at(source, Vector2(40.0, 0.0), weapon, 0.0)
	combat.advance_frame()
	assert(is_equal_approx(target.health, 140.0))
	assert(is_equal_approx(nearby.health, 197.75))
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
	assert(is_zero_approx(turret.get_weapon_rotation(0)))
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


func _test_projectile_split_on_expiry() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var submarine_definition: RwUnitDefinition = registry.find_definition("custom", "heavySub")
	var target_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "custom", "heavySub", "1", Vector2.ZERO, submarine_definition)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(1000.0, 0.0), target_definition)
	var split_weapon: RwWeaponDefinition
	for weapon: RwWeaponDefinition in submarine_definition.combat_weapons:
		if not weapon.projectile.spawn_on_end_of_life.is_empty():
			split_weapon = weapon
			break
	assert(split_weapon != null, "The heavy submarine torpedo must retain its terminal projectile profile")
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: target,}, registry, _players())
	var parent: RwProjectileState = RwProjectileState.new()
	parent.configure(source, target, split_weapon, 0.0)
	parent.remaining_frames = 1.0
	parent.world_position = Vector2(50.0, 0.0)
	combat.projectiles.append(parent)
	combat.advance_frame()
	assert(combat.projectiles.size() == 1, "The expiring torpedo must be replaced by its split child")
	var child: RwProjectileState = combat.projectiles[0]
	assert(child.definition.damage == 95.0)
	assert(child.definition.lifetime_frames == 300)
	assert(child.target_id == target.object_id)
	assert(child.recursion_depth == 1)
	var delayed_definition: RwProjectileDefinition = split_weapon.projectile.duplicate() as RwProjectileDefinition
	delayed_definition.damage = 0.0
	delayed_definition.instant = true
	delayed_definition.lifetime_frames = 3
	var delayed_weapon: RwWeaponDefinition = split_weapon.duplicate() as RwWeaponDefinition
	delayed_weapon.projectile = delayed_definition
	combat.configure({1: source, 2: target,}, registry, _players())
	var impacted_parent: RwProjectileState = RwProjectileState.new()
	impacted_parent.configure(source, target, delayed_weapon, 0.0)
	combat.projectiles.append(impacted_parent)
	combat.advance_frame()
	assert(impacted_parent.has_impacted)
	assert(combat.projectiles.size() == 1, "The torpedo split must wait until the parent projectile lifetime ends")
	combat.advance_frame()
	assert(combat.projectiles.size() == 1)
	combat.advance_frame()
	assert(combat.projectiles.size() == 1)
	assert(combat.projectiles[0].definition.damage == 95.0)
	var scout_projectile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"nautilusSubmarine",
		"scoutBotProjectileSplit",
	)
	assert(scout_projectile != null)
	assert(str(scout_projectile.spawn_units_on_explode[0]["unit_name"]) == "robotCrab")


func _test_synchronized_projectile_child_spawn() -> void:
	var source: RwUnitState = _unit(42, "custom", "source", "1", Vector2(100.0, 200.0), null)
	source.random_counter = 7
	var target: RwUnitState = _unit(43, "vanilla", "target", "2", Vector2(900.0, 500.0), null)
	var parent_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	var child_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	child_definition.target_ground = true
	child_definition.lead_target = true
	child_definition.speed_per_frame = 4.0
	var parent_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	parent_weapon.projectile = parent_definition
	var parent: RwProjectileState = RwProjectileState.new()
	parent.owner_id = source.object_id
	parent.target_id = target.object_id
	parent.team = source.team
	parent.definition = parent_definition
	parent.weapon_definition = parent_weapon
	parent.world_position = Vector2(300.0, 400.0)
	parent.target_position = Vector2(50.0, 75.0)
	parent.velocity = Vector2.RIGHT
	parent.heading_degrees = 30.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({42: source, 43: target,}, RwVanillaUnitDefinitions.create_registry(), _players())
	combat.set_simulation_context(1, 123456789)
	var spawn_specs: Array[Dictionary] = [
		{
			"projectile_definition": child_definition,
			"count": 1,
			"spawn_chance": 0.0,
			"max_spawn_limit": 8,
			"recursion_limit": 0,
		},
		{
			"projectile_definition": child_definition,
			"count": 1,
			"spawn_chance": 1.0,
			"max_spawn_limit": 8,
			"recursion_limit": 0,
			"offset_dir": 10.0,
			"offset_x": 5.0,
			"offset_y": -2.0,
			"offset_x_relative": 6.0,
			"offset_y_relative": -8.0,
			"offset_random_dir": 12.0,
			"offset_random_x": 3.0,
			"offset_random_y": 4.0,
		},
		{
			"projectile_definition": child_definition,
			"count": 1,
			"spawn_chance": 1.0,
			"max_spawn_limit": 1,
			"recursion_limit": 0,
		},
	]
	var skipped_roll: int = RwVanillaRandom.unit_range(
		0,
		1000,
		source.object_id,
		source.world_position,
		source.random_counter,
		1,
		123456789,
		1,
	)
	assert(skipped_roll > 0, "The first candidate must deterministically fail its zero chance")
	var direction_spread: float = float(RwVanillaRandom.unit_range(
		-12000,
		12000,
		source.object_id,
		source.world_position,
		source.random_counter,
		1,
		123456789,
		11,
	)) * 0.001
	var random_x: float = float(RwVanillaRandom.unit_range(
		-3000,
		3000,
		source.object_id,
		source.world_position,
		source.random_counter,
		1,
		123456789,
		5,
	)) * 0.001
	var random_y: float = float(RwVanillaRandom.unit_range(
		-4000,
		4000,
		source.object_id,
		source.world_position,
		source.random_counter,
		1,
		123456789,
		8,
	)) * 0.001
	combat.call("_spawn_projectile_children", parent, spawn_specs)
	assert(combat.projectiles.size() == 1, "maxSpawnLimit applies to total children created by this list")
	var child: RwProjectileState = combat.projectiles[0]
	var expected_position: Vector2 = (
		Vector2(300.0, 400.0)
		+ Vector2(5.0, -2.0)
		+ Vector2(-8.0, 6.0).rotated(deg_to_rad(30.0))
	)
	expected_position += Vector2(random_x, random_y)
	assert(child.world_position.distance_to(expected_position) < 0.001)
	assert(
		is_equal_approx(child.velocity.angle(), deg_to_rad(40.0 + direction_spread)),
		"Cluster direction mismatch: actual=%s expected=%s spread=%s" % [
			child.velocity.angle(),
			deg_to_rad(40.0 + direction_spread),
			direction_spread,
		],
	)
	assert(child.target_id == -1)
	assert(child.target_position.distance_to(target.world_position) < 0.001, "A target-ground child inherits the live unit target")
	assert(child.recursion_depth == 1)


func _test_tank_projectile_collision_after_movement() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(10.0, 0.0), tank_definition)
	target.health = 5.0
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 5.0
	projectile_definition.native_target_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	assert(not projectile.advance_frame(target), "Native shells test target distance from the start of the movement step")
	assert(is_equal_approx(projectile.world_position.x, 5.0))
	assert(projectile.advance_frame(target), "A later step must hit once its starting distance is inside the native hit radius")
	var near_target: RwUnitState = _unit(3, "vanilla", "tank", "2", Vector2(3.0, 0.0), tank_definition)
	var near_projectile: RwProjectileState = RwProjectileState.new()
	near_projectile.configure(source, near_target, weapon, 0.0)
	assert(near_projectile.advance_frame(near_target), "The source clamps the travel step at the target distance")
	assert(is_equal_approx(near_projectile.world_position.x, 3.0))


func _test_native_building_projectile_radius() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(12.5, 0.0), tank_definition)
	target.is_building = true
	target.build_progress = 1.0
	target.health = 10.0
	target.collision_radius = 10.0
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 5.0
	projectile_definition.damage = 25.0
	projectile_definition.native_target_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	assert(not projectile.advance_frame(target), "A building hit radius is checked before this movement step")
	assert(
		projectile.advance_frame(target),
		"Completed vanilla buildings must use their reduced projectile hit radius",
	)


func _test_expanding_projectile_area_damage() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	tank_definition.combat_weapons.clear()
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var near_target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(15.0, 0.0), tank_definition)
	var far_target: RwUnitState = _unit(3, "vanilla", "tank", "2", Vector2(5.0, 0.0), tank_definition)
	near_target.build_progress = 1.0
	far_target.build_progress = 1.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source, 2: near_target, 3: far_target,}, registry, _players())
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.instant = true
	projectile_definition.target_ground = true
	projectile_definition.splash_damage = 20.0
	projectile_definition.splash_radius = 20.0
	projectile_definition.area_expand_time = 2.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	combat.spawn_projectile_at(source, Vector2(20.0, 0.0), weapon, 0.0)
	combat.advance_frame()
	assert(near_target.health < near_target.max_health)
	assert(is_equal_approx(far_target.health, far_target.max_health))
	var near_health_after_first_frame: float = near_target.health
	combat.advance_frame()
	assert(is_equal_approx(near_target.health, near_health_after_first_frame))
	assert(far_target.health < far_target.max_health)
	assert(combat.projectiles.is_empty())


func _test_projectile_turn_speed_when_near() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var target: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(8.0, 8.0), tank_definition)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.speed_per_frame = 2.0
	projectile_definition.turn_speed_degrees = 1.0
	projectile_definition.turn_speed_near_degrees = -1.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	var _hit_target: bool = projectile.advance_frame(target)
	assert(is_equal_approx(rad_to_deg(projectile.velocity.angle()), 45.0))


func _test_projectile_unit_spawn() -> void:
	_projectile_spawn_requests.clear()
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _unit(1, "vanilla", "tank", "1", Vector2.ZERO, tank_definition)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: source,}, registry, _players())
	combat.projectile_unit_spawn_requested.connect(_on_projectile_unit_spawn_requested)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.instant = true
	projectile_definition.target_ground = true
	projectile_definition.spawn_units_on_explode.append({"unit_name": "robotCrab", "count": 1,})
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	combat.spawn_projectile_at(source, Vector2(20.0, 0.0), weapon, 0.0)
	combat.advance_frame()
	assert(_projectile_spawn_requests.size() == 1)
	assert(str(_projectile_spawn_requests[0]["unit_name"]) == "robotCrab")


func _test_projectile_interception() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var interceptor_definition: RwUnitDefinition = registry.find_definition("vanilla", "AntiNukeLaucher")
	var attacker_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var interceptor_unit: RwUnitState = _unit(
		1,
		"vanilla",
		"AntiNukeLaucher",
		"1",
		Vector2.ZERO,
		interceptor_definition,
	)
	var attacker: RwUnitState = _unit(2, "vanilla", "tank", "2", Vector2(1000.0, 0.0), attacker_definition)
	interceptor_unit.build_progress = 1.0
	interceptor_unit.resource_balances["ammo"] = 0.0
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: interceptor_unit, 2: attacker,}, registry, _players())
	var incoming_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	incoming_definition.tags.append("nuke")
	incoming_definition.speed_per_frame = 0.0
	var incoming_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	incoming_weapon.projectile = incoming_definition
	var incoming: RwProjectileState = combat.spawn_projectile_at(
		attacker,
		Vector2(300.0, 0.0),
		incoming_weapon,
		180.0,
	)
	incoming.world_position = Vector2(25.0, 0.0)
	incoming.origin_position = incoming.world_position
	incoming.height = 80.0
	incoming.velocity = Vector2.ZERO
	incoming.remaining_frames = 600.0
	combat.advance_frame()
	assert(combat.projectiles.size() == 1, "Anti-nuke ammo must block firing without stockpiled ammo")
	interceptor_unit.resource_balances["ammo"] = 1.0
	combat.advance_frame()
	assert(interceptor_unit.resource_balances["ammo"] == 0.0, "Interceptor launch must consume one ammo")
	var launched_interceptor: RwProjectileState
	for projectile: RwProjectileState in combat.projectiles:
		if projectile.intercept_target_projectile == incoming:
			launched_interceptor = projectile
	assert(launched_interceptor != null, "Matching enemy projectile must be assigned an interceptor")
	for frame: int in 180:
		combat.advance_frame()
	assert(not combat.projectiles.has(incoming), "Interceptor impact must destroy its tagged target")
	assert(launched_interceptor.has_impacted, "Interceptor missile must impact the moving projectile target")
	var life_only_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	life_only_definition.intercept_projectile_remove_target_life_only = true
	var life_only_interceptor: RwProjectileState = RwProjectileState.new()
	life_only_interceptor.definition = life_only_definition
	life_only_interceptor.intercept_target_projectile = RwProjectileState.new()
	life_only_interceptor.intercept_target_projectile.remaining_frames = 25.0
	combat.call("_resolve_impact", life_only_interceptor, null)
	assert(life_only_interceptor.intercept_target_projectile.remaining_frames == 0.0)
	assert(not life_only_interceptor.intercept_target_projectile.remove_requested)


func _test_projectile_initial_velocity_axes() -> void:
	var definition: RwProjectileDefinition = RwProjectileDefinition.new()
	definition.speed_per_frame = 0.0
	definition.initial_velocity = Vector2(1.0, 2.0)
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = definition
	var source: RwUnitState = RwUnitState.new()
	source.object_id = 1
	var target: RwUnitState = RwUnitState.new()
	target.object_id = 2
	target.world_position = Vector2(100.0, 0.0)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 90.0)
	assert(projectile.velocity == Vector2(1.0, 2.0), "Initial unguided velocity uses world axes")


func _test_ground_target_snapshot_and_lead() -> void:
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.target_ground = true
	projectile_definition.lead_target = true
	projectile_definition.speed_per_frame = 10.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var source: RwUnitState = RwUnitState.new()
	source.object_id = 1
	var target: RwUnitState = RwUnitState.new()
	target.object_id = 2
	target.world_position = Vector2(100.0, 0.0)
	target._movement_velocity = 2.0
	target.body_rotation_degrees = 0.0
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	assert(projectile.target_id == -1, "Ground-targeted shots must retain a fixed impact point")
	assert(projectile.target_position.distance_to(Vector2(124.8, 0.0095108)) < 0.05)
	target.world_position = Vector2(150.0, 0.0)
	projectile.advance_frame(target)
	assert(
		projectile.target_position.distance_to(Vector2(124.8, 0.0095108)) < 0.05,
		"Ground-targeted shots must not follow the unit after firing: %s" % projectile.target_position,
	)
	var spread_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	spread_definition.target_ground = true
	spread_definition.target_ground_spread = 30.0
	spread_definition.speed_per_frame = 5.0
	var spread_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	spread_weapon.projectile = spread_definition
	var spread_source: RwUnitState = _unit(41, "vanilla", "artillery", "1", Vector2.ZERO, null)
	var spread_target: RwUnitState = _unit(42, "vanilla", "target", "2", Vector2(100.0, 100.0), null)
	var spread_projectile: RwProjectileState = RwProjectileState.new()
	spread_projectile.configure(spread_source, spread_target, spread_weapon, 0.0, null, 1, 1, 123456789)
	var expected_spread_angle: float = (spread_projectile.target_position - spread_projectile.world_position).angle()
	assert(not is_equal_approx(spread_projectile.velocity.angle(), expected_spread_angle))
	spread_projectile.advance_frame(spread_target)
	assert(is_equal_approx(spread_projectile.velocity.angle(), expected_spread_angle))
	assert(is_equal_approx(spread_projectile.heading_degrees, rad_to_deg(expected_spread_angle)))


func _on_projectile_unit_spawn_requested(_projectile: RwProjectileState, spawn_spec: Dictionary) -> void:
	_projectile_spawn_requests.append(spawn_spec)


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
