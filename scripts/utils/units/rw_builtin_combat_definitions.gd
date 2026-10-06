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
		if replacement.is_empty():
			continue
		var definition: RwUnitDefinition = registry.find_definition("vanilla", native_name)
		if definition != null:
			if RwBuiltinCombatSpecs.SPECS.has(replacement):
				configure_definition(definition, replacement)
			if RwBuiltinCombatSpecs.INTERCEPTOR_SPECS.has(replacement):
				configure_interceptors(definition, replacement)
	for unit_name: String in RwBuiltinCombatSpecs.INTERCEPTOR_SPECS:
		var definition: RwUnitDefinition = registry.find_definition("custom", unit_name)
		if definition != null:
			configure_interceptors(definition, unit_name)


## 使用给定内置单位的炮塔参数配置可开火武器
static func configure_definition(definition: RwUnitDefinition, source_name: String) -> void:
	var weapon_specs: Array = RwBuiltinCombatSpecs.SPECS.get(source_name, [])
	if weapon_specs.is_empty():
		return
	definition.combat_weapons.clear()
	var visual_spec: Dictionary = RwBuiltinUnitSpecs.get_spec(source_name)
	for weapon_spec: Dictionary in weapon_specs:
		var projectile: RwProjectileDefinition = _create_projectile_definition(weapon_spec, source_name)
		var weapon: RwWeaponDefinition = RwWeaponDefinition.new()
		weapon.projectile = projectile
		weapon.shoot_sound_name = str(weapon_spec.get("shoot_sound", ""))
		weapon.shoot_sound_volume = float(weapon_spec.get("shoot_sound_volume", 0.3))
		weapon.shoot_flame = str(weapon_spec.get("shoot_flame", ""))
		weapon.shoot_light_color = _parse_argb_color(str(weapon_spec.get("shoot_light", "")))
		weapon.attack_range = float(weapon_spec["range"])
		weapon.minimum_range = float(weapon_spec["minimum_range"])
		weapon.reload_frames = int(weapon_spec["reload"])
		weapon.warmup_frames = int(weapon_spec["warmup"])
		weapon.turn_speed_degrees = float(weapon_spec["turn_speed"])
		weapon.muzzle_offset = Vector2(float(weapon_spec["muzzle_x"]), float(weapon_spec["muzzle_y"]))
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


## 将原版内置单位的自动拦截炮塔挂到统一单位定义
static func configure_interceptors(definition: RwUnitDefinition, source_name: String) -> void:
	definition.projectile_interceptors.clear()
	for interceptor_spec: Dictionary in RwBuiltinCombatSpecs.INTERCEPTOR_SPECS.get(source_name, []):
		var interceptor: RwProjectileInterceptorDefinition = RwProjectileInterceptorDefinition.new()
		interceptor.turret_name = str(interceptor_spec["turret"])
		for tag: String in interceptor_spec["tags"]:
			interceptor.projectile_tags.append(tag.to_lower())
		interceptor.target_ground_under_distance = float(interceptor_spec["target_ground_under_distance"])
		interceptor.projectile_under_distance = float(interceptor_spec["projectile_under_distance"])
		interceptor.projectile_over_height = float(interceptor_spec["projectile_over_height"])
		interceptor.muzzle_offset = Vector2(float(interceptor_spec["muzzle_x"]), float(interceptor_spec["muzzle_y"]))
		interceptor.resource_usage = (interceptor_spec["resource_usage"] as Dictionary).duplicate()
		interceptor.projectile = _create_projectile_definition(
			interceptor_spec["projectile_profile"] as Dictionary,
			source_name,
		)
		interceptor.shoot_sound_name = str(interceptor_spec.get("shoot_sound", ""))
		interceptor.shoot_sound_volume = float(interceptor_spec.get("shoot_sound_volume", 0.3))
		interceptor.shoot_flame = str(interceptor_spec.get("shoot_flame", ""))
		interceptor.shoot_light_color = _parse_argb_color(str(interceptor_spec.get("shoot_light", "")))
		definition.projectile_interceptors.append(interceptor)


## 按单位与配置名构造弹体定义，供自动炮塔和特殊动作共用
static func create_projectile_profile(source_name: String, projectile_name: String) -> RwProjectileDefinition:
	var profiles: Dictionary = RwBuiltinCombatSpecs.PROJECTILE_PROFILES.get(source_name, {})
	var profile: Dictionary = profiles.get(projectile_name.strip_edges().trim_prefix("projectile_").to_lower(), {})
	return _create_projectile_definition(profile, source_name) if not profile.is_empty() else null


