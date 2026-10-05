extends SceneTree
## 逐位验证原版编队槽位、距离舍入与路径前瞻

var _scratch: StreamPeerBuffer = StreamPeerBuffer.new()


func _initialize() -> void:
	var source: FileAccess = FileAccess.open(OS.get_environment("RW_FORMATION_REFERENCE"), FileAccess.READ)
	if source == null:
		push_error("RW_FORMATION_REFERENCE must point to the Java reference TSV")
		quit(2)
		return
	source.get_line()
	var cases: int
	var differences: int
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t")
		var inputs: PackedStringArray = fields[1].split(",")
		var expected: PackedStringArray = fields[2].split("|")
		match fields[0]:
			"offsets":
				var points: PackedVector2Array = RwGameMath.formation_offsets(inputs[0].to_int(), inputs[1].to_float(), inputs[2].to_float())
				if points.is_empty() and fields[2].is_empty():
					pass
				elif points.size() != expected.size():
					differences += 1
				else:
					for index: int in points.size():
						var components: PackedStringArray = expected[index].split(",")
						for component: int in 2:
							if _bits(points[index][component]) != components[component].to_int():
								differences += 1
			"distance":
				var start: Vector2 = Vector2(inputs[0].to_float(), inputs[1].to_float())
				var end: Vector2 = Vector2(inputs[2].to_float(), inputs[3].to_float())
				var components: PackedStringArray = fields[2].split(",")
				if _bits(RwGameMath.distance_squared(start, end)) != components[0].to_int() or RwGameMath.rounded_distance(start, end) != components[1].to_int():
					differences += 1
			"target":
				var points: PackedVector2Array
				for index: int in range(6, inputs.size(), 2):
					points.append(Vector2(inputs[index].to_float(), inputs[index + 1].to_float()))
				var actual: Vector3 = RwGameMath.formation_target(Vector2(inputs[0].to_float(), inputs[1].to_float()), Vector2(inputs[2].to_float(), inputs[3].to_float()), points, inputs[4].to_int(), inputs[5].to_int())
				var components: PackedStringArray = fields[2].split(",")
				for component: int in 3:
					if _bits(actual[component]) != components[component].to_int():
						differences += 1
		cases += 1
	print("RW115_FORMATION_MATH cases=%d differences=%d" % [cases, differences,])
	quit(0 if differences == 0 and cases > 0 else 1)


func _bits(value: float) -> int:
	_scratch.seek(0)
	_scratch.put_float(value)
	_scratch.seek(0)
	return _scratch.get_u32()
