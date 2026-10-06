extends RefCounted
class_name RwVanillaProductionActions
## 根据原生工厂和内置 INI 关系注册生产、建造与形态切换动作

const NATIVE_PRODUCTION: Dictionary = {
	"commandCenter": [["builder", 1,],],
	"landFactory": [
		["builder", 1,], ["tank", 1,], ["hoverTank", 1,], ["artillery", 1,],
		["hovercraft", 2,], ["heavyTank", 2,], ["heavyHoverTank", 2,], ["laserTank", 2,],
	],
	"airFactory": [["dropship", 2,], ["gunShip", 2,], ["amphibiousJet", 2,],],
	"seaFactory": [
		["builderShip", 1,], ["gunBoat", 1,], ["missileShip", 1,],
		["hovercraft", 1,], ["battleShip", 1,], ["attackSubmarine", 1,],
	],
	"experimentalLandFactory": [["experimentalTank", 1,], ["experimentalHoverTank", 1,],],
}

const BUILDER_SHIP_BUILDINGS: Array[String] = [
	"extractor", "turret", "antiAirTurret", "landFactory", "airFactory",
	"seaFactory", "fabricator", "laserDefence", "repairbay",
]

const VANILLA_BUILDER_BUILDINGS: Array[String] = [
	"extractor", "turret", "antiAirTurret", "landFactory", "airFactory", "seaFactory",
	"laserDefence", "repairbay", "fabricator", "experimentalLandFactory", "NukeLaucher", "AntiNukeLaucher",
]


## 注册原版生产关系和内置定义声明的特殊动作
static func register_actions(registry: RwUnitRegistry, include_builtin_custom_actions: bool = false) -> void:
	for producer_name: String in NATIVE_PRODUCTION:
		var producer: RwUnitDefinition = registry.find_definition("vanilla", producer_name)
		for entry: Array in NATIVE_PRODUCTION[producer_name]:
			var target: RwUnitDefinition = _resolve_target(registry, str(entry[0]))
			if producer != null and target != null:
				_upsert(producer, _production_action(target, int(entry[1]), false))
	var builder_ship: RwUnitDefinition = registry.find_definition("vanilla", "builderShip")
	if builder_ship != null:
		for target_name: String in BUILDER_SHIP_BUILDINGS:
			var target: RwUnitDefinition = _resolve_target(registry, target_name)
			if target != null:
				_upsert(builder_ship, _production_action(target, 1, true))
	_apply_native_replacements(registry)
	for unit_name: String in RwBuiltinActionSpecs.SPECS:
		var action_spec: Dictionary = RwBuiltinActionSpecs.SPECS[unit_name]
		var target_definition: RwUnitDefinition = registry.find_definition("custom", unit_name)
		for relation: Dictionary in action_spec.get("built_from", []):
			var producer: RwUnitDefinition = _resolve_producer(registry, str(relation["producer"]))
			if producer == null or target_definition == null:
				continue
			_upsert(producer, _production_action(target_definition, int(relation["tech"]), bool(relation["force_nano"])))
		if target_definition == null:
			continue
		for can_build: Dictionary in action_spec.get("can_build", []):
			var target_name: String = str(can_build["target"])
			if target_name.to_lower() == "reclaim":
				target_definition.can_reclaim = true
				continue
			if target_name.to_lower() in ["repair", "setrally",]:
				continue
			var target: RwUnitDefinition = _resolve_target(registry, target_name)
			if target != null:
				_upsert(target_definition, _production_action(target, int(can_build["tech"]), bool(can_build["force_nano"])))
		for conversion: Dictionary in action_spec.get("conversions", []):
			var result: RwUnitDefinition = _resolve_target(registry, str(conversion["target"]))
			if result == null:
				continue
			var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
			action.action_id = "convert:%s" % str(conversion["action_id"])
			action.network_action_id = str(conversion["network_id"])
			action.kind = RwUnitActionDefinition.Kind.CONVERT_UNIT
			action.target_source_id = result.source_id
			action.target_unit_name = result.unit_name
			action.icon_image = result.body_image
			action.icon_frames = result.body_frames
			action.display_name = str(conversion.get("text", ""))
			if action.display_name.is_empty() or action.display_name.begins_with("i:"):
				action.display_name = "Convert to %s" % result.display_name
			action.resource_costs = {"credits": float(conversion.get("cost", 0.0)),}
			action.build_rate_per_frame = float(conversion.get("rate", 1000.0))
			action.is_visible = bool(conversion.get("visible", true))
			_upsert(target_definition, action)
		for resource_spec: Dictionary in action_spec.get("resource_actions", []):
			var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
			action.action_id = "resource:%s" % str(resource_spec["action_id"])
			action.network_action_id = str(resource_spec["network_id"])
			action.kind = RwUnitActionDefinition.Kind.QUEUE_RESOURCE
			action.icon_image = "builtin:shared/icon_build.png"
			action.display_name = str(resource_spec.get("text", ""))
			if action.display_name.is_empty() or action.display_name.begins_with("i:"):
				match str(resource_spec["action_id"]):
					"buildnuke":
						action.display_name = "Build nuke"
					"buildantinuke":
						action.display_name = "Build anti-nuke"
					_:
						action.display_name = "Produce %s" % str(resource_spec["resource"])
			action.resource_costs = {"credits": float(resource_spec["cost"]),}
			action.resource_delta = {str(resource_spec["resource"]): float(resource_spec["amount"]),}
			action.build_rate_per_frame = float(resource_spec["rate"])
			action.max_stockpile = int(resource_spec["max_stockpile"])
			action.is_visible = bool(resource_spec["visible"])
			_upsert(target_definition, action)
	_register_factory_upgrade(registry, "landFactory", 2000.0, "land_factory_front_t2.png")
	_register_factory_upgrade(registry, "airFactory", 1500.0, "air_factory_t2.png")
	if not include_builtin_custom_actions:
		_filter_non_vanilla_factory_actions(registry)


