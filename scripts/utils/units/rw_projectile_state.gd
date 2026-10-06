class_name RwProjectileState
extends RefCounted
## 保存单个弹体在同步帧之间的运行状态

## 与原版 GameObject 共用的对象编号
var object_id: int
var owner_id: int
var target_id: int
var target_position: Vector2
var team: String
var origin_position: Vector2
var world_position: Vector2
var velocity: Vector2
var heading_degrees: float
## 原版用于绘制弹体的平滑朝向
var render_heading_degrees: float
var remaining_frames: float
var elapsed_frames: float
## 原版激光防御还需命中多少次才能销毁该弹体
var deflection_remaining: float = 1.0
var delayed_start_remaining_frames: float
var area_expansion_elapsed_frames: float
var trail_emission_serial: int
var recursion_depth: int
var area_damaged_unit_ids: Dictionary
var height: float
var height_velocity: float
var target_velocity: Vector2
## 发射单位攻击配置应用到本弹体直击和范围伤害的倍率
var source_damage_multiplier: float = 1.0
var trail_positions: Array[Vector3]
var trail_spawn_frames: Array[float]
var definition: RwProjectileDefinition
var weapon_definition: RwWeaponDefinition
var intercept_target_projectile: RwProjectileState
## 原版扫动弹体当前帧的横纵偏移
var current_sweep_offset: Vector2
var target_lost: bool
var remove_requested: bool
var has_impacted: bool
var hit_shield: bool
var visible_by_fog: bool = true
var fog_reveal_triggered: bool
var retarget_search_timer: float
var random_seed: float
var source_random_phase: float
## 结合弹药颜色与发射方颜色后的绘制颜色
var render_color: Color = Color.WHITE
var parent_anchor_position: Vector2
var parent_anchor_height: float
var _last_target_position: Vector2
var _last_target_altitude: float
var _trail_elapsed_frames: float
var _previous_wobble_offset: float
var _altitude_reached_maximum: bool
var _altitude_descending: bool
var _spread_seed: int


## 按发射信息初始化弹体
func configure(
	source: RwUnitState,
	target: RwUnitState,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	projectile_override: RwProjectileDefinition = null,
	spread_seed: int = -1,
	simulation_frame: int = -1,
	global_seed: int = 0,
	reuse_existing: bool = false,
	targeting_origin_override: Vector2 = Vector2.ZERO,
	use_targeting_origin_override: bool = false,
) -> void:
	owner_id = source.object_id
	target_id = target.object_id
	target_position = target.world_position
	_last_target_position = target.world_position
	_last_target_altitude = target.altitude
	team = source.team
	definition = weapon.projectile if projectile_override == null else projectile_override
	render_color = definition.visual_color
	weapon_definition = weapon
	_spread_seed = spread_seed if spread_seed >= 0 else source.object_id * 37 + target.object_id * 19
	if not reuse_existing:
		_initialize_random_phase(source, simulation_frame, global_seed)
	var speed_spread_value: float = _roll_speed_spread(source, simulation_frame, global_seed)
	if definition.target_ground:
		var shot_direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
		var firing_position: Vector2 = source.world_position
		firing_position += _rotated_muzzle_offset(weapon, angle_degrees)
		firing_position += shot_direction * weapon.muzzle_distance
		if use_targeting_origin_override:
			firing_position = targeting_origin_override
		var resolved_target_position: Vector2 = target.world_position
		if definition.lead_target:
			var lead_speed: float = definition.lead_target_speed_calculation
			if lead_speed < 0.0:
				lead_speed = definition.target_speed_per_frame
			if lead_speed <= 0.0:
				lead_speed = definition.speed_per_frame
			if lead_speed > 0.0:
				var target_velocity_at_fire: Vector2 = target.get_world_velocity()
				var lead_time: float
				for iteration: int in 3:
					var predicted_position: Vector2 = target.world_position + target_velocity_at_fire * lead_time
					lead_time = firing_position.distance_to(predicted_position) / maxf(lead_speed, 0.1)
				lead_time = minf(lead_time, float(definition.lifetime_frames))
				resolved_target_position += target_velocity_at_fire * lead_time
		if definition.target_ground_spread > 0.0:
			resolved_target_position.x = RwGameMath.float32(
				resolved_target_position.x
				+ _roll_target_ground_spread(source, definition.target_ground_spread, 2, simulation_frame, global_seed)
			)
			resolved_target_position.y = RwGameMath.float32(
				resolved_target_position.y
				+ _roll_target_ground_spread(source, definition.target_ground_spread, 7, simulation_frame, global_seed)
			)
		target_position = resolved_target_position
		_last_target_position = resolved_target_position
		_last_target_altitude = target.altitude if definition.target_ground_include_target_height else 0.0
		_last_target_altitude += definition.target_ground_height_offset
		target_id = -1
	_initialize_motion(source, weapon, angle_degrees, speed_spread_value, reuse_existing)


