extends SceneTree
## 将 OPEN-RW 注入的全部原生单位逐一转换为 Godot 初始状态轨迹


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_NATIVE_REFERENCE")
	var output_path: String = OS.get_environment("RW_PROBE_PATH")
	assert(not reference_path.is_empty() and not output_path.is_empty())
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	assert(source != null)
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var declared_type_index: int = headers.find("declared_type")
	assert(declared_type_index >= 0)
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var units: Dictionary = {}
	var reference_delta: float = 1.0
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields.size() <= declared_type_index or fields[declared_type_index].is_empty():
			continue
		var unit_name: String = fields[declared_type_index]
		var definition: RwUnitDefinition = registry.find_definition("vanilla", unit_name)
		assert(definition != null, "Missing native definition: %s" % unit_name)
		var object_id: int = fields[2].to_int()
		var state: RwUnitState = RwUnitState.new()
		state.initialize_from_spawn({
			"object_id": object_id,
			"source_id": "vanilla",
			"unit_name": unit_name,
			"team": fields[4],
			"position": Vector2(fields[5].to_float(), fields[6].to_float()),
		}, definition)
		units[object_id] = state
		reference_delta = fields[1].to_float()
	assert(units.size() == RwVanillaUnitCatalog.NATIVE_TYPES.size())
	var probe: RwBattleStateProbe = RwBattleStateProbe.new()
	probe.capture(1, reference_delta, units)
	probe.close()
	assert(FileAccess.file_exists(output_path))
	print("ALL_NATIVE_REFERENCE_CHECK_OK units=%d" % units.size())
	quit()
