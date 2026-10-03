extends RefCounted
class_name RwBattleStateProbe
## 将联机同步帧末尾的单位状态写入可与 OPEN-RW 探针对照的 TSV 文件

const HEADER: String = "frame\tdelta\tid\ttype\tteam\tx\ty\tpush_x\tpush_y\trot\tweapon_rot\thp\tbuild\torder\torder_x\torder_y\n"

var _file: FileAccess
var _interval: int = 1


## 环境变量 RW_PROBE_PATH 未设置时不产生文件
func _init() -> void:
	var path: String = OS.get_environment("RW_PROBE_PATH")
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
	if _file == null or frame % _interval != 0:
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
		]
		_file.store_string("\t".join(fields) + "\n")
	_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
