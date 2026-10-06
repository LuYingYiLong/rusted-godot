extends SceneTree

var _shots: int
var _deaths: int
var _fog_reveal_requests: Array[RwProjectileState]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle_scene: PackedScene = load("uid://c0w7n4afw43pa") as PackedScene
	assert(battle_scene != null)
	var battle_map: Node = battle_scene.instantiate()
	assert(battle_map.get_node("MapRoot/ProjectileLayer") is RwBattleProjectileLayer)
	_test_reused_projectile_keeps_global_object_id(battle_map)
	_test_mobile_death_allocations(battle_map)
	battle_map.free()
	var first: PackedFloat32Array = _simulate()
	var second: PackedFloat32Array = _simulate()
	assert(first == second, "Combat must be deterministic")
	assert(first[1] < 210.0, "Enemy tank must take damage")
	assert(first[0] == 210.0, "Unarmed enemy must not damage the attacker")
	assert(first[2] == 210.0, "Allied tank must be ignored")
	assert(_shots > 0, "Weapons must fire")
	assert(_deaths > 0, "Damage must destroy units")
	_test_turret()
	_test_ground_projectile()
	_test_projectile_damage_rules()
	_test_projectile_fog_visibility()
	_test_projectile_fog_reveal_trigger()
	_test_projectile_source_teleport()
	_test_projectile_custom_effects()
	_test_native_weapon_muzzle_effects()
	_test_command_center_projectile()
	_test_projectile_ballistic_and_ground_impact()
	_test_command_center_target_reacquisition()
	_test_attack_move_acquisition()
	_test_attack_move_pursuit_preempts_long_path()
	_test_native_projectile_profiles()
	_test_native_weapon_coverage()
	_test_laser_defense_and_deflection_power()
	var economy: RwVanillaEconomy = RwVanillaEconomy.new()
	economy.initialize([{"slot": 1, "credits": 125.0,},], 1.0)
	economy.set_command_centers({1: 1,})
	assert(economy.get_income_rate(1, "credits") == 18.0)
	assert(economy.get_balance(1, "credits") == 125.0)
	economy.remove_command_center(1)
	assert(economy.get_income_rate(1, "credits") == 0.0)
	print("COMBAT_CHECK_OK shots=%d deaths=%d" % [_shots, _deaths])
	quit()


func _simulate() -> PackedFloat32Array:
	_shots = 0
	_deaths = 0
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var turret: RwUnitDefinition = registry.find_definition("vanilla", "turret")
	assert(tank != null and tank.combat_weapons.size() == 1)
	assert(turret != null and turret.combat_weapons.size() == 1)
	var units: Dictionary = {}
	var positions: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(95.0, 0.0), Vector2(10.0, 20.0),]
	var teams: Array[String] = ["1", "2", "3",]
	for index: int in 3:
		var spawn: Dictionary = {
			"object_id": index + 1,
			"source_id": "vanilla",
			"unit_name": "tank",
			"team": teams[index],
			"position": positions[index],
			"build_progress": 0.5 if index == 1 else 1.0,
		}
		var state: RwUnitState = RwUnitState.new()
		state.initialize_from_spawn(spawn, tank)
		units[index + 1] = state
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
		{"slot": 3, "color": 1,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.projectile_fired.connect(_on_projectile_fired)
	combat.unit_destroyed.connect(_on_unit_destroyed)
	combat.configure(units, registry, players)
	for frame: int in 700:
		combat.advance_frame()
	return PackedFloat32Array([
		(units[1] as RwUnitState).health,
		(units[2] as RwUnitState).health,
		(units[3] as RwUnitState).health,
	])


func _test_reused_projectile_keeps_global_object_id(battle_map: Node) -> void:
	battle_map.set("_next_object_id", 400)
	var projectile: RwProjectileState = RwProjectileState.new()
	battle_map.call("_assign_projectile_object_id", projectile)
	assert(projectile.object_id == 400)
	assert(int(battle_map.get("_next_object_id")) == 401)
	battle_map.call("_assign_projectile_object_id", projectile)
	assert(projectile.object_id == 400, "Reused projectile objects must retain their original global ID")
	assert(int(battle_map.get("_next_object_id")) == 401, "Reusing a projectile must not consume a global object ID")



func _test_mobile_death_allocations(battle_map: Node) -> void:
	var path_grid: RwPathGrid = RwPathGrid.new()
	path_grid.size = Vector2i(3, 3)
	path_grid.tile_size = Vector2i(20, 20)
	path_grid.set("_liquid_tiles", PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0, 0,]))
	battle_map.set("_path_grid", path_grid)
	battle_map.set("_next_object_id", 500)
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var tank: RwUnitState = RwUnitState.new()
	tank.initialize_from_spawn({
		"object_id": 10,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "1",
		"position": Vector2(30.0, 30.0),
	}, tank_definition)
	battle_map.call("_allocate_mobile_death_effect_ids", tank)
	assert(int(battle_map.get("_next_object_id")) == 500, "Living units must not consume death effect IDs")
	tank.is_dead = true
	battle_map.call("_allocate_mobile_death_effect_ids", tank)
	assert(int(battle_map.get("_next_object_id")) == 503, "Ground tank death must allocate two emitters and one scorch mark")
	var nearby_tank: RwUnitState = RwUnitState.new()
	nearby_tank.initialize_from_spawn({
		"object_id": 11,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "1",
		"position": Vector2(32.0, 30.0),
	}, tank_definition)
	nearby_tank.is_dead = true
	battle_map.call("_allocate_mobile_death_effect_ids", nearby_tank)
	assert(int(battle_map.get("_next_object_id")) == 505, "Nearby deaths reuse the scorch mark slot but still allocate both emitters")
	var builder_definition: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	var builder: RwUnitState = RwUnitState.new()
	builder.initialize_from_spawn({
		"object_id": 12,
		"source_id": "vanilla",
		"unit_name": "builder",
		"team": "1",
		"position": Vector2(30.0, 30.0),
	}, builder_definition)
	builder.is_dead = true
	battle_map.call("_allocate_mobile_death_effect_ids", builder)
	assert(int(battle_map.get("_next_object_id")) == 507, "Stock builders use the small death effect and allocate both emitters")
	var water_tank: RwUnitState = RwUnitState.new()
	water_tank.initialize_from_spawn({
		"object_id": 13,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "1",
		"position": Vector2(10.0, 10.0),
	}, tank_definition)
	water_tank.is_dead = true
	battle_map.call("_allocate_mobile_death_effect_ids", water_tank)
	assert(int(battle_map.get("_next_object_id")) == 507, "Liquid deaths must not allocate ground death effects")



func _test_ground_projectile() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var units: Dictionary = {}
	for index: int in 2:
		var state: RwUnitState = RwUnitState.new()
		state.initialize_from_spawn({
			"object_id": index + 1,
			"source_id": "vanilla",
			"unit_name": "tank",
			"team": str(index + 1),
			"position": Vector2(float(index) * 30.0, 0.0),
			"build_progress": 0.5,
		}, definition)
		units[index + 1] = state
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.damage = 20.0
	projectile_definition.splash_damage = 20.0
	projectile_definition.speed_per_frame = 10.0
	projectile_definition.splash_radius = 15.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = combat.spawn_projectile_at(units[1], Vector2(30.0, 0.0), weapon, 0.0)
	assert(projectile != null and projectile.target_id == -1)
	for frame: int in 3:
		combat.advance_frame()
	assert((units[2] as RwUnitState).health == 175.0, "Under-construction targets must take 1.75 times projectile damage")
	assert((units[1] as RwUnitState).health == 210.0)


