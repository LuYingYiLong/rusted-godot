class_name RwVanillaBuildings
extends RefCounted

const SPECS: Dictionary = {
	"extractor": {"index": 0, "cost": 700.0, "rate": 0.001, "image": "extractor.png", "dead": "extractor_dead.png", "health": 800.0, "radius": 18.0, "min": Vector2i(0, -1), "max": Vector2i(0, 0), "pool": true,},
	"landFactory": {"index": 1, "cost": 700.0, "rate": 0.001, "image": "land_factory.png", "dead": "land_factory_dead.png", "health": 1200.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"airFactory": {"index": 2, "cost": 1000.0, "rate": 0.001, "image": "air_factory.png", "dead": "air_factory_dead.png", "health": 1000.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"seaFactory": {"index": 3, "cost": 1000.0, "rate": 0.0007, "image": "sea_factory.png", "dead": "sea_factory_dead.png", "health": 1000.0, "radius": 45.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 2), "water": true, "construction_range_bonus": 110.0,},
	"turret": {"index": 5, "cost": 500.0, "rate": 0.0006, "image": "turret_base.png", "turret": "turret_top.png", "dead": "turret_base_dead.png", "health": 700.0, "radius": 16.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"antiAirTurret": {"index": 6, "cost": 600.0, "rate": 0.0008, "image": "turret_base.png", "turret": "anti_air_top.png", "dead": "turret_base_dead.png", "health": 800.0, "radius": 16.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"laserDefence": {"index": 24, "cost": 1200.0, "rate": 0.001, "image": "laser_defence.png", "dead": "laser_defence_dead.png", "health": 500.0, "radius": 20.0, "min": Vector2i(0, 0), "max": Vector2i(1, 1),},
	"repairbay": {"index": 27, "cost": 1500.0, "rate": 0.001, "image": "repair_bay.png", "dead": "repair_bay_dead.png", "health": 1000.0, "radius": 25.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"NukeLaucher": {"index": 28, "cost": 45000.0, "rate": 0.0001, "image": "nuke_launcher.png", "dead": "nuke_launcher_dead.png", "health": 1500.0, "radius": 40.0, "min": Vector2i(-2, -1), "max": Vector2i(2, 1),},
	"AntiNukeLaucher": {"index": 29, "cost": 15000.0, "rate": 0.0007, "image": "antinuke_launcher.png", "dead": "antinuke_launcher_dead.png", "health": 2800.0, "radius": 30.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
	"experimentalLandFactory": {"index": 32, "cost": 11000.0, "rate": 0.00035, "image": "experimental_unit_factory_base.png", "dead": "experimental_unit_factory_dead.png", "health": 3200.0, "radius": 50.0, "min": Vector2i(-2, -2), "max": Vector2i(2, 2),},
	"fabricator": {"index": 35, "cost": 1500.0, "rate": 0.0006, "image": "power.png", "dead": "power_dead.png", "health": 500.0, "radius": 25.0, "min": Vector2i(-1, -1), "max": Vector2i(1, 1),},
}
## 原版内置自定义单位对原生建筑类型的替换名称
const BUILTIN_CUSTOM_REPLACEMENTS: Dictionary = {
	"extractor": "extractorT1",
	"fabricator": "fabricatorT1",
	"turret": "c_turret_t1",
	"antiAirTurret": "c_antiAirTurret",
	"NukeLaucher": "nukeLauncherC",
	"AntiNukeLaucher": "antiNukeLauncherC",
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


## 将网络中的原生索引或内置自定义单位名称解析为建筑定义
static func name_for_network_type(unit_type_index: int, custom_name: String) -> String:
	if unit_type_index != -2:
		return name_for_index(unit_type_index)
	for unit_name: String in BUILTIN_CUSTOM_REPLACEMENTS:
		if BUILTIN_CUSTOM_REPLACEMENTS[unit_name] == custom_name:
			return unit_name
	return ""


## 返回原版会用于序列化该建筑的内置自定义单位名称
static func custom_name_for_index(unit_type_index: int) -> String:
	return str(BUILTIN_CUSTOM_REPLACEMENTS.get(name_for_index(unit_type_index), ""))


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
			turret_top.rotation_offset_degrees = 90.0
			if unit_name == "turret":
				turret_top.reset_when_idle = false
			elif unit_name == "antiAirTurret":
				turret_top.reset_when_idle = false
				turret_top.idle_spin_degrees = 0.6
			if unit_name == "turret":
				turret_top.images_by_level = {2: "turret_top_l2.png", 3: "turret_top_l3.png",}
			definition.weapon_parts = [turret_top,]
		definition.dead_image = str(spec.get("dead", ""))
		match unit_name:
			"extractor":
				definition.body_frames = 4
				definition.back_image = "extractor_back.png"
				definition.body_images_by_level = {2: "extractor_t2.png", 3: "extractor_t3.png",}
				definition.animation_step_frames = 17
				definition.animation_ping_pong = true
				definition.animation_speed_follows_tech_level = true
				definition.build_actions = [
					_extractor_upgrade("extractorT2", "102", 1, 2, 1200.0, 0.0006, "extractor_t2.png"),
					_extractor_upgrade("extractorT3", "103", 2, 3, 2500.0, 0.0003, "extractor_t3.png"),
				]
			"airFactory":
				definition.body_frames = 5
			"fabricator":
				definition.body_frames = 3
		definition.applies_spawn_rotation = false
		definition.default_body_rotation_degrees = -90.0
		definition.render_rotation_offset_degrees = 90.0
		definition.selection_shape = RwUnitDefinition.SelectionShape.RECTANGLE
		definition.max_health = float(spec["health"])
		definition.collision_radius = float(spec["radius"])
		definition.construction_range_bonus = float(spec.get("construction_range_bonus", 0.0))
		definition.blocks_movement = true
		definition.structure_footprint_min = spec["min"]
		definition.structure_footprint_max = spec["max"]
		match unit_name:
			"landFactory":
				definition.construction_footprint = Rect2i(-1, -1, 3, 5)
			"airFactory":
				definition.construction_footprint = Rect2i(-1, -1, 3, 4)
			"experimentalLandFactory":
				definition.construction_footprint = Rect2i(-2, -2, 5, 7)
			"NukeLaucher":
				definition.construction_footprint = Rect2i(-2, -1, 5, 4)
		definition.placement_requires_resource_pool = bool(spec.get("pool", false))
		definition.placement_requires_water = bool(spec.get("water", false))
		if unit_name == "turret":
			RwVanillaCombatDefinitions.configure_turret(definition)
		registry.register_definition(definition, assets)


static func _extractor_upgrade(action_id: String, network_id: String, required_level: int, result_level: int, cost: float, rate: float, icon_image: String) -> RwUnitActionDefinition:
	var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
	action.action_id = action_id
	action.network_action_id = network_id
	action.display_name = "Upgrade T%d" % result_level
	action.icon_image = icon_image
	action.icon_frames = 4
	action.kind = RwUnitActionDefinition.Kind.UPGRADE_UNIT
	action.required_tech_level = required_level
	action.result_tech_level = result_level
	action.resource_costs = {"credits": cost,}
	action.build_rate_per_frame = rate
	return action
