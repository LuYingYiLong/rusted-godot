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
var remaining_frames: float
var elapsed_frames: float
var height: float
var height_velocity: float
var target_velocity: Vector2
var trail_positions: Array[Vector3]
var trail_spawn_frames: Array[float]
var definition: RwProjectileDefinition
var weapon_definition: RwWeaponDefinition
var target_lost: bool
var remove_requested: bool
var retarget_search_timer: float
var random_seed: float
var _last_target_position: Vector2
var _last_target_altitude: float
var _trail_elapsed_frames: float
var _previous_wobble_offset: float
var _altitude_reached_maximum: bool
var _altitude_descending: bool


## 按发射信息初始化弹体
func configure(
	source: RwUnitState,
	target: RwUnitState,
	weapon: RwWeaponDefinition,
	angle_degrees: float,
	projectile_override: RwProjectileDefinition = null
) -> void:
	owner_id = source.object_id
	target_id = target.object_id
	target_position = target.world_position
	_last_target_position = target.world_position
	_last_target_altitude = target.altitude
	team = source.team
	definition = weapon.projectile if projectile_override == null else projectile_override
	weapon_definition = weapon
	random_seed = fposmod(float(source.object_id * 37 + target.object_id * 19), 360.0)
	_initialize_motion(source, weapon, angle_degrees)


## 按地面目标初始化没有目标单位的弹体
func configure_at(source: RwUnitState, position: Vector2, weapon: RwWeaponDefinition, angle_degrees: float) -> void:
	owner_id = source.object_id
	target_id = -1
	target_position = position
	_last_target_position = position
	_last_target_altitude = 0.0
	team = source.team
	definition = weapon.projectile
	weapon_definition = weapon
	random_seed = fposmod(float(source.object_id * 37), 360.0)
	_initialize_motion(source, weapon, angle_degrees)


## 推进一帧并返回弹体是否命中目标
func advance_frame(target: RwUnitState, simulation_delta: float = 1.0) -> bool:
	if remaining_frames <= 0.0 or definition == null:
		return false
	var step: float = maxf(simulation_delta, 0.0)
	if step <= 0.0:
		return false
	if target_id > 0 and (target == null or target.is_dead):
		mark_target_lost()
		if definition.detonate_on_target_loss:
			return true
	if target_lost and target == null and definition.remove_on_target_loss:
		remove_requested = true
		return false
	elif target != null and target_id > 0:
		target_position = target.world_position
		_last_target_altitude = target.altitude
		target_velocity = (target.world_position - _last_target_position) / step
		_last_target_position = target.world_position
	elapsed_frames += step
	if elapsed_frames <= definition.delayed_start_frames:
		return false
	remaining_frames = maxf(remaining_frames - step, 0.0)
	if definition.instant:
		world_position = target.world_position if target != null else target_position
		height = target.altitude if target != null else _last_target_altitude
		return true
	var speed: float = velocity.length()
	var aim_position: Vector2 = target_position
	var target_altitude: float = _last_target_altitude
	if target != null and not target.is_dead and target_id > 0:
		aim_position = target.world_position
		target_altitude = target.altitude
		if definition.lead_target:
			var lead_speed: float = definition.lead_target_speed_calculation
			if lead_speed <= 0.0:
				lead_speed = maxf(speed, definition.target_speed_per_frame)
			var lead_time: float = world_position.distance_to(aim_position) / maxf(lead_speed, 0.1)
			aim_position += target_velocity * lead_time
	var native_target_position: Vector2 = target.world_position if target != null else aim_position
	var native_target_distance_squared: float = world_position.distance_squared_to(native_target_position)
	var native_target_height_delta: float = target_altitude - height
	var ballistic_maximum: float = definition.altitude_maximum if definition.altitude_maximum > 0.0 else definition.ballistic_height
	var ballistic_threshold: float = definition.ballistic_delay_move_height if definition.ballistic_delay_move_height > 0.0 else definition.altitude_move_start
	var ballistic_speed: float = definition.altitude_change_per_frame if definition.altitude_change_per_frame > 0.0 else definition.ballistic_vertical_speed
	var ballistic_step: float = ballistic_speed * step
	var uses_altitude_arc: bool = (definition.ballistic or ballistic_maximum > 0.0) and ballistic_maximum > 0.0 and ballistic_step > 0.0
	var move_horizontally: bool = true
	if uses_altitude_arc:
		move_horizontally = _altitude_reached_maximum or height > ballistic_threshold
		if not _altitude_reached_maximum:
			height = move_toward(height, ballistic_maximum, ballistic_step)
			if height >= ballistic_maximum:
				_altitude_reached_maximum = true
		elif _altitude_reached_maximum and world_position.distance_squared_to(aim_position) <= definition.altitude_descent_range * definition.altitude_descent_range:
			_altitude_descending = true
		if _altitude_descending:
			height = move_toward(height, target_altitude, ballistic_step)
	elif elapsed_frames > definition.ballistic_delay_move_height:
		height += height_velocity * step
		height_velocity -= definition.gravity_per_frame * step
		height_velocity -= definition.true_gravity_per_frame * step
	native_target_height_delta = target_altitude - height
	if definition.homing and (target_id > 0 or target_lost):
		var offset: Vector2 = aim_position - world_position
		if offset.length_squared() > 0.0001:
			var desired_angle: float = offset.angle()
			var current_angle: float = velocity.angle()
			var next_angle: float = desired_angle
			var turn_speed: float = definition.turn_speed_degrees
			if offset.length_squared() < 225.0 and definition.turn_speed_near_degrees != -2.0:
				turn_speed = definition.turn_speed_near_degrees
			if turn_speed >= 0.0:
				var limit: float = deg_to_rad(turn_speed * step)
				next_angle = current_angle + clampf(wrapf(desired_angle - current_angle, -PI, PI), -limit, limit)
			velocity = Vector2.RIGHT.rotated(next_angle) * speed
	elif speed > 0.0:
		velocity = velocity.normalized() * speed
	var remaining_distance: float = world_position.distance_to(aim_position)
	var travel_distance: float = speed * step
	if move_horizontally:
		if target_id > 0 and remaining_distance < travel_distance and not definition.native_target_collision_rules:
			world_position = aim_position
			native_target_distance_squared = 0.0
		else:
			world_position += velocity.normalized() * travel_distance
	if definition.target_ground and remaining_distance <= travel_distance and move_horizontally:
		world_position = aim_position
		return true
	if definition.wobble_amplitude != 0.0 and definition.wobble_frequency > 0.0 and velocity.length_squared() > 0.0001:
		var wobble_angle: float = elapsed_frames * 360.0 / definition.wobble_frequency + random_seed
		var wobble_offset: float = sin(deg_to_rad(wobble_angle)) * definition.wobble_amplitude * step
		world_position += velocity.normalized().rotated(PI * 0.5) * wobble_offset
	if definition.trail_length_frames > 0 and definition.trail_width > 0.0 and (move_horizontally or definition.trail_during_stationary):
		_trail_elapsed_frames += step
		var emission_interval: float = maxf(definition.trail_emission_interval_frames, 0.01)
		if _trail_elapsed_frames > emission_interval:
			_trail_elapsed_frames = 0.0
			_append_trail_position(world_position, height)
	if move_horizontally and definition.target_speed_per_frame > 0.0 and definition.speed_acceleration_per_frame > 0.0:
		speed = move_toward(speed, definition.target_speed_per_frame, definition.speed_acceleration_per_frame * step)
		if velocity.length_squared() > 0.0001:
			velocity = velocity.normalized() * speed
	if definition.native_target_collision_rules and target != null and not target.is_dead and target_id > 0:
		var target_hit_radius: float = definition.native_minimum_target_hit_radius
		if target.is_building and target.build_progress < 1.0:
			target_hit_radius = maxf(target.collision_radius * definition.native_building_radius_scale, target_hit_radius)
		if target.health > definition.native_health_damage_threshold + definition.damage:
			target_hit_radius = target.collision_radius * definition.native_high_health_radius_scale
		var vertical_tolerance: float = definition.altitude_hit_tolerance
		if definition.native_altitude_collision_rules:
			var vertical_speed_delta: float = absf(height_velocity * step) + absf(definition.gravity_per_frame * step)
			vertical_tolerance = 3.0 + vertical_speed_delta
		var height_matches_target: bool = absf(native_target_height_delta) < vertical_tolerance
		var is_inside_target_radius: bool = native_target_distance_squared < target_hit_radius * target_hit_radius
		return height_matches_target and is_inside_target_radius
	var collision_radius: float
	if definition.include_target_collision_radius and target != null and not target.is_dead and target_id > 0:
		collision_radius = target.collision_radius
	var hit_distance: float = collision_radius + definition.hit_radius
	var inside_height: bool = not uses_altitude_arc or absf(height - target_altitude) <= definition.altitude_hit_tolerance
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