func _test_projectile_damage_rules() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	var artillery_definition: RwUnitDefinition = registry.find_definition("vanilla", "artillery")
	var source: RwUnitState = _create_combat_test_unit(1, "tank", "1", Vector2.ZERO, tank_definition)
	var direct_target: RwUnitState = _create_combat_test_unit(2, "tank", "2", Vector2(30.0, 0.0), tank_definition)
	var splash_target: RwUnitState = _create_combat_test_unit(3, "tank", "2", Vector2(50.0, 0.0), tank_definition)
	var allied_target: RwUnitState = _create_combat_test_unit(4, "tank", "1", Vector2(30.0, 5.0), tank_definition)
	var units: Dictionary = {1: source, 2: direct_target, 3: splash_target, 4: allied_target,}
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.damage = 20.0
	projectile_definition.splash_damage = 10.0
	projectile_definition.splash_radius = 40.0
	var projectile: RwProjectileState = _create_test_projectile(projectile_definition, "1", Vector2(30.0, 0.0))
	combat._resolve_impact(projectile, direct_target)
	assert(direct_target.health == 180.0, "Direct and area damage must be applied as separate values")
	assert(splash_target.health == 204.0, "Area damage must use the original distance falloff")
	assert(allied_target.health == allied_target.max_health, "Default splash damage must skip friendly units")

	tank_definition.shoot_damage_multiplier = 1.5
	direct_target.health = direct_target.max_health
	splash_target.health = splash_target.max_health
	var scaled_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	scaled_definition.damage = 20.0
	scaled_definition.splash_damage = 10.0
	scaled_definition.splash_radius = 40.0
	var scaled_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	scaled_weapon.projectile = scaled_definition
	var scaled_projectile: RwProjectileState = combat.spawn_projectile_at(
		source,
		Vector2(30.0, 0.0),
		scaled_weapon,
		0.0,
	)
	scaled_projectile.world_position = Vector2(30.0, 0.0)
	combat._resolve_impact(scaled_projectile, direct_target)
	assert(
		direct_target.health == 165.0,
		"Shooter damage multiplier must scale direct and splash damage: hp=%s multiplier=%s" % [
			direct_target.health,
			scaled_projectile.source_damage_multiplier,
		]
	)
	assert(splash_target.health == 201.0, "Shooter damage multiplier must preserve area falloff: hp=%s" % splash_target.health)
	var radius_target: RwUnitState = _create_combat_test_unit(
		5,
		"tank",
		"2",
		Vector2(20.0, 0.0),
		tank_definition,
	)
	radius_target.is_building = true
	radius_target.collision_radius = 20.0
	radius_target.health = 40.0
	var radius_projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	radius_projectile_definition.damage = 25.0
	radius_projectile_definition.speed_per_frame = 5.0
	radius_projectile_definition.native_target_collision_rules = true
	var radius_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	radius_weapon.projectile = radius_projectile_definition
	var radius_projectile: RwProjectileState = RwProjectileState.new()
	radius_projectile.configure(source, radius_target, radius_weapon, 0.0)
	radius_projectile.source_damage_multiplier = 1.5
	assert(
		not radius_projectile.advance_frame(radius_target),
		"Native high-health collision radius must use direct damage after the source multiplier",
	)
	assert(radius_projectile.world_position == Vector2(5.0, 0.0))
	assert(radius_projectile.advance_frame(radius_target))

	direct_target.health = direct_target.max_health
	splash_target.health = splash_target.max_health
	var ignored_multiplier_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	ignored_multiplier_definition.damage = 20.0
	ignored_multiplier_definition.splash_damage = 10.0
	ignored_multiplier_definition.splash_radius = 40.0
	ignored_multiplier_definition.ignore_parent_shoot_damage_multiplier = true
	var ignored_multiplier_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	ignored_multiplier_weapon.projectile = ignored_multiplier_definition
	var ignored_multiplier_projectile: RwProjectileState = combat.spawn_projectile_at(
		source,
		Vector2(30.0, 0.0),
		ignored_multiplier_weapon,
		0.0,
	)
	ignored_multiplier_projectile.world_position = Vector2(30.0, 0.0)
	combat._resolve_impact(ignored_multiplier_projectile, direct_target)
	assert(direct_target.health == 180.0, "Projectile override must skip shooter damage multiplier")
	assert(splash_target.health == 204.0, "Projectile override must skip shooter multiplier for splash damage")
	tank_definition.shoot_damage_multiplier = 1.0

	var direct_only: RwProjectileDefinition = RwProjectileDefinition.new()
	direct_only.damage = 25.0
	direct_only.splash_radius = 40.0
	var target_ground: RwProjectileState = _create_test_projectile(direct_only, "1", direct_target.world_position)
	combat._resolve_impact(target_ground, null)
	assert(direct_target.health == 180.0, "Direct damage must not be converted into splash damage")
	target_ground.definition.target_ground = true
	combat._resolve_impact(target_ground, direct_target)
	assert(direct_target.health == 180.0, "Ground-targeted projectiles must not apply direct unit damage")

	var unfinished_target: RwUnitState = _create_combat_test_unit(5, "tank", "2", Vector2(200.0, 0.0), tank_definition)
	unfinished_target.build_progress = 0.5
	var unfinished_units: Dictionary = {1: source, 5: unfinished_target,}
	combat.configure(unfinished_units, registry, players)
	combat._damage_unit(unfinished_target, 20.0, projectile_definition)
	assert(unfinished_target.health == 175.0, "Unfinished targets must take the original 1.75 damage multiplier")

	var shielded_target: RwUnitState = _create_combat_test_unit(6, "tank", "2", Vector2(300.0, 0.0), tank_definition)
	shielded_target.max_shield = 100.0
	shielded_target.set_shield(100.0)
	tank_definition.behavior = RwShieldBehavior.new()
	var shield_units: Dictionary = {1: source, 6: shielded_target,}
	combat.configure(shield_units, registry, players)
	var shield_projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	shield_projectile.shield_damage_multiplier = 0.5
	shield_projectile.shield_deflection_multiplier = 0.2
	shield_projectile.hull_damage_multiplier = 0.5
	combat._damage_unit(shielded_target, 100.0, shield_projectile)
	assert(shielded_target.shield == 50.0)
	assert(shielded_target.health == 170.0, "Shield damage, deflection, and hull multipliers must match 1.15")

	var air_target: RwUnitState = _create_combat_test_unit(7, "helicopter", "2", Vector2(400.0, 0.0), helicopter_definition)
	var underwater_target: RwUnitState = _create_combat_test_unit(8, "tank", "2", Vector2(400.0, 0.0), tank_definition)
	air_target.movement_type = "AIR"
	underwater_target.submerged = true
	underwater_target.altitude = -10.0
	var category_units: Dictionary = {1: source, 7: air_target, 8: underwater_target,}
	combat.configure(category_units, registry, players)
	var area_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	area_definition.splash_damage = 20.0
	area_definition.splash_radius = 20.0
	var area_projectile: RwProjectileState = _create_test_projectile(area_definition, "1", Vector2(400.0, 0.0))
	combat._resolve_impact(area_projectile, null)
	assert(air_target.health == air_target.max_health, "Ground explosions must not hit air units by default")
	assert(underwater_target.health == underwater_target.max_health, "Surface explosions must not hit submerged units by default")
	area_definition.area_hit_air_and_land_at_same_time = true
	area_definition.area_hit_underwater_always = true
	combat._resolve_impact(area_projectile, null)
	assert(air_target.health < air_target.max_health)
	assert(underwater_target.health < underwater_target.max_health)

	var stock_tank: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	assert(stock_tank.combat_weapons[0].projectile.damage == 25.0)
	assert(stock_tank.combat_weapons[0].projectile.speed_per_frame == 5.0)
	assert(stock_tank.combat_weapons[0].projectile.texture_region == Rect2i(20, 0, 20, 20))
	assert(stock_tank.combat_weapons[0].projectile.impact_texture_name == "explode_big2.png")
	assert(stock_tank.combat_weapons[0].projectile.impact_frame_size == Vector2i(39, 40))
	assert(stock_tank.combat_weapons[0].projectile.impact_frame_offset == Vector2i(121, 1))
	assert(stock_tank.combat_weapons[0].projectile.impact_frame_count == 5)
	assert(artillery_definition.combat_weapons[0].projectile.draw_type == 0)
	assert(artillery_definition.combat_weapons[0].projectile.texture_region == Rect2i(40, 0, 20, 20))
	assert(artillery_definition.combat_weapons[0].projectile.large_hit_effect)
	assert(artillery_definition.combat_weapons[0].projectile.impact_texture_name == "explode_big.png")
	assert(artillery_definition.combat_weapons[0].projectile.impact_frame_size == Vector2i(39, 40))
	assert(artillery_definition.combat_weapons[0].projectile.impact_frame_offset == Vector2i(1, 1))
	assert(artillery_definition.combat_weapons[0].projectile.impact_frame_count == 13)
	assert(artillery_definition.combat_weapons[0].projectile.attached_light_color.a > 0.0)
	assert(artillery_definition.combat_weapons[0].projectile.attached_light_cast_on_ground)


