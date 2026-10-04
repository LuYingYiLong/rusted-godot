extends SceneTree
## 使用 OPEN-RW 的生产轨迹核对侦察机离厂后的逐帧运动


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_SCOUT_REFERENCE")
	if reference_path.is_empty():
		push_error("RW_SCOUT_REFERENCE is required")
		quit(2)
		return
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	if source == null:
		push_error("Could not open scout reference: " + reference_path)
		quit(2)
		return
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var rows: Array[Dictionary] = []
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields[headers.find("type")] != "scout":
			continue
		var row: Dictionary = {}
		for index: int in headers.size():
			row[headers[index]] = fields[index]
		rows.append(row)
		if rows.size() >= 100:
			break
	if rows.is_empty():
		push_error("No scout rows in reference")
		quit(2)
		return
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("custom", "scout")
	var factory_definition: RwUnitDefinition = registry.find_definition("vanilla", "commandCenter")
	var grid: RwPathGrid = RwPathGrid.load_map("[p2]Small_Island (2p).tmx")
	assert(definition != null and factory_definition != null and grid != null)
	var first: Dictionary = rows[0]
	var factory_position: Vector2 = Vector2(930.0, 370.0)
	grid.block_structure(factory_position, factory_definition.structure_footprint_min, factory_definition.structure_footprint_max)
	var state: RwUnitState = RwUnitState.new()
	state.initialize_from_spawn({
		"object_id": int(first["id"]),
		"source_id": "custom",
		"unit_name": "scout",
		"team": str(first["team"]),
		"position": factory_position + Vector2(0.0, 5.0),
		"rotation_degrees": 90.0,
	}, definition)
	var target: Vector2 = Vector2(float(first["order_x"]), float(first["order_y"]))
	var factory_cell: Vector2i = grid.structure_anchor_cell(factory_position, factory_definition.structure_footprint_min, factory_definition.structure_footprint_max)
	state.apply_factory_exit(target, factory_cell, factory_definition.structure_footprint_min, factory_definition.structure_footprint_max, 30.0)
	for row: Dictionary in rows:
		var frame: int = int(row["frame"])
		state.advance_movement(1, grid, float(row["delta"]))
		var expected_position: Vector2 = Vector2(float(row["x"]), float(row["y"]))
		var position_error: float = state.world_position.distance_to(expected_position)
		var expected_rotation: float = float(row["rot"])
		var angle_error: float = absf(RwGameMath.signed_angle_delta(state.body_rotation_degrees, expected_rotation))
		var path_points: PackedVector2Array = state.get_checksum_path_points()
		var expected_has_path: bool = not str(row["path_x"]).is_empty()
		var path_error: float = 0.0
		if expected_has_path != (not path_points.is_empty()):
			path_error = INF
		elif expected_has_path:
			var expected_path: Vector2 = Vector2(float(row["path_x"]), float(row["path_y"]))
			path_error = path_points[0].distance_to(expected_path)
		if position_error > 0.1 or angle_error > 0.1 or path_error > 0.1:
			print("SCOUT_FACTORY_FIRST_DIFFERENCE frame=%d position=%s expected=%s rotation=%.5f expected_rotation=%.5f position_error=%.5f angle_error=%.5f path_error=%.5f" % [frame, state.world_position, expected_position, state.body_rotation_degrees, expected_rotation, position_error, angle_error, path_error])
			quit(1)
			return
	print("SCOUT_FACTORY_REFERENCE_OK frames=%d" % rows.size())
	quit()
