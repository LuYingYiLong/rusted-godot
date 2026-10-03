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
	var economy: RwVanillaEconomy = RwVanillaEconomy.new()
	economy.initialize([{"slot": 1, "credits": 0,},], 1.0)
	economy.set_command_centers({1: 1,})
	assert(economy.get_income_rate(1, "credits") == 18.0)
	economy.reconcile_credits(1, 125.0)
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
