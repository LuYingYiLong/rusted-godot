extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var missing_native_weapons: Array[String] = []
	var armed_native_units: int
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		if unit_name in ["builderShip", "dropship",]:
			continue
		var definition: RwUnitDefinition = registry.find_definition("vanilla", unit_name)
		if definition == null:
			continue
		if definition.attack_range > 0.0:
			armed_native_units += 1
			if definition.combat_weapons.is_empty():
				missing_native_weapons.append(unit_name)
	var missing_builtin_weapons: Array[String] = []
	for unit_name: String in RwBuiltinCombatSpecs.SPECS:
		if (RwBuiltinCombatSpecs.SPECS[unit_name] as Array).is_empty():
			continue
		var definition: RwUnitDefinition = registry.find_definition("custom", unit_name)
		if definition != null and definition.combat_weapons.is_empty():
			missing_builtin_weapons.append(unit_name)
	print("NATIVE_ARMED=%d NATIVE_MISSING=%s" % [armed_native_units, str(missing_native_weapons)])
	print("BUILTIN_MISSING=%s" % str(missing_builtin_weapons))
	quit()
