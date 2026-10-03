extends SceneTree
## 检查出厂位置与原版软碰撞优先级


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var native_factory: RwUnitDefinition = registry.find_definition("vanilla", "landFactory")
	var mech_factory: RwUnitDefinition = registry.find_definition("custom", "mechFactory")
	assert(native_factory.factory_exit_offset == Vector2(0.0, 9.0))
	assert(native_factory.factory_exit_move_away == 70.0)
	assert(mech_factory.factory_exit_move_away == 120.0)
	var battle_map: Node = (load("uid://c0w7n4afw43pa") as PackedScene).instantiate()
	var first: RwUnitState = _unit(1, "1", Vector2.ZERO, 24)
	var second: RwUnitState = _unit(2, "1", Vector2(8.0, 0.0), 0)
	var mobile_units: Array = battle_map.get("_mobile_unit_states")
	mobile_units.append(first)
	mobile_units.append(second)
	battle_map.call("_separate_mobile_units")
	assert(is_equal_approx(first.world_position.x, -0.2375))
	assert(is_equal_approx(second.world_position.x, 8.2375))
	first.world_position = Vector2.ZERO
	second.world_position = Vector2(8.0, 0.0)
	battle_map.call("_separate_mobile_units", 2.0)
	assert(is_equal_approx(first.world_position.x, -0.475))
	assert(is_equal_approx(second.world_position.x, 8.475))
	first.world_position = Vector2.ZERO
	second.world_position = Vector2(8.0, 0.0)
	second.team = "2"
	battle_map.call("_separate_mobile_units")
	assert(first.world_position == Vector2.ZERO)
	assert(second.world_position == Vector2(8.0, 0.0))
	var builder: RwUnitState = _unit(3, "1", Vector2(0.0, 20.0), 0)
	var produced: RwUnitState = _unit(4, "1", Vector2(0.0, 9.0), 0)
	produced.movement_speed = 1.0
	produced.turn_speed = 3.8
	produced.turn_acceleration = 0.35
	produced.movement_acceleration = 0.04
	produced.movement_deceleration = 0.1
	produced.body_rotation_degrees = 90.0
	produced.apply_factory_exit(Vector2(0.0, 70.0), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	mobile_units.clear()
	mobile_units.append(builder)
	mobile_units.append(produced)
	battle_map.call("_separate_mobile_units")
	assert(not is_zero_approx(produced.world_position.x))
	produced.advance_movement(1, null)
	assert(not is_equal_approx(produced.body_rotation_degrees, 90.0))
	battle_map.free()
	print("BATTLE_COLLISION_CHECK_OK")
	quit()


func _unit(object_id: int, team: String, position: Vector2, soft_priority: int) -> RwUnitState:
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.object_id = object_id
	unit_state.team = team
	unit_state.world_position = position
	unit_state.collision_radius = 10.0
	unit_state.push_mass = 3000.0
	unit_state.soft_collision_on_all = soft_priority
	unit_state.weapon_rotations_degrees = PackedFloat32Array([0.0,])
	return unit_state
