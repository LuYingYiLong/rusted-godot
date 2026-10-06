extends RefCounted
class_name RwBattleStateProbe
## 将联机同步帧末尾的单位状态写入可与原版探针对照的 TSV 文件

const HEADER: String = "frame\tdelta\tid\ttype\tteam\tx\ty\tpush_x\tpush_y\trot\tweapon_rot\thp\tbuild\torder\torder_x\torder_y\tattack_mode\tnavigation_attack_target_id\tnavigation_attack_search_timer\tnavigation_repath_timer\tnavigation_attack_target_active\tnavigation_attack_override_active\tnavigation_attack_target_x\tnavigation_attack_target_y\tnavigation_repath_requested\tbuild_type\tpath_x\tpath_y\tmovement_factor\tturn_velocity\tpending_path_frames\tpath_count\toperation_charge\tconstruction_warmup\tfactory_clearance\tterrain_blocked_time\tterrain_clear_steps\twaypoint_time\tslide_x\tslide_y\tdead\tformation_leader\tformation_x\tformation_y\tformation_angle\tformation_size\tformation_leader_age\tformation_recovery\tformation_lag\tcollision_candidates\tcollision_next_refresh\tpath_points\tarrival_time\n"
const CHECKSUM_HISTORY_FRAMES: int = 640

var _file: FileAccess
var _team_file: FileAccess
var _projectile_file: FileAccess
var _object_id_file: FileAccess
var _capture_checksums: bool
var _interval: int = 1
var _checksum_stride: int = 1
var _unit_checksums: Dictionary
var _unit_debug_snapshots: Dictionary
var _checksum_frames: Array[int]
var _trace_unit_ids: Dictionary


## 环境变量 RW_PROBE_PATH 未设置时不产生文件
func _init() -> void:
	var path: String = OS.get_environment("RW_PROBE_PATH")
	_capture_checksums = OS.get_environment("RW_PROBE_CHECKSUMS") == "1"
	_checksum_stride = maxi(int(OS.get_environment("RW_PROBE_CHECKSUM_STRIDE")), 1)
	if path.is_empty():
		return
	_interval = maxi(int(OS.get_environment("RW_PROBE_INTERVAL")), 1)
	for id_text: String in OS.get_environment("RW_PROBE_UNIT_IDS").split(",", false):
		if id_text.is_valid_int():
			_trace_unit_ids[id_text.to_int()] = true
	var directory: String = path.get_base_dir()
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Could not open RW probe trace: %s" % path)
		return
	_file.store_string(HEADER)
	_object_id_file = FileAccess.open(path.get_base_dir().path_join("godot-object-ids.tsv"), FileAccess.WRITE)
	if _object_id_file != null:
		_object_id_file.store_string("frame\tid\tkind\ttype\n")
	_team_file = FileAccess.open(path.get_basename() + ".teams.tsv", FileAccess.WRITE)
	if _team_file != null:
		_team_file.store_string("frame\tslot\tcredits\n")
	var projectile_path: String = OS.get_environment("RW_PROBE_PROJECTILES")
	if not projectile_path.is_empty():
		var projectile_directory: String = projectile_path.get_base_dir()
		if not projectile_directory.is_empty():
			DirAccess.make_dir_recursive_absolute(projectile_directory)
		_projectile_file = FileAccess.open(projectile_path, FileAccess.WRITE)
		if _projectile_file == null:
			push_warning("Could not open RW projectile trace: %s" % projectile_path)


