extends SceneTree
## 使用原版录像中第 1538 帧树木清场状态验证建筑放置与残骸位移

const FIXTURE_PATH: String = "res://tests/fixtures/rw115_factory_tree_clear.obstacles.csv"
const BATTLE_MAP_UID: String = "uid://c0w7n4afw43pa"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert(source != null)
	source.get_csv_line()
	var before: PackedStringArray
	var after: PackedStringArray
	while not source.eof_reached():
		var fields: PackedStringArray = source.get_csv_line()
		if fields.size() < 10:
			continue
		if fields[0].to_int() == 1537:
			before = fields
		elif fields[0].to_int() == 1538:
			after = fields
	assert(not before.is_empty() and not after.is_empty())
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var tree: RwUnitState = RwUnitState.new()
	tree.initialize_from_spawn({
		"object_id": 14,
		"unit_name": "tree",
		"position": Vector2(before[3].to_float(), before[4].to_float()),
		"variant": "1",
	}, registry.find_definition("vanilla", "tree"))
	assert(tree.body_rotation_degrees == -20.0 and not tree.is_dead)
	var building: RwUnitState = RwUnitState.new()
	building.world_position = Vector2(1890.0, 230.0)
	var map: Node = (load(BATTLE_MAP_UID) as PackedScene).instantiate()
	map.set("_map_tile_size", Vector2i(20, 20))
	(map.get("_unit_states") as Dictionary)[14] = tree
	map.call("_clear_trees_for_building", building, registry.find_definition("vanilla", "landFactory"))
	assert(tree.is_dead and after[6] == "true")
	assert(tree.health == after[5].to_float())
	assert(tree.animation_frame == 2)
	assert(tree.world_position == Vector2(after[3].to_float(), after[4].to_float()))
	var corpse_position: Vector2 = tree.world_position
	tree.fall_tree()
	assert(tree.world_position == corpse_position)
	map.free()
	print("RW115_BUILDING_TREE_CLEAR passed")
	quit()
