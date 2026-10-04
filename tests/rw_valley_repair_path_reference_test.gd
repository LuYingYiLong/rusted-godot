extends SceneTree
## 对照 OPEN-RW Valley Pass 中建造者修理资源抽取器的路径点


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid: RwPathGrid = RwPathGrid.load_map("[p6]Valley Pass (6p).tmx")
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var command_center: RwUnitDefinition = registry.find_definition("vanilla", "commandCenter")
	var extractor: RwUnitDefinition = registry.find_definition("custom", "extractorT1")
	var builder_definition: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	assert(grid != null and command_center != null and extractor != null and builder_definition != null)
	grid.block_structure(Vector2(190.0, 1250.0), command_center.structure_footprint_min, command_center.structure_footprint_max)
	grid.block_structure(Vector2(90.0, 1250.0), extractor.structure_footprint_min, extractor.structure_footprint_max)
	var neighbor: RwUnitState = RwUnitState.new()
	neighbor.initialize_from_spawn({
		"object_id": 294,
		"source_id": "vanilla",
		"unit_name": "builder",
		"team": "4",
		"position": Vector2(149.75241, 1304.2416),
	}, builder_definition)
	neighbor.apply_order("repair", Vector2(90.0, 1250.0), 299)
	grid.update_object_costs({294: neighbor,}, 304)
	var position: Vector2 = Vector2(188.99799, 1337.0892)
	var target: Vector2 = Vector2(90.0, 1250.0)
	var goal_radius_cells: int = int((85.0 - 41.0) / (float(grid.tile_size.x) * 1.414))
	var path: Array[Vector2] = grid.find_path(position, target, "LAND", true, 90.55951, true, goal_radius_cells)
	var expected: Array[Vector2] = [
		Vector2(170.0, 1330.0),
		Vector2(150.0, 1330.0),
		Vector2(130.0, 1310.0),
		Vector2(110.0, 1290.0),
		Vector2(90.0, 1270.0),
	]
	assert(path == expected, "Repair path differs: %s" % [path,])
	print("VALLEY_REPAIR_PATH_REFERENCE_OK points=%d radius=%d" % [path.size(), goal_radius_cells])
	quit()
