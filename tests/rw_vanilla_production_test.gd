extends SceneTree
## 校验原版生产菜单、联机动作编号与自定义建筑命令


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var failures: Array[String] = []
	_check_action(registry, "vanilla", "commandCenter", "builder", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_builder", failures)
	_check_action(registry, "vanilla", "landFactory", "c_tank", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_c_tank", failures)
	_check_action(registry, "vanilla", "airFactory", "c_helicopter", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_c_helicopter", failures)
	_check_action(registry, "vanilla", "builder", "mechFactory", RwUnitActionDefinition.Kind.PLACE_BUILDING, "", failures)
	_check_action(registry, "custom", "mechFactory", "mechGun", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_mechGun", failures)
	_check_action(registry, "custom", "extractorT1", "convert:upgradet2", RwUnitActionDefinition.Kind.CONVERT_UNIT, "extractorT2_0", failures)
	_check_action(registry, "custom", "mechFactory", "convert:upgrade", RwUnitActionDefinition.Kind.CONVERT_UNIT, "mechFactoryT2_2", failures)
	_check_action(registry, "custom", "nukeLauncherC", "resource:buildnuke", RwUnitActionDefinition.Kind.QUEUE_RESOURCE, "_0", failures)
	_check_action(registry, "custom", "antiNukeLauncherC", "resource:buildantinuke", RwUnitActionDefinition.Kind.QUEUE_RESOURCE, "_0", failures)
	var nuke_launcher: RwUnitDefinition = registry.find_definition("custom", "nukeLauncherC")
	var nuke_ammo: RwUnitActionDefinition = _find_action(nuke_launcher, "resource:buildnuke")
	if nuke_ammo == null or nuke_ammo.max_stockpile != 4 or float(nuke_ammo.resource_delta.get("ammo", 0.0)) != 1.0:
		failures.append("Nuke stockpile production is incorrect")
	var builder: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	var stock_extractor: RwUnitActionDefinition = _find_action(builder, "extractor")
	if stock_extractor == null or stock_extractor.target_source_id != "custom" or stock_extractor.target_unit_name != "extractorT1":
		failures.append("Original extractor replacement is missing from the builder menu")
	var building: RwUnitActionDefinition = _find_action(builder, "mechFactory")
	if building == null or building.network_build_index != -2 or building.network_build_custom_name != "mechFactory":
		failures.append("Custom building network descriptor is incorrect")
	else:
		var frame: StreamPeerBuffer = RwBinary.writer()
		frame.put_32(30)
		frame.put_32(1)
		frame.put_data(RwBattleCommandWriter.write_build(1, [42,], building.network_build_index, Vector2(300.0, 400.0), false, building.network_build_custom_name))
		var parsed: Dictionary = RwBattleCommandReader.read_frame_packet(frame.data_array)
		if not str(parsed.get("error", "")).is_empty():
			failures.append("Custom building command failed to parse")
		else:
			var command: Dictionary = (parsed["commands"] as Array)[0]
			if command["build_unit_index"] != -2 or command["custom_build_unit_name"] != "mechFactory":
				failures.append("Custom building command lost its unit name")
	var income: RwVanillaEconomy = RwVanillaEconomy.new()
	income.initialize([{"slot": 1, "credits": 0.0,},], 1.0)
	income.set_command_centers({})
	var extractor_definition: RwUnitDefinition = registry.find_definition("custom", "extractorT3_overclocked")
	var extractor: RwUnitState = RwUnitState.new()
	extractor.initialize_from_spawn({"object_id": 88, "source_id": "custom", "unit_name": "extractorT3_overclocked", "team": "1",}, extractor_definition)
	income.register_extractor(extractor)
	if not is_equal_approx(income.get_income_rate(1, "credits"), 30.0):
		failures.append("Converted extractor income is incorrect")
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		_check_targets(registry, registry.find_definition("vanilla", unit_name), failures)
	for unit_name: String in RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS:
		_check_targets(registry, registry.find_definition("custom", unit_name), failures)
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RW production: factory menus, custom placement and conversion actions verified")
	quit(0 if failures.is_empty() else 1)


func _check_action(registry: RwUnitRegistry, source_id: String, producer_name: String, action_id: String, kind: RwUnitActionDefinition.Kind, network_id: String, failures: Array[String]) -> void:
	var producer: RwUnitDefinition = registry.find_definition(source_id, producer_name)
	var action: RwUnitActionDefinition = _find_action(producer, action_id)
	if action == null or action.kind != kind or action.network_action_id != network_id:
		failures.append("Missing or incorrect action: %s:%s -> %s" % [source_id, producer_name, action_id])
	elif action.build_rate_per_frame <= 0.0:
		failures.append("Action has no production rate: %s" % action_id)


func _find_action(producer: RwUnitDefinition, action_id: String) -> RwUnitActionDefinition:
	if producer == null:
		return null
	for action: RwUnitActionDefinition in producer.build_actions:
		if action.action_id == action_id:
			return action
	return null


func _check_targets(registry: RwUnitRegistry, producer: RwUnitDefinition, failures: Array[String]) -> void:
	if producer == null:
		return
	var network_ids: Dictionary = {}
	for action: RwUnitActionDefinition in producer.build_actions:
		if action.kind == RwUnitActionDefinition.Kind.UNSUPPORTED:
			failures.append("Unsupported production action: %s -> %s" % [producer.unit_name, action.action_id])
		if action.kind in [RwUnitActionDefinition.Kind.QUEUE_UNIT, RwUnitActionDefinition.Kind.PLACE_BUILDING, RwUnitActionDefinition.Kind.CONVERT_UNIT,]:
			if registry.find_definition(action.target_source_id, action.target_unit_name) == null:
				failures.append("Action target is missing: %s -> %s" % [producer.unit_name, action.target_unit_name])
		if not action.network_action_id.is_empty():
			if network_ids.has(action.network_action_id):
				failures.append("Duplicate network action: %s -> %s" % [producer.unit_name, action.network_action_id])
			network_ids[action.network_action_id] = true