func _test_projectile_fog_visibility() -> void:
	var fog: RwFogOfWar = RwFogOfWar.new()
	fog.configure(Vector2i(64, 64), Vector2i(20, 20), RwFogOfWar.Mode.LOS_FOG, false)
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var reveal_position: Vector2 = Vector2(640.0, 640.0)
	fog.add_temporary_reveal(reveal_position, "1", 15, 2.0)
	assert(fog.update_visibility({}, players, 1))
	assert(fog.is_visible_at(reveal_position), "Nuke projectile must reveal fog at its impact position")
	fog.advance_temporary_reveals(1.0)
	fog.update_visibility({}, players, 1)
	assert(fog.is_visible_at(reveal_position), "Temporary projectile vision must remain active through its duration")
	fog.advance_temporary_reveals(1.0)
	assert(fog.update_visibility({}, players, 1))
	assert(not fog.is_visible_at(reveal_position), "Temporary projectile vision must expire after its configured frames")


func _test_projectile_fog_reveal_trigger() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({}, registry, [])
	combat.projectile_fog_reveal_requested.connect(_on_projectile_fog_reveal_requested)
	var projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile_definition.should_reveal_fog = true
	projectile_definition.instant = true
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.definition = projectile_definition
	projectile.team = "1"
	projectile.remaining_frames = 1.0
	projectile.target_position = Vector2(640.0, 640.0)
	combat.projectiles.append(projectile)
	combat.advance_frame()
	assert(_fog_reveal_requests.size() == 1, "A fog revealing projectile must request vision when it hits")
	assert(_fog_reveal_requests[0] == projectile)
	assert(projectile.fog_reveal_triggered)

	var descending_projectile: RwProjectileState = RwProjectileState.new()
	descending_projectile.definition = projectile_definition
	descending_projectile._altitude_descending = true
	descending_projectile.height = 29.0
	assert(descending_projectile.should_reveal_fog_this_frame(false))
	descending_projectile.fog_reveal_triggered = true
	assert(not descending_projectile.should_reveal_fog_this_frame(false))


func _on_projectile_fog_reveal_requested(projectile: RwProjectileState) -> void:
	_fog_reveal_requests.append(projectile)


func _test_projectile_source_teleport() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var source_definition: RwUnitDefinition = registry.find_definition("custom", "experimentalGunship")
	assert(source_definition != null)
	var source: RwUnitState = _create_combat_test_unit(
		1,
		"experimentalGunship",
		"1",
		Vector2(100.0, 100.0),
		source_definition,
	)
	var projectile_definition: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"experimentalGunship",
		"blink",
	)
	assert(projectile_definition != null and projectile_definition.teleport_source)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.definition = projectile_definition
	projectile.owner_id = source.object_id
	projectile.team = source.team
	projectile.remaining_frames = 1.0
	projectile.target_position = Vector2(600.0, 400.0)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({source.object_id: source,}, registry, [])
	combat.projectiles.append(projectile)
	combat.advance_frame()
	assert(source.world_position == Vector2(600.0, 400.0), "Blink ammunition must teleport its source to impact")


func _test_projectile_custom_effects() -> void:
	var blink: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"experimentalGunship",
		"blink",
	)
	assert(blink != null and blink.effect_profiles.has("blinkflash"))
	assert(blink.effect_profiles["blinkflash"]["texture_name"] == "builtin:shared/light_50.png")
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.definition = blink
	projectile.world_position = Vector2(40.0, 60.0)
	projectile.render_color = Color.CYAN
	var layer: RwBattleProjectileLayer = RwBattleProjectileLayer.new()
	layer.show_creation(projectile)
	assert(layer._projectile_effects.size() == 3, "Projectile creation must spawn all three original effect entries")
	for effect: Dictionary in layer._projectile_effects:
		assert(layer._get_texture(str(effect["texture_name"])) != null)
	layer.free()

	var lightning: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"c_amphibiousJet",
		"lightning",
	)
	assert(lightning != null and not lightning.explode_effect_on_shield.is_empty())
	var shield_projectile: RwProjectileState = RwProjectileState.new()
	shield_projectile.definition = lightning
	shield_projectile.hit_shield = true
	shield_projectile.world_position = Vector2(100.0, 120.0)
	var shield_layer: RwBattleProjectileLayer = RwBattleProjectileLayer.new()
	shield_layer.show_impact(shield_projectile, null)
	assert(shield_layer._projectile_effects.size() == 2, "Shield impacts must select the original shield-specific effects")
	for effect: Dictionary in shield_layer._projectile_effects:
		assert(shield_layer._get_texture(str(effect["texture_name"])) != null)
	shield_layer.free()

	var plasma_trail: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"experimentalGunship",
		"main",
	)
	assert(plasma_trail != null and plasma_trail.trail_effect_name == "CUSTOM:projectileTrail")
	var trail_projectile: RwProjectileState = RwProjectileState.new()
	trail_projectile.definition = plasma_trail
	trail_projectile.object_id = 91
	trail_projectile.trail_emission_serial = 1
	trail_projectile.trail_positions.append(Vector3(12.0, 24.0, 0.0))
	var trail_layer: RwBattleProjectileLayer = RwBattleProjectileLayer.new()
	trail_layer.set_projectiles([trail_projectile,])
	assert(trail_layer._projectile_effects.size() == 1, "Custom trail settings must spawn a detached sprite effect")
	assert(trail_layer._get_texture(str(trail_layer._projectile_effects[0]["texture_name"])) != null)
	trail_layer.free()


func _create_combat_test_unit(
	object_id: int,
	unit_name: String,
	team: String,
	position: Vector2,
	definition: RwUnitDefinition,
) -> RwUnitState:
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.initialize_from_spawn({
		"object_id": object_id,
		"source_id": "vanilla",
		"unit_name": unit_name,
		"team": team,
		"position": position,
	}, definition)
	return unit_state


func _create_test_projectile(
	definition: RwProjectileDefinition,
	team: String,
	position: Vector2,
) -> RwProjectileState:
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.definition = definition
	projectile.team = team
	projectile.world_position = position
	projectile.velocity = Vector2.RIGHT
	return projectile


