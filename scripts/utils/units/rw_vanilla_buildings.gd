class_name RwVanillaBuildings
extends RefCounted

const SPECS: Dictionary = {
	"extractor": {"index": 0, "cost": 700.0, "rate": 0.001, "image": "extractor.png", "dead": "extractor_dead.png", "health": 800.0, "radius": 18.0, "min": Vector2i(0, -1), "max": Vector2i(0, 0), "pool": true,},
	"landFactory": {"index": 1, "cost": 700.0, "rate": 0.001, "image": "land_factory.png", "dead": "land_factory_dead.png", "health": 1200.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"airFactory": {"index": 2, "cost": 1000.0, "rate": 0.001, "image": "air_factory.png", "dead": "air_factory_dead.png", "health": 1000.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"seaFactory": {"index": 3, "cost": 1000.0, "rate": 0.0007, "image": "sea_factory.png", "dead": "sea_factory_dead.png", "health": 1000.0, "radius": 45.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 2), "water": true,},
	"turret": {"index": 5, "cost": 500.0, "rate": 0.0006, "image": "turret_base.png", "turret": "turret_top.png", "dead": "turret_base_dead.png", "health": 700.0, "radius": 16.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"antiAirTurret": {"index": 6, "cost": 600.0, "rate": 0.0008, "image": "turret_base.png", "turret": "anti_air_top.png", "dead": "turret_base_dead.png", "health": 700.0, "radius": 16.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"laserDefence": {"index": 24, "cost": 1200.0, "rate": 0.001, "image": "laser_defence.png", "dead": "laser_defence_dead.png", "health": 1000.0, "radius": 20.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"repairbay": {"index": 27, "cost": 1500.0, "rate": 0.001, "image": "repair_bay.png", "dead": "repair_bay_dead.png", "health": 1000.0, "radius": 25.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"NukeLaucher": {"index": 28, "cost": 45000.0, "rate": 0.0001, "image": "nuke_launcher.png", "dead": "nuke_launcher_dead.png", "health": 1500.0, "radius": 40.0, "min": Vector2i(-2, -1), "max": Vector2i(2, 1),},
	"AntiNukeLaucher": {"index": 29, "cost": 15000.0, "rate": 0.0007, "image": "antinuke_launcher.png", "dead": "antinuke_launcher_dead.png", "health": 2800.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"experimentalLandFactory": {"index": 32, "cost": 11000.0, "rate": 0.00035, "image": "experimental_unit_factory_base.png", "dead": "experimental_unit_factory_dead.png", "health": 3200.0, "radius": 50.0, "min": Vector2i(-2, -2), "max": Vector2i(2, 2),},
	"fabricator": {"index": 35, "cost": 1500.0, "rate": 0.0006, "image": "power.png", "dead": "power_dead.png", "health": 900.0, "radius": 25.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
}
const DISPLAY_NAMES: Dictionary = {
	"extractor": "Extractor",
	"landFactory": "Land factory",
	"airFactory": "Air factory",
	"seaFactory": "Sea factory",
	"turret": "Turret",
	"antiAirTurret": "Anti-air turret",
	"laserDefence": "Laser defence",
	"repairbay": "Repair bay",
	"NukeLaucher": "Nuke launcher",
	"AntiNukeLaucher": "Anti-nuke launcher",
	"experimentalLandFactory": "Experimental factory",
	"fabricator": "Fabricator",
}


static func find_spec(unit_name: String) -> Dictionary:
	return SPECS.get(unit_name, {})


static func name_for_index(unit_type_index: int) -> String:
	for unit_name: String in SPECS:
		if int(SPECS[unit_name].get("index", -1)) == unit_type_index:
			return unit_name
	return ""


static func configure_action(action: RwUnitActionDefinition) -> void:
	var spec: Dictionary = find_spec(action.action_id)
	if spec.is_empty():
		return
	action.kind = RwUnitActionDefinition.Kind.PLACE_BUILDING
	action.target_unit_name = action.action_id
	action.network_build_index = int(spec["index"])
	action.resource_costs = {"credits": float(spec["cost"]),}
	action.build_rate_per_frame = float(spec["rate"])


static func register_definitions(registry: RwUnitRegistry, assets: RwVanillaUnitAssets) -> void:
	for unit_name: String in SPECS:
		if unit_name == "seaFactory":
			continue
		var spec: Dictionary = SPECS[unit_name]
		var definition: RwUnitDefinition = RwUnitDefinition.new()
		definition.unit_name = unit_name
		definition.display_name = str(DISPLAY_NAMES.get(unit_name, unit_name))
		definition.body_image = str(spec["image"])
		var turret_image: String = str(spec.get("turret", ""))
		if not turret_image.is_empty():
			var turret_top: RwUnitWeaponDefinition = RwUnitWeaponDefinition.new()
			turret_top.image = turret_image
			turret_top.mount_offset = Vector2(0.0, -5.0)
			turret_top.mount_follows_body = false
			definition.weapon_parts = [turret_top,]
		definition.dead_image = str(spec.get("dead", ""))
		match unit_name:
			"extractor":
				definition.body_frames = 4
			"airFactory":
				definition.body_frames = 5
			"fabricator":
				definition.body_frames = 3
		definition.applies_spawn_rotation = false
		definition.selection_shape = RwUnitDefinition.SelectionShape.RECTANGLE
		definition.max_health = float(spec["health"])
		definition.collision_radius = float(spec["radius"])
		definition.blocks_movement = true
		definition.structure_footprint_min = spec["min"]
		definition.structure_footprint_max = spec["max"]
		definition.placement_requires_resource_pool = bool(spec.get("pool", false))
		definition.placement_requires_water = bool(spec.get("water", false))
		registry.register_definition(definition, assets)
