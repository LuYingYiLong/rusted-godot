extends SceneTree
## 校验原版生产菜单、联机动作编号、生产数值与建筑命令


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var failures: Array[String] = []
	_check_action(registry, "vanilla", "commandCenter", "builder", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_builder", failures)
	_check_native_production_values(_find_action(registry.find_definition("vanilla", "commandCenter"), "builder"), "builder", failures)
	_check_action(registry, "vanilla", "landFactory", "c_tank", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_tank", failures)
	_check_action(registry, "vanilla", "airFactory", "dropship", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_dropship", failures)
	_check_action(registry, "vanilla", "builder", "landFactory", RwUnitActionDefinition.Kind.PLACE_BUILDING, "", failures)
	_check_action(registry, "custom", "mechFactory", "mechGun", RwUnitActionDefinition.Kind.QUEUE_UNIT, "u_mechGun", failures)
	if (
		RwVanillaUnitCatalog.native_action_id("extractor") != "u_extractor"
		or RwVanillaUnitCatalog.native_action_id("builder") != "u_builder"
		or RwVanillaUnitCatalog.native_action_id("c_tank") != "u_tank"
		or RwVanillaUnitCatalog.native_action_id("c_helicopter") != "u_helicopter"
		or RwVanillaUnitCatalog.native_action_id("dropship") != "u_dropship"
		or RwVanillaUnitCatalog.native_action_id("mechGun") != "u_mechGun"
	):
		failures.append("Native production action IDs do not match the 1.15 unit enum")
	_check_action(registry, "custom", "extractorT1", "convert:upgradet2", RwUnitActionDefinition.Kind.CONVERT_UNIT, "extractorT2_0", failures)
	_check_action(registry, "custom", "mechFactory", "convert:upgrade", RwUnitActionDefinition.Kind.CONVERT_UNIT, "mechFactoryT2_2", failures)
	_check_action(registry, "custom", "nukeLauncherC", "resource:buildnuke", RwUnitActionDefinition.Kind.QUEUE_RESOURCE, "_0", failures)
	_check_action(registry, "custom", "antiNukeLauncherC", "resource:buildantinuke", RwUnitActionDefinition.Kind.QUEUE_RESOURCE, "_0", failures)
	var land_factory: RwUnitDefinition = registry.find_definition("vanilla", "landFactory")
	var tank_action: RwUnitActionDefinition = _find_action(land_factory, "c_tank")
	var expected_land_factory_units: Array[String] = [
		"builder", "tank", "hoverTank", "artillery", "hovercraft", "heavyTank", "heavyHoverTank", "laserTank",
	]
	var expected_land_factory_action_ids: Dictionary = {
		"builder": "u_builder",
		"tank": "u_tank",
		"hoverTank": "u_hoverTank",
		"artillery": "u_artillery",
		"hovercraft": "u_hovercraft",
		"heavyTank": "u_heavyTank",
		"heavyHoverTank": "u_heavyHoverTank",
		"laserTank": "u_laserTank",
	}
	var expected_native_types: Dictionary = {
		"builder": "builder",
		"tank": "tank",
		"hoverTank": "hoverTank",
		"artillery": "artillery",
		"hovercraft": "hovercraft",
		"heavyTank": "heavyTank",
		"heavyHoverTank": "heavyHoverTank",
		"laserTank": "laserTank",
	}
	var expected_factory_menus: Dictionary = {
		"commandCenter": ["builder",],
		"landFactory": ["builder", "c_tank", "hoverTank", "c_artillery", "hovercraft", "heavyTank", "heavyHoverTank", "c_laserTank",],
		"airFactory": ["dropship", "gunShip", "amphibiousJet",],
		"seaFactory": ["builderShip", "gunBoat", "missileShip", "hovercraft", "battleShip", "attackSubmarine",],
		"experimentalLandFactory": ["c_experimentalTank", "experimentalHoverTank",],
	}
	_check_vanilla_factory_menus(registry, expected_factory_menus, failures)
	for unit_name: String in expected_land_factory_units:
		var native_action: RwUnitActionDefinition = _find_action(land_factory, RwVanillaUnitCatalog.native_replacement(unit_name))
		if native_action == null:
			native_action = _find_action(land_factory, unit_name)
		var expected_action_id: String = str(expected_land_factory_action_ids[unit_name])
		if native_action == null or native_action.network_action_id != expected_action_id:
			failures.append("Land factory production does not use native action ID for %s" % unit_name)
		else:
			_check_action_packet(native_action, expected_action_id, failures)
			_check_native_production_values(native_action, str(expected_native_types[unit_name]), failures)
	if tank_action != null:
		var action_frame: StreamPeerBuffer = RwBinary.writer()
		action_frame.put_32(29)
		action_frame.put_32(1)
		action_frame.put_data(RwBattleCommandWriter.write_action(1, [42,], tank_action.network_action_id))
		var action_result: Dictionary = RwBattleCommandReader.read_frame_packet(action_frame.data_array)
		var action_commands: Array = action_result.get("commands", [])
		var action_command: Dictionary = action_commands[0] if not action_commands.is_empty() else {}
		if (
			not str(action_result.get("error", "")).is_empty()
			or action_command.is_empty()
			or str(action_command.get("action_id", "")) != "u_tank"
			or int(action_command.get("team", -1)) != 1
			or int(action_command.get("source_team", -1)) != 1
			or action_command.get("unit_ids", []) != [42,]
			or bool(action_command.get("stop_current_action", true))
			or bool(action_command.get("is_instant_command", true))
			or int(action_command.get("allowed_team_mask", -1)) != 0
		):
			failures.append("Land factory replacement tank does not use the recorded vanilla action ID")
	if tank_action == null or tank_action.target_unit_name != "c_tank" or tank_action.network_action_id != "u_tank":
		failures.append("Land factory replacement tank is not mapped to the original tank action")
	var nuke_launcher: RwUnitDefinition = registry.find_definition("custom", "nukeLauncherC")
	var nuke_ammo: RwUnitActionDefinition = _find_action(nuke_launcher, "resource:buildnuke")
	if nuke_ammo == null or nuke_ammo.max_stockpile != 4 or float(nuke_ammo.resource_delta.get("ammo", 0.0)) != 1.0:
		failures.append("Nuke stockpile production is incorrect")
	var builder: RwUnitDefinition = registry.find_definition("vanilla", "builder")
	var stock_extractor: RwUnitActionDefinition = _find_action(builder, "extractor")
	if stock_extractor == null or stock_extractor.target_source_id != "custom" or stock_extractor.target_unit_name != "extractorT1":
		failures.append("Original extractor replacement is missing from the builder menu")
	var building: RwUnitActionDefinition = _find_action(builder, "landFactory")
	if building == null or building.network_build_index != 1 or not building.network_build_custom_name.is_empty():
		failures.append("Native land factory network descriptor is incorrect")
	else:
		var frame: StreamPeerBuffer = RwBinary.writer()
		frame.put_32(30)
		frame.put_32(1)
		frame.put_data(RwBattleCommandWriter.write_build(1, [42,], building.network_build_index, Vector2(300.0, 400.0), false))
		var parsed: Dictionary = RwBattleCommandReader.read_frame_packet(frame.data_array)
		if not str(parsed.get("error", "")).is_empty():
			failures.append("Native building command failed to parse")
		else:
			var command: Dictionary = (parsed["commands"] as Array)[0]
			if command["build_unit_index"] != 1 or not str(command["custom_build_unit_name"]).is_empty():
				failures.append("Native building command lost its unit index")
	var income: RwVanillaEconomy = RwVanillaEconomy.new()
	income.initialize([{"slot": 1, "credits": 0.0,},], 1.0)
	income.set_command_centers({})
	var extractor_definition: RwUnitDefinition = registry.find_definition("custom", "extractorT3_overclocked")
	var extractor: RwUnitState = RwUnitState.new()
	extractor.initialize_from_spawn({"object_id": 88, "source_id": "custom", "unit_name": "extractorT3_overclocked", "team": "1",}, extractor_definition)
	income.register_income_unit(extractor)
	if not is_equal_approx(income.get_income_rate(1, "credits"), 30.0):
		failures.append("Converted extractor income is incorrect")
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		_check_targets(registry, registry.find_definition("vanilla", unit_name), failures)
	for unit_name: String in RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS:
		_check_targets(registry, registry.find_definition("custom", unit_name), failures)
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RW production: vanilla factory menus, network IDs, stock values and placement verified")
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


func _check_action_packet(action: RwUnitActionDefinition, expected_action_id: String, failures: Array[String]) -> void:
	var frame: StreamPeerBuffer = RwBinary.writer()
	frame.put_32(29)
	frame.put_32(1)
	frame.put_data(RwBattleCommandWriter.write_action(1, [42,], expected_action_id))
	var parsed: Dictionary = RwBattleCommandReader.read_frame_packet(frame.data_array)
	var commands: Array = parsed.get("commands", [])
	var command: Dictionary = commands[0] if not commands.is_empty() else {}
	if (
		not str(parsed.get("error", "")).is_empty()
		or command.is_empty()
		or str(command.get("action_id", "")) != expected_action_id
		or int(command.get("team", -1)) != 1
		or int(command.get("source_team", -1)) != 1
		or command.get("unit_ids", []) != [42,]
		or bool(command.get("stop_current_action", true))
		or bool(command.get("is_instant_command", true))
		or int(command.get("allowed_team_mask", -1)) != 0
	):
		failures.append("Land factory action packet is incorrect: %s -> %s" % [action.action_id, expected_action_id])


func _check_vanilla_factory_menus(registry: RwUnitRegistry, expected_menus: Dictionary, failures: Array[String]) -> void:
	for producer_name: String in expected_menus:
		var producer: RwUnitDefinition = registry.find_definition("vanilla", producer_name)
		var actual_actions: Array[String] = []
		if producer != null:
			for action: RwUnitActionDefinition in producer.build_actions:
				if action.kind == RwUnitActionDefinition.Kind.QUEUE_UNIT:
					actual_actions.append(action.action_id)
		var expected_actions: Array[String] = []
		for expected_action: String in expected_menus[producer_name]:
			expected_actions.append(expected_action)
		actual_actions.sort()
		expected_actions.sort()
		if actual_actions != expected_actions:
			failures.append("Vanilla %s production menu differs from the 1.15 menu: %s" % [producer_name, actual_actions])


func _check_native_production_values(action: RwUnitActionDefinition, native_name: String, failures: Array[String]) -> void:
	if action == null:
		failures.append("Production action is missing for native %s" % native_name)
		return
	var expected: Dictionary = RwNativeProductionSpecs.SPECS.get(native_name, {})
	var actual_cost: float = float(action.resource_costs.get("credits", -1.0))
	var expected_cost: float = float(expected.get("cost", -2.0))
	var expected_rate: float = float(expected.get("rate", -2.0))
	if not is_equal_approx(actual_cost, expected_cost) or not is_equal_approx(action.build_rate_per_frame, expected_rate):
		failures.append("Production values differ from native %s: cost=%s rate=%s" % [native_name, actual_cost, action.build_rate_per_frame])


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
			if action.kind in [RwUnitActionDefinition.Kind.QUEUE_UNIT, RwUnitActionDefinition.Kind.PLACE_BUILDING,] and action.target_source_id == "custom":
				var native_target_name: String = RwVanillaUnitCatalog.native_name_for_replacement(action.target_unit_name)
				if native_target_name != action.target_unit_name:
					_check_native_production_values(action, native_target_name, failures)
		if not action.network_action_id.is_empty():
			if network_ids.has(action.network_action_id):
				failures.append("Duplicate network action: %s -> %s" % [producer.unit_name, action.network_action_id])
			network_ids[action.network_action_id] = true