func _test_command_center_projectile() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var command_center: RwUnitDefinition = registry.find_definition("vanilla", "commandCenter")
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	assert(command_center != null and not command_center.combat_weapons.is_empty())
	var weapon: RwWeaponDefinition = command_center.combat_weapons[0]
	var projectile_definition: RwProjectileDefinition = weapon.projectile
	assert(projectile_definition.texture_name.is_empty())
	assert(projectile_definition.visual_radius == 2.0)
	assert(projectile_definition.visual_color == Color8(230, 230, 50))
	assert(projectile_definition.native_target_collision_rules)
	assert(projectile_definition.homing and not projectile_definition.lead_target)
	assert(not projectile_definition.detonate_on_target_loss)
	assert(projectile_definition.retarget_on_target_loss)
	assert(projectile_definition.target_loss_retarget_range == 120.0)
	assert(projectile_definition.target_loss_retarget_lead_distance == 15.0)
	assert(projectile_definition.hit_radius == 2.0)
	assert(projectile_definition.include_target_collision_radius)
	assert(projectile_definition.retarget_on_target_loss)
	assert(not projectile_definition.remove_on_target_loss)
	assert(projectile_definition.altitude_move_start == 40.0)
	assert(projectile_definition.altitude_maximum == 60.0)
	assert(projectile_definition.render_shadow)
	assert(projectile_definition.trail_as_particles)
	assert(projectile_definition.trail_emission_interval_frames == 3.0)
	assert(projectile_definition.trail_texture_name == "effects.png")
	assert(projectile_definition.trail_texture_frame_size == Vector2i(25, 25))
	assert(projectile_definition.trail_texture_frame_offset == Vector2i(1, 1))
	assert(not projectile_definition.trail_animate_frames)
	assert(projectile_definition.trail_particle_scale_from == 1.2)
	assert(projectile_definition.trail_particle_scale_to == 0.5)
	assert(projectile_definition.trail_particle_fade_duration_frames == 65.0)
	assert(projectile_definition.trail_particle_fade_in_duration_frames == 5.0)
	assert(RwDrawableCatalog.load_texture(projectile_definition.trail_texture_name) != null)
	assert(projectile_definition.impact_texture_name == "explode_big.png")
	assert(projectile_definition.impact_frame_size == Vector2i(39, 40))
	assert(projectile_definition.impact_frame_offset == Vector2i(1, 1))
	assert(projectile_definition.impact_frame_step == Vector2i(40, 41))
	assert(projectile_definition.impact_frame_count == 13)
	assert(is_equal_approx(projectile_definition.impact_duration, 0.583333))
	assert(projectile_definition.impact_animation_duration == 0.4)
	assert(projectile_definition.impact_scale == 0.9)
	assert(projectile_definition.impact_scale_variance == 0.2)
	assert(projectile_definition.impact_random_rotation)
	assert(projectile_definition.impact_color == Color8(255, 255, 255, 250))
	assert(RwDrawableCatalog.load_texture(projectile_definition.impact_texture_name) != null)
	var trail_test: RwProjectileDefinition = RwProjectileDefinition.new()
	trail_test.damage = 1.0
	trail_test.speed_per_frame = 1.0
	trail_test.lifetime_frames = 20
	trail_test.trail_length_frames = 8
	trail_test.trail_width = 1.0
	trail_test.trail_as_particles = true
	trail_test.trail_emission_interval_frames = 3.0
	trail_test.trail_during_stationary = true
	var trail_test_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	trail_test_weapon.projectile = trail_test
	var source: RwUnitState = RwUnitState.new()
	source.initialize_from_spawn({
		"object_id": 1,
		"source_id": "vanilla",
		"unit_name": "commandCenter",
		"team": "1",
		"position": Vector2.ZERO,
	}, command_center)
	var target: RwUnitState = RwUnitState.new()
	target.initialize_from_spawn({
		"object_id": 2,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(100.0, 0.0),
	}, helicopter_definition)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	assert(is_equal_approx(projectile.velocity.length(), 2.0))
	var initial_position: Vector2 = projectile.world_position
	target.world_position = Vector2(100.0, 20.0)
	assert(not projectile.advance_frame(target))
	assert(projectile.height == 2.0 and projectile.world_position == initial_position)
	for frame: int in 20:
		assert(not projectile.advance_frame(target))
	assert(projectile.height > projectile_definition.altitude_move_start)
	assert(projectile.world_position == initial_position)
	assert(is_equal_approx(projectile.velocity.length(), 2.0))
	var near_ground_target: RwUnitState = RwUnitState.new()
	near_ground_target.initialize_from_spawn({
		"object_id": 3,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(15.0, 0.0),
		"altitude": 0.0,
	}, helicopter_definition)
	near_ground_target.collision_radius = 0.0
	var ascent_projectile: RwProjectileState = RwProjectileState.new()
	ascent_projectile.configure(source, near_ground_target, weapon, 0.0)
	ascent_projectile.world_position = Vector2.ZERO
	for frame: int in 10:
		assert(not ascent_projectile.advance_frame(near_ground_target))
	assert(is_equal_approx(ascent_projectile.height, 20.0), "The missile must finish its ascent before descending toward a nearby target")
	assert(not projectile.advance_frame(target))
	assert(is_equal_approx(projectile.velocity.length(), 2.1) and projectile.velocity.y > 0.0)
	assert(not projectile.trail_positions.is_empty())
	var native_crossing_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	native_crossing_definition.damage = 10.0
	native_crossing_definition.speed_per_frame = 10.0
	native_crossing_definition.native_target_collision_rules = true
	var native_crossing_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	native_crossing_weapon.projectile = native_crossing_definition
	var native_crossing_target: RwUnitState = RwUnitState.new()
	native_crossing_target.initialize_from_spawn({
		"object_id": 4,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(50.0, 0.0),
	}, helicopter_definition)
	native_crossing_target.collision_radius = 0.0
	var native_crossing_projectile: RwProjectileState = RwProjectileState.new()
	native_crossing_projectile.configure(source, native_crossing_target, native_crossing_weapon, 0.0)
	assert(not native_crossing_projectile.advance_frame(native_crossing_target))
	assert(native_crossing_projectile.world_position == Vector2(10.0, 0.0), "Native projectiles must not snap to a target beyond the hit radius")
	var trail_projectile: RwProjectileState = RwProjectileState.new()
	trail_projectile.configure(source, target, trail_test_weapon, 0.0)
	for frame: int in 3:
		assert(not trail_projectile.advance_frame(target))
	assert(trail_projectile.trail_positions.is_empty())
	assert(not trail_projectile.advance_frame(target))
	assert(trail_projectile.trail_positions.size() == 1)
	var previous_position: Vector2 = projectile.world_position
	var previous_lifetime: float = projectile.remaining_frames
	assert(not projectile.advance_frame(null))
	assert(projectile.target_lost)
	assert(not projectile.remove_requested)
	assert(projectile.world_position != previous_position)
	assert(projectile.remaining_frames < previous_lifetime)
	var impact_projectile: RwProjectileState = RwProjectileState.new()
	impact_projectile.configure(source, target, weapon, 0.0)
	var did_hit: bool
	for frame: int in projectile_definition.lifetime_frames:
		if impact_projectile.advance_frame(target):
			did_hit = true
			break
	assert(did_hit, "The command center missile must descend and hit a live target")
	var projectile_layer: RwBattleProjectileLayer = RwBattleProjectileLayer.new()
	projectile_layer.show_impact(projectile, target)
	assert(projectile_layer._impact_flashes.size() == 1)
	assert(projectile_layer._impact_flashes[0]["texture_name"] == "explode_big.png")
	assert(projectile_layer._impact_flashes[0]["frame_count"] == 13)
	assert(projectile_layer._impact_flashes[0]["color"] == Color8(255, 255, 255, 250))
	projectile_layer.finish_projectile(projectile)
	assert(not projectile_layer._detached_trail_particles.is_empty())
	projectile_layer.advance_effects(projectile_definition.trail_particle_lifetime_frames)
	assert(projectile_layer._detached_trail_particles.is_empty())
	projectile_layer._process(projectile_definition.impact_duration + 0.01)
	assert(projectile_layer._impact_flashes.is_empty())
	projectile_layer.free()
	var crossing_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	crossing_definition.damage = 10.0
	crossing_definition.speed_per_frame = 10.0
	crossing_definition.hit_radius = 1.0
	crossing_definition.homing = false
	var crossing_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	crossing_weapon.projectile = crossing_definition
	target.world_position = Vector2(10.0, 15.0)
	target.collision_radius = 0.5
	var crossing_projectile: RwProjectileState = RwProjectileState.new()
	crossing_projectile.configure(source, target, crossing_weapon, 0.0)
	target.world_position = Vector2(10.0, 0.0)
	assert(crossing_projectile.advance_frame(target), "A projectile must collide with the target's actual motion path")


