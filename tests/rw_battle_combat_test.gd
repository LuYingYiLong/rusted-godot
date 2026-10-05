extends SceneTree

var _shots: int
var _deaths: int


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle_scene: PackedScene = load("uid://c0w7n4afw43pa") as PackedScene
	assert(battle_scene != null)
	var battle_map: Node = battle_scene.instantiate()
	assert(battle_map.get_node("MapRoot/ProjectileLayer") is RwBattleProjectileLayer)
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
	_test_command_center_projectile()
	_test_command_center_target_reacquisition()
	_test_attack_move_acquisition()
	_test_native_projectile_profiles()
	_test_native_weapon_coverage()
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
	projectile_definition.speed_per_frame = 10.0
	projectile_definition.splash_radius = 15.0
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile_definition
	var projectile: RwProjectileState = combat.spawn_projectile_at(units[1], Vector2(30.0, 0.0), weapon, 0.0)
	assert(projectile != null and projectile.target_id == -1)
	for frame: int in 3:
		combat.advance_frame()
	assert((units[2] as RwUnitState).health == 190.0)
	assert((units[1] as RwUnitState).health == 210.0)


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
	assert(projectile_definition.remove_on_target_loss)
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
	assert(projectile.remove_requested)
	assert(projectile.world_position == previous_position)
	assert(projectile.remaining_frames == previous_lifetime)
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
	var amphibious_jet: RwUnitDefinition = registry.find_definition("vanilla", "amphibiousJet")
	var jet_weapon: RwWeaponDefinition = amphibious_jet.combat_weapons[0]
	assert(jet_weapon.projectile.instant and jet_weapon.projectile.render_jitter)
	assert(jet_weapon.surface_attack_range == 170.0 and jet_weapon.submerged_attack_range == 100.0)
	assert(not jet_weapon.can_target_air_when_submerged)


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
	assert(not completed_building_projectile.advance_frame(building), "Completed buildings must not use the construction-slot hit radius")


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
	helicopter.navigation_repath_timer = 2.0
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_attack_target_id == target.object_id)
	assert(not helicopter.navigation_attack_override_active)
	helicopter.navigation_repath_timer = 1.0
	combat.prepare_navigation_target(helicopter)
	assert(helicopter.navigation_attack_target_id == target.object_id)
	assert(helicopter.navigation_attack_override_active)
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
