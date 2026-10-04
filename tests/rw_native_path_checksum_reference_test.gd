extends SceneTree
## 对照 OPEN-RW 全原生单位探针的首次路径校验值


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_NATIVE_REFERENCE")
	assert(not reference_path.is_empty())
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	assert(source != null)
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var path_sum_index: int = headers.find("path_sum")
	var declared_type_index: int = headers.find("declared_type")
	assert(path_sum_index >= 0 and declared_type_index >= 0)
	var first_rows: Dictionary = {}
	var expected_sums: Dictionary = {}
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields[13] != "move":
			continue
		var object_id: int = fields[2].to_int()
		if fields[0] == "1":
			first_rows[object_id] = fields
		if not expected_sums.has(object_id) and fields[path_sum_index] != "0":
			expected_sums[object_id] = fields[path_sum_index].to_int()
	assert(first_rows.size() == 23)
	assert(expected_sums.size() == first_rows.size())
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var path_grid: RwPathGrid = RwPathGrid.load_map("[p2]Small_Island (2p).tmx")
	assert(path_grid != null)
	for object_id: int in first_rows:
		var fields: PackedStringArray = first_rows[object_id]
		var declared_type: String = fields[declared_type_index]
		var effective_type: String = fields[3]
		var source_id: String = "custom" if effective_type != declared_type else "vanilla"
		var definition: RwUnitDefinition = registry.find_definition(source_id, effective_type)
		assert(definition != null)
		var state: RwUnitState = RwUnitState.new()
		var position: Vector2 = Vector2(fields[5].to_float(), fields[6].to_float())
		var target: Vector2 = Vector2(fields[14].to_float(), fields[15].to_float())
		state.initialize_from_spawn({
			"object_id": object_id,
			"source_id": source_id,
			"unit_name": effective_type,
			"team": fields[4],
			"position": position,
		}, definition)
		state.apply_move_order(target, path_grid.find_path(position, target, state.movement_type))
		var checksum: Dictionary = RwGameStateChecksum.calculate_unit_fields({object_id: state,})
		assert(int(checksum["UnitPaths"]) == int(expected_sums[object_id]), "Path checksum differs for %s #%d" % [effective_type, object_id])
	print("NATIVE_PATH_CHECKSUM_REFERENCE_CHECK_OK units=%d" % first_rows.size())
	quit()