func _test_projectile_ballistic_and_ground_impact() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = RwUnitState.new()
	source.initialize_from_spawn({
		"object_id": 1,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "1",
		"position": Vector2.ZERO,
	}, tank_definition)
	var target: RwUnitState = RwUnitState.new()
	target.initialize_from_spawn({
		"object_id": 2,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "2",
		"position": Vector2(1000.0, 0.0),
	}, tank_definition)
	var default_ballistic_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	default_ballistic_definition.speed_per_frame = 4.0
	default_ballistic_definition.ballistic = true
	default_ballistic_definition.native_target_collision_rules = true
	var default_ballistic_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	default_ballistic_weapon.projectile = default_ballistic_definition
	var default_ballistic_projectile: RwProjectileState = RwProjectileState.new()
	default_ballistic_projectile.configure(source, target, default_ballistic_weapon, 0.0)
	for frame: int in 15:
		assert(not default_ballistic_projectile.advance_frame(target))
	assert(default_ballistic_projectile.height == 60.0, "Unspecified ballistic height uses the original 60-unit default")
	assert(default_ballistic_projectile.world_position == Vector2(16.0, 0.0), "Unspecified ballistic delay uses the original 40-unit threshold")

	var ballistic_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	ballistic_definition.speed_per_frame = 4.0
	ballistic_definition.lifetime_frames = 60
	ballistic_definition.ballistic = true
	ballistic_definition.ballistic_height = 30.0
	ballistic_definition.ballistic_delay_move_height = 25.0
	ballistic_definition.target_speed_per_frame = 5.0
	ballistic_definition.speed_acceleration_per_frame = 0.5
	ballistic_definition.native_target_collision_rules = true
	var ballistic_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	ballistic_weapon.projectile = ballistic_definition
	var ballistic_projectile: RwProjectileState = RwProjectileState.new()
	ballistic_projectile.configure(source, target, ballistic_weapon, 0.0)
	assert(not ballistic_projectile.advance_frame(target))
	assert(ballistic_projectile.height == 4.0, "Original ballistic lift uses the current projectile speed")
	assert(ballistic_projectile.velocity.length() == 4.5, "Ballistic ammunition accelerates while it is still climbing")
	assert(ballistic_projectile.world_position == Vector2.ZERO, "Ballistic projectiles wait for the original height threshold")
	for frame: int in 5:
		assert(not ballistic_projectile.advance_frame(target))
	assert(ballistic_projectile.height == 28.5)
	assert(ballistic_projectile.world_position == Vector2.ZERO)
	assert(not ballistic_projectile.advance_frame(target))
	assert(ballistic_projectile.height == 30.0)
	assert(ballistic_projectile.world_position == Vector2(5.0, 0.0))
	var ground_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	ground_definition.speed_per_frame = 2.0
	ground_definition.target_ground = true
	ground_definition.native_target_collision_rules = true
	var ground_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	ground_weapon.projectile = ground_definition
	var ground_projectile: RwProjectileState = RwProjectileState.new()
	ground_projectile.configure_at(source, Vector2(5.0, 0.0), ground_weapon, 0.0)
	assert(ground_projectile.advance_frame(null), "Original ground-target ammunition impacts inside its six-unit collision radius")
	assert(ground_projectile.world_position == Vector2(2.0, 0.0), "Ground-target impact preserves the position reached during the hit frame")


func _test_native_projectile_profiles() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var hover_tank: RwUnitDefinition = registry.find_definition("vanilla", "hoverTank")
	var mega_tank: RwUnitDefinition = registry.find_definition("vanilla", "megaTank")
	var heavy_tank: RwUnitDefinition = registry.find_definition("vanilla", "heavyTank")
	var ladybug: RwUnitDefinition = registry.find_definition("vanilla", "ladybug")
	assert(hover_tank != null and hover_tank.combat_weapons.size() == 1)
	assert(hover_tank.combat_weapons[0].projectile.texture_region == Rect2i(120, 0, 20, 20))
	assert(hover_tank.combat_weapons[0].projectile.visual_color == Color8(50, 230, 50))
	assert(mega_tank != null and mega_tank.combat_weapons.size() == 1)
	assert(heavy_tank != null and heavy_tank.combat_weapons.size() == 1)
	assert(mega_tank.combat_weapons[0].air_projectile != null)
	assert(heavy_tank.combat_weapons[0].air_projectile != null)
	assert(heavy_tank.combat_weapons[0].air_projectile.altitude_maximum == 15.0)
	assert(heavy_tank.combat_weapons[0].air_projectile.retarget_on_target_loss)
	assert(ladybug != null and ladybug.combat_weapons.size() == 1)
	assert(ladybug.combat_weapons[0].projectile.instant)
	var artillery_definition: RwUnitDefinition = registry.find_definition("vanilla", "artillery")
	assert(artillery_definition != null and artillery_definition.combat_weapons.size() == 1)
	var artillery_projectile: RwProjectileDefinition = artillery_definition.combat_weapons[0].projectile
	assert(artillery_projectile.texture_name == "projectiles.png")
	assert(artillery_projectile.texture_region == Rect2i(40, 0, 20, 20))
	assert(artillery_projectile.large_hit_effect and artillery_projectile.attached_light_cast_on_ground)
	var artillery_turret: RwUnitDefinition = registry.find_definition("vanilla", "turret_artillery")
	assert(artillery_turret.combat_weapons[0].projectile.draw_type == 2)
	assert(artillery_turret.combat_weapons[0].projectile.texture_name == "projectiles2.png")
	var flame_turret: RwUnitDefinition = registry.find_definition("vanilla", "turret_flamethrower")
	assert(flame_turret.combat_weapons[0].projectile.flame_weapon)
	assert(flame_turret.combat_weapons[0].projectile.impact_texture_name == "flame_large.png")
	assert(not flame_turret.combat_weapons[0].projectile.hit_sound)
	var nuke_projectile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"nukeLauncherC",
		"nukeProjectile",
	)
	assert(nuke_projectile.nuke_weapon and nuke_projectile.always_visible_in_fog)
	assert(nuke_projectile.draw_type == 1 and nuke_projectile.shadow_frame >= 0)
	assert(nuke_projectile.impact_texture_name == "explode_big.png")
	var custom_image_projectile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"experiementalCarrier",
		"gunshot",
	)
	assert(custom_image_projectile.texture_name == "builtin:experimental_carrier/projectile.png")
	assert(RwBuiltinUnitImageCatalog.load_texture("experimental_carrier/projectile.png") != null)
	var beam_projectile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile(
		"aaBeamGunship",
		"beam",
	)
	assert(beam_projectile.beam_texture_name == "builtin:shared/beam3.png")
	assert(beam_projectile.beam_start_texture_name == "builtin:shared/beam1_start.png")
	assert(beam_projectile.beam_end_texture_name == "builtin:shared/beam1_end.png")
	assert(beam_projectile.team_color_ratio == 0.5)
	assert(beam_projectile.team_color_source_ratio == 0.8)
	assert(RwBuiltinUnitImageCatalog.load_texture("shared/beam3.png") != null)
	assert(RwBuiltinUnitImageCatalog.load_texture("shared/beam1_start.png") != null)
	assert(RwBuiltinUnitImageCatalog.load_texture("shared/beam1_end.png") != null)
	var beam_source_definition: RwUnitDefinition = registry.find_definition("custom", "aaBeamGunship")
	var beam_source: RwUnitState = _create_combat_test_unit(
		77,
		"aaBeamGunship",
		"1",
		Vector2.ZERO,
		beam_source_definition,
	)
	var beam_combat: RwBattleCombat = RwBattleCombat.new()
	beam_combat.configure({77: beam_source,}, registry, [{"slot": 1, "assigned_color": 0,},])
	var beam_state: RwProjectileState = RwProjectileState.new()
	beam_state.definition = beam_projectile
	beam_combat._configure_source_damage_multiplier(beam_state, beam_source)
	assert(is_equal_approx(beam_state.render_color.r, 0.8 * beam_projectile.visual_color.r))
	assert(beam_state.render_color.g == 1.0)
	assert(is_equal_approx(beam_state.render_color.b, 0.8 * beam_projectile.visual_color.b))
	var smoothing_probe: RwProjectileState = RwProjectileState.new()
	smoothing_probe.heading_degrees = 90.0
	smoothing_probe.render_heading_degrees = 0.0
	smoothing_probe._update_render_heading(1.0)
	assert(smoothing_probe.render_heading_degrees == 12.0)
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	var helicopter: RwUnitState = RwUnitState.new()
	helicopter.initialize_from_spawn({
		"object_id": 100,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
	}, helicopter_definition)
	assert(mega_tank.combat_weapons[0].projectile_for_target(helicopter) == mega_tank.combat_weapons[0].air_projectile)
	assert(heavy_tank.combat_weapons[0].projectile_for_target(helicopter) == heavy_tank.combat_weapons[0].air_projectile)
	var mega_state: RwUnitState = RwUnitState.new()
	mega_state.initialize_from_spawn({
		"object_id": 99,
		"source_id": "vanilla",
		"unit_name": "megaTank",
		"team": "1",
	}, mega_tank)
	helicopter.world_position = Vector2(50.0, 0.0)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({99: mega_state, 100: helicopter,}, registry, [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	])
	combat.advance_frame()
	assert(combat.projectiles.size() == 1)
	assert(combat.projectiles[0].definition == mega_tank.combat_weapons[0].air_projectile)


