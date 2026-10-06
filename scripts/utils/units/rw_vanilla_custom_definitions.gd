extends RefCounted
class_name RwVanillaCustomDefinitions
## 将 RWX 内置 INI 数据转换为可绘制的单位定义

const WEAPON_STATE_COUNTS: Dictionary = {
	"airShip": 2,
	"c_interceptor": 2,
	"battleShip": 2,
	"experimentalTank": 10,
	"c_experimentalTank": 10,
	"amphibiousJet": 3,
	"antiAirTurretT2": 3,
	"c_antiAirTurretT2": 3,
}
## 原版 INI 中同时启用 moveSlidingMode 和 moveIgnoringBody 的单位
const SLIDING_UNIT_TYPES: Array[String] = [
	"aaBeamGunship",
	"c_amphibiousJet",
	"bugMeleeT31",
	"combatEngineer",
	"experimentalDropship",
	"experimentalGunship",
	"fireBee",
	"heavyInterceptor",
	"c_helicopter",
	"c_interceptor",
	"lightGunship",
	"mechBunker",
	"mechHeavyMissile",
	"mechLightning",
	"mechEngineer",
	"missileAirship",
	"scout",
	"bugPickup",
	"bugWasp",
	"bugRangedT2",
	"bugBee",
	"bugFly",
	"bugMelee",
	"bugMeleeLarge",
	"bugMeleeSmall",
	"bugRanged",
	"bugSpore",
]


## 注册游戏自带的自定义单位及其升级和形态变体
static func register_definitions(registry: RwUnitRegistry, assets: RwVanillaUnitAssets) -> void:
	for unit_name: String in RwBuiltinUnitSpecs.SPECS:
		var spec: Dictionary = RwBuiltinUnitSpecs.SPECS[unit_name]
		registry.register_definition(create_definition(unit_name, spec, "custom"), assets)


