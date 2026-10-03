class_name RwVanillaRandom
extends RefCounted

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


static func _java_int(value: int) -> int:
	return posmod(value + INT32_HALF_RANGE, UINT32_RANGE) - INT32_HALF_RANGE
