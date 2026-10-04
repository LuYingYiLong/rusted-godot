extends RefCounted
class_name RwGameStateChecksum
## 按 OPEN-RW 1.15 的浮点精度计算单位部分的同步校验值

const COMMAND_ORDINALS: Dictionary = {
	"move": 0,
	"attack": 1,
	"build": 2,
	"repair": 3,
	"loadInto": 4,
	"unloadAt": 5,
	"reclaim": 6,
	"attackMove": 7,
	"loadUp": 8,
	"patrol": 9,
	"guard": 10,
	"guardAt": 11,
	"touchTarget": 12,
	"follow": 13,
	"triggerAction": 14,
	"triggerActionWhenInRange": 15,
	"setPassiveTarget": 16,
}
const NON_CHECKSUM_UNIT_TYPES: Array[String] = ["tree", "spreadingFire",]


## 返回不依赖玩家资金与指挥中心内部计数的单位校验字段
static func calculate_unit_fields(units: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"checksum": 0,
		"Unit Pos": 0,
		"Unit Dir": 0,
		"Unit Hp": 0,
		"Unit Id": 0,
		"Waypoints": 0,
		"Waypoints Pos": 0,
		"UnitPaths": 0,
	}
	var ids: Array[int] = []
	ids.assign(units.keys())
	ids.sort()
	var scratch: StreamPeerBuffer = StreamPeerBuffer.new()
	scratch.big_endian = true
	scratch.put_32(0)
	for object_id: int in ids:
		var unit: RwUnitState = units[object_id] as RwUnitState
		if unit == null or NON_CHECKSUM_UNIT_TYPES.has(unit.unit_name):
			continue
		result["checksum"] = _java_float_sum(result["checksum"], unit.world_position.x * 1000.0, scratch)
		result["checksum"] = _java_float_sum(result["checksum"], unit.world_position.y * 1000.0, scratch)
		result["checksum"] = _java_float_sum(result["checksum"], unit.health, scratch)
		result["checksum"] = int(result["checksum"]) + object_id
		result["Unit Pos"] = int(result["Unit Pos"]) + _float_bits(unit.world_position.x, scratch) + _float_bits(unit.world_position.y, scratch)
		result["Unit Dir"] = int(result["Unit Dir"]) + _float_bits(unit.body_rotation_degrees, scratch)
		result["Unit Hp"] = _java_float_sum(result["Unit Hp"], unit.health, scratch)
		result["Unit Id"] = int(result["Unit Id"]) + object_id
		if not unit.order_type.is_empty():
			result["Waypoints"] = int(result["Waypoints"]) + int(COMMAND_ORDINALS.get(unit.order_type, 0))
			result["Waypoints Pos"] = _java_float_sum(result["Waypoints Pos"], unit.order_target.x * 1000.0, scratch)
		for waypoint: Vector2 in unit.get_checksum_path_points():
			result["UnitPaths"] = int(result["UnitPaths"]) + _float_bits(waypoint.x, scratch) + _float_bits(waypoint.y, scratch)
	return result


static func _java_float_sum(current: int, addition: float, scratch: StreamPeerBuffer) -> int:
	var current_value: float = _float32(float(current), scratch)
	var added_value: float = _float32(addition, scratch)
	return int(_float32(current_value + added_value, scratch))


static func _float32(value: float, scratch: StreamPeerBuffer) -> float:
	scratch.seek(0)
	scratch.put_float(value)
	scratch.seek(0)
	return scratch.get_float()


static func _float_bits(value: float, scratch: StreamPeerBuffer) -> int:
	scratch.seek(0)
	scratch.put_float(value)
	scratch.seek(0)
	var bits: int = scratch.get_u32()
	return bits - 4_294_967_296 if bits >= 2_147_483_648 else bits
