extends Node2D
class_name RwBattleProjectileLayer
## 绘制战斗系统中的弹体；模拟状态由 RwBattleCombat 管理

@export var draw_under_units_only: bool

var _projectiles: Array[RwProjectileState]
var _texture_cache: Dictionary
var _beam_flashes: Array[Dictionary]
var _impact_flashes: Array[Dictionary]
var _detached_trail_particles: Array[Dictionary]
var _projectile_effects: Array[Dictionary]
var _custom_trail_counts: Dictionary


func _process(delta: float) -> void:
	if _beam_flashes.is_empty() and _impact_flashes.is_empty() and _projectile_effects.is_empty():
		return
	for effect_index: int in range(_projectile_effects.size() - 1, -1, -1):
		var effect: Dictionary = _projectile_effects[effect_index]
		var parent: RwProjectileState = effect.get("parent") as RwProjectileState
		if parent != null:
			if (parent.has_impacted or parent.remove_requested) and not bool(effect["live_after_parent_dies"]):
				var parent_team_color: Color = effect["team_color"]
				_spawn_effect_sequence(
					str(effect["effects_on_death"]),
					effect["profiles"],
					effect["position"],
					parent_team_color,
					float(effect["heading"]),
					null,
					1,
				)
				_projectile_effects.remove_at(effect_index)
				continue
			if parent.has_impacted or parent.remove_requested:
				effect["parent"] = null
			else:
				effect["position"] = parent.world_position + Vector2.UP * parent.height
		var elapsed_delta: Vector2 = effect["velocity"] * delta
		effect["position"] = (effect["position"] as Vector2) + elapsed_delta
		if bool(effect["physics"]):
			effect["height_velocity"] = float(effect["height_velocity"]) - float(effect["physics_gravity"]) * delta * 60.0
			effect["height"] = float(effect["height"]) + float(effect["height_velocity"]) * delta * 60.0
		var elapsed: float = float(effect["elapsed_seconds"]) + delta
		effect["elapsed_seconds"] = elapsed
		if elapsed >= float(effect["duration_seconds"]):
			var ended_team_color: Color = effect["team_color"]
			_spawn_effect_sequence(
				str(effect["effects_on_death"]),
				effect["profiles"],
				effect["position"],
				ended_team_color,
				float(effect["heading"]),
				null,
				1,
			)
			_projectile_effects.remove_at(effect_index)
	for index: int in range(_beam_flashes.size() - 1, -1, -1):
		_beam_flashes[index]["time"] = float(_beam_flashes[index]["time"]) - delta
		if float(_beam_flashes[index]["time"]) <= 0.0:
			_beam_flashes.remove_at(index)
	for index: int in range(_impact_flashes.size() - 1, -1, -1):
		_impact_flashes[index]["time"] = float(_impact_flashes[index]["time"]) + delta
		if float(_impact_flashes[index]["time"]) >= float(_impact_flashes[index]["duration"]):
			_impact_flashes.remove_at(index)
	queue_redraw()


