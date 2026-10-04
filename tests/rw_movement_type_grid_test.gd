extends SceneTree
## 检查内置跨悬崖单位的通行类型及地图格成本


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var cliff_unit: RwUnitDefinition = registry.find_definition("custom", "mechEngineer")
	var cliff_water_unit: RwUnitDefinition = registry.find_definition("custom", "experimentalSpider")
	assert(cliff_unit != null and cliff_unit.movement_type == "OVER_CLIFF")
	assert(cliff_water_unit != null and cliff_water_unit.movement_type == "OVER_CLIFF_WATER")
	var cliff_accessible: int
	var cliff_water_accessible: int
	var large_cliff_accessible: int
	for map_name: String in ["[p6]Valley Pass (6p).tmx", "[p2]Small_Island (2p).tmx",]:
		var grid: RwPathGrid = RwPathGrid.load_map(map_name)
		assert(grid != null)
		for y: int in grid.size.y:
			for x: int in grid.size.x:
				var cell: Vector2i = Vector2i(x, y)
				var land: int = grid.cost_at(cell, "LAND")
				var hover: int = grid.cost_at(cell, "HOVER")
				var cliff: int = grid.cost_at(cell, "OVER_CLIFF")
				var cliff_water: int = grid.cost_at(cell, "OVER_CLIFF_WATER")
				if land < 0 and cliff >= 0:
					cliff_accessible += 1
				if cliff < 0 and cliff_water >= 0:
					cliff_water_accessible += 1
				if hover < 0 and cliff >= 0:
					large_cliff_accessible += 1
	assert(cliff_accessible > 0)
	assert(cliff_water_accessible > 0)
	print("MOVEMENT_TYPE_GRID_OK cliff=%d cliff_water=%d large_cliff=%d" % [cliff_accessible, cliff_water_accessible, large_cliff_accessible])
	quit()
