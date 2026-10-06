class_name RwVanillaCombatDefinitions
extends RefCounted
## 首批原版武器定义，基础伤害、射程、冷却和弹速参考 RWX


## 补充尚无 RWX 内置替换配置的原版单位武器
static func register_native_weapons(registry: RwUnitRegistry) -> void:
	_configure_hover_tank(registry.find_definition("vanilla", "hoverTank"))
	_configure_mega_tank(registry.find_definition("vanilla", "megaTank"))
	_configure_heavy_tank(registry.find_definition("vanilla", "heavyTank"))
	_configure_gunship(registry.find_definition("vanilla", "gunShip"))
	_configure_missile_ship(registry.find_definition("vanilla", "missileShip"))
	_configure_gun_boat(registry.find_definition("vanilla", "gunBoat"))
	_configure_battleship(registry.find_definition("vanilla", "battleShip"))
	_configure_tank_destroyer(registry.find_definition("vanilla", "tankDestroyer"))
	_configure_heavy_hover_tank(registry.find_definition("vanilla", "heavyHoverTank"))
	_configure_amphibious_jet(registry.find_definition("vanilla", "amphibiousJet"))
	_configure_ladybug(registry.find_definition("vanilla", "ladybug"))


## 为坦克配置普通炮弹和自动攻击行为
static func configure_tank(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 25.0
	projectile.speed_per_frame = 5.0
	projectile.texture_name = "projectiles.png"
	projectile.texture_region = Rect2i(20, 0, 20, 20)
	projectile.texture_rotation_offset_degrees = 90.0
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 130.0
	weapon.reload_frames = 75
	weapon.turn_speed_degrees = 4.0
	weapon.muzzle_distance = 0.0
	weapon.can_target_water = true
	definition.combat_weapons = [weapon,]
	definition.behavior = RwAutoAttackBehavior.new()


## 配置悬浮坦克的绿色追踪弹
static func _configure_hover_tank(definition: RwUnitDefinition) -> void:
	if definition == null or not definition.combat_weapons.is_empty():
		return
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 23.0
	projectile.speed_per_frame = 2.0
	projectile.target_speed_per_frame = 6.0
	projectile.speed_acceleration_per_frame = 0.2
	projectile.lifetime_frames = 85
	projectile.texture_name = "projectiles.png"
	projectile.texture_region = Rect2i(120, 0, 20, 20)
	projectile.visual_color = Color8(50, 230, 50)
	projectile.texture_rotation_offset_degrees = 90.0
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 140.0
	weapon.reload_frames = 90
	weapon.turn_speed_degrees = 4.0
	weapon.muzzle_distance = 2.0
	definition.combat_weapons = [weapon,]
	definition.attack_range = weapon.attack_range
	definition.behavior = RwAutoAttackBehavior.new()


## 配置重型坦克对地炮弹和对空升降弹
static func _configure_heavy_tank(definition: RwUnitDefinition) -> void:
	if definition == null or not definition.combat_weapons.is_empty():
		return
	var ground_projectile: RwProjectileDefinition = _create_native_shell(50.0, 4.0, 60)
	var air_projectile: RwProjectileDefinition = _create_native_shell(50.0, 0.5, 190)
	air_projectile.target_speed_per_frame = 5.0
	air_projectile.speed_acceleration_per_frame = 0.1
	air_projectile.altitude_move_start = 10.0
	air_projectile.altitude_maximum = 15.0
	air_projectile.altitude_change_per_frame = 2.0
	air_projectile.altitude_descent_range = 20.0
	air_projectile.retarget_on_target_loss = true
	air_projectile.target_loss_retarget_range = 120.0
	air_projectile.target_loss_retarget_lead_distance = 15.0
	air_projectile.trail_length_frames = 18
	air_projectile.trail_width = 1.2
	air_projectile.trail_color = Color8(170, 170, 170, 100)
	air_projectile.trail_as_particles = true
	air_projectile.trail_emission_interval_frames = 3.0
	air_projectile.trail_texture_name = "smoke_white.png"
	air_projectile.trail_texture_frame_size = Vector2i(19, 19)
	air_projectile.trail_texture_scale = 0.25
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = ground_projectile
	weapon.air_projectile = air_projectile
	weapon.attack_range = 160.0
	weapon.reload_frames = 60
	weapon.turn_speed_degrees = 3.0
	weapon.muzzle_distance = 21.0
	weapon.can_target_air = true
	weapon.can_target_water = true
	definition.combat_weapons = [weapon,]
	definition.attack_range = weapon.attack_range
	definition.behavior = RwAutoAttackBehavior.new()


## 配置超重坦克按目标高度切换绿色炮弹和黄色升降弹
static func _configure_mega_tank(definition: RwUnitDefinition) -> void:
	if definition == null or not definition.combat_weapons.is_empty():
		return
	var ground_projectile: RwProjectileDefinition = _create_native_shell(50.0, 3.0, 60)
	var air_projectile: RwProjectileDefinition = _create_native_shell(40.0, 4.0, 190)
	air_projectile.visual_color = Color8(230, 230, 50)
	air_projectile.altitude_move_start = 10.0
	air_projectile.altitude_maximum = 15.0
	air_projectile.altitude_change_per_frame = 2.0
	air_projectile.altitude_descent_range = 20.0
	air_projectile.trail_length_frames = 18
	air_projectile.trail_width = 1.2
	air_projectile.trail_color = Color8(170, 170, 170, 100)
	air_projectile.trail_as_particles = true
	air_projectile.trail_emission_interval_frames = 3.0
	air_projectile.trail_texture_name = "smoke_white.png"
	air_projectile.trail_texture_frame_size = Vector2i(19, 19)
	air_projectile.trail_texture_scale = 0.25
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = ground_projectile
	weapon.air_projectile = air_projectile
	weapon.attack_range = 140.0
	weapon.reload_frames = 70
	weapon.turn_speed_degrees = 2.0
	weapon.muzzle_distance = 12.0
	weapon.can_target_air = true
	weapon.can_target_water = true
	definition.combat_weapons = [weapon,]
	definition.attack_range = weapon.attack_range
	definition.behavior = RwAutoAttackBehavior.new()


## 配置瓢虫单位的瞬发近战攻击
static func _configure_ladybug(definition: RwUnitDefinition) -> void:
	if definition == null or not definition.combat_weapons.is_empty():
		return
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 14.0
	projectile.instant = true
	projectile.hit_radius = 0.0
	projectile.include_target_collision_radius = false
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 43.0
	weapon.reload_frames = 17
	weapon.turn_speed_degrees = 99.0
	weapon.can_target_air = false
	weapon.can_target_water = false
	definition.combat_weapons = [weapon,]
	definition.attack_range = weapon.attack_range
	definition.behavior = RwAutoAttackBehavior.new()


static func _configure_gunship(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = _create_native_projectile(35.0, 4.0, 80, Color8(150, 230, 40))
	var weapon: RwWeaponDefinition = _create_native_weapon(projectile, 140.0, 40, 99.0, 15.0)
	weapon.can_target_air = false
	_apply_native_weapon(definition, weapon)


static func _configure_missile_ship(definition: RwUnitDefinition) -> void:
	var surface_projectile: RwProjectileDefinition = _create_native_projectile(62.0, 2.0, 190, Color8(230, 230, 50))
	surface_projectile.ballistic = true
	surface_projectile.altitude_move_start = 40.0
	surface_projectile.altitude_maximum = 60.0
	surface_projectile.altitude_change_per_frame = 2.0
	surface_projectile.altitude_descent_range = 20.0
	surface_projectile.small_explosion = true
	_configure_native_smoke_trail(surface_projectile)
	var submerged_projectile: RwProjectileDefinition = _create_native_projectile(42.0, 1.9, 220, Color8(0, 0, 150))
	submerged_projectile.texture_scale = 1.0
	submerged_projectile.small_explosion = true
	_configure_native_smoke_trail(submerged_projectile)
	var weapon: RwWeaponDefinition = _create_native_weapon(surface_projectile, 200.0, 170, 99.0, 6.0)
	weapon.submerged_projectile = submerged_projectile
	weapon.can_target_water = true
	_apply_native_weapon(definition, weapon)


static func _configure_gun_boat(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = _create_native_projectile(12.0, 8.0, 30, Color8(180, 180, 0))
	projectile.visible_in_flight = false
	var weapon: RwWeaponDefinition = _create_native_weapon(projectile, 120.0, 60, 99.0, 6.0)
	_apply_native_weapon(definition, weapon)


static func _configure_battleship(definition: RwUnitDefinition) -> void:
	var first_projectile: RwProjectileDefinition = _create_native_projectile(65.0, 4.0, 80, Color8(180, 180, 0))
	first_projectile.texture_scale = 2.0
	first_projectile.small_explosion = true
	var second_projectile: RwProjectileDefinition = first_projectile.duplicate() as RwProjectileDefinition
	var first_weapon: RwWeaponDefinition = _create_native_weapon(first_projectile, 240.0, 120, 2.5, 22.0)
	var second_weapon: RwWeaponDefinition = _create_native_weapon(second_projectile, 240.0, 92, 2.5, 4.0)
	second_weapon.warmup_frames = 30
	_apply_native_weapons(definition, [first_weapon, second_weapon,])


static func _configure_tank_destroyer(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = _create_native_projectile(35.0, 3.0, 60, Color8(100, 30, 30))
	var weapon: RwWeaponDefinition = _create_native_weapon(projectile, 150.0, 70, 3.0, 10.0)
	_apply_native_weapon(definition, weapon)


static func _configure_heavy_hover_tank(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = _create_native_projectile(40.0, 1.0, 95, Color8(230, 0, 50))
	projectile.target_speed_per_frame = 7.0
	projectile.speed_acceleration_per_frame = 0.2
	projectile.texture_name = "projectiles.png"
	projectile.texture_region = Rect2i(140, 0, 20, 20)
	projectile.texture_scale = 1.0
	var weapon: RwWeaponDefinition = _create_native_weapon(projectile, 160.0, 75, 2.4, 0.0)
	weapon.rotation_state_index = 0
	_apply_native_weapon(definition, weapon)


static func _configure_amphibious_jet(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = _create_native_projectile(45.0, 4.0, 10, Color8(247, 212, 129))
	projectile.instant = true
	projectile.render_jitter = true
	projectile.small_explosion = false
	projectile.building_damage_multiplier = 0.5
	projectile.shield_damage_multiplier = 1.0
	projectile.shield_deflection_multiplier = 0.1
	var weapon: RwWeaponDefinition = _create_native_weapon(projectile, 170.0, 110, 4.0, 0.0)
	weapon.surface_attack_range = 170.0
	weapon.submerged_attack_range = 100.0
	weapon.can_target_air = true
	weapon.can_target_air_when_submerged = false
	weapon.can_target_water = true
	_apply_native_weapon(definition, weapon)


static func _create_native_projectile(
	damage: float,
	speed: float,
	lifetime: int,
	color: Color,
) -> RwProjectileDefinition:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = damage
	projectile.speed_per_frame = speed
	projectile.lifetime_frames = lifetime
	projectile.visual_color = color
	projectile.visual_radius = 2.0
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	return projectile


static func _create_native_weapon(
	projectile: RwProjectileDefinition,
	attack_range: float,
	reload_frames: int,
	turn_speed_degrees: float,
	muzzle_distance: float,
) -> RwWeaponDefinition:
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = attack_range
	weapon.reload_frames = reload_frames
	weapon.turn_speed_degrees = turn_speed_degrees
	weapon.muzzle_distance = muzzle_distance
	return weapon


static func _configure_native_smoke_trail(projectile: RwProjectileDefinition) -> void:
	projectile.trail_length_frames = 24
	projectile.trail_width = 1.4
	projectile.trail_color = Color8(180, 180, 180, 115)
	projectile.trail_as_particles = true
	projectile.trail_emission_interval_frames = 3.0
	projectile.trail_texture_name = "smoke_white.png"
	projectile.trail_texture_frame_size = Vector2i(19, 19)
	projectile.trail_texture_scale = 0.25


static func _apply_native_weapon(definition: RwUnitDefinition, weapon: RwWeaponDefinition) -> void:
	_apply_native_weapons(definition, [weapon,])


static func _apply_native_weapons(definition: RwUnitDefinition, weapons: Array[RwWeaponDefinition]) -> void:
	if definition == null or not definition.combat_weapons.is_empty():
		return
	definition.combat_weapons = weapons
	for weapon: RwWeaponDefinition in weapons:
		definition.attack_range = maxf(definition.attack_range, weapon.attack_range)
	definition.behavior = RwAutoAttackBehavior.new()


## 创建原版小型炮弹的公共参数
static func _create_native_shell(damage: float, speed: float, lifetime: int) -> RwProjectileDefinition:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = damage
	projectile.speed_per_frame = speed
	projectile.lifetime_frames = lifetime
	projectile.visual_color = Color8(150, 230, 40)
	projectile.visual_radius = 2.0
	projectile.lead_target = false
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	return projectile


## 为指挥中心配置追踪弹及自动防卫行为
static func configure_command_center(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 70.0
	projectile.speed_per_frame = 2.0
	projectile.target_speed_per_frame = 5.0
	projectile.speed_acceleration_per_frame = 0.1
	projectile.lifetime_frames = 180
	projectile.ballistic_vertical_speed = 2.0
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	projectile.retarget_on_target_loss = true
	projectile.remove_on_target_loss = false
	projectile.target_loss_retarget_range = 120.0
	projectile.target_loss_retarget_lead_distance = 15.0
	projectile.lead_target = false
	projectile.visual_radius = 2.0
	projectile.visual_color = Color8(230, 230, 50)
	projectile.render_shadow = true
	projectile.small_explosion = true
	projectile.altitude_move_start = 40.0
	projectile.altitude_maximum = 60.0
	projectile.altitude_change_per_frame = 2.0
	projectile.altitude_descent_range = 20.0
	projectile.altitude_hit_tolerance = 3.0
	projectile.trail_length_frames = 24
	projectile.trail_width = 25.0
	projectile.trail_color = Color8(255, 255, 255, 128)
	projectile.trail_as_particles = true
	projectile.trail_emission_interval_frames = 3.0
	projectile.trail_texture_name = "effects.png"
	projectile.trail_texture_frame_size = Vector2i(25, 25)
	projectile.trail_texture_frame_offset = Vector2i(1, 1)
	projectile.trail_texture_frame_step = Vector2i(26, 26)
	projectile.trail_texture_scale = 1.0
	projectile.trail_animate_frames = false
	projectile.trail_particle_scale_from = 1.2
	projectile.trail_particle_scale_to = 0.5
	projectile.trail_particle_fade_duration_frames = 65.0
	projectile.trail_particle_fade_in_duration_frames = 5.0
	projectile.trail_particle_drift_y_per_frame = 0.1
	projectile.trail_particle_shadow = true
	projectile.trail_during_stationary = true
	projectile.impact_texture_name = "explode_big.png"
	projectile.impact_frame_size = Vector2i(39, 40)
	projectile.impact_frame_offset = Vector2i(1, 1)
	projectile.impact_frame_step = Vector2i(40, 41)
	projectile.impact_frame_count = 13
	projectile.impact_duration = 0.583333
	projectile.impact_animation_duration = 0.4
	projectile.impact_scale = 0.9
	projectile.impact_scale_variance = 0.2
	projectile.impact_random_rotation = true
	projectile.impact_color = Color8(255, 255, 255, 250)
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 280.0
	weapon.reload_frames = 70
	weapon.turn_speed_degrees = 999.0
	weapon.can_target_air = true
	weapon.can_target_water = true
	definition.combat_weapons = [weapon,]
	definition.behavior = RwAutoAttackBehavior.new()


## 为一级普通炮塔配置炮弹和自动攻击行为
static func configure_turret(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 41.0
	projectile.speed_per_frame = 5.0
	projectile.texture_name = "projectiles.png"
	projectile.texture_region = Rect2i(100, 0, 20, 20)
	projectile.texture_rotation_offset_degrees = 90.0
	projectile.visual_color = Color8(100, 30, 30)
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 165.0
	weapon.reload_frames = 30
	weapon.turn_speed_degrees = 4.0
	weapon.muzzle_offset = Vector2(0.0, -5.0)
	weapon.muzzle_distance = 21.0
	weapon.can_target_water = true
	definition.attack_range = weapon.attack_range
	definition.combat_weapons = [weapon,]
	definition.behavior = RwAutoAttackBehavior.new()