static func _filter_non_vanilla_factory_actions(registry: RwUnitRegistry) -> void:
	var producer_names: Array[String] = []
	for producer_name: String in NATIVE_PRODUCTION:
		producer_names.append(producer_name)
	producer_names.append("builder")
	producer_names.append("builderShip")
	for producer_name: String in producer_names:
		var producer: RwUnitDefinition = registry.find_definition("vanilla", producer_name)
		if producer == null:
			continue
		var allowed_queue_targets: Dictionary = {}
		for entry: Array in NATIVE_PRODUCTION.get(producer_name, []):
			var target: RwUnitDefinition = _resolve_target(registry, str(entry[0]))
			if target != null:
				allowed_queue_targets[target.unit_name] = true
		var allowed_build_actions: Array[String] = []
		if producer_name == "builder":
			allowed_build_actions.append_array(VANILLA_BUILDER_BUILDINGS)
		elif producer_name == "builderShip":
			allowed_build_actions.append_array(BUILDER_SHIP_BUILDINGS)
		for action_index: int in range(producer.build_actions.size() - 1, -1, -1):
			var action: RwUnitActionDefinition = producer.build_actions[action_index]
			if action.kind == RwUnitActionDefinition.Kind.QUEUE_UNIT and not allowed_queue_targets.has(action.target_unit_name):
				producer.build_actions.remove_at(action_index)
			elif action.kind == RwUnitActionDefinition.Kind.PLACE_BUILDING and not allowed_build_actions.has(action.action_id):
				producer.build_actions.remove_at(action_index)


static func _apply_native_replacements(registry: RwUnitRegistry) -> void:
	for producer_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		var producer: RwUnitDefinition = registry.find_definition("vanilla", producer_name)
		if producer == null:
			continue
		for existing_action: RwUnitActionDefinition in producer.build_actions.duplicate():
			if existing_action.kind != RwUnitActionDefinition.Kind.PLACE_BUILDING or existing_action.target_source_id != "vanilla":
				continue
			var replacement_name: String = RwVanillaUnitCatalog.native_replacement(existing_action.target_unit_name)
			var replacement: RwUnitDefinition = registry.find_definition("custom", replacement_name)
			if replacement == null:
				continue
			var action: RwUnitActionDefinition = _production_action(replacement, existing_action.required_tech_level, true)
			action.action_id = existing_action.action_id
			action.display_name = existing_action.display_name
			_upsert(producer, action)


