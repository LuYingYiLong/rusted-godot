extends RefCounted
class_name RwVanillaRandom
## 复现原版 1.15 的同步随机数公式

const UINT32_RANGE: int = 4_294_967_296
const INT32_HALF_RANGE: int = 2_147_483_648


static func initial_range(minimum: int, maximum: int, _seed: int) -> int:
	if minimum >= maximum:
		return minimum
	var spread: int = maximum - minimum
	var first_product: int = _java_int(_seed * 133_333_333)
	var second_product: int = _java_int(first_product * spread)
	var third_product: int = _java_int(_seed * 13_131_313)
	var value: int = _java_int(second_product + third_product)
	return absi(value % spread) + minimum


## 计算原版按单位状态和同步帧生成的随机整数，最大值不包含在范围内
static func unit_range(
	minimum: int,
	maximum: int,
	object_id: int,
	position: Vector2,
	random_counter: int,
	frame: int,
	global_seed: int,
	stream: int,
) -> int:
	if minimum >= maximum:
		return minimum
	var frame_seed: int = _java_int32(frame + 1)
	var value: int = _java_int32(global_seed + object_id * 1313)
	value = int(RwGameMath.float32(RwGameMath.float32(float(value)) + RwGameMath.float32(position.x * 13.0)))
	value = int(RwGameMath.float32(RwGameMath.float32(float(value)) + RwGameMath.float32(position.y * 13.0)))
	value = int(RwGameMath.float32(RwGameMath.float32(float(value)) + RwGameMath.float32(position.x * 130.0)))
	value = int(RwGameMath.float32(RwGameMath.float32(float(value)) + RwGameMath.float32(position.y * 130.0)))
	value = _java_int32(value + random_counter * 13131)
	value = _java_int32(value + random_counter * frame_seed)
	value = _java_int32(value + stream * 133 * maximum)
	value = _java_int32(value + stream * object_id + stream)
	value = _java_int32(value + stream * frame_seed * 1313)
	value = _java_int32(value + frame_seed * 13 + frame_seed % 10)
	var spread: int = _java_int32(maximum - minimum)
	var remainder: int = value - int(float(value) / float(spread)) * spread
	if remainder < 0:
		remainder = -remainder
	return _java_int32(remainder + minimum)


## 按原版自定义单位发射弹体时的规则推进随机计数器
static func advance_projectile_counter(random_counter: int, object_id: int) -> int:
	return _java_int32(random_counter + 1 + object_id)


## 按原版普通弹体构造时推进单位随机计数器
static func advance_projectile_creation_counter(random_counter: int) -> int:
	return _java_int32(random_counter + 1)


static func _java_int32(value: int) -> int:
	return posmod(value + INT32_HALF_RANGE, UINT32_RANGE) - INT32_HALF_RANGE


static func _java_int(value: int) -> int:
	return posmod(value + INT32_HALF_RANGE, UINT32_RANGE) - INT32_HALF_RANGE
