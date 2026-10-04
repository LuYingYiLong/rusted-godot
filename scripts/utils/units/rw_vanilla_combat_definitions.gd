class_name RwVanillaCombatDefinitions
extends RefCounted
## 首批原版武器定义，基础伤害、射程、冷却和弹速参考 RWX


## 为坦克配置普通炮弹和自动攻击行为
static func configure_tank(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 30.0
	projectile.speed_per_frame = 3.0
	projectile.texture_name = "projectiles.png"
	projectile.texture_region = Rect2i(20, 0, 20, 20)
	var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
	weapon.projectile = projectile
	weapon.attack_range = 130.0
	weapon.reload_frames = 75
	weapon.turn_speed_degrees = 4.0
	weapon.muzzle_distance = 13.0
	weapon.can_target_water = true
	definition.combat_weapons = [weapon,]
	definition.behavior = RwAutoAttackBehavior.new()


## 为指挥中心配置追踪弹及自动防卫行为
static func configure_command_center(definition: RwUnitDefinition) -> void:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.damage = 70.0
	projectile.speed_per_frame = 2.0
	projectile.target_speed_per_frame = 5.0
	projectile.speed_acceleration_per_frame = 0.1
	projectile.lifetime_frames = 180
	projectile.visual_color = Color8(230, 230, 50)
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
	projectile.visual_color = Color8(100, 30, 30)
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