func _test_native_weapon_coverage() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		if unit_name in ["builderShip", "dropship",]:
			continue
		var definition: RwUnitDefinition = registry.find_definition("vanilla", unit_name)
		if definition != null and definition.attack_range > 0.0:
			assert(not definition.combat_weapons.is_empty(), "Missing stock weapon definition: %s" % unit_name)
			for native_weapon: RwWeaponDefinition in definition.combat_weapons:
				var native_projectiles: Array = [native_weapon.projectile, native_weapon.air_projectile, native_weapon.submerged_projectile,]
				for native_projectile_value: Variant in native_projectiles:
					var native_projectile: RwProjectileDefinition = native_projectile_value as RwProjectileDefinition
					if native_projectile != null:
						assert(native_projectile.native_target_collision_rules, "Native projectile is missing original collision rules: %s" % unit_name)
	for unit_name: String in RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS:
		var builtin_definition: RwUnitDefinition = registry.find_definition("custom", unit_name)
		if builtin_definition == null:
			continue
		for builtin_weapon: RwWeaponDefinition in builtin_definition.combat_weapons:
			var builtin_projectiles: Array = [builtin_weapon.projectile, builtin_weapon.air_projectile, builtin_weapon.submerged_projectile,]
			for builtin_projectile_value: Variant in builtin_projectiles:
				var builtin_projectile: RwProjectileDefinition = builtin_projectile_value as RwProjectileDefinition
				if builtin_projectile != null:
					assert(builtin_projectile.native_target_collision_rules, "Builtin projectile is missing original collision rules: %s" % unit_name)
	var missile_ship: RwUnitDefinition = registry.find_definition("vanilla", "missileShip")
	var missile_weapon: RwWeaponDefinition = missile_ship.combat_weapons[0]
	assert(missile_weapon.projectile.damage == 62.0)
	assert(missile_weapon.submerged_projectile.damage == 42.0)
	assert(missile_weapon.projectile.ballistic and missile_weapon.submerged_projectile.trail_as_particles)
	var battleship: RwUnitDefinition = registry.find_definition("vanilla", "battleShip")
	assert(battleship.combat_weapons.size() == 2)
	assert(battleship.combat_weapons[0].reload_frames == 120 and battleship.combat_weapons[1].reload_frames == 92)
	var heavy_hover_tank: RwUnitDefinition = registry.find_definition("vanilla", "heavyHoverTank")
	assert(heavy_hover_tank.combat_weapons[0].projectile.texture_region.position.x == 140)
	var tank: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var tank_weapon: RwWeaponDefinition = tank.combat_weapons[0]
	assert(tank_weapon.shoot_sound_name == "tank_firing")
	assert(tank_weapon.projectile.deflection_power == 1.0)
	assert(is_equal_approx(tank_weapon.shoot_sound_volume, 0.3))
	assert(tank_weapon.shoot_flame == "small")
	assert(tank_weapon.shoot_light_color == Color8(238, 204, 204, 255))
	var native_turret: RwUnitDefinition = registry.find_definition("vanilla", "turret")
	assert(native_turret.combat_weapons[0].shoot_sound_name == "firing3")
	assert(native_turret.combat_weapons[0].shoot_flame == "small")
	var amphibious_jet: RwUnitDefinition = registry.find_definition("vanilla", "amphibiousJet")
	var jet_weapon: RwWeaponDefinition = amphibious_jet.combat_weapons[0]
	assert(jet_weapon.projectile.instant and jet_weapon.projectile.render_jitter)
	assert(jet_weapon.surface_attack_range == 170.0 and jet_weapon.submerged_attack_range == 100.0)
	assert(not jet_weapon.can_target_air_when_submerged)
	assert(RwAudioCatalog.unit_sound(&"tank_firing") != null)
	assert(RwAudioCatalog.unit_sound(&"firing3") != null)


