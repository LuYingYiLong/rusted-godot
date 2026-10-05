extends Node2D
class_name RwBattleProjectileLayer
## 绘制战斗系统中的弹体；模拟状态由 RwBattleCombat 管理

var _projectiles: Array[RwProjectileState]
var _texture_cache: Dictionary
var _beam_flashes: Array[Dictionary]
var _impact_flashes: Array[Dictionary]
var _detached_trail_particles: Array[Dictionary]


func _process(delta: float) -> void:
	if _beam_flashes.is_empty() and _impact_flashes.is_empty():
		return
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
	for beam: Dictionary in _beam_flashes:
		var beam_color: Color = beam["color"]
		if bool(beam.get("render_jitter", false)):
			_draw_jitter_beam(beam["origin"], beam["target"], beam_color, float(beam.get("seed", 0.0)))
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
		if definition == null or not definition.visible_in_flight:
			continue
		if definition.trail_as_particles:
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
					Rect2(draw_position - light_size * 0.5, light_size),
					false,
					light_color,
				)
		if definition.texture_name.is_empty():
			if projectile.height > 0.0 and definition.render_shadow:
				draw_circle(projectile.world_position, definition.visual_radius, Color(0.0, 0.0, 0.0, 0.42))
			if definition.glow_radius > 0.0:
				draw_circle(draw_position, definition.glow_radius, Color(definition.visual_color, 0.16))
			draw_circle(draw_position, definition.visual_radius, definition.visual_color)
			continue
		var texture: Texture2D = _get_texture(definition.texture_name)
		if texture == null:
			draw_circle(draw_position, definition.visual_radius, definition.visual_color)
			continue
		var region: Rect2i = definition.texture_region
		if region.size == Vector2i.ZERO:
			region = Rect2i(Vector2i.ZERO, texture.get_size())
		var size: Vector2 = Vector2(region.size) * definition.texture_scale
		var destination: Rect2 = Rect2(-size * 0.5, size)
		var rotation: float = projectile.velocity.angle() + deg_to_rad(definition.texture_rotation_offset_degrees)
		if projectile.height > 0.0 and definition.render_shadow:
			draw_circle(projectile.world_position, definition.visual_radius, Color(0.0, 0.0, 0.0, 0.42))
		if definition.glow_radius > 0.0:
			draw_circle(draw_position, definition.glow_radius, Color(definition.visual_color, 0.16))
		draw_set_transform(draw_position, rotation, Vector2.ONE)
		draw_texture_rect_region(texture, destination, Rect2(region), definition.visual_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 接收当前弹体列表并请求重绘
func set_projectiles(projectiles: Array[RwProjectileState]) -> void:
	_projectiles = projectiles
	queue_redraw()


## 按弹体定义显示光束或爆炸图集
func show_impact(projectile: RwProjectileState, _target: RwUnitState) -> void:
	if projectile.definition == null:
		return
	var impact_radius: float = projectile.definition.impact_radius
	if impact_radius <= 0.0 and projectile.definition.small_explosion:
		impact_radius = maxf(projectile.definition.visual_radius * 4.0, 8.0)
	if projectile.definition.instant and projectile.definition.render_jitter:
		_beam_flashes.append({
			"origin": projectile.origin_position,
			"target": projectile.world_position,
			"color": projectile.definition.visual_color,
			"render_jitter": true,
			"seed": projectile.random_seed,
			"time": 0.08,
		})
	elif projectile.definition.instant and projectile.definition.beam:
		_beam_flashes.append({
			"origin": projectile.origin_position,
			"target": projectile.world_position,
			"color": projectile.definition.visual_color,
			"time": 0.08,
		})
	elif not projectile.definition.impact_texture_name.is_empty() or impact_radius > 0.0:
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
			"color": projectile.definition.impact_color if projectile.definition.impact_color.a > 0.0 else projectile.definition.visual_color,
			"radius": impact_radius,
			"time": 0.0,
		})
	else:
		return
	queue_redraw()


## 在弹体结束后保留尚未消散的独立烟尘
func finish_projectile(projectile: RwProjectileState) -> void:
	if projectile == null or projectile.definition == null or not projectile.definition.trail_as_particles:
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
		_texture_cache[image_name] = RwDrawableCatalog.load_texture(image_name)
	return _texture_cache[image_name] as Texture2D
