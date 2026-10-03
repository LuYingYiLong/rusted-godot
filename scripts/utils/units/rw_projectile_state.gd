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
var definition: RwProjectileDefinition


## 按发射信息初始化弹体
func configure(source: RwUnitState, target: RwUnitState, weapon: RwWeaponDefinition, angle_degrees: float) -> void:
	owner_id = source.object_id
	target_id = target.object_id
	target_position = target.world_position
	team = source.team
	definition = weapon.projectile
	_initialize_motion(source, weapon, angle_degrees)


## 按地面目标初始化没有目标单位的弹体
func configure_at(source: RwUnitState, position: Vector2, weapon: RwWeaponDefinition, angle_degrees: float) -> void:
	owner_id = source.object_id
	target_id = -1
	target_position = position
	team = source.team
	definition = weapon.projectile
	_initialize_motion(source, weapon, angle_degrees)


## 推进一帧并返回弹体是否命中目标
func advance_frame(target: RwUnitState, simulation_delta: float = 1.0) -> bool:
	if remaining_frames <= 0.0 or definition == null:
		return false
	if target_id > 0 and (target == null or target.is_dead):
		return false
	if definition.instant:
		world_position = target.world_position if target != null else target_position
		remaining_frames -= simulation_delta
		return true
	var speed: float = velocity.length()
	if definition.target_speed_per_frame > 0.0 and definition.speed_acceleration_per_frame > 0.0:
		speed = move_toward(speed, definition.target_speed_per_frame, definition.speed_acceleration_per_frame * simulation_delta)
	if definition.homing and target != null and not target.is_dead:
		var offset: Vector2 = target.world_position - world_position
		if offset.length_squared() > 0.0001:
			var desired_angle: float = offset.angle()
			var current_angle: float = velocity.angle()
			var next_angle: float = desired_angle
			if definition.turn_speed_degrees >= 0.0:
				var limit: float = deg_to_rad(definition.turn_speed_degrees * simulation_delta)
				next_angle = current_angle + clampf(wrapf(desired_angle - current_angle, -PI, PI), -limit, limit)
			velocity = Vector2.RIGHT.rotated(next_angle) * speed
	elif speed > 0.0:
		velocity = velocity.normalized() * speed
	var start: Vector2 = world_position
	world_position += velocity * simulation_delta
	remaining_frames -= simulation_delta
	var aim_position: Vector2 = target.world_position if target != null else target_position
	var collision_radius: float = target.collision_radius if target != null else 0.0
	var segment: Vector2 = world_position - start
	var projection: float = (aim_position - start).dot(segment)
	var fraction: float = clampf(projection / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	var closest: Vector2 = start + segment * fraction
	var hit_distance: float = collision_radius + definition.hit_radius
	return closest.distance_squared_to(aim_position) <= hit_distance * hit_distance


func _initialize_motion(source: RwUnitState, weapon: RwWeaponDefinition, angle_degrees: float) -> void:
	var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
	var mount_offset: Vector2 = weapon.muzzle_offset.rotated(deg_to_rad(source.body_rotation_degrees))
	world_position = source.world_position + mount_offset + direction * weapon.muzzle_distance
	origin_position = world_position
	velocity = direction * definition.speed_per_frame
	remaining_frames = definition.lifetime_frames
