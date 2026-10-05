extends SceneTree
## 使用原版 Java 方向查表逐位验证滑行速度和减速惯性

var _scratch: StreamPeerBuffer = StreamPeerBuffer.new()


func _initialize() -> void:
	var source: FileAccess = FileAccess.open(OS.get_environment("RW_SLIDING_REFERENCE"), FileAccess.READ)
	if source == null:
		push_error("RW_SLIDING_REFERENCE must point to the Java reference TSV")
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
		var actual: Vector2 = RwGameMath.sliding_velocity(
			Vector2(fields[0].to_float(), fields[1].to_float()),
			Vector2(fields[2].to_float(), fields[3].to_float()),
			fields[4].to_float(),
			fields[5].to_float(),
			fields[6].to_float(),
		)
		for index: int in 2:
			_scratch.seek(0)
			_scratch.put_float(actual[index])
			_scratch.seek(0)
			if _scratch.get_u32() != fields[7 + index].to_int():
				differences += 1
		cases += 1
	print("RW115_SLIDING_MATH cases=%d differences=%d" % [cases, differences,])
	quit(0 if differences == 0 and cases > 0 else 1)
