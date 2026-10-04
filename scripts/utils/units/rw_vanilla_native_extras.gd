extends RefCounted
class_name RwVanillaNativeExtras
## 补齐未在核心单位与建筑定义中注册的原生单位

const SPECS: Dictionary = {
	"hoverTank": {
		"body": "hover_tank.png",
		"dead": "hover_tank_dead.png",
		"shadow": "hover_tank_shadow.png",
		"health": 150.0,
		"radius": 7.0,
		"speed": 1.0,
		"turn_speed": 180.0,
		"turn_accel": 0.5,
		"move_accel": 0.04,
		"move_decel": 0.09,
		"move_sliding": true,
		"move_ignoring_body": true,
		"attack_range": 140.0,
		"movement_type": "HOVER",
	},
	"gunShip": {
		"body": "gunship.png",
		"dead": "gunship_dead.png",
		"shadow": "gunship_shadow.png",
		"health": 260.0,
		"radius": 15.0,
		"speed": 1.4,
		"turn_speed": 4.0,
		"turn_accel": 0.4,
		"move_accel": 0.2,
		"move_decel": 0.1,
		"move_sliding": true,
		"attack_range": 140.0,
		"movement_type": "AIR",
	},
	"missileShip": {
		"body": "scout_ship.png",
		"dead": "scout_ship_dead.png",
		"health": 350.0,
		"radius": 15.0,
		"speed": 1.2,
		"turn_speed": 1.9,
		"turn_accel": 0.2,
		"move_accel": 0.05,
		"move_decel": 0.1,
		"attack_range": 200.0,
		"movement_type": "WATER",
	},
	"gunBoat": {
		"body": "gun_boat.png",
		"dead": "gun_boat_dead.png",
		"health": 170.0,
		"radius": 12.0,
		"speed": 1.5,
		"turn_speed": 2.8,
		"turn_accel": 0.35,
		"move_accel": 0.06,
		"move_decel": 0.2,
		"attack_range": 120.0,
		"movement_type": "WATER",
	},
	"megaTank": {
		"body": "mega_tank.png",
		"dead": "mega_tank_dead.png",
		"turret": "mega_tank_turret.png",
		"health": 550.0,
		"radius": 12.0,
		"speed": 0.8,
		"turn_speed": 1.2,
		"move_accel": 0.05,
		"move_decel": 0.1,
		"attack_range": 140.0,
		"movement_type": "LAND",
	},
	"ladybug": {
		"body": "ladybug.png",
		"hide_on_death": true,
		"health": 130.0,
		"radius": 5.0,
		"speed": 1.7,
		"turn_speed": 5.5,
		"move_accel": 0.07,
		"move_decel": 0.12,
		"attack_range": 43.0,
		"movement_type": "LAND",
	},
	"battleShip": {
		"body": "battle_ship_t2.png",
		"dead": "battle_ship_t2_dead.png",
		"turret": "battle_ship_t2_turret.png",
		"health": 1200.0,
		"radius": 20.0,
		"speed": 0.8,
		"turn_speed": 1.8,
		"turn_accel": 0.08,
		"move_accel": 0.03,
		"move_decel": 0.1,
		"attack_range": 240.0,
		"movement_type": "WATER",
	},
	"tankDestroyer": {
		"body": "tank2.png",
		"dead": "tank2_dead.png",
		"turret": "tank2_turret.png",
		"health": 350.0,
		"radius": 11.0,
		"speed": 1.0,
		"turn_speed": 1.9,
		"move_accel": 0.07,
		"move_decel": 0.12,
		"attack_range": 150.0,
		"movement_type": "LAND",
	},
	"heavyTank": {
		"body": "heavy_tank.png",
		"dead": "heavy_tank_dead.png",
		"turret": "heavy_tank_turret.png",
		"health": 600.0,
		"radius": 15.0,
		"speed": 0.8,
		"turn_speed": 1.9,
		"turn_accel": 0.2,
		"move_accel": 0.05,
		"move_decel": 0.1,
		"attack_range": 160.0,
		"movement_type": "LAND",
	},
	"heavyHoverTank": {
		"body": "heavy_hover_tank.png",
		"dead": "heavy_hover_tank_dead.png",
		"shadow": "heavy_hover_tank_shadow.png",
		"health": 450.0,
		"radius": 11.0,
		"speed": 0.7,
		"turn_speed": 20.0,
		"move_accel": 0.06,
		"move_decel": 0.09,
		"move_sliding": true,
		"move_ignoring_body": true,
		"attack_range": 160.0,
		"movement_type": "HOVER",
	},
	"dropship": {
		"body": "dropship.png",
		"dead": "dropship_dead.png",
		"shadow": "dropship_shadow.png",
		"health": 500.0,
		"radius": 20.0,
		"speed": 2.3,
		"turn_speed": 1.4,
		"move_accel": 0.03,
		"move_decel": 0.05,
		"attack_range": 140.0,
		"movement_type": "AIR",
	},
	"crystalResource": {
		"body": "crystal.png",
		"hide_on_death": true,
		"team_colored": false,
		"health": 600.0,
		"radius": 11.0,
		"movement_type": "NONE",
	},
	"wall_v": {
		"body": "wall_v.png",
		"hide_on_death": true,
		"health": 700.0,
		"radius": 15.0,
		"building": true,
		"footprint": [0, 0, 0, 0,],
		"movement_type": "NONE",
	},
	"builderShip": {
		"body": "builder_ship.png",
		"dead": "builder_ship_dead.png",
		"turret": "builder_ship_turret.png",
		"health": 500.0,
		"radius": 13.0,
		"speed": 0.8,
		"turn_speed": 1.9,
		"turn_accel": 0.12,
		"move_accel": 0.03,
		"move_decel": 0.1,
		"attack_range": 240.0,
		"movement_type": "WATER",
		"reclaim": true,
		"build_warmup": 30.0,
	},
	"amphibiousJet": {
		"body": "amphibious_jet.png",
		"dead": "amphibious_jet_dead.png",
		"shadow": "amphibious_jet_shadow.png",
		"health": 530.0,
		"radius": 12.0,
		"speed": 1.4,
		"turn_speed": 3.8,
		"turn_accel": 0.3,
		"move_accel": 0.03,
		"move_decel": 0.1,
		"move_sliding": true,
		"move_ignoring_body": true,
		"attack_range": 100.0,
		"movement_type": "AIR",
	},
	"supplyDepot": {
		"body": "supply_depot.png",
		"dead": "supply_depot_dead.png",
		"health": 800.0,
		"radius": 20.0,
		"building": true,
		"movement_type": "NONE",
	},
	"spreadingFire": {
		"body": "fire.png",
		"hide_on_death": true,
		"team_colored": false,
		"health": 100.0,
		"radius": 20.0,
		"movement_type": "NONE",
	},
}