func _draw() -> void:
	for effect: Dictionary in _projectile_effects:
		_draw_projectile_effect(effect)
	for beam: Dictionary in _beam_flashes:
		var beam_color: Color = beam["color"]
		if bool(beam.get("render_jitter", false)):
			_draw_jitter_beam(beam["origin"], beam["target"], beam_color, float(beam.get("seed", 0.0)))
		elif not str(beam.get("texture_name", "")).is_empty():
			_draw_textured_beam(beam)
		else:
			draw_line(beam["origin"], beam["target"], beam_color, 3.0, false)
	for impact: Dictionary in _impact_flashes:
		var frame_size: Vector2i = impact["frame_size"]
		var frame_count: int = int(impact["frame_count"])
		var duration: float = maxf(float(impact["duration"]), 0.001)
		var animation_duration: float = maxf(float(impact.get("animation_duration", duration)), 0.001)
		var progress: float = clampf(float(impact["time"]) / animation_duration, 0.0, 1.0)
		var texture_name: String = str(impact["texture_name"])
		if texture_name.is_empty():
			var impact_color: Color = impact["color"]
			impact_color.a *= 1.0 - progress
			var impact_radius: float = float(impact["radius"]) * (0.5 + progress * 0.5)
			draw_circle(impact["position"], impact_radius, impact_color)
			continue
		var texture: Texture2D = _get_texture(texture_name)
		if texture == null:
			continue
		var frame_index: int = mini(int(progress * frame_count), frame_count - 1)
		var frame_offset: Vector2i = impact.get("frame_offset", Vector2i.ZERO)
		var frame_step: Vector2i = impact.get("frame_step", frame_size)
		var source: Rect2 = Rect2(
			Vector2(frame_offset + Vector2i(frame_index * frame_step.x, 0)),
			Vector2(frame_size),
		)
		var size: Vector2 = Vector2(frame_size) * float(impact["scale"])
		var rotation: float = float(impact.get("rotation", 0.0))
		draw_set_transform(impact["position"], rotation, Vector2.ONE)
		var destination: Rect2 = Rect2(-size * 0.5, size)
		var impact_color: Color = impact["color"]
		impact_color.a *= 1.0 - progress
		draw_texture_rect_region(texture, destination, source, impact_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for particle: Dictionary in _detached_trail_particles:
		_draw_trail_particle(
			particle["position"],
			particle["definition"],
			float(particle["age_frames"])
		)
	for projectile: RwProjectileState in _projectiles:
		var definition: RwProjectileDefinition = projectile.definition
		if projectile.has_impacted or definition == null or not definition.visible_in_flight:
			continue
		if definition.draw_under_units != draw_under_units_only:
			continue
		if not projectile.visible_by_fog and not definition.always_visible_in_fog and not definition.nuke_weapon:
			continue
		if definition.trail_as_particles:
			if definition.trail_effect_name.is_empty():
				for trail_index: int in projectile.trail_positions.size():
					var trail_age: float = projectile.elapsed_frames - projectile.trail_spawn_frames[trail_index]
					_draw_trail_particle(projectile.trail_positions[trail_index], definition, trail_age)
		else:
			for trail_index: int in range(1, projectile.trail_positions.size()):
				var trail_color: Color = definition.trail_color
				trail_color.a *= float(trail_index) / float(projectile.trail_positions.size())
				var trail_point: Vector3 = projectile.trail_positions[trail_index]
				var trail_position: Vector2 = Vector2(trail_point.x, trail_point.y) + Vector2.UP * trail_point.z
				draw_line(
					Vector2(projectile.trail_positions[trail_index - 1].x, projectile.trail_positions[trail_index - 1].y) + Vector2.UP * projectile.trail_positions[trail_index - 1].z,
					trail_position,
					trail_color,
					definition.trail_width,
					true,
				)
		var draw_position: Vector2 = projectile.world_position + Vector2.UP * projectile.height
		if definition.attached_light_color.a > 0.0:
			var light_texture: Texture2D = _get_texture("light_50.png")
			if light_texture != null:
				var light_size: Vector2 = Vector2(light_texture.get_size()) * definition.attached_light_scale
				var light_color: Color = definition.attached_light_color
				light_color.a *= definition.attached_light_alpha
				draw_texture_rect(
					light_texture,
					Rect2(
						(projectile.world_position if definition.attached_light_cast_on_ground else draw_position)
						- light_size * 0.5,
						light_size,
					),
					false,
					light_color,
				)
		if definition.invisible:
			continue
		if definition.texture_name.is_empty():
			if projectile.height > 0.0 and definition.render_shadow:
				draw_circle(projectile.world_position, definition.visual_radius, Color(0.0, 0.0, 0.0, 0.42))
			if definition.glow_radius > 0.0:
				draw_circle(draw_position, definition.glow_radius, Color(projectile.render_color, 0.16))
			draw_circle(draw_position, definition.visual_radius, projectile.render_color)
			continue
		var texture: Texture2D = _get_texture(definition.texture_name)
		if texture == null:
			draw_circle(draw_position, definition.visual_radius, projectile.render_color)
			continue
		var region: Rect2i = definition.texture_region
		if region.size == Vector2i.ZERO:
			region = Rect2i(Vector2i.ZERO, texture.get_size())
		var size: Vector2 = Vector2(region.size) * definition.texture_scale
		var destination: Rect2 = Rect2(-size * 0.5, size)
		var rotation: float = deg_to_rad(
			projectile.render_heading_degrees + definition.texture_rotation_offset_degrees
		)
		if projectile.height > 0.0 and definition.render_shadow and not definition.shadow_texture_name.is_empty():
			var shadow_texture: Texture2D = _get_texture(definition.shadow_texture_name)
			if shadow_texture != null:
				var shadow_size: Vector2 = Vector2(shadow_texture.get_size()) * definition.texture_scale
				draw_texture_rect(
					shadow_texture,
					Rect2(projectile.world_position - shadow_size * 0.5, shadow_size),
					false,
					Color(1.0, 1.0, 1.0, 0.7),
				)
		elif projectile.height > 0.0 and definition.render_shadow and definition.shadow_frame >= 0:
			var shadow_region: Rect2 = Rect2(
				Vector2(definition.shadow_frame * region.size.x, region.position.y),
				Vector2(region.size),
			)
			draw_set_transform(projectile.world_position, rotation, Vector2.ONE)
			draw_texture_rect_region(
				texture,
				destination,
				shadow_region,
				Color(0.0, 0.0, 0.0, 0.42),
			)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if definition.glow_radius > 0.0:
			draw_circle(draw_position, definition.glow_radius, Color(projectile.render_color, 0.16))
		draw_set_transform(draw_position, rotation, Vector2.ONE)
		draw_texture_rect_region(texture, destination, Rect2(region), projectile.render_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 接收当前弹体列表并请求重绘
func set_projectiles(projectiles: Array[RwProjectileState]) -> void:
	_projectiles = projectiles
	var active_projectile_ids: Dictionary = {}
	for projectile: RwProjectileState in projectiles:
		if projectile == null or projectile.definition == null or projectile.definition.trail_effect_name.is_empty():
			continue
		var projectile_id: int = projectile.object_id
		active_projectile_ids[projectile_id] = true
		var emitted_count: int = int(_custom_trail_counts.get(projectile_id, 0))
		if emitted_count < projectile.trail_emission_serial and not projectile.trail_positions.is_empty():
			var trail_point: Vector3 = projectile.trail_positions.back()
			var trail_position: Vector2 = Vector2(trail_point.x, trail_point.y) + Vector2.UP * trail_point.z
			_spawn_effect_sequence(
				projectile.definition.trail_effect_name,
				projectile.definition.effect_profiles,
				trail_position,
				projectile.render_color,
				projectile.heading_degrees,
				projectile,
				0,
			)
			_custom_trail_counts[projectile_id] = projectile.trail_emission_serial
	for projectile_id: int in _custom_trail_counts.keys():
		if not active_projectile_ids.has(projectile_id):
			_custom_trail_counts.erase(projectile_id)
	queue_redraw()


## 按弹体定义显示光束或爆炸图集
func show_impact(projectile: RwProjectileState, _target: RwUnitState) -> void:
	if projectile.definition == null:
		return
	var impact_effect: String = projectile.definition.explode_effect
	if projectile.hit_shield and not projectile.definition.explode_effect_on_shield.is_empty():
		impact_effect = projectile.definition.explode_effect_on_shield
	var has_custom_impact: bool = not impact_effect.strip_edges().is_empty() and impact_effect.to_upper() != "NONE"
	if has_custom_impact:
		_spawn_effect_sequence(
			impact_effect,
			projectile.definition.effect_profiles,
			projectile.world_position,
			projectile.render_color,
			projectile.heading_degrees,
			null,
			0,
		)
	var impact_radius: float = projectile.definition.impact_radius
	if impact_radius <= 0.0 and projectile.definition.small_explosion:
		impact_radius = maxf(projectile.definition.visual_radius * 4.0, 8.0)
	if projectile.definition.instant and projectile.definition.render_jitter:
		_beam_flashes.append({
			"origin": projectile.origin_position,
			"target": projectile.world_position,
			"color": projectile.render_color,
			"texture_name": projectile.definition.beam_texture_name,
			"start_texture_name": projectile.definition.beam_start_texture_name,
			"end_texture_name": projectile.definition.beam_end_texture_name,
			"start_rotated": projectile.definition.beam_start_rotated,
			"end_rotated": projectile.definition.beam_end_rotated,
			"offset_rate": projectile.definition.beam_image_offset_rate,
			"render_jitter": true,
			"seed": projectile.random_seed,
			"time": 0.08,
		})
	elif projectile.definition.instant and projectile.definition.beam:
		_beam_flashes.append({
			"origin": projectile.origin_position,
			"target": projectile.world_position,
			"color": projectile.render_color,
			"texture_name": projectile.definition.beam_texture_name,
			"start_texture_name": projectile.definition.beam_start_texture_name,
			"end_texture_name": projectile.definition.beam_end_texture_name,
			"start_rotated": projectile.definition.beam_start_rotated,
			"end_rotated": projectile.definition.beam_end_rotated,
			"offset_rate": projectile.definition.beam_image_offset_rate,
			"time": 0.08,
		})
	elif not has_custom_impact and (not projectile.definition.impact_texture_name.is_empty() or impact_radius > 0.0):
		var impact_rotation: float
		var impact_scale: float = projectile.definition.impact_scale
		if projectile.definition.impact_scale_variance > 0.0:
			var scale_seed: float = fposmod(projectile.random_seed * 7.13, 1.0)
			impact_scale += (scale_seed - 0.5) * projectile.definition.impact_scale_variance
		if projectile.definition.impact_random_rotation:
			impact_rotation = deg_to_rad(fposmod(projectile.random_seed * 3.17, 360.0) - 180.0)
		_impact_flashes.append({
			"position": projectile.world_position,
			"texture_name": projectile.definition.impact_texture_name,
			"frame_size": projectile.definition.impact_frame_size,
			"frame_offset": projectile.definition.impact_frame_offset,
			"frame_step": projectile.definition.impact_frame_step if projectile.definition.impact_frame_step != Vector2i.ZERO else projectile.definition.impact_frame_size,
			"frame_count": maxi(projectile.definition.impact_frame_count, 1),
			"duration": maxf(projectile.definition.impact_duration, 0.001),
			"animation_duration": projectile.definition.impact_animation_duration if projectile.definition.impact_animation_duration > 0.0 else projectile.definition.impact_duration,
			"scale": impact_scale,
			"rotation": impact_rotation,
			"color": projectile.definition.impact_color if projectile.definition.impact_color.a > 0.0 else projectile.render_color,
			"radius": impact_radius,
			"time": 0.0,
		})
	elif not has_custom_impact:
		return
	queue_redraw()


## 绘制原版激光防御命中弹体时的短暂光束与拦截火花
func show_laser_deflection(origin: Vector2, projectile: RwProjectileState, destroyed: bool) -> void:
	if projectile == null:
		return
	var color: Color = Color(0.45, 1.0, 0.25, 0.92)
	_beam_flashes.append({
		"origin": origin,
		"target": projectile.world_position + Vector2.UP * projectile.height,
		"color": color,
		"time": 0.08,
	})
	if destroyed:
		_impact_flashes.append({
			"position": projectile.world_position + Vector2.UP * projectile.height,
			"texture_name": "",
			"frame_size": Vector2i.ZERO,
			"frame_offset": Vector2i.ZERO,
			"frame_step": Vector2i.ZERO,
			"frame_count": 1,
			"duration": 0.12,
			"animation_duration": 0.12,
			"scale": 1.0,
			"rotation": 0.0,
			"color": color,
			"radius": 5.0,
			"time": 0.0,
		})
	queue_redraw()


## 播放弹药定义的发射特效
func show_creation(projectile: RwProjectileState) -> void:
	if projectile == null or projectile.definition == null:
		return
	var weapon: RwWeaponDefinition = projectile.weapon_definition
	if weapon != null:
		_show_weapon_muzzle(projectile, weapon)
	if not projectile.definition.effect_on_create.is_empty():
		_spawn_effect_sequence(
			projectile.definition.effect_on_create,
			projectile.definition.effect_profiles,
			projectile.origin_position,
			projectile.render_color,
			projectile.heading_degrees,
			projectile,
			0,
		)
	queue_redraw()


func _show_weapon_muzzle(projectile: RwProjectileState, weapon: RwWeaponDefinition) -> void:
	var effect_profiles: Dictionary = projectile.definition.effect_profiles
	if not weapon.shoot_flame.is_empty() and weapon.shoot_flame.to_upper() != "NONE":
		_spawn_weapon_flame(
			weapon.shoot_flame,
			effect_profiles,
			projectile.origin_position,
			projectile.render_color,
			projectile.heading_degrees,
		)
	if weapon.shoot_light_color.a > 0.0:
		var light_effect: Dictionary = _create_projectile_effect(
			_builtin_effect_profile("light_50.png", Vector2i.ZERO, Vector2i.ZERO, 1, 5.0 / 60.0, 0.7),
			effect_profiles,
			projectile.origin_position,
			projectile.render_color,
			projectile.heading_degrees,
			null,
		)
		light_effect["color"] = weapon.shoot_light_color
		light_effect["alpha"] = 0.8
		_projectile_effects.append(light_effect)


func _spawn_weapon_flame(
	effect_text: String,
	profiles: Dictionary,
	position: Vector2,
	team_color: Color,
	heading_degrees: float,
) -> void:
	for entry: String in effect_text.split(",", false):
		var effect_entry: String = entry.strip_edges()
		var count: int = 1
		var count_separator: int = effect_entry.rfind("*")
		if count_separator >= 0:
			count = clampi(effect_entry.substr(count_separator + 1).to_int(), 1, 12)
			effect_entry = effect_entry.substr(0, count_separator).strip_edges()
		var effect_name: String = effect_entry.trim_prefix("CUSTOM:").to_lower()
		if effect_entry.to_upper().begins_with("CUSTOM:") or profiles.has(effect_name):
			for _effect_index: int in count:
				_spawn_effect_sequence(effect_entry, profiles, position, team_color, heading_degrees, null, 0)
			continue
		var profile: Dictionary = _builtin_muzzle_effect_profile(effect_name)
		if profile.is_empty():
			continue
		for _effect_index: int in count:
			_projectile_effects.append(
				_create_projectile_effect(profile, profiles, position, team_color, heading_degrees, null)
			)


func _builtin_muzzle_effect_profile(effect_name: String) -> Dictionary:
	var texture_name: String
	var duration_frames: float = 8.0
	var scale: float = 0.55
	var frame_count: int = 5
	match effect_name:
		"verysmallflame":
			texture_name = "flame.png"
			duration_frames = 5.0
			scale = 0.3
		"small":
			texture_name = "flame.png"
			duration_frames = 6.0
			scale = 0.5
		"medium":
			texture_name = "flame.png"
			duration_frames = 8.0
			scale = 0.75
		"large":
			texture_name = "flame_large.png"
			duration_frames = 10.0
			scale = 1.0
		"shockwave":
			texture_name = "shockwave_normal_64.png"
			duration_frames = 8.0
			scale = 0.65
			frame_count = 1
		"smoke":
			texture_name = "smoke_white.png"
			duration_frames = 24.0
			scale = 0.45
			frame_count = 1
		_:
			return {}
	var profile: Dictionary = _builtin_effect_profile(
		texture_name,
		Vector2i.ZERO,
		Vector2i.ZERO,
		frame_count,
		duration_frames / 60.0,
		scale,
	)
	profile["frame_width"] = 0
	profile["frame_height"] = 0
	profile["y_speed_absolute"] = -3.0 if effect_name == "smoke" else 0.0
	return profile


func _spawn_effect_sequence(
	effect_text: String,
	profiles: Dictionary,
	position: Vector2,
	team_color: Color,
	heading_degrees: float,
	parent: RwProjectileState,
	depth: int,
) -> void:
	if effect_text.strip_edges().is_empty() or effect_text.to_upper() == "NONE" or depth > 3:
		return
	for entry: String in effect_text.split(",", false):
		var effect_entry: String = entry.strip_edges()
		var count: int = 1
		var count_separator: int = effect_entry.rfind("*")
		if count_separator >= 0:
			count = clampi(effect_entry.substr(count_separator + 1).to_int(), 1, 12)
			effect_entry = effect_entry.substr(0, count_separator).strip_edges()
		var effect_name: String = effect_entry.trim_prefix("CUSTOM:").to_lower()
		var profile: Dictionary = profiles.get(effect_name, {})
		if profile.is_empty() and effect_name == "smallexplosion":
			profile = _builtin_effect_profile("explode_big2.png", Vector2i(39, 40), Vector2i(121, 1), 5, 10.0 / 60.0, 0.5)
		elif profile.is_empty() and effect_name == "largeexplosion":
			profile = _builtin_effect_profile("explode_big.png", Vector2i(39, 40), Vector2i(1, 1), 13, 26.0 / 60.0, 0.9)
		if profile.is_empty():
			continue
		for _effect_index: int in count:
			var effect_state: Dictionary = _create_projectile_effect(
				profile,
				profiles,
				position,
				team_color,
				heading_degrees,
				parent,
			)
			_projectile_effects.append(effect_state)
			_spawn_effect_sequence(
				str(profile.get("also_emit_effects", "")),
				profiles,
				effect_state["position"],
				team_color,
				heading_degrees,
				parent,
				depth + 1,
			)


func _create_projectile_effect(
	profile: Dictionary,
	profiles: Dictionary,
	position: Vector2,
	team_color: Color,
	heading_degrees: float,
	parent: RwProjectileState,
) -> Dictionary:
	var angle: float = deg_to_rad(heading_degrees + float(profile.get("dir_offset", 0.0)))
	var effect_position: Vector2 = position + Vector2(
		float(profile.get("x_offset_absolute", 0.0)),
		float(profile.get("y_offset_absolute", 0.0)),
	)
	effect_position += Vector2(
		float(profile.get("x_offset_relative", 0.0)),
		float(profile.get("y_offset_relative", 0.0)),
	).rotated(angle)
	var velocity: Vector2 = Vector2(
		float(profile.get("x_speed_absolute", 0.0)),
		float(profile.get("y_speed_absolute", 0.0)),
	)
	velocity += Vector2(
		float(profile.get("x_speed_relative", 0.0)),
		float(profile.get("y_speed_relative", 0.0)),
	).rotated(angle)
	velocity += Vector2.RIGHT.rotated(angle) * float(profile.get("h_speed", 0.0))
	var effect_color: Color = _parse_effect_color(str(profile.get("color", "")))
	var team_color_ratio: float = clampf(float(profile.get("team_color_ratio", 0.0)), 0.0, 1.0)
	effect_color = Color(
		effect_color.r * (1.0 - team_color_ratio) + team_color.r * team_color_ratio,
		effect_color.g * (1.0 - team_color_ratio) + team_color.g * team_color_ratio,
		effect_color.b * (1.0 - team_color_ratio) + team_color.b * team_color_ratio,
		effect_color.a,
	)
	var duration_frames: float = maxf(float(profile.get("life", 20.0)), 1.0)
	return {
		"texture_name": str(profile.get("texture_name", "")),
		"frame_index": int(profile.get("frame_index", 0)),
		"frame_width": int(profile.get("frame_width", 0)),
		"frame_height": int(profile.get("frame_height", 0)),
		"frame_offset": profile.get("frame_offset", Vector2i.ZERO),
		"total_frames": maxi(int(profile.get("total_frames", 1)), 1),
		"animate_frame_start": int(profile.get("animate_frame_start", 0)),
		"animate_frame_end": int(profile.get("animate_frame_end", 0)),
		"animate_frame_speed": float(profile.get("animate_frame_speed", 0.5)),
		"animate_frame_looping": bool(profile.get("animate_frame_looping", false)),
		"animate_frame_ping_pong": bool(profile.get("animate_frame_ping_pong", false)),
		"scale_from": float(profile.get("scale_from", 1.0)),
		"scale_to": float(profile.get("scale_to", 1.0)),
		"alpha": clampf(float(profile.get("alpha", 1.0)), 0.0, 1.0),
		"fade_in_time": float(profile.get("fade_in_time", 0.0)) / 60.0,
		"fade_out": bool(profile.get("fade_out", true)),
		"color": effect_color,
		"team_color": team_color,
		"position": effect_position,
		"velocity": velocity,
		"heading": angle,
		"height": 0.0,
		"height_velocity": float(profile.get("h_speed", 0.0)),
		"physics": bool(profile.get("physics", false)),
		"physics_gravity": float(profile.get("physics_gravity", 1.0)),
		"duration_seconds": duration_frames / 60.0,
		"elapsed_seconds": 0.0,
		"attached": bool(profile.get("attached_to_unit", true)),
		"parent": parent if bool(profile.get("attached_to_unit", true)) else null,
		"live_after_parent_dies": bool(profile.get("live_after_attached_dies", true)),
		"effects_on_death": str(profile.get("also_emit_effects_on_death", "")),
		"profiles": profiles,
	}


func _builtin_effect_profile(
	texture_name: String,
	frame_size: Vector2i,
	frame_offset: Vector2i,
	frame_count: int,
	duration: float,
	scale: float,
) -> Dictionary:
	return {
		"texture_name": texture_name,
		"frame_index": 0,
		"frame_width": frame_size.x,
		"frame_height": frame_size.y,
		"frame_offset": frame_offset,
		"total_frames": frame_count,
		"animate_frame_start": 0,
		"animate_frame_end": frame_count - 1,
		"animate_frame_speed": 30.0 / maxf(duration * 60.0, 1.0),
		"animate_frame_looping": false,
		"animate_frame_ping_pong": false,
		"scale_from": scale,
		"scale_to": scale,
		"alpha": 1.0,
		"fade_in_time": 0.0,
		"fade_out": true,
		"color": "#FFFFFFFF",
		"life": duration * 60.0,
		"attached_to_unit": false,
		"live_after_attached_dies": true,
		"also_emit_effects": "",
		"also_emit_effects_on_death": "",
	}


func _draw_projectile_effect(effect: Dictionary) -> void:
	var duration: float = maxf(float(effect["duration_seconds"]), 0.001)
	var progress: float = clampf(float(effect["elapsed_seconds"]) / duration, 0.0, 1.0)
	var fade: float = 1.0
	var fade_in_time: float = float(effect["fade_in_time"])
	if fade_in_time > 0.0:
		fade *= clampf(float(effect["elapsed_seconds"]) / fade_in_time, 0.0, 1.0)
	if bool(effect["fade_out"]):
		fade *= 1.0 - progress
	var color: Color = effect["color"]
	color.a *= float(effect["alpha"]) * fade
	var scale_factor: float = lerpf(float(effect["scale_from"]), float(effect["scale_to"]), progress)
	var texture_name: String = str(effect["texture_name"])
	var texture: Texture2D = _get_texture(texture_name) if not texture_name.is_empty() else null
	if texture == null:
		draw_circle(effect["position"], maxf(scale_factor * 6.0, 1.0), color)
		return
	var frame_width: int = int(effect["frame_width"])
	var frame_height: int = int(effect["frame_height"])
	var total_frames: int = int(effect["total_frames"])
	if frame_width <= 0:
		frame_width = maxi(texture.get_width() / total_frames, 1)
	if frame_height <= 0:
		frame_height = texture.get_height()
	var frame_index: int = int(effect["frame_index"])
	var animation_start: int = int(effect["animate_frame_start"])
	var animation_end: int = int(effect["animate_frame_end"])
	if animation_end > animation_start:
		var animation_frame: int = int(float(effect["elapsed_seconds"]) * 60.0 * float(effect["animate_frame_speed"]))
		var animation_count: int = animation_end - animation_start + 1
		if bool(effect["animate_frame_ping_pong"]) and animation_count > 1:
			var ping_pong_length: int = animation_count * 2 - 2
			animation_frame = posmod(animation_frame, ping_pong_length)
			if animation_frame >= animation_count:
				animation_frame = ping_pong_length - animation_frame
		elif bool(effect["animate_frame_looping"]):
			animation_frame = posmod(animation_frame, animation_count)
		else:
			animation_frame = mini(animation_frame, animation_count - 1)
		frame_index += animation_start + animation_frame
	var frame_offset: Vector2i = effect.get("frame_offset", Vector2i.ZERO)
	var source: Rect2 = Rect2(
		Vector2(frame_offset + Vector2i(frame_index * frame_width, 0)),
		Vector2(frame_width, frame_height),
	)
	var size: Vector2 = Vector2(frame_width, frame_height) * scale_factor
	var height_offset: float = float(effect["height"])
	draw_set_transform(effect["position"] + Vector2.UP * height_offset, float(effect["heading"]), Vector2.ONE)
	draw_texture_rect_region(texture, Rect2(-size * 0.5, size), source, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _parse_effect_color(color_text: String) -> Color:
	if color_text.is_empty():
		return Color.WHITE
	if color_text.begins_with("#") and color_text.length() == 9:
		return Color.from_string("#%s%s" % [color_text.substr(3, 6), color_text.substr(1, 2)], Color.WHITE)
	return Color.from_string(color_text, Color.WHITE)


## 在弹体结束后保留尚未消散的独立烟尘
func finish_projectile(projectile: RwProjectileState) -> void:
	if (
		projectile == null
		or projectile.definition == null
		or not projectile.definition.trail_as_particles
		or not projectile.definition.trail_effect_name.is_empty()
	):
		return
	var lifetime: float = maxf(projectile.definition.trail_particle_lifetime_frames, 0.0)
	for index: int in projectile.trail_positions.size():
		var age: float = projectile.elapsed_frames - projectile.trail_spawn_frames[index]
		if age >= lifetime:
			continue
		_detached_trail_particles.append({
			"position": projectile.trail_positions[index],
			"definition": projectile.definition,
			"age_frames": age,
		})
	queue_redraw()


## 按模拟步长推进已脱离弹体的视觉粒子
func advance_effects(simulation_delta: float) -> void:
	var step: float = maxf(simulation_delta, 0.0)
	for index: int in range(_detached_trail_particles.size() - 1, -1, -1):
		var particle: Dictionary = _detached_trail_particles[index]
		var definition: RwProjectileDefinition = particle["definition"]
		var age: float = float(particle["age_frames"]) + step
		if age >= definition.trail_particle_lifetime_frames:
			_detached_trail_particles.remove_at(index)
		else:
			particle["age_frames"] = age
	queue_redraw()


func _draw_trail_particle(point: Vector3, definition: RwProjectileDefinition, age_frames: float) -> void:
	var lifetime: float = maxf(definition.trail_particle_lifetime_frames, 0.001)
	var age_ratio: float = clampf(age_frames / lifetime, 0.0, 1.0)
	if age_ratio >= 1.0:
		return
	var color: Color = definition.trail_color
	var fade_in_duration: float = definition.trail_particle_fade_in_duration_frames
	if fade_in_duration > 0.0 and age_frames < fade_in_duration:
		color.a *= clampf(age_frames / fade_in_duration, 0.0, 1.0)
	var fade_out_duration: float = definition.trail_particle_fade_duration_frames
	if fade_out_duration > 0.0:
		var fade_out_start: float = maxf(lifetime - fade_out_duration, 0.0)
		if age_frames >= fade_out_start:
			color.a *= clampf((lifetime - age_frames) / fade_out_duration, 0.0, 1.0)
	elif fade_in_duration <= 0.0:
		color.a *= 1.0 - age_ratio
	var position: Vector2 = Vector2(point.x, point.y + age_frames * definition.trail_particle_drift_y_per_frame) + Vector2.UP * point.z
	var texture: Texture2D = _get_texture(definition.trail_texture_name) if not definition.trail_texture_name.is_empty() else null
	if texture == null:
		var radius: float = definition.trail_width * lerpf(definition.trail_particle_scale_from, definition.trail_particle_scale_to, age_ratio)
		draw_circle(position, radius, color)
		return
	var frame_size: Vector2i = definition.trail_texture_frame_size
	var frame_offset: Vector2i = definition.trail_texture_frame_offset
	var frame_index: int
	if definition.trail_animate_frames:
		var frame_step: Vector2i = definition.trail_texture_frame_step if definition.trail_texture_frame_step != Vector2i.ZERO else frame_size
		var frame_count: int = maxi((texture.get_width() - frame_offset.x) / maxi(frame_step.x, 1), 1)
		frame_index = mini(int(age_ratio * frame_count), frame_count - 1)
	var step: Vector2i = definition.trail_texture_frame_step if definition.trail_texture_frame_step != Vector2i.ZERO else frame_size
	var source: Rect2 = Rect2(Vector2(frame_offset + Vector2i(frame_index * step.x, 0)), Vector2(frame_size))
	var size_scale: float = lerpf(definition.trail_particle_scale_from, definition.trail_particle_scale_to, age_ratio)
	var size: Vector2 = Vector2(frame_size) * definition.trail_texture_scale * size_scale
	if definition.trail_particle_shadow:
		draw_circle(Vector2(point.x, point.y), size.length() * 0.12, Color(0.0, 0.0, 0.0, 0.12))
	var destination: Rect2 = Rect2(position - size * 0.5, size)
	draw_texture_rect_region(texture, destination, source, color)


func _draw_textured_beam(beam: Dictionary) -> void:
	var origin: Vector2 = beam["origin"]
	var target: Vector2 = beam["target"]
	var direction: Vector2 = target - origin
	var beam_texture: Texture2D = _get_texture(str(beam["texture_name"]))
	if beam_texture == null or direction.length_squared() <= 0.0001:
		draw_line(origin, target, beam["color"], 3.0, false)
		return
	var beam_color: Color = beam["color"]
	var beam_size: Vector2 = Vector2(float(beam_texture.get_width()), direction.length())
	draw_set_transform((origin + target) * 0.5, direction.angle() + PI * 0.5, Vector2.ONE)
	draw_texture_rect(beam_texture, Rect2(-beam_size * 0.5, beam_size), false, beam_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_beam_cap(
		str(beam.get("start_texture_name", "")),
		origin,
		direction.angle() + PI * 0.5 if bool(beam.get("start_rotated", false)) else 0.0,
		beam_color,
	)
	_draw_beam_cap(
		str(beam.get("end_texture_name", "")),
		target,
		direction.angle() + PI * 0.5 if bool(beam.get("end_rotated", false)) else 0.0,
		beam_color,
	)


func _draw_beam_cap(texture_name: String, position: Vector2, rotation: float, color: Color) -> void:
	if texture_name.is_empty():
		return
	var texture: Texture2D = _get_texture(texture_name)
	if texture == null:
		return
	var size: Vector2 = Vector2(texture.get_size())
	draw_set_transform(position, rotation, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-size * 0.5, size), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_jitter_beam(origin: Vector2, target: Vector2, color: Color, seed: float) -> void:
	var direction: Vector2 = target - origin
	var perpendicular: Vector2 = direction.normalized().orthogonal()
	var previous: Vector2 = origin
	for segment_index: int in 20:
		var progress: float = float(segment_index + 1) / 20.0
		var point: Vector2 = origin.lerp(target, progress)
		if segment_index < 19:
			point += perpendicular * sin(float(segment_index) * 19.17 + seed * 0.07) * 10.0
		draw_line(previous, point, color, 2.0, false)
		previous = point


func _get_texture(image_name: String) -> Texture2D:
	if not _texture_cache.has(image_name):
		if image_name.begins_with("builtin:"):
			_texture_cache[image_name] = RwBuiltinUnitImageCatalog.load_texture(image_name.trim_prefix("builtin:"))
		else:
			_texture_cache[image_name] = RwDrawableCatalog.load_texture(image_name)
	return _texture_cache[image_name] as Texture2D
