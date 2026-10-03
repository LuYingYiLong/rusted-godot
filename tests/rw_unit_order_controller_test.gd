extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid: RwPathGrid = RwPathGrid.load_map("[p2]Lake (2p).tmx")
	assert(grid != null)
	var start_cell: Vector2i = _find_clear_run(grid)
	assert(start_cell.x >= 0)
	var start: Vector2 = grid.cell_to_world(start_cell)
	var first_target: Vector2 = grid.cell_to_world(start_cell + Vector2i(3, 0))
	var second_target: Vector2 = grid.cell_to_world(start_cell + Vector2i(5, 0))
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("vanilla", "tank")
	var own: RwUnitState = _unit(1, "1", start, definition)
	var enemy: RwUnitState = _unit(2, "2", second_target, definition)
	var units: Dictionary = {1: own, 2: enemy,}
	var orders: RwUnitOrderController = RwUnitOrderController.new()
	orders.configure(units, registry, grid)
	orders.apply_command({
		"team": 1,
		"unit_ids": [1,],
		"order_type": "move",
		"target": second_target,
		"command_targets": {1: {
			"start_position": start,
			"target_position": first_target,
			"path": [],
		},},
	})
	assert(own.order_target == first_target)
	orders.apply_command({
		"team": 1,
		"unit_ids": [1,],
		"order_type": "move",
		"target": second_target,
		"is_queued": true,
	})
	assert(own.order_target == first_target)
	for frame: int in 500:
		orders.advance_unit(own, frame)
	assert(own.world_position.distance_to(second_target) < 2.0)
	orders.apply_command({
		"team": 1,
		"unit_ids": [1,],
		"order_type": "attack",
		"target_id": 2,
	})
	assert(own.order_type == "attack" and own.order_target_id == 2)
	orders.apply_command({
		"team": 1,
		"source_team": 2,
		"unit_ids": [1,],
		"order_type": "move",
		"target": first_target,
	})
	assert(own.order_type == "attack")
	orders.apply_command({
		"team": 2,
		"unit_ids": [1,],
		"order_type": "move",
		"target": first_target,
	})
	assert(own.order_type == "attack")
	orders.apply_command({
		"team": 2,
		"allowed_team_mask": 1 << 1,
		"unit_ids": [1,],
		"order_type": "move",
		"target": first_target,
	})
	assert(own.order_type == "move" and own.order_target == first_target)
	own.apply_order("", own.world_position)
	orders.apply_command({
		"team": 1,
		"unit_ids": [1,],
		"order_type": "move",
		"target": second_target,
		"is_queued": true,
	}, {}, [1,])
	assert(own.order_type.is_empty())
	orders.advance_unit(own, 501, true)
	assert(own.order_type.is_empty())
	orders.advance_unit(own, 502)
	assert(own.order_type == "move" and own.order_target == second_target)
	print("UNIT_ORDER_CHECK_OK")
	quit()


func _unit(object_id: int, team: String, position: Vector2, definition: RwUnitDefinition) -> RwUnitState:
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.initialize_from_spawn({
		"object_id": object_id,
		"source_id": "vanilla",
		"unit_name": "tank",
		"team": team,
		"position": position,
	}, definition)
	return unit_state


func _find_clear_run(grid: RwPathGrid) -> Vector2i:
	for y: int in grid.size.y:
		for x: int in grid.size.x - 5:
			var is_clear: bool = true
			for offset: int in 6:
				if not grid.is_passable(Vector2i(x + offset, y), "LAND"):
					is_clear = false
					break
			if is_clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