## 记录帧末单位和队伍资金，资金保留 double 精度供逐位比较
func capture(
	frame: int,
	step_delta: float,
	units: Dictionary,
	economy: RwVanillaEconomy = null,
	collisions: RwUnitCollisionController = null,
	projectiles: Array[RwProjectileState] = [],
) -> void:
	if _file == null and not _capture_checksums and _projectile_file == null:
		return
	if _capture_checksums and frame % _checksum_stride == 0:
		if not _unit_checksums.has(frame):
			_checksum_frames.append(frame)
		_unit_checksums[frame] = RwGameStateChecksum.calculate_unit_fields(units)
		_unit_debug_snapshots[frame] = _capture_unit_snapshot(units)
		if _checksum_frames.size() > CHECKSUM_HISTORY_FRAMES:
			var expired_frame: int = _checksum_frames.pop_front()
			_unit_checksums.erase(expired_frame)
			_unit_debug_snapshots.erase(expired_frame)
	if _file == null and _projectile_file == null:
		return
	if frame % _interval != 0:
		return
	if _file != null:
		var ids: Array[int]
		ids.assign(units.keys())
		ids.sort()
		for object_id: int in ids:
			if not _trace_unit_ids.is_empty() and not _trace_unit_ids.has(object_id):
				continue
			var unit: RwUnitState = units[object_id] as RwUnitState
			if unit == null:
				continue
			# 原版逐单位探针默认只记录 y 类单位，树木需通过编号显式选择
			if _trace_unit_ids.is_empty() and unit.unit_name == "tree":
				continue
			var angles: PackedStringArray
			for angle: float in unit.weapon_rotations_degrees:
				angles.append(_float_text(angle))
			var team_number: int = unit.team.to_int() if unit.team.is_valid_int() else -1
			var path_points: PackedVector2Array = unit.get_checksum_path_points()
			var path_coordinates: PackedStringArray
			for point: Vector2 in path_points:
				path_coordinates.append(_float_text(point.x) + ":" + _float_text(point.y))
			var waypoint: Vector2 = path_points[0] if not path_points.is_empty() else Vector2.ZERO
			var collision_state: Dictionary = collisions.debug_state(object_id) if collisions != null else {}
			var candidates: PackedStringArray
			for candidate: int in collision_state.get("candidates", []):
				candidates.append(str(candidate))
			var fields: PackedStringArray = [
				str(frame),
				_float_text(step_delta),
				str(object_id),
				unit.unit_name.replace("\t", " "),
				str(team_number),
				_float_text(unit.world_position.x),
				_float_text(unit.world_position.y),
				_float_text(unit.collision_push_offset.x),
				_float_text(unit.collision_push_offset.y),
				_float_text(unit.body_rotation_degrees),
				"|".join(angles),
				_float_text(unit.health),
				_float_text(unit.build_progress),
				unit.order_type,
				_float_text(unit.order_target.x) if not unit.order_type.is_empty() else "",
				_float_text(unit.order_target.y) if not unit.order_type.is_empty() else "",
				str(unit.attack_mode),
				str(unit.navigation_attack_target_id),
				_float_text(unit.navigation_attack_search_timer),
				_float_text(unit.navigation_repath_timer),
				str(unit.navigation_attack_target_active),
				str(unit.navigation_attack_override_active),
				_float_text(unit.navigation_attack_target_position.x),
				_float_text(unit.navigation_attack_target_position.y),
				str(unit.navigation_repath_requested),
				unit.order_action_id if unit.order_type == "build" else "",
				_float_text(waypoint.x) if not path_points.is_empty() else "",
				_float_text(waypoint.y) if not path_points.is_empty() else "",
				_float_text(float(unit.get("_movement_velocity"))),
				_float_text(float(unit.get("_turn_velocity"))),
				_float_text(float(unit.get("_pending_path_frames"))),
				str(path_points.size()),
				_float_text(unit.operation_charge),
				_float_text(unit.construction_warmup_limit),
				_float_text(unit.factory_clearance_frames),
				_float_text(unit.terrain_blocked_time),
				str(unit.terrain_clear_steps),
				_float_text(unit.waypoint_time),
				_float_text((unit.get("_sliding_velocity") as Vector2).x),
				_float_text((unit.get("_sliding_velocity") as Vector2).y),
				str(unit.is_dead),
				str(unit.formation_leader_id),
				_float_text(unit.formation_offset.x),
				_float_text(unit.formation_offset.y),
				_float_text(unit.formation_angle),
				str(unit.formation_size),
				str(unit.formation_leader_age),
				_float_text(unit.formation_recovery),
				_float_text(unit.formation_lag),
				"|".join(candidates),
				str(collision_state.get("next_refresh", 0)),
				"|".join(path_coordinates),
				_float_text(unit.navigation_arrival_time),
			]
			_file.store_string("\t".join(fields) + "\n")
		_file.flush()
	if _projectile_file != null:
		_capture_projectiles(frame, projectiles)
	if _team_file != null and economy != null:
		for slot: int in economy.get_team_slots():
			_team_file.store_string("%d\t%d\t%s\n" % [frame, slot, _float_text(economy.get_balance(slot, "credits")),])
		_team_file.flush()


