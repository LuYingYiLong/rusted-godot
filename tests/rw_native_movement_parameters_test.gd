extends SceneTree
## 对照 OPEN-RW 探针记录的全部原生单位移动参数

const FLOAT_FIELDS: Dictionary = {
	"speed": "movement_speed",
	"turn_speed": "turn_speed",
	"turn_accel": "turn_acceleration",
	"move_accel": "movement_acceleration",
	"move_decel": "movement_deceleration",
}
const BOOLEAN_FIELDS: Dictionary = {
	"sliding": "movement_sliding",
	"ignores_body": "movement_ignores_body",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_path: String = OS.get_environment("RW_NATIVE_REFERENCE")
	assert(not reference_path.is_empty())
	var source: FileAccess = FileAccess.open(reference_path, FileAccess.READ)
	assert(source != null)
	var headers: PackedStringArray = source.get_line().split("\t", true)
	var declared_index: int = headers.find("declared_type")
	assert(declared_index >= 0)
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var mismatches: Array[String] = []
	var checked_units: int
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split("\t", true)
		if fields[0].to_int() > 1:
			break
		var declared_type: String = fields[declared_index]
		if declared_type.is_empty():
			continue
		var effective_type: String = fields[3]
		var source_id: String = "custom" if effective_type != declared_type else "vanilla"
		var definition: RwUnitDefinition = registry.find_definition(source_id, effective_type)
		if definition == null and source_id == "custom":
			definition = registry.find_definition("vanilla", declared_type)
		if definition == null:
			mismatches.append("%s: missing definition %s" % [declared_type, effective_type])
			continue
		checked_units += 1
		if definition.movement_speed <= 0.0:
			continue
		for trace_field: String in FLOAT_FIELDS:
			var column: int = headers.find(trace_field)
			assert(column >= 0)
			if fields[column].is_empty():
				continue
			var expected: float = fields[column].to_float()
			if trace_field == "speed" and declared_type == "gunShip" and expected == 0.0:
				continue
			if trace_field == "turn_accel":
				expected = maxf(expected, 0.0)
			var property_name: String = FLOAT_FIELDS[trace_field]
			var actual: float = float(definition.get(property_name))
			if trace_field == "speed" and is_equal_approx(expected, definition.water_movement_speed):
				continue
			if trace_field == "turn_speed" and is_equal_approx(expected, definition.water_turn_speed):
				continue
			if not is_equal_approx(expected, actual):
				mismatches.append("%s (%s) %s expected=%s actual=%s" % [declared_type, effective_type, trace_field, expected, actual])
		for trace_field: String in BOOLEAN_FIELDS:
			var column: int = headers.find(trace_field)
			assert(column >= 0)
			if fields[column].is_empty():
				continue
			var expected: bool = fields[column] == "true"
			var property_name: String = BOOLEAN_FIELDS[trace_field]
			var actual: bool = bool(definition.get(property_name))
			if expected != actual:
				mismatches.append("%s (%s) %s expected=%s actual=%s" % [declared_type, effective_type, trace_field, expected, actual])
	if checked_units != RwVanillaUnitCatalog.NATIVE_TYPES.size():
		mismatches.append("Expected %d native definitions, checked %d" % [RwVanillaUnitCatalog.NATIVE_TYPES.size(), checked_units])
	for mismatch: String in mismatches:
		print(mismatch)
	if not mismatches.is_empty():
		printerr("NATIVE_MOVEMENT_PARAMETERS_MISMATCH count=%d" % mismatches.size())
		quit(1)
		return
	print("NATIVE_MOVEMENT_PARAMETERS_CHECK_OK units=%d" % checked_units)
	quit()
