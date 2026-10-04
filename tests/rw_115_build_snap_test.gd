extends SceneTree
## 验证原版建造指令按地图格锚点截断，而不是取最近格


func _initialize() -> void:
	var grid: RwPathGrid = RwPathGrid.new()
	grid.tile_size = Vector2i(20, 20)
	var minimum: Vector2i = Vector2i(-1, -1)
	var maximum: Vector2i = Vector2i(1, 1)
	var cases: Array[Dictionary] = [
		{"target": Vector2(44.4886, 1266.872), "expected": Vector2(30.0, 1250.0),},
		{"target": Vector2(1892.441, 2140.407), "expected": Vector2(1890.0, 2130.0),},
		{"target": Vector2(2083.406, 283.2924), "expected": Vector2(2070.0, 270.0),},
	]
	for test_case: Dictionary in cases:
		var target: Vector2 = test_case["target"]
		var expected: Vector2 = test_case["expected"]
		var actual: Vector2 = grid.snap_structure_position(target, minimum, maximum)
		if actual != expected:
			printerr("RW_115_BUILD_SNAP_GAP target=%s actual=%s expected=%s" % [target, actual, expected])
			quit(1)
			return
		if grid.structure_anchor_cell(actual, minimum, maximum) != grid.structure_anchor_cell(target, minimum, maximum):
			printerr("RW_115_BUILD_SNAP_GAP anchor changed for %s" % target)
			quit(1)
			return
	var even_footprint_target: Vector2 = Vector2(2193.067, 232.9642)
	var even_footprint_position: Vector2 = grid.snap_structure_position(even_footprint_target, Vector2i.ZERO, Vector2i.ONE)
	if even_footprint_position != Vector2(2180.0, 220.0):
		printerr("RW_115_BUILD_SNAP_GAP even footprint=%s" % even_footprint_position)
		quit(1)
		return
	print("RW_115_BUILD_SNAP_OK cases=%d" % (cases.size() + 1))
	quit()
