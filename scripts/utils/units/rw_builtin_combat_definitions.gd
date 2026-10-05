extends RefCounted
class_name RwBuiltinCombatDefinitions
## 将 RWX 内置 INI 的炮塔和弹体数据接入通用战斗系统


## 为自定义单位及其原生替换单位注册武器
static func register_weapons(registry: RwUnitRegistry) -> void:
	for unit_name: String in RwBuiltinCombatSpecs.SPECS:
		var definition: RwUnitDefinition = registry.find_definition("custom", unit_name)
		if definition != null:
			configure_definition(definition, unit_name)
	for native_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		var replacement: String = RwVanillaUnitCatalog.native_replacement(native_name)
		if replacement.is_empty() or not RwBuiltinCombatSpecs.SPECS.has(replacement):
			continue
		var definition: RwUnitDefinition = registry.find_definition("vanilla", native_name)
		if definition != null:
			configure_definition(definition, replacement)


## 使用给定内置单位的炮塔参数配置可开火武器
static func configure_definition(definition: RwUnitDefinition, source_name: String) -> void:
	var weapon_specs: Array = RwBuiltinCombatSpecs.SPECS.get(source_name, [])
	if weapon_specs.is_empty():
		return
	definition.combat_weapons.clear()
	var visual_spec: Dictionary = RwBuiltinUnitSpecs.get_spec(source_name)
	for weapon_spec: Dictionary in weapon_specs:
		var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
		projectile.damage = float(weapon_spec["direct_damage"])
		projectile.splash_damage = float(weapon_spec["splash_damage"])
		projectile.splash_radius = float(weapon_spec["splash_radius"])
		projectile.area_damage_no_falloff = bool(weapon_spec["area_no_falloff"])
		projectile.area_radius_from_edge = bool(weapon_spec["area_from_edge"])
		projectile.area_minimum_distance = float(weapon_spec["area_minimum_distance"])
		projectile.speed_per_frame = float(weapon_spec["speed"])
		projectile.target_speed_per_frame = float(weapon_spec["target_speed"])
		projectile.speed_acceleration_per_frame = float(weapon_spec["speed_acceleration"])
		projectile.turn_speed_degrees = float(weapon_spec["projectile_turn_speed"])
		projectile.turn_speed_near_degrees = float(weapon_spec.get("projectile_turn_speed_near", -2.0))
		projectile.lifetime_frames = int(weapon_spec["lifetime"])
		projectile.instant = bool(weapon_spec["instant"])
		projectile.beam = bool(weapon_spec["beam"])
		projectile.target_ground = bool(weapon_spec["target_ground"])
		projectile.ballistic = bool(weapon_spec.get("ballistic", false))
		projectile.ballistic_height = float(weapon_spec.get("ballistic_height", 0.0))
		projectile.ballistic_delay_move_height = float(weapon_spec.get("ballistic_delay_move_height", 0.0))
		projectile.gravity_per_frame = float(weapon_spec.get("gravity", 0.0))
		projectile.true_gravity_per_frame = float(weapon_spec.get("true_gravity", 0.0))
		projectile.wobble_amplitude = float(weapon_spec.get("wobble_amplitude", 0.0))
		projectile.wobble_frequency = float(weapon_spec.get("wobble_frequency", 5.0))
		projectile.trail_as_particles = bool(weapon_spec.get("trail_effect", false))
		projectile.trail_emission_interval_frames = float(weapon_spec.get("trail_effect_rate", 3.0))
		projectile.trail_length_frames = ceili(projectile.trail_particle_lifetime_frames / maxf(projectile.trail_emission_interval_frames, 0.01)) if projectile.trail_as_particles else 0
		projectile.trail_width = 1.0 if projectile.trail_as_particles else 0.0
		projectile.trail_color = Color(0.75, 0.75, 0.75, 0.55)
		projectile.trail_texture_name = "smoke_white.png" if projectile.trail_as_particles else ""
		projectile.trail_texture_frame_size = Vector2i(19, 19)
		projectile.trail_texture_scale = 0.5
		projectile.explode_on_end_of_life = bool(weapon_spec.get("explode_on_end_of_life", false))
		projectile.retarget_on_target_loss = bool(weapon_spec.get("auto_target_dead", false))
		projectile.remove_on_target_loss = true
		projectile.target_loss_retarget_range = float(weapon_spec.get("auto_target_range", 120.0))
		projectile.target_loss_retarget_lead_distance = float(weapon_spec.get("auto_target_lead", 15.0))
		projectile.retarget_in_flight = bool(weapon_spec.get("retarget_in_flight", false))
		projectile.retarget_in_flight_search_delay = float(weapon_spec.get("retarget_search_delay", 5.0))
		projectile.retarget_in_flight_search_range = float(weapon_spec.get("retarget_search_range", 120.0))
		projectile.retarget_in_flight_lead_distance = float(weapon_spec.get("retarget_search_lead", 15.0))
		projectile.friendly_fire = bool(weapon_spec["friendly_fire"])
		projectile.building_damage_multiplier = float(weapon_spec.get("building_damage_multiplier", 1.0))
		projectile.air_damage_multiplier = float(weapon_spec.get("air_damage_multiplier", 1.0))
		projectile.shield_damage_multiplier = float(weapon_spec.get("shield_damage_multiplier", 1.0))
		projectile.hull_damage_multiplier = float(weapon_spec.get("hull_damage_multiplier", 1.0))
		projectile.armor_ignore = float(weapon_spec.get("armor_ignore", 0.0))
		projectile.push_force = float(weapon_spec.get("push_force", 0.0))
		projectile.push_velocity = float(weapon_spec.get("push_velocity", 0.0))
		projectile.homing = not projectile.target_ground
		var frame: int = int(weapon_spec["frame"])
		if frame >= 0:
			projectile.texture_name = "projectiles.png"
			projectile.texture_region = Rect2i(frame * 20, 0, 20, 20)
			projectile.texture_rotation_offset_degrees = 90.0
		projectile.texture_scale = float(weapon_spec.get("texture_scale", float(weapon_spec["draw_size"]) * 2.0))
		projectile.visual_radius = maxf(float(weapon_spec["draw_size"]) * 2.0, 1.0)
		projectile.render_shadow = true
		projectile.native_target_collision_rules = true
		projectile.native_altitude_collision_rules = true
		var color_text: String = str(weapon_spec["color"])
		if not color_text.is_empty():
			projectile.visual_color = _projectile_color(color_text)
		var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
		weapon.projectile = projectile
		weapon.attack_range = float(weapon_spec["range"])
		weapon.minimum_range = float(weapon_spec["minimum_range"])
		weapon.reload_frames = int(weapon_spec["reload"])
		weapon.warmup_frames = int(weapon_spec["warmup"])
		weapon.turn_speed_degrees = float(weapon_spec["turn_speed"])
		weapon.muzzle_offset = Vector2(float(weapon_spec["muzzle_x"]), -float(weapon_spec["muzzle_y"]))
		weapon.muzzle_distance = float(weapon_spec["muzzle_distance"])
		weapon.can_target_ground = bool(weapon_spec["ground"])
		weapon.can_target_air = bool(weapon_spec["air"])
		weapon.can_target_water = bool(weapon_spec["underwater"])
		weapon.rotation_state_index = _visual_rotation_index(definition, visual_spec, str(weapon_spec["turret"]))
		definition.combat_weapons.append(weapon)
		definition.attack_range = maxf(definition.attack_range, weapon.attack_range)
	if definition.behavior == null:
		if definition.max_shield > 0.0:
			definition.behavior = RwShieldBehavior.new()
		else:
			definition.behavior = RwAutoAttackBehavior.new()


static func _visual_rotation_index(definition: RwUnitDefinition, visual_spec: Dictionary, turret_name: String) -> int:
	var visual_index: int = 1 if not str(visual_spec.get("turret", "")).is_empty() else 0
	for part_spec: Dictionary in visual_spec.get("turret_parts", []):
		if str(part_spec["name"]) == turret_name and visual_index < definition.weapon_parts.size():
			return visual_index
		visual_index += 1
	return 0


static func _projectile_color(color_text: String) -> Color:
	if color_text.begins_with("#") and color_text.length() == 9:
		return Color.from_string("#%s%s" % [color_text.substr(3, 6), color_text.substr(1, 2),], Color.WHITE)
	return Color.from_string(color_text, Color.WHITE)
