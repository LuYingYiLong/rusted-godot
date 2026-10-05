extends SceneTree
## 检查奇偶占地建筑的吸附中心与占地锚点


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid: RwPathGrid = RwPathGrid.new()
	grid.tile_size = Vector2i(20, 20)
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var turret: RwUnitDefinition = registry.find_definition("vanilla", "turret")
	var turret_position: Vector2 = grid.snap_structure_position(Vector2(41.0, 41.0), turret.structure_footprint_min, turret.structure_footprint_max)
	assert(turret_position == Vector2(40.0, 40.0))
	assert(grid.structure_anchor_cell(turret_position, turret.structure_footprint_min, turret.structure_footprint_max) == Vector2i(1, 1))
	var visual: RwUnitVisual = RwUnitVisual.new()
	visual.definition = turret
	visual.set_footprint_tile_size(grid.tile_size)
	assert(visual.call("_get_footprint_rect") == Rect2(-20.0, -20.0, 40.0, 40.0))
	visual.free()
	var extractor: RwUnitDefinition = registry.find_definition("vanilla", "extractor")
	var extractor_position: Vector2 = grid.snap_structure_position(Vector2(46.0, 37.0), extractor.structure_footprint_min, extractor.structure_footprint_max)
	assert(extractor_position == Vector2(30.0, 30.0))
	assert(grid.structure_anchor_cell(extractor_position, extractor.structure_footprint_min, extractor.structure_footprint_max) == Vector2i(1, 1))
	print("STRUCTURE_GRID_CHECK_OK")
	quit()
