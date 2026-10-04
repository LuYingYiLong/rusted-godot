extends SceneTree
## 验证建筑目标格被占用时按原版顺序选择替代终点


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid: RwPathGrid = RwPathGrid.load_map("[p6]Valley Pass (6p).tmx")
	if grid == null:
		printerr("RW_115_FAKE_GOAL_GAP map failed to load")
		quit(1)
		return
	grid.block_structure(Vector2(250.0, 2090.0), Vector2i(-1, -1), Vector2i(1, 1))
	grid.finalize_obstacles()
	var goal: Vector2i = grid.call("_nearest_passable_native_goal", Vector2i(12, 104), "LAND", 9)
	if goal != Vector2i(10, 104):
		printerr("RW_115_FAKE_GOAL_GAP goal=%s expected=(10, 104)" % goal)
		quit(1)
		return
	var path: Array[Vector2] = grid.find_path(Vector2(261.66638, 2173.9265), Vector2(250.0, 2090.0), "LAND", true, -97.894966, true, 1)
	if path.is_empty() or path.back() != Vector2(210.0, 2090.0):
		printerr("RW_115_FAKE_GOAL_GAP path=%s" % path)
		quit(1)
		return
	print("RW_115_FAKE_GOAL_OK goal=%s path_points=%d" % [goal, path.size()])
	quit()