## 按地面目标初始化没有目标单位的弹体
func configure_at(
	source: RwUnitState,
	position: Vector2,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	projectile_override: RwProjectileDefinition = null,
	target_altitude: float = 0.0,
	spread_seed: int = -1,
	simulation_frame: int = -1,
	global_seed: int = 0,
	reuse_existing: bool = false,
) -> void:
	owner_id = source.object_id
	target_id = -1
	definition = weapon.projectile if projectile_override == null else projectile_override
	weapon_definition = weapon
	_spread_seed = spread_seed if spread_seed >= 0 else source.object_id * 37 + int(round(position.x)) * 19 + int(round(position.y))
	if not reuse_existing:
		_initialize_random_phase(source, simulation_frame, global_seed)
	var speed_spread_value: float = _roll_speed_spread(source, simulation_frame, global_seed)
	target_position = position
	if definition.target_ground_spread > 0.0:
		target_position.x = RwGameMath.float32(
			target_position.x
			+ _roll_target_ground_spread(source, definition.target_ground_spread, 2, simulation_frame, global_seed)
		)
		source.random_counter = int(RwGameMath.float32(float(source.random_counter) + target_position.x))
		target_position.y = RwGameMath.float32(
			target_position.y
			+ _roll_target_ground_spread(source, definition.target_ground_spread, 3, simulation_frame, global_seed)
		)
		source.random_counter = int(RwGameMath.float32(float(source.random_counter) + target_position.y))
	_last_target_position = target_position
	var resolved_target_altitude: float = target_altitude if definition.target_ground_include_target_height else 0.0
	_last_target_altitude = resolved_target_altitude + definition.target_ground_height_offset
	team = source.team
	_initialize_motion(source, weapon, angle_degrees, speed_spread_value, reuse_existing)


