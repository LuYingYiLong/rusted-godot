extends SceneTree
## 检查同步帧探针是否输出可对照的单位状态


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path: String = OS.get_environment("RW_PROBE_PATH")
	assert(not path.is_empty())
	var unit: RwUnitState = RwUnitState.new()
	unit.object_id = 7
	unit.unit_name = "builder"
	unit.team = "1"
	unit.world_position = Vector2(12.5, 20.0)
	unit.body_rotation_degrees = 90.0
	unit.weapon_rotations_degrees = PackedFloat32Array([45.0])
	unit.health = 170.0
	unit.build_progress = 1.0
	unit.order_type = "move"
	unit.order_target = Vector2(30.0, 40.0)
	var probe: RwBattleStateProbe = RwBattleStateProbe.new()
	probe.capture(1, 1.0, {7: unit,})
	probe.close()
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert(lines.size() == 2)
	assert(lines[1] == "1\t1.0\t7\tbuilder\t1\t12.5\t20.0\t\t\t90.0\t45.0\t170.0\t1.0\tmove\t30.0\t40.0")
	print("STATE_PROBE_CHECK_OK")
	quit()
