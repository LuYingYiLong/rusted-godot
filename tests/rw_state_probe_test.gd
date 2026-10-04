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
	var checksum: Dictionary = probe.unit_checksum_for_frame(1)
	assert(checksum.size() == 8)
	assert(int(checksum["Unit Id"]) == 7)
	assert(int(checksum["Waypoints"]) == 0)
	assert(probe.unit_checksum_for_frame(2).is_empty())
	var snapshot: Array[Dictionary] = probe.unit_snapshot_for_frame(1)
	assert(snapshot.size() == 1 and int(snapshot[0]["id"]) == 7)
	assert(probe.unit_snapshot_for_frame(2).is_empty())
	probe.close()
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).trim_suffix("\n").split("\n")
	assert(lines.size() == 2)
	assert(lines[1] == "1\t1.0\t7\tbuilder\t1\t12.5\t20.0\t\t\t90.0\t45.0\t170.0\t1.0\tmove\t30.0\t40.0\t\t\t")
	print("STATE_PROBE_CHECK_OK")
	quit()
