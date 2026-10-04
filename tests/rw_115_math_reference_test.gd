extends SceneTree
## 对照 Java StrictMath 生成的原版 1.15 样本逐位检查原生数值接口

var _scratch: StreamPeerBuffer = StreamPeerBuffer.new()


func _initialize() -> void:
	var source: FileAccess = FileAccess.open(OS.get_environment("RW_MATH_REFERENCE"), FileAccess.READ)
	if source == null:
		push_error("RW_MATH_REFERENCE must point to the generated Java reference TSV")
		quit(2)
		return
	source.get_line()
	var totals: Dictionary[String, int] = {}
	var differences: Dictionary[String, int] = {}
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var columns: PackedStringArray = line.split("\t")
		var operation: String = columns[0]
		var a: float = columns[1].to_float()
		var b: float = columns[2].to_float()
		var c: float = columns[3].to_float()
		var d: float = columns[4].to_float()
		var e: float = columns[7].to_float()
		var f: float = columns[8].to_float()
		var x: float
		var y: float
		var z: float
		match operation:
			"direction":
				var direction: Vector2 = RwGameMath.direction_for_angle(a)
				x = direction.x
				y = direction.y
			"angle":
				x = RwGameMath.direction_degrees(Vector2(a, b), Vector2(c, d))
			"delta", "double_delta":
				x = RwGameMath.signed_angle_delta(a, b)
			"factory":
				var target: Vector2 = RwGameMath.factory_exit_target(Vector2(a, b), c)
				x = target.x
				y = target.y
			"turn":
				var turn_state: Vector3 = RwGameMath.turn_toward(a, b, c, d, e, f)
				x = turn_state.x
				y = turn_state.y
				z = turn_state.z
			"speed":
				x = RwGameMath.advance_speed(a, b, c, d)
			"movement":
				var position: Vector2 = RwGameMath.movement_position(Vector2(a, b), c, d, e, f)
				x = position.x
				y = position.y
		totals[operation] = totals.get(operation, 0) + 1
		if _float_bits(x) != columns[5].to_int() or _float_bits(y) != columns[6].to_int() or _float_bits(z) != columns[9].to_int():
			differences[operation] = differences.get(operation, 0) + 1
			if differences[operation] <= 2:
				print("RW115_MATH_DIFFERENCE operation=%s input=%s actual_bits=%s,%s expected_bits=%s,%s" % [operation, columns.slice(1, 5), _float_bits(x), _float_bits(y), columns[5], columns[6],])
	print("RW115_MATH_REFERENCE totals=%s differences=%s" % [totals, differences,])
	quit(1 if not differences.is_empty() and OS.get_environment("RW_MATH_ALLOW_DIFFERENCES") != "1" else 0)


func _float_bits(value: float) -> int:
	_scratch.seek(0)
	_scratch.put_float(value)
	_scratch.seek(0)
	return _scratch.get_u32()