func _initialize_motion(source: RwUnitState, weapon: RwWeaponDefinition, angle_degrees: float) -> void:
	world_position = Vector2.ZERO
	origin_position = Vector2.ZERO
	velocity = Vector2.ZERO
	target_velocity = Vector2.ZERO
	remaining_frames = 0.0
	elapsed_frames = 0.0
	height = 0.0
	height_velocity = 0.0
	trail_positions.clear()
	trail_spawn_frames.clear()
	target_lost = false
	remove_requested = false
	retarget_search_timer = 0.0
	_trail_elapsed_frames = 0.0
	_previous_wobble_offset = 0.0
	_altitude_reached_maximum = false
	_altitude_descending = false
	var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
	var mount_offset: Vector2 = weapon.muzzle_offset.rotated(deg_to_rad(source.body_rotation_degrees))
	world_position = source.world_position + mount_offset + direction * weapon.muzzle_distance
	origin_position = world_position
	velocity = direction * definition.speed_per_frame + definition.initial_velocity.rotated(deg_to_rad(angle_degrees))
	height_velocity = definition.initial_height_velocity
	if definition.ballistic_height > 0.0 and definition.target_speed_per_frame > 0.0:
		var flight_time: float = world_position.distance_to(target_position) / definition.target_speed_per_frame
		height_velocity = 4.0 * definition.ballistic_height / maxf(flight_time, 1.0)
	remaining_frames = definition.lifetime_frames
	if not definition.trail_as_particles:
		_append_trail_position(world_position, height)


func _append_trail_position(position: Vector2, trail_height: float) -> void:
	trail_positions.append(Vector3(position.x, position.y, trail_height))
	trail_spawn_frames.append(elapsed_frames)
	while trail_positions.size() > definition.trail_length_frames:
		trail_positions.pop_front()
		trail_spawn_frames.pop_front()