## 返回指定同步帧的单位校验值，超过保留窗口时返回空字典
func unit_checksum_for_frame(frame: int) -> Dictionary:
	var checksum: Dictionary = _unit_checksums.get(frame, {})
	return checksum.duplicate()


## 返回指定同步帧的逐单位诊断快照
func unit_snapshot_for_frame(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var snapshot: Array = _unit_debug_snapshots.get(frame, [])
	for unit: Dictionary in snapshot:
		result.append(unit.duplicate(true))
	return result


## 记录模拟对象申请的全局编号，供原版同步问题对照
func record_object_id(frame: int, object_id: int, kind: String, type_name: String) -> void:
	if _object_id_file == null:
		return
	_object_id_file.store_string("%d\t%d\t%s\t%s\n" % [frame, object_id, kind, type_name.replace("\t", " "),])
	_object_id_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
	if _team_file != null:
		_team_file.close()
		_team_file = null
	if _projectile_file != null:
		_projectile_file.close()
		_projectile_file = null
	if _object_id_file != null:
		_object_id_file.close()
		_object_id_file = null


func _capture_projectiles(frame: int, projectiles: Array[RwProjectileState]) -> void:
	var ordered_projectiles: Array[RwProjectileState] = projectiles.duplicate()
	ordered_projectiles.sort_custom(func(first: RwProjectileState, second: RwProjectileState) -> bool: return first.object_id < second.object_id)
	for projectile: RwProjectileState in ordered_projectiles:
		if projectile == null or projectile.definition == null:
			continue
		var row: Dictionary = {
			"frame": frame,
			"id": projectile.object_id,
			"owner_id": projectile.owner_id,
			"target_id": projectile.target_id,
			"team": projectile.team,
			"x": projectile.world_position.x,
			"y": projectile.world_position.y,
			"height": projectile.height,
			"velocity_x": projectile.velocity.x,
			"velocity_y": projectile.velocity.y,
			"height_velocity": projectile.height_velocity,
			"heading": projectile.heading_degrees,
			"remaining": projectile.remaining_frames,
			"age": projectile.elapsed_frames,
			"impacted": projectile.has_impacted,
			"target_lost": projectile.target_lost,
			"target_ground": projectile.definition.target_ground,
			"target_x": projectile.target_position.x,
			"target_y": projectile.target_position.y,
			"direct_damage": projectile.definition.damage * projectile.source_damage_multiplier,
			"splash_damage": projectile.definition.splash_damage * projectile.source_damage_multiplier,
			"splash_radius": projectile.definition.splash_radius,
			"deflection_remaining": projectile.deflection_remaining,
			"random_phase": projectile.source_random_phase,
		}
		_projectile_file.store_string(JSON.stringify(row) + "\n")
	_projectile_file.flush()


func _capture_unit_snapshot(units: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[int] = []
	ids.assign(units.keys())
	ids.sort()
	for object_id: int in ids:
		var unit: RwUnitState = units[object_id] as RwUnitState
		if unit == null:
			continue
		var path_points: PackedVector2Array = unit.get_checksum_path_points()
		var first_path_point: Array[float] = []
		var path_snapshot: Array[Dictionary] = []
		for point: Vector2 in path_points:
			path_snapshot.append({"x": point.x, "y": point.y,})
		if not path_points.is_empty():
			first_path_point = [path_points[0].x, path_points[0].y,]
		result.append({
			"id": object_id,
			"type": unit.unit_name,
			"team": unit.team,
			"position": [unit.world_position.x, unit.world_position.y,],
			"rotation": unit.body_rotation_degrees,
			"health": unit.health,
			"build_progress": unit.build_progress,
			"order": unit.order_type,
			"target": [unit.order_target.x, unit.order_target.y,],
			"path_count": path_points.size(),
			"first_path_point": first_path_point,
			"path_points": path_snapshot,
		})
	return result


## 固定保留足够小数位，避免微小转向速度经字符串转换后丢失 float 位值
func _float_text(value: float) -> String:
	return "%.17f" % value