## 推进一帧并返回弹体是否命中目标
func advance_frame(target: RwUnitState, simulation_delta: float = 1.0, parent: RwUnitState = null) -> bool:
	if definition == null:
		return false
	var step: float = maxf(simulation_delta, 0.0)
	if step <= 0.0:
		return false
	if remaining_frames <= 0.0:
		return false
	if not has_impacted and delayed_start_remaining_frames > 0.0:
		delayed_start_remaining_frames = maxf(delayed_start_remaining_frames - step, 0.0)
		if delayed_start_remaining_frames > 0.0:
			return false
	_follow_parent(parent)
	if has_impacted:
		elapsed_frames += step
		remaining_frames = maxf(remaining_frames - step, 0.0)
		return false
	var projectile_age: float = elapsed_frames
	var tracked_projectile: RwProjectileState = intercept_target_projectile
	if tracked_projectile != null and not tracked_projectile.remove_requested and tracked_projectile.remaining_frames > 0.0:
		target_position = tracked_projectile.world_position
		_last_target_altitude = tracked_projectile.height
	if target_id > 0 and (target == null or target.is_dead):
		mark_target_lost()
		if definition.detonate_on_target_loss:
			return true
	if target_lost and definition.remove_on_target_loss:
		remove_requested = true
		return false
	elif target != null and target_id > 0:
		target_position = target.world_position
		_last_target_altitude = target.altitude
		target_velocity = (target.world_position - _last_target_position) / step
		_last_target_position = target.world_position
	elapsed_frames += step
	remaining_frames = maxf(remaining_frames - step, 0.0)
	if definition.instant:
		world_position = target.world_position if target != null and not definition.target_ground else target_position
		height = target.altitude if target != null and not definition.target_ground else _last_target_altitude
		return true
	var speed: float = velocity.length()
	var aim_position: Vector2 = target_position
	var target_altitude: float = _last_target_altitude
	if tracked_projectile != null:
		aim_position = tracked_projectile.world_position
		target_altitude = tracked_projectile.height
	if target != null and not target.is_dead and target_id > 0:
		aim_position = target.world_position
		target_altitude = target.altitude
	var sweep_offset: Vector2 = _calculate_sweep_offset(target, projectile_age)
	current_sweep_offset = sweep_offset
	aim_position += sweep_offset
	var native_target_position: Vector2 = target.world_position if target != null else aim_position
	if target != null:
		native_target_position += sweep_offset
	var native_target_distance_squared: float = world_position.distance_squared_to(native_target_position)
	var native_target_height_delta: float = target_altitude - height
	var ballistic_maximum: float = definition.ballistic_height
	if ballistic_maximum == -1.0:
		ballistic_maximum = 60.0 if definition.ballistic else 0.0
	if definition.altitude_maximum > 0.0:
		ballistic_maximum = definition.altitude_maximum
	var ballistic_threshold: float = definition.ballistic_delay_move_height
	if ballistic_threshold == -1.0:
		ballistic_threshold = 40.0 if definition.ballistic else definition.altitude_move_start
	var ballistic_speed: float = definition.altitude_change_per_frame
	if ballistic_speed <= 0.0:
		ballistic_speed = definition.ballistic_vertical_speed if definition.ballistic_vertical_speed > 0.0 else speed
	var ballistic_step: float = ballistic_speed * step
	var uses_altitude_arc: bool = (
		definition.ballistic and ballistic_step > 0.0
		or not definition.ballistic and ballistic_maximum > 0.0 and ballistic_step > 0.0
	)
	var move_horizontally: bool = true
	if definition.ballistic:
		height += height_velocity * step
		if height > 0.0:
			height -= definition.gravity_per_frame * step
			height_velocity -= definition.true_gravity_per_frame * step
		move_horizontally = _altitude_reached_maximum or height > ballistic_threshold
		if not _altitude_reached_maximum:
			height = move_toward(height, ballistic_maximum, ballistic_step)
			if height >= ballistic_maximum:
				_altitude_reached_maximum = true
		elif world_position.distance_squared_to(aim_position) <= definition.altitude_descent_range * definition.altitude_descent_range:
			_altitude_descending = true
		if _altitude_descending:
			height = move_toward(height, target_altitude, ballistic_step)
	elif uses_altitude_arc:
		move_horizontally = _altitude_reached_maximum or height > ballistic_threshold
		if not _altitude_reached_maximum:
			height = move_toward(height, ballistic_maximum, ballistic_step)
			if height >= ballistic_maximum:
				_altitude_reached_maximum = true
		elif _altitude_reached_maximum and world_position.distance_squared_to(aim_position) <= definition.altitude_descent_range * definition.altitude_descent_range:
			_altitude_descending = true
		if _altitude_descending:
			height = move_toward(height, target_altitude, ballistic_step)
	else:
		height += height_velocity * step
		if height > 0.0:
			height -= definition.gravity_per_frame * step
			height_velocity -= definition.true_gravity_per_frame * step
		var altitude_delta: float = target_altitude - height
		if altitude_delta != 0.0:
			var vertical_travel: float = speed * step
			var horizontal_distance_squared: float = world_position.distance_squared_to(aim_position)
			if horizontal_distance_squared > 0.1:
				vertical_travel = minf(
					absf(altitude_delta) / sqrt(horizontal_distance_squared) * vertical_travel,
					vertical_travel,
				)
			height += signf(altitude_delta) * vertical_travel
	native_target_height_delta = target_altitude - height
	var has_aim_target: bool = (
		(definition.homing and (target_id > 0 or target_lost))
		or tracked_projectile != null
		or definition.target_ground
	)
	if has_aim_target:
		var offset: Vector2 = aim_position - world_position
		if offset.length_squared() > 0.0001:
			var desired_angle: float = offset.angle()
			var current_angle: float = velocity.angle()
			var next_angle: float = desired_angle
			var turn_speed: float = definition.turn_speed_degrees
			if offset.length_squared() < 225.0:
				turn_speed = definition.turn_speed_near_degrees
			if turn_speed >= 0.0:
				var limit: float = deg_to_rad(turn_speed * step)
				next_angle = current_angle + clampf(wrapf(desired_angle - current_angle, -PI, PI), -limit, limit)
			velocity = Vector2.RIGHT.rotated(next_angle) * speed
			heading_degrees = rad_to_deg(next_angle)
	elif speed > 0.0:
		velocity = velocity.normalized() * speed
	var remaining_distance: float = world_position.distance_to(aim_position)
	var travel_distance: float = speed * step
	var reaches_unit_target: bool = target_id > 0 and remaining_distance < travel_distance
	var reaches_ground_point: bool = (
		definition.target_ground
		and definition.native_target_collision_rules
		and remaining_distance < travel_distance
	)
	if reaches_unit_target or reaches_ground_point:
		travel_distance = remaining_distance
		native_target_distance_squared = 0.0
	world_position += definition.initial_unguided_velocity * step
	if move_horizontally:
		world_position += velocity.normalized() * travel_distance
	if tracked_projectile != null and remaining_distance <= travel_distance and move_horizontally:
		world_position = aim_position
		_update_render_heading(step)
		return true
	if definition.target_ground and not definition.native_target_collision_rules and remaining_distance <= travel_distance and move_horizontally:
		world_position = aim_position
		_update_render_heading(step)
		return true
	if definition.wobble_amplitude != 0.0 and definition.wobble_frequency > 0.0 and velocity.length_squared() > 0.0001:
		var wobble_angle: float = projectile_age * 360.0 / definition.wobble_frequency + source_random_phase * 360.0
		var wobble_offset: float = sin(deg_to_rad(wobble_angle)) * definition.wobble_amplitude * step
		world_position += velocity.normalized().rotated(PI * 0.5) * wobble_offset
	if definition.trail_length_frames > 0 and definition.trail_width > 0.0 and (move_horizontally or definition.trail_during_stationary):
		_trail_elapsed_frames += step
		var emission_interval: float = maxf(definition.trail_emission_interval_frames, 0.01)
		if _trail_elapsed_frames > emission_interval:
			_trail_elapsed_frames = 0.0
			_append_trail_position(world_position, height)
	if (move_horizontally or definition.ballistic) and definition.target_speed_per_frame > 0.0 and definition.speed_acceleration_per_frame > 0.0:
		speed = move_toward(speed, definition.target_speed_per_frame, definition.speed_acceleration_per_frame * step)
		if velocity.length_squared() > 0.0001:
			velocity = velocity.normalized() * speed
	if definition.native_target_collision_rules and (
		target != null and not target.is_dead and target_id > 0 or definition.target_ground
	):
		var target_hit_radius: float = definition.native_minimum_target_hit_radius
		if definition.target_ground:
			target_hit_radius = definition.native_minimum_target_hit_radius
		else:
			native_target_height_delta = target.altitude - height
			if target.is_building:
				target_hit_radius = maxf(target.collision_radius * definition.native_building_radius_scale, target_hit_radius)
			if target.health > definition.native_health_damage_threshold + definition.damage * source_damage_multiplier:
				target_hit_radius = target.collision_radius * definition.native_high_health_radius_scale
		var vertical_tolerance: float = definition.altitude_hit_tolerance
		if definition.native_altitude_collision_rules:
			var vertical_speed_delta: float = absf(height_velocity * step) + absf(definition.gravity_per_frame * step)
			vertical_tolerance = 3.0 + vertical_speed_delta
		var height_matches_target: bool = absf(native_target_height_delta) < vertical_tolerance
		var is_inside_target_radius: bool = native_target_distance_squared < target_hit_radius * target_hit_radius
		_update_render_heading(step)
		return height_matches_target and is_inside_target_radius
	var collision_radius: float
	if definition.include_target_collision_radius and target != null and not target.is_dead and target_id > 0:
		collision_radius = target.collision_radius
	var hit_distance: float = collision_radius + definition.hit_radius
	var inside_height: bool = not uses_altitude_arc or absf(height - target_altitude) <= definition.altitude_hit_tolerance
	_update_render_heading(step)
	return inside_height and world_position.distance_squared_to(target_position) <= hit_distance * hit_distance