func _test_laser_defense_and_deflection_power() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var laser_definition: RwUnitDefinition = registry.find_definition("vanilla", "laserDefence")
	assert(laser_definition != null and laser_definition.behavior is RwLaserDefenseBehavior)
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	assert(tank_definition.combat_weapons[0].projectile.deflection_power == 1.0)
	var bomber_projectile: RwProjectileDefinition = RwBuiltinCombatDefinitions.create_projectile_profile("bomber", "1")
	assert(bomber_projectile != null and bomber_projectile.deflection_power == 3.0)
	var defense: RwUnitState = _create_combat_test_unit(
		1,
		"laserDefence",
		"1",
		Vector2.ZERO,
		laser_definition,
	)
	var attacker_definition: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	var attacker: RwUnitState = _create_combat_test_unit(
		2,
		"builder",
		"2",
		Vector2(40.0, 0.0),
		attacker_definition,
	)
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure({1: defense, 2: attacker,}, registry, [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	])
	var bomb_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	bomber_projectile.speed_per_frame = 0.0
	bomber_projectile.target_speed_per_frame = 0.0
	bomb_weapon.projectile = bomber_projectile
	var bomb: RwProjectileState = combat.spawn_projectile_at(
		attacker,
		Vector2(1000.0, 0.0),
		bomb_weapon,
		0.0,
	)
	assert(bomb != null)
	bomb.world_position = Vector2(40.0, 0.0)
	bomb.elapsed_frames = 8.0
	combat.advance_frame()
	assert(bomb.deflection_remaining == 2.0 and not bomb.remove_requested)
	combat.advance_frame()
	assert(bomb.deflection_remaining == 1.0 and not bomb.remove_requested)
	combat.advance_frame()
	assert(combat.projectiles.is_empty(), "A bomber bomb with deflectionPower=3 must take three laser hits")
	assert(is_equal_approx(defense.laser_defense_charge, 0.6708), "Each laser hit must consume 0.11 charge while charging by 0.0004")

	var immune_projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	immune_projectile.target_ground = true
	immune_projectile.speed_per_frame = 0.0
	immune_projectile.deflection_power = -1.0
	var immune_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	immune_weapon.projectile = immune_projectile
	var immune_combat: RwBattleCombat = RwBattleCombat.new()
	var immune_defense: RwUnitState = _create_combat_test_unit(
		3,
		"laserDefence",
		"1",
		Vector2.ZERO,
		laser_definition,
	)
	var immune_attacker: RwUnitState = _create_combat_test_unit(
		4,
		"builder",
		"2",
		Vector2(40.0, 0.0),
		attacker_definition,
	)
	immune_combat.configure({3: immune_defense, 4: immune_attacker,}, registry, [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	])
	var immune_bomb: RwProjectileState = immune_combat.spawn_projectile_at(
		immune_attacker,
		Vector2(1000.0, 0.0),
		immune_weapon,
		0.0,
	)
	immune_bomb.world_position = Vector2(40.0, 0.0)
	immune_bomb.elapsed_frames = 8.0
	immune_combat.advance_frame()
	assert(immune_combat.projectiles.size() == 1 and immune_bomb.deflection_remaining == -1.0)
	assert(immune_defense.laser_defense_charge == 1.0, "Un-deflectable ammunition must not consume laser charge")

	var upgraded_defense: RwUnitState = _create_combat_test_unit(
		5,
		"laserDefence",
		"1",
		Vector2.ZERO,
		laser_definition,
	)
	upgraded_defense.tech_level = 2
	var upgraded_attacker: RwUnitState = _create_combat_test_unit(
		6,
		"builder",
		"2",
		Vector2(180.0, 0.0),
		attacker_definition,
	)
	var upgraded_combat: RwBattleCombat = RwBattleCombat.new()
	upgraded_combat.configure({5: upgraded_defense, 6: upgraded_attacker,}, registry, [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	])
	var upgraded_weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	var upgraded_projectile_definition: RwProjectileDefinition = RwProjectileDefinition.new()
	upgraded_projectile_definition.target_ground = true
	upgraded_projectile_definition.speed_per_frame = 0.0
	upgraded_projectile_definition.deflection_power = 2.0
	upgraded_weapon.projectile = upgraded_projectile_definition
	var upgraded_projectile: RwProjectileState = upgraded_combat.spawn_projectile_at(
		upgraded_attacker,
		Vector2(1000.0, 0.0),
		upgraded_weapon,
		0.0,
	)
	upgraded_projectile.world_position = Vector2(180.0, 0.0)
	upgraded_projectile.elapsed_frames = 8.0
	upgraded_combat.advance_frame()
	assert(upgraded_projectile.deflection_remaining == 1.0, "Upgraded laser defense must intercept within 210 units")
	assert(is_equal_approx(upgraded_defense.laser_defense_charge, 0.95), "Upgraded laser defense must cap charge before spending 0.05")


func _test_native_weapon_muzzle_effects() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var source: RwUnitState = _create_combat_test_unit(1, "tank", "1", Vector2(40.0, 60.0), tank_definition)
	var target: RwUnitState = _create_combat_test_unit(2, "tank", "2", Vector2(140.0, 60.0), tank_definition)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, tank_definition.combat_weapons[0], 0.0)
	var projectile_layer: RwBattleProjectileLayer = RwBattleProjectileLayer.new()
	projectile_layer.show_creation(projectile)
	assert(projectile_layer._projectile_effects.size() == 2)
	assert(projectile_layer._projectile_effects[0]["texture_name"] == "flame.png")
	assert(projectile_layer._projectile_effects[1]["texture_name"] == "light_50.png")
	assert(projectile_layer._projectile_effects[0]["position"] == projectile.origin_position)
	projectile_layer.free()


func _test_command_center_target_reacquisition() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var command_center: RwUnitDefinition = registry.find_definition("vanilla", "commandCenter")
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	var source: RwUnitState = RwUnitState.new()
	source.initialize_from_spawn({
		"object_id": 10,
		"source_id": "vanilla",
		"unit_name": "commandCenter",
		"team": "1",
		"position": Vector2.ZERO,
		"build_progress": 0.5,
	}, command_center)
	var lost_target: RwUnitState = RwUnitState.new()
	lost_target.initialize_from_spawn({
		"object_id": 11,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(80.0, 0.0),
	}, helicopter_definition)
	lost_target.is_dead = true
	var replacement_target: RwUnitState = RwUnitState.new()
	replacement_target.initialize_from_spawn({
		"object_id": 12,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(45.0, 18.0),
	}, helicopter_definition)
	var units: Dictionary = {10: source, 11: lost_target, 12: replacement_target,}
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, lost_target, command_center.combat_weapons[0], 0.0)
	combat.projectiles.append(projectile)
	source.is_dead = true
	combat.advance_frame()
	assert(projectile.target_id == replacement_target.object_id)
	assert(not projectile.target_lost)
	var unmatched_projectile: RwProjectileState = RwProjectileState.new()
	combat.configure({10: source, 11: lost_target,}, registry, players)
	unmatched_projectile.configure(source, lost_target, command_center.combat_weapons[0], 0.0)
	combat.projectiles.append(unmatched_projectile)
	combat.advance_frame()
	assert(unmatched_projectile.target_lost)
	assert(unmatched_projectile.target_id == lost_target.object_id)
	assert(not unmatched_projectile.remove_requested)
	assert(combat.projectiles.has(unmatched_projectile))
	_test_native_projectile_collision_rule(registry, command_center)


func _test_native_projectile_collision_rule(registry: RwUnitRegistry, command_center: RwUnitDefinition) -> void:
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	var weapon: RwWeaponDefinition = command_center.combat_weapons[0]
	var projectile_definition: RwProjectileDefinition = weapon.projectile
	var source: RwUnitState = RwUnitState.new()
	source.initialize_from_spawn({
		"object_id": 30,
		"source_id": "vanilla",
		"unit_name": "commandCenter",
		"team": "1",
	}, command_center)
	var target: RwUnitState = RwUnitState.new()
	target.initialize_from_spawn({
		"object_id": 31,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "2",
		"position": Vector2(12.0, 0.0),
	}, helicopter_definition)
	target.collision_radius = 10.0
	target.altitude = 2.0
	target.health = 20.0
	var projectile: RwProjectileState = RwProjectileState.new()
	projectile.configure(source, target, weapon, 0.0)
	projectile.world_position = Vector2(3.0, 0.0)
	assert(not projectile.advance_frame(target), "Low-health targets must use the original 0.8 collision-radius scale")
	target.shield = 100.0
	projectile.configure(source, target, weapon, 0.0)
	projectile.world_position = Vector2(3.0, 0.0)
	assert(not projectile.advance_frame(target), "Shield value must not change the original health-based hit radius")
	target.shield = 0.0
	target.health = 100.0
	projectile.configure(source, target, weapon, 0.0)
	projectile.world_position = Vector2(3.0, 0.0)
	assert(projectile.advance_frame(target), "Healthy targets must use the original 1.1 collision-radius scale")
	var building_definition: RwUnitDefinition = registry.find_definition("vanilla", "landFactory")
	var building: RwUnitState = RwUnitState.new()
	building.initialize_from_spawn({
		"object_id": 32,
		"source_id": "vanilla",
		"unit_name": "landFactory",
		"team": "2",
		"position": Vector2(12.0, 0.0),
	}, building_definition)
	building.collision_radius = 10.0
	building.is_building = true
	building.health = 1.0
	building.build_progress = 0.5
	var building_projectile: RwProjectileState = RwProjectileState.new()
	building_projectile.configure(source, building, weapon, 0.0)
	building_projectile.world_position = Vector2(5.0, 0.0)
	assert(building_projectile.advance_frame(building), "Under-construction buildings must use the original reduced hit radius")
	building.build_progress = 1.0
	var completed_building_projectile: RwProjectileState = RwProjectileState.new()
	completed_building_projectile.configure(source, building, weapon, 0.0)
	completed_building_projectile.world_position = Vector2(5.0, 0.0)
	assert(completed_building_projectile.advance_frame(building), "Completed buildings must retain the original reduced building hit radius")