## 由原版数值和纹理配置创建可绘制单位定义
static func create_definition(unit_name: String, spec: Dictionary, source_id: String) -> RwUnitDefinition:
	var definition: RwUnitDefinition = RwUnitDefinition.new()
	definition.source_id = source_id
	definition.unit_name = unit_name
	definition.display_name = str(spec.get("display_name", unit_name))
	definition.description = str(spec.get("description", ""))
	definition.weapon_state_count = int(WEAPON_STATE_COUNTS.get(unit_name, 1))
	definition.body_image = str(spec["body"])
	definition.visual_hidden = bool(spec.get("hidden", false))
	definition.dead_image = str(spec.get("dead", ""))
	definition.hide_on_death = bool(spec.get("hide_on_death", definition.dead_image.is_empty()))
	definition.back_image = str(spec.get("back", ""))
	definition.shadow_image = str(spec.get("shadow", ""))
	definition.shadow_is_silhouette = bool(spec.get("shadow_silhouette", false))
	definition.generates_shadow = bool(spec.get("generated_shadow", false))
	definition.shadow_offset = Vector2(float(spec.get("shadow_offset_x", 0.0)), float(spec.get("shadow_offset_y", 0.0)))
	definition.body_frames = int(spec.get("frames", 1))
	definition.idle_animation_start = int(spec.get("idle_animation_start", 0))
	definition.idle_animation_end = int(spec.get("idle_animation_end", 0))
	definition.idle_animation_step = float(spec.get("idle_animation_step", 0.0))
	definition.idle_animation_ping_pong = bool(spec.get("idle_animation_ping_pong", false))
	definition.moving_animation_start = int(spec.get("moving_animation_start", 0))
	definition.moving_animation_end = int(spec.get("moving_animation_end", 0))
	definition.moving_animation_step = float(spec.get("moving_animation_step", 0.0))
	definition.moving_animation_ping_pong = bool(spec.get("moving_animation_ping_pong", false))
	var scale: float = float(spec.get("scale", 1.0))
	definition.body_scale = Vector2(scale, scale)
	definition.body_team_colored = bool(spec.get("team_colored", true))
	definition.max_health = float(spec["health"])
	definition.max_shield = float(spec.get("shield", 0.0))
	definition.tech_level = int(spec.get("tech_level", 1))
	definition.collision_radius = float(spec["radius"])
	definition.push_mass = float(spec.get("mass", 3000.0))
	definition.soft_collision_on_all = int(spec.get("soft_collision_on_all", 0))
	definition.factory_exit_offset = Vector2(float(spec.get("exit_x", 0.0)), float(spec.get("exit_y", 9.0)))
	definition.factory_exit_move_away = float(spec.get("exit_move_away", 70.0))
	definition.sight_range = int(spec.get("sight", 15))
	definition.movement_type = _movement_type(str(spec["movement_type"]))
	definition.movement_speed = float(spec.get("speed", 0.0))
	definition.turn_speed = float(spec.get("turn_speed", 0.0))
	definition.turn_acceleration = float(spec.get("turn_accel", 0.0))
	definition.movement_acceleration = float(spec.get("move_accel", 0.0))
	definition.movement_deceleration = float(spec.get("move_decel", 0.0))
	var effective_name: String = RwVanillaUnitCatalog.native_replacement(unit_name) if source_id == "vanilla" else unit_name
	var uses_sliding: bool = SLIDING_UNIT_TYPES.has(effective_name)
	definition.movement_sliding = bool(spec.get("move_sliding", uses_sliding))
	definition.movement_ignores_body = bool(spec.get("move_ignoring_body", uses_sliding))
	definition.attack_range = float(spec.get("attack_range", 0.0))
	definition.shoot_damage_multiplier = float(spec.get("shoot_damage_multiplier", 1.0))
	definition.can_reclaim = bool(spec.get("reclaim", false))
	definition.resource_costs = {"credits": float(spec.get("price", 0.0)),}
	definition.build_rate_per_frame = float(spec.get("build_rate", 0.0))
	definition.construction_warmup = float(spec.get("build_warmup", 0.0))
	definition.render_rotation_offset_degrees = 0.0 if bool(spec.get("building", false)) else 90.0
	definition.applies_spawn_rotation = not bool(spec.get("building", false))
	if bool(spec.get("building", false)):
		definition.default_body_rotation_degrees = -90.0
		definition.render_rotation_offset_degrees = 90.0
	definition.draw_layer = 3 if bool(spec.get("building", false)) or definition.movement_type in ["AIR", "HOVER",] else 2
	definition.dead_draw_layer = 0
	if bool(spec.get("building", false)):
		_configure_building(definition, spec)
	_configure_visual_parts(definition, spec)
	return definition


static func _movement_type(source_type: String) -> String:
	match source_type:
		"AIR", "LAND", "BUILDING", "WATER", "HOVER", "NONE", "OVER_CLIFF", "OVER_CLIFF_WATER":
			return source_type
		_:
			return "LAND"


static func _configure_building(definition: RwUnitDefinition, spec: Dictionary) -> void:
	definition.selection_shape = RwUnitDefinition.SelectionShape.RECTANGLE
	definition.blocks_movement = bool(spec.get("blocks_movement", true))
	definition.placement_requires_water = bool(spec.get("water_placement", false))
	definition.placement_requires_resource_pool = bool(spec.get("resource_pool", false))
	var footprint: Array = spec.get("footprint", [])
	if footprint.size() == 4:
		definition.structure_footprint_min = Vector2i(int(footprint[0]), int(footprint[1]))
		definition.structure_footprint_max = Vector2i(int(footprint[2]), int(footprint[3]))
	else:
		var radius_tiles: int = maxi(int(ceilf(definition.collision_radius / 20.0)) - 1, 0)
		definition.structure_footprint_min = Vector2i(-radius_tiles, -radius_tiles)
		definition.structure_footprint_max = Vector2i(radius_tiles, radius_tiles)
	var construction_footprint: Array = spec.get("construction_footprint", [])
	if construction_footprint.size() == 4:
		var minimum: Vector2i = Vector2i(int(construction_footprint[0]), int(construction_footprint[1]))
		var maximum: Vector2i = Vector2i(int(construction_footprint[2]), int(construction_footprint[3]))
		definition.construction_footprint = Rect2i(minimum, maximum - minimum + Vector2i.ONE)


