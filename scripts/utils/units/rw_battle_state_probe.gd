extends RefCounted
class_name RwBattleStateProbe
## 将联机同步帧末尾的单位状态写入可与 OPEN-RW 探针对照的 TSV 文件

const HEADER: String = "frame\tdelta\tid\ttype\tteam\tx\ty\tpush_x\tpush_y\trot\tweapon_rot\thp\tbuild\torder\torder_x\torder_y\tbuild_type\tpath_x\tpath_y\n"
const CHECKSUM_HISTORY_FRAMES: int = 640

var _file: FileAccess
var _capture_checksums: bool
var _interval: int = 1
var _unit_checksums: Dictionary
var _unit_debug_snapshots: Dictionary
var _checksum_frames: Array[int]


## 环境变量 RW_PROBE_PATH 未设置时不产生文件
func _init() -> void:
	var path: String = OS.get_environment("RW_PROBE_PATH")
	_capture_checksums = OS.get_environment("RW_PROBE_CHECKSUMS") == "1"
	if path.is_empty():
		return
	_interval = maxi(int(OS.get_environment("RW_PROBE_INTERVAL")), 1)
	var directory: String = path.get_base_dir()
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Could not open RW probe trace: %s" % path)
		return
	_file.store_string(HEADER)


func capture(frame: int, step_delta: float, units: Dictionary) -> void:
	if _file == null and not _capture_checksums:
		return
	if not _unit_checksums.has(frame):
		_checksum_frames.append(frame)
	_unit_checksums[frame] = RwGameStateChecksum.calculate_unit_fields(units)
	_unit_debug_snapshots[frame] = _capture_unit_snapshot(units)
	if _checksum_frames.size() > CHECKSUM_HISTORY_FRAMES:
		var expired_frame: int = _checksum_frames.pop_front()
		_unit_checksums.erase(expired_frame)
		_unit_debug_snapshots.erase(expired_frame)
	if _file == null:
		return
	if frame % _interval != 0:
		return
	var ids: Array[int]
	ids.assign(units.keys())
	ids.sort()
	for object_id: int in ids:
		var unit: RwUnitState = units[object_id] as RwUnitState
		if unit == null:
			continue
		var angles: PackedStringArray
		for angle: float in unit.weapon_rotations_degrees:
			angles.append(str(angle))
		var team_number: int = unit.team.to_int() if unit.team.is_valid_int() else -1
		var path_points: PackedVector2Array = unit.get_checksum_path_points()
		var waypoint: Vector2 = path_points[0] if not path_points.is_empty() else Vector2.ZERO
		var fields: PackedStringArray = [
			str(frame),
			str(step_delta),
			str(object_id),
			unit.unit_name.replace("\t", " "),
			str(team_number),
			str(unit.world_position.x),
			str(unit.world_position.y),
			"",
			"",
			str(unit.body_rotation_degrees),
			"|".join(angles),
			str(unit.health),
			str(unit.build_progress),
			unit.order_type,
			str(unit.order_target.x) if not unit.order_type.is_empty() else "",
			str(unit.order_target.y) if not unit.order_type.is_empty() else "",
			unit.order_action_id if unit.order_type == "build" else "",
			str(waypoint.x) if not path_points.is_empty() else "",
			str(waypoint.y) if not path_points.is_empty() else "",
		]
		_file.store_string("\t".join(fields) + "\n")
	_file.flush()


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


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


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
		})
	return result