static func _create_projectile_definition(
	projectile_spec: Dictionary,
	source_name: String = "",
) -> RwProjectileDefinition:
	var projectile: RwProjectileDefinition = RwProjectileDefinition.new()
	projectile.effect_owner_name = source_name
	projectile.effect_profiles = RwBuiltinCombatSpecs.EFFECT_PROFILES.get(source_name, {})
	projectile.damage = float(projectile_spec.get("direct_damage", 0.0))
	projectile.deflection_power = float(projectile_spec.get("deflection_power", 1.0))
	projectile.draw_type = int(projectile_spec.get("draw_type", 0))
	projectile.shadow_frame = int(projectile_spec.get("shadow_frame", -1))
	projectile.invisible = bool(projectile_spec.get("invisible", false))
	projectile.draw_under_units = bool(projectile_spec.get("draw_under_units", false))
	projectile.large_hit_effect = bool(projectile_spec.get("large_hit_effect", false))
	projectile.nuke_weapon = bool(projectile_spec.get("nuke_weapon", false))
	projectile.always_visible_in_fog = bool(projectile_spec.get("always_visible_in_fog", false))
	projectile.should_reveal_fog = bool(projectile_spec.get("should_reveal_fog", false))
	projectile.hit_sound = bool(projectile_spec.get("hit_sound", true))
	projectile.flame_weapon = bool(projectile_spec.get("flame_weapon", false))
	projectile.explode_effect = str(projectile_spec.get("explode_effect", ""))
	projectile.explode_effect_on_shield = str(projectile_spec.get("explode_effect_on_shield", ""))
	projectile.effect_on_create = str(projectile_spec.get("effect_on_create", ""))
	projectile.teleport_source = bool(projectile_spec.get("teleport_source", false))
	projectile.convert_hit_to_source_team = bool(projectile_spec.get("convert_hit_to_source_team", false))
	projectile.shadow_texture_name = str(projectile_spec.get("shadow_image", ""))
	projectile.beam_texture_name = str(projectile_spec.get("beam_image", ""))
	projectile.beam_start_texture_name = str(projectile_spec.get("beam_image_start", ""))
	projectile.beam_end_texture_name = str(projectile_spec.get("beam_image_end", ""))
	projectile.beam_image_offset_rate = float(projectile_spec.get("beam_image_offset_rate", 0.0))
	projectile.beam_start_rotated = bool(projectile_spec.get("beam_image_start_rotated", false))
	projectile.beam_end_rotated = bool(projectile_spec.get("beam_image_end_rotated", false))
	projectile.team_color_ratio = float(projectile_spec.get("team_color_ratio", 0.0))
	projectile.team_color_source_ratio = float(projectile_spec.get("team_color_source_ratio", 1.0))
	for tag: String in projectile_spec.get("tags", []):
		projectile.tags.append(tag.to_lower())
	projectile.intercept_projectile_remove_target_life_only = bool(
		projectile_spec.get("intercept_projectile_remove_target_life_only", false)
	)
	projectile.splash_damage = float(projectile_spec.get("splash_damage", 0.0))
	projectile.splash_radius = float(projectile_spec.get("splash_radius", 0.0))
	projectile.area_expand_time = float(projectile_spec.get("area_expand_time", 0.0))
	projectile.area_damage_no_falloff = bool(projectile_spec.get("area_no_falloff", false))
	projectile.area_radius_from_edge = bool(projectile_spec.get("area_from_edge", false))
	projectile.area_minimum_distance = float(projectile_spec.get("area_minimum_distance", 0.0))
	projectile.area_hit_air_and_land_at_same_time = bool(projectile_spec.get("area_hit_air_and_land_at_same_time", false))
	projectile.area_hit_underwater_always = bool(projectile_spec.get("area_hit_underwater_always", false))
	projectile.speed_per_frame = float(projectile_spec.get("speed", 5.0))
	projectile.delayed_start_frames = float(projectile_spec.get("delayed_start", 0.0))
	projectile.target_speed_per_frame = float(projectile_spec.get("target_speed", 0.0))
	projectile.speed_acceleration_per_frame = float(projectile_spec.get("speed_acceleration", 0.0))
	projectile.turn_speed_degrees = float(projectile_spec.get("projectile_turn_speed", -1.0))
	projectile.turn_speed_near_degrees = float(projectile_spec.get("projectile_turn_speed_near", -1.0))
	projectile.lifetime_frames = int(projectile_spec.get("lifetime", 60))
	projectile.instant = bool(projectile_spec.get("instant", false))
	projectile.beam = bool(projectile_spec.get("beam", false))
	projectile.target_ground = bool(projectile_spec.get("target_ground", false))
	projectile.target_ground_include_target_height = bool(projectile_spec.get("target_ground_include_target_height", false))
	projectile.target_ground_spread = float(projectile_spec.get("target_ground_spread", 0.0))
	projectile.target_ground_height_offset = float(projectile_spec.get("target_ground_height_offset", 0.0))
	projectile.ballistic = bool(projectile_spec.get("ballistic", false))
	projectile.lead_target = bool(projectile_spec.get("lead_target", false))
	projectile.lead_target_speed_calculation = float(projectile_spec.get("lead_target_speed_calculation", -1.0))
	projectile.instant_reuse_last = bool(projectile_spec.get("instant_reuse_last", false))
	projectile.instant_reuse_last_also_change_turret_aim = bool(
		projectile_spec.get("instant_reuse_last_also_change_turret_aim", false)
	)
	projectile.instant_reuse_last_keep_area_damage_list = bool(
		projectile_spec.get("instant_reuse_last_keep_area_damage_list", false)
	)
	projectile.move_with_parent = bool(projectile_spec.get("move_with_parent", false))
	projectile.sweep_speed = float(projectile_spec.get("sweep_speed", 0.0))
	projectile.sweep_offset = float(projectile_spec.get("sweep_offset", 0.0))
	projectile.sweep_offset_from_target_radius = float(projectile_spec.get("sweep_offset_from_target_radius", 0.0))
	projectile.ballistic_height = float(projectile_spec.get("ballistic_height", 60.0 if projectile.ballistic else -1.0))
	projectile.ballistic_delay_move_height = float(projectile_spec.get("ballistic_delay_move_height", 40.0 if projectile.ballistic else -1.0))
	projectile.gravity_per_frame = float(projectile_spec.get("gravity", 0.0))
	projectile.true_gravity_per_frame = float(projectile_spec.get("true_gravity", 0.0))
	projectile.initial_unguided_velocity = Vector2(
		float(projectile_spec.get("initial_unguided_speed_x", 0.0)),
		float(projectile_spec.get("initial_unguided_speed_y", 0.0)),
	)
	projectile.initial_height_velocity = float(projectile_spec.get("initial_unguided_speed_height", 0.0))
	projectile.speed_spread = float(projectile_spec.get("speed_spread", 0.0))
	projectile.wobble_amplitude = float(projectile_spec.get("wobble_amplitude", 0.0))
	projectile.wobble_frequency = float(projectile_spec.get("wobble_frequency", 5.0))
	projectile.trail_as_particles = bool(projectile_spec.get("trail_effect", false))
	projectile.trail_effect_name = str(projectile_spec.get("trail_effect_name", ""))
	projectile.trail_emission_interval_frames = float(projectile_spec.get("trail_effect_rate", 3.0))
	projectile.trail_length_frames = ceili(projectile.trail_particle_lifetime_frames / maxf(projectile.trail_emission_interval_frames, 0.01)) if projectile.trail_as_particles else 0
	projectile.trail_width = 1.0 if projectile.trail_as_particles else 0.0
	projectile.trail_color = Color(0.75, 0.75, 0.75, 0.55)
	projectile.trail_texture_name = "smoke_white.png" if projectile.trail_as_particles else ""
	projectile.trail_texture_frame_size = Vector2i(19, 19)
	projectile.trail_texture_scale = 0.5
	projectile.explode_on_end_of_life = bool(projectile_spec.get("explode_on_end_of_life", false))
	projectile.ignore_parent_shoot_damage_multiplier = bool(
		projectile_spec.get("ignore_parent_shoot_damage_multiplier", false)
	)
	projectile.retarget_on_target_loss = bool(projectile_spec.get("auto_target_dead", false))
	projectile.remove_on_target_loss = false
	projectile.target_loss_retarget_range = float(projectile_spec.get("auto_target_range", 120.0))
	projectile.target_loss_retarget_lead_distance = float(projectile_spec.get("auto_target_lead", 15.0))
	projectile.retarget_in_flight = bool(projectile_spec.get("retarget_in_flight", false))
	projectile.retarget_in_flight_search_delay = float(projectile_spec.get("retarget_search_delay", 5.0))
	projectile.retarget_in_flight_search_range = float(projectile_spec.get("retarget_search_range", 120.0))
	projectile.retarget_in_flight_lead_distance = float(projectile_spec.get("retarget_search_lead", 15.0))
	projectile.friendly_fire = bool(projectile_spec.get("friendly_fire", false))
	projectile.friendly_fire_mode = str(projectile_spec.get("friendly_fire_mode", ""))
	projectile.building_damage_multiplier = float(projectile_spec.get("building_damage_multiplier", 1.0))
	projectile.air_damage_multiplier = float(projectile_spec.get("air_damage_multiplier", 1.0))
	projectile.shield_damage_multiplier = float(projectile_spec.get("shield_damage_multiplier", 1.0))
	projectile.shield_deflection_multiplier = float(projectile_spec.get("shield_deflection_multiplier", 1.0))
	projectile.hull_damage_multiplier = float(projectile_spec.get("hull_damage_multiplier", 1.0))
	projectile.armor_ignore = float(projectile_spec.get("armor_ignore", 0.0))
	projectile.push_force = float(projectile_spec.get("push_force", 0.0))
	projectile.push_velocity = float(projectile_spec.get("push_velocity", 0.0))
	projectile.homing = not projectile.target_ground
	projectile.texture_scale = float(projectile_spec.get("texture_scale", float(projectile_spec.get("draw_size", 1.0)) * 2.0))
	projectile.visual_radius = maxf(float(projectile_spec.get("draw_size", 1.0)) * 2.0, 1.0)
	projectile.render_shadow = true
	projectile.native_target_collision_rules = true
	projectile.native_altitude_collision_rules = true
	var frame: int = int(projectile_spec.get("frame", -1))
	var image_name: String = str(projectile_spec.get("image", ""))
	if not image_name.is_empty():
		projectile.texture_name = image_name
		projectile.texture_region = Rect2i()
		projectile.texture_rotation_offset_degrees = 0.0
	if frame >= 0 and image_name.is_empty():
		var frame_size: int = 20
		match projectile.draw_type:
			1:
				projectile.texture_name = "projectiles_large.png"
				frame_size = 60
			2:
				projectile.texture_name = "projectiles2.png"
			_:
				projectile.texture_name = "projectiles.png"
		projectile.texture_region = Rect2i(frame * frame_size, 0, frame_size, frame_size)
		projectile.texture_rotation_offset_degrees = 90.0
	var color_text: String = str(projectile_spec.get("color", ""))
	if not color_text.is_empty():
		projectile.visual_color = _projectile_color(color_text)
	var light_color_text: String = str(projectile_spec.get("light_color", ""))
	if not light_color_text.is_empty():
		projectile.attached_light_color = _projectile_color(light_color_text)
	projectile.attached_light_scale = float(projectile_spec.get("light_size", 0.5))
	projectile.attached_light_cast_on_ground = bool(projectile_spec.get("light_cast_on_ground", false))
	projectile.impact_texture_name = "explode_big2.png"
	projectile.impact_frame_size = Vector2i(39, 40)
	projectile.impact_frame_offset = Vector2i(121, 1)
	projectile.impact_frame_step = Vector2i(40, 0)
	projectile.impact_frame_count = 5
	projectile.impact_duration = 10.0 / 60.0
	projectile.impact_animation_duration = projectile.impact_duration
	projectile.impact_scale = 0.5
	if projectile.flame_weapon:
		projectile.impact_texture_name = "flame_large.png"
		projectile.impact_frame_size = Vector2i(20, 25)
		projectile.impact_frame_count = 4
		projectile.impact_duration = 0.3
		projectile.impact_animation_duration = 0.3
	elif projectile.large_hit_effect:
		projectile.impact_texture_name = "explode_big.png"
		projectile.impact_frame_size = Vector2i(39, 40)
		projectile.impact_frame_offset = Vector2i(1, 1)
		projectile.impact_frame_step = Vector2i(40, 0)
		projectile.impact_frame_count = 13
		projectile.impact_duration = 26.0 / 60.0
		projectile.impact_animation_duration = projectile.impact_duration
		projectile.impact_scale = 0.9
		projectile.impact_scale_variance = 0.2
	for spawn_unit_spec: Dictionary in projectile_spec.get("spawn_units_on_explode", []):
		projectile.spawn_units_on_explode.append(spawn_unit_spec)
	for spawn_field: String in ["spawn_on_end_of_life", "spawn_on_explode", "spawn_on_create",]:
		var child_spawns: Array[Dictionary] = []
		for spawn_spec: Dictionary in projectile_spec.get(spawn_field, []):
			var child_profile: Dictionary = spawn_spec.get("profile", {})
			var child_spawn: Dictionary = spawn_spec.duplicate()
			child_spawn["projectile_definition"] = _create_projectile_definition(
				child_profile,
				projectile.effect_owner_name,
			)
			child_spawns.append(child_spawn)
		match spawn_field:
			"spawn_on_end_of_life":
				projectile.spawn_on_end_of_life = child_spawns
			"spawn_on_explode":
				projectile.spawn_on_explode = child_spawns
			"spawn_on_create":
				projectile.spawn_on_create = child_spawns
	return projectile


static func _parse_argb_color(color_text: String) -> Color:
	if color_text.begins_with("#") and color_text.length() == 9:
		return Color.from_string("#%s%s" % [color_text.substr(3, 6), color_text.substr(1, 2)], Color.WHITE)
	return Color.from_string(color_text, Color.TRANSPARENT)


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
