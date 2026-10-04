extends SceneTree
## 对照 OPEN-RW 联机异步寻路的释放帧


func _initialize() -> void:
	var grid: RwPathGrid = RwPathGrid.load_map("[p2]Small_Island (2p).tmx")
	assert(grid != null)
	var start: Vector2 = Vector2(930.0, 430.0)
	var target: Vector2 = Vector2(1010.0, 270.0)
	assert(not grid.has_clear_line(start, target, "LAND"))
	assert(grid.network_path_delay_frames(start, target, "LAND") == 12)
	assert(grid.network_path_delay_frames(start, target, "AIR") == 0)
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.world_position = start
	unit_state.movement_speed = 1.0
	unit_state.movement_type = "LAND"
	unit_state.turn_speed = 3.0
	unit_state.weapon_rotations_degrees = PackedFloat32Array([0.0,])
	var waypoints: Array[Vector2] = grid.find_path(start, target, "LAND", false)
	assert(not waypoints.is_empty())
	unit_state.apply_move_order(target, waypoints, "build", -1, "extractorT1", 12)
	for frame: int in range(1, 14):
		unit_state.advance_movement(1, grid)
		assert(unit_state.has_pending_path())
		assert(unit_state.get_checksum_path_points().is_empty())
		assert(unit_state.world_position == start)
	unit_state.advance_movement(1, grid)
	assert(not unit_state.has_pending_path())
	assert(not unit_state.get_checksum_path_points().is_empty())
	var fast_unit: RwUnitState = RwUnitState.new()
	fast_unit.world_position = start
	fast_unit.movement_speed = 1.0
	fast_unit.movement_type = "LAND"
	fast_unit.turn_speed = 3.0
	fast_unit.weapon_rotations_degrees = PackedFloat32Array([0.0,])
	fast_unit.apply_move_order(target, waypoints, "build", -1, "extractorT1", 12)
	for frame: int in range(1, 8):
		fast_unit.advance_movement(1, grid, 2.0)
		assert(fast_unit.has_pending_path())
	fast_unit.advance_movement(1, grid, 2.0)
	assert(not fast_unit.has_pending_path())
	print("PATH_DELAY_REFERENCE_CHECK_OK release_frame=14")
	quit(0)
