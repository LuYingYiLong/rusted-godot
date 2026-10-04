extends RefCounted
class_name RwGameMath
## 复现 OPEN-RW 用于同步状态的角度查表与 32 位浮点计算

const HALF_PI_FLOAT: float = 1.5707964
const PI_FLOAT: float = 3.1415927
const DEGREE_FACTOR: float = 57.29578
const TRIG_INDEX_FACTOR: float = 22.755556
const TRIG_TABLE_MASK: int = 8191


## 返回原版直线路径所用的量化方向
static func path_direction(start_position: Vector2, target_position: Vector2) -> Vector2:
	return direction_for_angle(direction_degrees(start_position, target_position))
## 返回原版按查表量化后的目标方向角
static func direction_degrees(start_position: Vector2, target_position: Vector2) -> float:
	var delta: Vector2 = target_position - start_position
	var angle: float = _fast_angle(delta.y, delta.x)
	return _float32(angle * _float32(DEGREE_FACTOR))


## 返回原版的有符号最短转角，正好 180 度时保持正方向
static func signed_angle_delta(current_degrees: float, target_degrees: float) -> float:
	var delta: float = fmod(target_degrees, 360.0) - fmod(current_degrees, 360.0)
	if delta > 180.0:
		delta -= 360.0
	if delta < -180.0:
		delta += 360.0
	return delta


## 返回原版按度数查表的移动方向
static func direction_for_angle(angle_degrees: float) -> Vector2:
	var table_index: int = int(_float32(angle_degrees * _float32(TRIG_INDEX_FACTOR))) & TRIG_TABLE_MASK
	var radians: float = _float32(_float32((float(table_index) + 0.5) / 8192.0) * _float32(PI_FLOAT * 2.0))
	return Vector2(cos(radians), sin(radians))


## 返回原版工厂在没有集结点时给新单位下达的离厂目标
static func factory_exit_target(factory_position: Vector2, factory_radius: float) -> Vector2:
	var facing: Vector2 = direction_for_angle(90.0)
	var exit_distance: float = _float32(factory_radius * 3.0)
	var target_x: float = _float32(factory_position.x + _float32(facing.x * exit_distance))
	var target_y: float = _float32(factory_position.y + _float32(facing.y * exit_distance))
	return Vector2(_float32(target_x - facing.y), _float32(target_y + facing.x))


static func _fast_angle(y: float, x: float) -> float:
	if x >= 0.0:
		if y >= 0.0:
			if x >= y:
				return _atan_lookup(y, x)
			return _float32(_float32(HALF_PI_FLOAT) - _atan_lookup(x, y))
		if x >= -y:
			return -_atan_lookup(-y, x)
		return _float32(_atan_lookup(x, -y) - _float32(HALF_PI_FLOAT))
	if y >= 0.0:
		if -x >= y:
			return _float32(_float32(PI_FLOAT) - _atan_lookup(y, -x))
		return _float32(_atan_lookup(-x, y) + _float32(HALF_PI_FLOAT))
	if x <= y:
		return _float32(_atan_lookup(-y, -x) - _float32(PI_FLOAT))
	return _float32(-_float32(HALF_PI_FLOAT) - _atan_lookup(-x, -y))


static func _atan_lookup(numerator: float, denominator: float) -> float:
	if denominator == 0.0:
		return 0.0
	var scaled: float = _float32(_float32(1024.0 * numerator) / denominator)
	var lookup_index: int = clampi(int(scaled + 0.5), 0, 1024)
	var ratio: float = float(lookup_index) / 1024.0
	return _float32(atan(ratio) * _float32(PI_FLOAT) / PI)


static func _float32(value: float) -> float:
	return Vector2(value, 0.0).x
