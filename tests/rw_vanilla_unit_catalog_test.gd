extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(RwVanillaUnitCatalog.NATIVE_TYPES.size() == 52)
	assert(RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.size() == 121)
	assert(RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.size() == RwVanillaUnits.HASHES.size())
	for index: int in RwVanillaUnitCatalog.NATIVE_TYPES.size():
		var name: String = RwVanillaUnitCatalog.native_name(index)
		assert(RwVanillaUnitCatalog.native_index(name) == index)
		var identity: Dictionary = RwVanillaUnitCatalog.network_identity(name)
		assert(identity == {"index": index, "custom_name": "",})
	for name: String in RwVanillaUnits.HASHES:
		assert(RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.has(name))
		var identity: Dictionary = RwVanillaUnitCatalog.network_identity(name)
		assert(identity == {"index": -2, "custom_name": name,})
		var info: Dictionary = RwVanillaUnitCatalog.builtin_info(name)
		assert(str(info.get("source", "")).begins_with("assets/units/"))
		var variant_of: String = str(info.get("variant_of", ""))
		assert(variant_of.is_empty() or RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.has(variant_of))
	assert(RwVanillaUnitCatalog.native_name(-1).is_empty())
	assert(RwVanillaUnitCatalog.native_name(52).is_empty())
	assert(RwVanillaUnitCatalog.network_identity("unknown").is_empty())
	assert(RwVanillaUnitCatalog.native_replacement("tank") == "c_tank")
	assert(RwVanillaUnitCatalog.native_replacement("builder").is_empty())
	assert(RwVanillaUnitCatalog.preferred_network_identity("tank") == {"index": -2, "custom_name": "c_tank",})
	assert(RwVanillaUnitCatalog.preferred_network_identity("builder") == {"index": 7, "custom_name": "",})
	assert(RwVanillaUnitCatalog.builtin_info("extractorT3")["variant_of"] == "extractorT1")
	assert(RwVanillaUnitCatalog.builtin_info("c_amphibiousJet_transition")["variant_of"] == "c_amphibiousJet")
	assert(RwVanillaUnitCatalog.builtin_info("robotCrabWater")["variant_of"] == "robotCrab")
	assert(RwVanillaUnitCatalog.builtin_info("modularSpider_nonEmpty")["variant_of"] == "modularSpider")
	assert(RwVanillaUnitCatalog.builtin_info("mechGun")["built_from"] == ["mechFactory", "mechFactoryT2",])
	print("RW vanilla unit catalog: 52 native types and 121 bundled custom units")
	quit()