func _test_attack_move_acquisition() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var helicopter_definition: RwUnitDefinition = registry.find_definition("vanilla", "helicopter")
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	assert(helicopter_definition != null and helicopter_definition.combat_weapons.size() > 0)
	var helicopter: RwUnitState = RwUnitState.new()
	helicopter.initialize_from_spawn({
		"object_id": 1,
		"source_id": "vanilla",
		"unit_name": "helicopter",
		"team": "1",
		"position": Vector2.ZERO,
	}, helicopter_definition)
	helicopter.attack_mode = 0
	helicopter.apply_move_order(Vector2(800.0, 0.0), [], "attackMove")
	var target: RwUnitState = RwUnitState.new()
	target.initialize_from_spawn({
		"object_id": 2,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "2",
		"position": Vector2(330.0, 0.0),
	}, tank_definition)
	var units: Dictionary = {1: helicopter, 2: target,}
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	helicopter.navigation_repath_timer = 240.0
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_attack_target_id == target.object_id)
	assert(helicopter.navigation_attack_override_active, "Acquiring an out-of-range target must immediately replace the navigation endpoint")
	assert(helicopter.navigation_repath_timer == 0.0)
	assert(helicopter.navigation_repath_requested)
	assert(helicopter.navigation_attack_target_position == target.world_position)
	helicopter.navigation_repath_requested = false
	helicopter.navigation_repath_timer = 500.0
	target.world_position += Vector2(20.0, 0.0)
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_repath_timer == 90.0)
	assert(not helicopter.navigation_repath_requested)
	helicopter.navigation_repath_timer = 1.0
	target.world_position += Vector2(5.0, 0.0)
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_repath_requested)
	assert(helicopter.navigation_attack_target_position == target.world_position)
	var controller: RwUnitOrderController = RwUnitOrderController.new()
	controller.configure(units, registry, null)
	controller.apply_command({
		"team": 1,
		"source_team": 1,
		"unit_ids": [1,],
		"order_type": "attackMove",
		"target": Vector2(800.0, 0.0),
	})
	assert(helicopter.order_target == Vector2(800.0, 0.0))


func _test_attack_move_pursuit_preempts_long_path() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var helicopter_definition: RwUnitDefinition = registry.find_definition("custom", "c_helicopter")
	var builder_definition: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	assert(helicopter_definition != null and helicopter_definition.combat_weapons.size() > 0)
	assert(builder_definition != null)
	var helicopter: RwUnitState = RwUnitState.new()
	helicopter.initialize_from_spawn({
		"object_id": 335,
		"source_id": "custom",
		"unit_name": "c_helicopter",
		"team": "0",
		"position": Vector2(221.27734, 1197.0564),
	}, helicopter_definition)
	helicopter.attack_mode = 0
	var command_target: Vector2 = Vector2(705.23486, 1349.9924)
	helicopter.apply_move_order(command_target, [command_target,], "attackMove")
	var builder: RwUnitState = RwUnitState.new()
	builder.initialize_from_spawn({
		"object_id": 298,
		"source_id": "vanilla",
		"unit_name": "builder",
		"team": "1",
		"position": Vector2(544.37823, 1244.9607),
	}, builder_definition)
	var units: Dictionary = {335: helicopter, 298: builder,}
	var players: Array[Dictionary] = [
		{"slot": 0, "color": 0,},
		{"slot": 1, "color": 1,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	helicopter.navigation_repath_timer = 240.0
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_attack_target_id == builder.object_id)
	assert(helicopter.navigation_attack_override_active, "A newly acquired target must immediately replace the stale path goal")
	assert(helicopter.navigation_attack_target_position == builder.world_position)
	assert(helicopter.navigation_repath_timer == 0.0)
	assert(helicopter.navigation_repath_requested)
	var controller: RwUnitOrderController = RwUnitOrderController.new()
	controller.configure(units, registry, null)
	controller.prepare_pending_path(helicopter)
	assert(helicopter.order_target == command_target, "Pursuit must keep the synchronized attack-move destination")
	assert(helicopter.navigation_repath_timer == 500.0)
	var negative_position_unit: RwUnitState = RwUnitState.new()
	negative_position_unit.initialize_from_spawn({
		"object_id": 336,
		"source_id": "custom",
		"unit_name": "c_helicopter",
		"team": "0",
		"position": Vector2(-1.0, -2.0),
	}, helicopter_definition)
	negative_position_unit.attack_mode = 0
	negative_position_unit.apply_move_order(Vector2(0.0, 0.0), [], "attackMove")
	var nearby_builder: RwUnitState = RwUnitState.new()
	nearby_builder.initialize_from_spawn({
		"object_id": 299,
		"source_id": "vanilla",
		"unit_name": "builder",
		"team": "1",
		"position": Vector2(100.0, -2.0),
	}, builder_definition)
	var negative_units: Dictionary = {336: negative_position_unit, 299: nearby_builder,}
	var negative_combat: RwBattleCombat = RwBattleCombat.new()
	negative_combat.configure(negative_units, registry, players)
	negative_combat.prepare_navigation_target(negative_position_unit)
	assert(negative_position_unit.navigation_attack_search_timer == 17.0, "Search staggering must preserve Java's signed float remainder")


func _test_turret() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var turret_definition: RwUnitDefinition = registry.find_definition("vanilla", "turret")
	var tank_definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var turret: RwUnitState = RwUnitState.new()
	turret.initialize_from_spawn({
		"object_id": 1,
		"source_id": "vanilla",
		"unit_name": "turret",
		"team": "1",
		"position": Vector2.ZERO,
	}, turret_definition)
	var target: RwUnitState = RwUnitState.new()
	target.initialize_from_spawn({
		"object_id": 2,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": "2",
		"position": Vector2(0.0, 100.0),
		"build_progress": 0.5,
	}, tank_definition)
	var units: Dictionary = {1: turret, 2: target,}
	var players: Array[Dictionary] = [
		{"slot": 1, "color": 1,},
		{"slot": 2, "color": 2,},
	]
	var combat: RwBattleCombat = RwBattleCombat.new()
	combat.configure(units, registry, players)
	for frame: int in 120:
		combat.advance_frame()
	assert(target.health < target.max_health)
	assert(turret.get_weapon_rotation(0) > 80.0)


func _on_projectile_fired(_projectile: RwProjectileState) -> void:
	_shots += 1


func _on_unit_destroyed(_unit_state: RwUnitState) -> void:
	_deaths += 1
