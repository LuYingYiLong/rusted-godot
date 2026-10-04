extends SceneTree
## 对照 1.15 源码中同碰撞组的敌对地面单位也会发生挤压


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle_map: Node = (load("uid://c0w7n4afw43pa") as PackedScene).instantiate()
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var definition: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	assert(definition != null)
	var first: RwUnitState = _unit(1, "0", Vector2.ZERO, definition)
	var second: RwUnitState = _unit(2, "1", Vector2(8.0, 0.0), definition)
	var mobile_units: Array = battle_map.get("_mobile_unit_states")
	mobile_units.append(first)
	mobile_units.append(second)
	battle_map.call("_separate_mobile_units")
	first.apply_collision_push(null)
	second.apply_collision_push(null)
	var distance_after: float = first.world_position.distance_to(second.world_position)
	if distance_after <= 8.0:
		printerr("RW_115_COLLISION_GAP enemy ground units did not separate")
		quit(1)
		return
	var ground: RwUnitState = _unit(3, "0", Vector2.ZERO, definition)
	var aircraft: RwUnitState = _unit(4, "1", Vector2(8.0, 0.0), definition)
	aircraft.movement_type = "AIR"
	mobile_units.clear()
	mobile_units.append(ground)
	mobile_units.append(aircraft)
	battle_map.call("_separate_mobile_units")
	ground.apply_collision_push(null)
	aircraft.apply_collision_push(null)
	if not is_equal_approx(ground.world_position.distance_to(aircraft.world_position), 8.0):
		printerr("RW_115_COLLISION_GROUP_GAP ground and air units separated")
		quit(1)
		return
	battle_map.free()
	print("RW_115_CROSS_TEAM_COLLISION_OK distance=%s" % distance_after)
	quit()


func _unit(object_id: int, team: String, position: Vector2, definition: RwUnitDefinition) -> RwUnitState:
	var state: RwUnitState = RwUnitState.new()
	state.initialize_from_spawn({
		"object_id": object_id,
		"source_id": "vanilla",
		"unit_name": "builder",
		"team": team,
		"position": position,
	}, definition)
	return state