## 标记原目标已失效并保留最后的瞄准位置
func mark_target_lost() -> void:
	target_lost = true


## 把弹体目标切换到重新捕获的单位
func retarget(target: RwUnitState) -> void:
	if target == null or target.is_dead:
		return
	target_id = target.object_id
	target_position = target.world_position
	_last_target_position = target.world_position
	_last_target_altitude = target.altitude
	target_velocity = Vector2.ZERO
	target_lost = false


func _update_render_heading(step: float) -> void:
	var heading_delta: float = wrapf(heading_degrees - render_heading_degrees, -180.0, 180.0)
	render_heading_degrees += clampf(heading_delta, -12.0 * step, 12.0 * step)


func should_reveal_fog_this_frame(hit: bool) -> bool:
	return (
		definition != null
		and definition.should_reveal_fog
		and not fog_reveal_triggered
		and (hit or _altitude_descending and height < 30.0)
	)


## 应用一次原版激光防御拦截并返回弹体是否被销毁
func apply_deflection() -> bool:
	if definition == null or definition.deflection_power < 0.5 or remove_requested:
		return false
	deflection_remaining -= 1.0
	if deflection_remaining <= 0.0:
		remove_requested = true
		return true
	return false


func _initialize_motion(
	source: RwUnitState,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	speed_spread_value: float,
	reuse_existing: bool,
) -> void:
	var previous_age: float = elapsed_frames if reuse_existing else 0.0
	var previous_trail_emission_serial: int = trail_emission_serial if reuse_existing else 0
	var previous_phase: float = source_random_phase
	var previous_sweep_offset: Vector2 = current_sweep_offset if reuse_existing else Vector2.ZERO
	var previous_areas: Dictionary = area_damaged_unit_ids.duplicate() if reuse_existing else {}
	world_position = Vector2.ZERO
	origin_position = Vector2.ZERO
	velocity = Vector2.ZERO
	target_velocity = Vector2.ZERO
	remaining_frames = 0.0
	elapsed_frames = previous_age
	deflection_remaining = definition.deflection_power
	trail_emission_serial = previous_trail_emission_serial
	delayed_start_remaining_frames = definition.delayed_start_frames
	area_expansion_elapsed_frames = 0.0
	area_damaged_unit_ids.clear()
	if reuse_existing and definition.instant_reuse_last_keep_area_damage_list:
		area_damaged_unit_ids = previous_areas
	height = 0.0
	height_velocity = 0.0
	trail_positions.clear()
	trail_spawn_frames.clear()
	target_lost = false
	remove_requested = false
	has_impacted = false
	hit_shield = false
	retarget_search_timer = 0.0
	_trail_elapsed_frames = 0.0
	_previous_wobble_offset = 0.0
	_altitude_reached_maximum = false
	_altitude_descending = false
	current_sweep_offset = previous_sweep_offset
	var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
	heading_degrees = angle_degrees
	render_heading_degrees = angle_degrees
	var mount_offset: Vector2 = _rotated_muzzle_offset(weapon, angle_degrees)
	world_position = source.world_position + mount_offset + direction * weapon.muzzle_distance
	origin_position = world_position
	var initial_speed: float = maxf(definition.speed_per_frame + speed_spread_value, 0.0)
	velocity = direction * initial_speed + definition.initial_velocity
	height_velocity = definition.initial_height_velocity
	remaining_frames = definition.lifetime_frames
	parent_anchor_position = source.world_position + mount_offset
	parent_anchor_height = source.altitude
	if reuse_existing:
		source_random_phase = previous_phase
	if not definition.trail_as_particles:
		_append_trail_position(world_position, height)