static func _resolve_producer(registry: RwUnitRegistry, unit_name: String) -> RwUnitDefinition:
	return _resolve_target(registry, unit_name, false)


static func _resolve_target(registry: RwUnitRegistry, unit_name: String, prefer_replacement: bool = true) -> RwUnitDefinition:
	var native_name: String = _matching_name(RwVanillaUnitCatalog.NATIVE_TYPES, unit_name)
	if not native_name.is_empty():
		if prefer_replacement:
			var replacement: String = RwVanillaUnitCatalog.native_replacement(native_name)
			if not replacement.is_empty():
				return registry.find_definition("custom", replacement)
		return registry.find_definition("vanilla", native_name)
	var custom_name: String = _matching_name(RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.keys(), unit_name)
	return registry.find_definition("custom", custom_name) if not custom_name.is_empty() else null


static func _matching_name(names: Array, requested: String) -> String:
	for name: String in names:
		if name.to_lower() == requested.to_lower():
			return name
	return ""


static func _production_action(target: RwUnitDefinition, required_level: int, force_nano: bool) -> RwUnitActionDefinition:
	var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
	action.action_id = target.unit_name
	action.display_name = target.display_name
	action.icon_image = target.body_image
	action.icon_frames = target.body_frames
	action.target_source_id = target.source_id
	action.target_unit_name = target.unit_name
	action.required_tech_level = required_level if required_level > 1 else 0
	var cost: float
	var rate: float
	var native_target_name: String = RwVanillaUnitCatalog.native_name_for_replacement(target.unit_name)
	if target.source_id == "custom" and native_target_name != target.unit_name:
		var spec: Dictionary = RwNativeProductionSpecs.SPECS.get(native_target_name, {})
		cost = float(spec.get("cost", 0.0))
		rate = float(spec.get("rate", 0.0))
	elif target.source_id == "custom":
		var spec: Dictionary = RwBuiltinUnitSpecs.SPECS.get(target.unit_name, {})
		cost = float(spec.get("price", 0.0))
		rate = float(spec.get("build_rate", 0.0))
	else:
		var spec: Dictionary = RwNativeProductionSpecs.SPECS.get(target.unit_name, {})
		cost = float(spec.get("cost", 0.0))
		rate = float(spec.get("rate", 0.0))
	action.resource_costs = {"credits": cost,}
	action.build_rate_per_frame = rate if rate > 0.0 else 0.001
	if target.selection_shape == RwUnitDefinition.SelectionShape.RECTANGLE or force_nano:
		action.kind = RwUnitActionDefinition.Kind.PLACE_BUILDING
		if target.source_id == "custom":
			action.network_build_index = -2
			action.network_build_custom_name = target.unit_name
		else:
			action.network_build_index = RwVanillaUnitCatalog.native_index(target.unit_name)
	else:
		action.kind = RwUnitActionDefinition.Kind.QUEUE_UNIT
		action.network_action_id = RwVanillaUnitCatalog.production_action_id(target.unit_name)
	return action


static func _upsert(producer: RwUnitDefinition, action: RwUnitActionDefinition) -> void:
	for index: int in producer.build_actions.size():
		if producer.build_actions[index].action_id == action.action_id:
			producer.build_actions[index] = action
			return
	producer.build_actions.append(action)


static func _register_factory_upgrade(registry: RwUnitRegistry, unit_name: String, cost: float, icon: String) -> void:
	var definition: RwUnitDefinition = registry.find_definition("vanilla", unit_name)
	if definition == null:
		return
	var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
	action.action_id = "upgradeT2"
	action.network_action_id = "110"
	action.display_name = "Upgrade T2"
	action.icon_image = icon
	action.kind = RwUnitActionDefinition.Kind.UPGRADE_UNIT
	action.required_tech_level = 1
	action.result_tech_level = 2
	action.resource_costs = {"credits": cost,}
	action.build_rate_per_frame = 0.0004
	_upsert(definition, action)