const HIDDEN_TYPES: Array[String] = [
	"fogRevealer",
	"damagingBorder",
	"zoneMarker",
	"editorOrBuilder",
	"dummyNonUnitWithTeam",
]
const HIDDEN_HEALTH: Dictionary = {
	"fogRevealer": 100.0,
	"damagingBorder": 100.0,
	"zoneMarker": 100.0,
	"editorOrBuilder": 170000.0,
	"dummyNonUnitWithTeam": 100.0,
}


## 注册原生单位，并对已由 INI 替换的单位复用相同外观数据
static func register_definitions(registry: RwUnitRegistry, assets: RwVanillaUnitAssets) -> void:
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		if registry.find_definition("vanilla", unit_name) != null:
			continue
		var replacement: String = RwVanillaUnitCatalog.native_replacement(unit_name)
		var spec: Dictionary
		if not replacement.is_empty():
			spec = RwBuiltinUnitSpecs.get_spec(replacement)
		elif SPECS.has(unit_name):
			spec = SPECS[unit_name]
		elif HIDDEN_TYPES.has(unit_name):
			spec = {"body": "", "health": float(HIDDEN_HEALTH.get(unit_name, 1.0)), "radius": 0.0, "movement_type": "NONE", "hidden": true,}
		else:
			push_error("Missing native unit definition: %s" % unit_name)
			continue
		var definition: RwUnitDefinition = RwVanillaCustomDefinitions.create_definition(unit_name, spec, "vanilla")
		if unit_name in ["crystalResource", "spreadingFire",]:
			definition.applies_spawn_rotation = false
			definition.default_body_rotation_degrees = -90.0
			definition.render_rotation_offset_degrees = 90.0
		registry.register_definition(definition, assets)