func _initialize_random_phase(source: RwUnitState, simulation_frame: int, global_seed: int) -> void:
	if simulation_frame < 0:
		source_random_phase = float(posmod(_spread_seed * 48271 + 1, 1000)) / 1000.0
		random_seed = fposmod(float(_spread_seed), 360.0)
		return
	var phase_counter: int = source.random_counter
	var phase_sample: int = RwVanillaRandom.unit_range(
		0,
		1000,
		source.object_id,
		source.world_position,
		phase_counter,
		simulation_frame,
		global_seed,
		phase_counter,
	)
	source_random_phase = float(phase_sample) * 0.001
	random_seed = fposmod(float(_spread_seed), 360.0)
	source.random_counter = RwVanillaRandom.advance_projectile_creation_counter(source.random_counter)


func _calculate_sweep_offset(target: RwUnitState, projectile_age: float) -> Vector2:
	if definition.sweep_offset == 0.0 and definition.sweep_offset_from_target_radius == 0.0:
		return Vector2.ZERO
	var amplitude: float = definition.sweep_offset
	if target != null:
		amplitude += target.collision_radius * definition.sweep_offset_from_target_radius
	var x_angle: float = fposmod(360.0 * source_random_phase + projectile_age, 360.0)
	var y_angle: float = fposmod(360.0 * source_random_phase + projectile_age * 1.5, 360.0)
	return Vector2(sin(deg_to_rad(x_angle)), sin(deg_to_rad(y_angle))) * amplitude