static func _configure_visual_parts(definition: RwUnitDefinition, spec: Dictionary) -> void:
	var turret_image: String = str(spec.get("turret", ""))
	var turret_scale: float = float(spec.get("turret_scale", 1.0))
	var turret_indices: Dictionary
	if not turret_image.is_empty():
		var turret: RwUnitWeaponDefinition = RwUnitWeaponDefinition.new()
		turret.image = turret_image
		turret.team_colored = bool(spec.get("turret_team_colored", false))
		turret.rotation_offset_degrees = 90.0
		turret.sprite_scale = Vector2(turret_scale, turret_scale)
		definition.weapon_parts.append(turret)
	for part_info: Dictionary in spec.get("turret_parts", []):
		var part: RwUnitWeaponDefinition = RwUnitWeaponDefinition.new()
		part.image = str(part_info["image"])
		part.mount_offset = Vector2(float(part_info["x"]), -float(part_info["y"]))
		part.team_colored = bool(part_info.get("team_colored", false))
		part.draw_order = int(part_info.get("draw_order", 1))
		part.rotation_offset_degrees = 90.0
		part.sprite_scale = Vector2(turret_scale, turret_scale)
		part.idle_spin_degrees = float(part_info.get("idle_spin", 0.0))
		part.idle_sweep_angle_degrees = float(part_info.get("idle_sweep_angle", 0.0))
		part.idle_sweep_delay = float(part_info.get("idle_sweep_delay", 0.0))
		part.idle_sweep_speed_degrees = float(part_info.get("idle_sweep_speed", 0.0))
		part.idle_sweep_random_delay = float(part_info.get("idle_sweep_random_delay", 0.0))
		part.idle_direction_degrees = float(part_info.get("idle_direction", 0.0))
		part.reset_when_idle = bool(part_info.get("reset_when_idle", true))
		part.idle_turn_speed_degrees = float(part_info.get("turn_speed", 0.0))
		part.rotation_state_index = definition.weapon_parts.size()
		turret_indices[str(part_info["name"])] = part.rotation_state_index
		definition.weapon_parts.append(part)
	var part_index: int = 0 if turret_image.is_empty() else 1
	for part_info: Dictionary in spec.get("turret_parts", []):
		var parent_name: String = str(part_info.get("parent", ""))
		if turret_indices.has(parent_name):
			definition.weapon_parts[part_index].parent_part_index = int(turret_indices[parent_name])
		part_index += 1
	for leg_info: Dictionary in spec.get("leg_parts", []):
		var leg: RwUnitLegDefinition = RwUnitLegDefinition.new()
		leg.leg_image = str(leg_info.get("image_leg", ""))
		leg.foot_image = str(leg_info.get("image_foot", ""))
		leg.foot_shadow_image = str(leg_info.get("image_foot_shadow", ""))
		leg.attachment = Vector2(float(leg_info["attach_x"]), -float(leg_info["attach_y"]))
		leg.foot_position = Vector2(float(leg_info["x"]), -float(leg_info["y"]))
		leg.draw_over_body = bool(leg_info.get("draw_over_body", false))
		leg.team_colored = bool(leg_info.get("team_colored", false))
		definition.leg_parts.append(leg)
	var front_image: String = str(spec.get("front", ""))
	if not front_image.is_empty() or definition.max_shield > 0.0 or definition.movement_type in ["AIR", "HOVER",]:
		var profile: RwUnitVisualProfile = RwUnitVisualProfile.new()
		if definition.movement_type == "AIR":
			profile.spawn_altitude = 20.0
		elif definition.movement_type == "HOVER":
			profile.spawn_altitude = 3.0
		if definition.max_shield > 0.0:
			profile.shield_image = "shield_mid.png"
		if not front_image.is_empty():
			var front: RwVisualOverlayDefinition = RwVisualOverlayDefinition.new()
			front.image = front_image
			front.draw_order = 3
			profile.overlays.append(front)
		definition.visual_profile = profile