func _rotated_muzzle_offset(weapon: RwWeaponDefinition, angle_degrees: float) -> Vector2:
	return weapon.muzzle_offset.rotated(deg_to_rad(angle_degrees))


func _follow_parent(parent: RwUnitState) -> void:
	if not definition.move_with_parent or parent == null or weapon_definition == null:
		return
	var parent_weapon_angle: float = parent.get_weapon_rotation(weapon_definition.rotation_state_index)
	var current_parent_anchor: Vector2 = parent.world_position + weapon_definition.muzzle_offset.rotated(
		deg_to_rad(parent_weapon_angle)
	)
	var parent_anchor_delta: Vector2 = current_parent_anchor - parent_anchor_position
	world_position += parent_anchor_delta
	origin_position += parent_anchor_delta
	height += parent.altitude - parent_anchor_height
	parent_anchor_position = current_parent_anchor
	parent_anchor_height = parent.altitude


func _roll_speed_spread(source: RwUnitState, simulation_frame: int, global_seed: int) -> float:
	if definition.speed_spread <= 0.0:
		return 0.0
	if simulation_frame < 0:
		return _seeded_spread(definition.speed_spread, 3)
	var minimum: int = int(-definition.speed_spread * 100.0)
	var maximum: int = int(definition.speed_spread * 100.0)
	var spread_value: int = RwVanillaRandom.unit_range(
		minimum,
		maximum,
		source.object_id,
		source.world_position,
		source.random_counter,
		simulation_frame,
		global_seed,
		1,
	)
	return float(spread_value) / 100.0


func _roll_target_ground_spread(
	source: RwUnitState,
	spread: float,
	stream: int,
	simulation_frame: int,
	global_seed: int,
) -> float:
	if simulation_frame < 0:
		return _seeded_spread(spread, stream)
	var minimum: int = int(-spread * 100.0)
	var maximum: int = int(spread * 100.0)
	var spread_value: int = RwVanillaRandom.unit_range(
		minimum,
		maximum,
		source.object_id,
		source.world_position,
		source.random_counter,
		simulation_frame,
		global_seed,
	stream,
	)
	return float(spread_value) / 100.0


func _seeded_spread(spread: float, stream: int) -> float:
	if spread <= 0.0:
		return 0.0
	var modulus: int = 2147483647
	var value: int = posmod(_spread_seed * 48271 + stream * 69621, modulus)
	value = posmod(value * 48271 + 1, modulus)
	var unit_value: float = float(value) / float(modulus)
	return (unit_value * 2.0 - 1.0) * spread


func _append_trail_position(position: Vector2, trail_height: float) -> void:
	trail_positions.append(Vector3(position.x, position.y, trail_height))
	trail_spawn_frames.append(elapsed_frames)
	trail_emission_serial += 1
	while trail_positions.size() > definition.trail_length_frames:
		trail_positions.pop_front()
		trail_spawn_frames.pop_front()
