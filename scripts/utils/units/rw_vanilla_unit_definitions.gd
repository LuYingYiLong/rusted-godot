class_name RwVanillaUnitDefinitions
extends RefCounted


static func create_registry() -> RwUnitRegistry:
	var registry: RwUnitRegistry = RwUnitRegistry.new()
	var assets: RwVanillaUnitAssets = RwVanillaUnitAssets.new()
	var command_center: RwUnitDefinition = RwUnitDefinition.new()
	command_center.unit_name = "commandCenter"
	command_center.display_name = "Command center"
	command_center.description = "Produces builders and generates team income."
	command_center.body_image = "base.png"
	command_center.back_image = "base_back.png"
	command_center.dead_image = "base_dead.png"
	command_center.applies_spawn_rotation = false
	command_center.draw_layer = 3
	command_center.dead_draw_layer = 0
	command_center.body_frames = 4
	command_center.selection_shape = RwUnitDefinition.SelectionShape.RECTANGLE
	command_center.attack_range = 280.0
	command_center.max_health = 4000.0
	command_center.collision_radius = 30.0
	command_center.blocks_movement = true
	command_center.structure_footprint_min = Vector2i(-1, -1)
	command_center.structure_footprint_max = Vector2i(1, 1)
	command_center.sight_range = 20
	var produce_builder: RwUnitActionDefinition = _action("builder", "Builder", "builder.png")
	produce_builder.kind = RwUnitActionDefinition.Kind.QUEUE_UNIT
	produce_builder.network_action_id = "u_builder"
	produce_builder.target_unit_name = "builder"
	produce_builder.resource_costs = {"credits": 500.0,}
	produce_builder.build_rate_per_frame = 0.002
	command_center.build_actions = [
		produce_builder,
	]
	registry.register_definition(command_center, assets)
	var builder: RwUnitDefinition = RwUnitDefinition.new()
	builder.unit_name = "builder"
	builder.display_name = "Builder"
	builder.description = "Constructs buildings and reclaims units."
	builder.body_image = "builder.png"
	builder.dead_image = "builder_dead.png"
	builder.dead_draw_layer = 0
	builder.render_rotation_offset_degrees = 90.0
	builder.generates_shadow = true
	builder.max_health = 170.0
	builder.movement_speed = 0.8
	builder.water_movement_speed = 0.6
	builder.turn_speed = 3.8
	builder.water_turn_speed = 1.7
	builder.turn_acceleration = 0.35
	builder.movement_acceleration = 0.04
	builder.movement_deceleration = 0.1
	builder.collision_radius = 10.0
	builder.can_reclaim = true
	builder.build_actions = [
		_action("extractor", "Extractor", "extractor.png", 4),
		_action("turret", "Turret", "turret_base.png"),
		_action("antiAirTurret", "Anti-air turret", "anti_air_top.png"),
		_action("landFactory", "Land factory", "land_factory.png"),
		_action("airFactory", "Air factory", "air_factory.png", 5),
		_action("seaFactory", "Sea factory", "sea_factory.png"),
		_action("laserDefence", "Laser defence", "laser_defence.png"),
		_action("repairbay", "Repair bay", "repair_bay.png"),
		_action("fabricator", "Fabricator", "power.png", 3),
		_action("experimentalLandFactory", "Experimental factory", "experimental_unit_factory_base.png"),
		_action("NukeLaucher", "Nuke launcher", "nuke_launcher.png"),
		_action("AntiNukeLaucher", "Anti-nuke launcher", "antinuke_launcher.png"),
	]
	for build_action: RwUnitActionDefinition in builder.build_actions:
		RwVanillaBuildings.configure_action(build_action)
	registry.register_definition(builder, assets)
	var tank: RwUnitDefinition = RwUnitDefinition.new()
	tank.unit_name = "tank"
	tank.display_name = "Tank"
	tank.description = "Ground combat unit."
	tank.body_image = "tank2.png"
	var tank_turret: RwUnitWeaponDefinition = RwUnitWeaponDefinition.new()
	tank_turret.image = "tank2_turret.png"
	tank_turret.rotation_offset_degrees = 90.0
	tank.weapon_parts = [tank_turret,]
	tank.render_rotation_offset_degrees = 90.0
	tank.shadow_image = "tank2_shadow.png"
	tank.dead_image = "tank2_dead.png"
	tank.dead_draw_layer = 0
	tank.body_frames = 3
	tank.attack_range = 130.0
	tank.shadow_offset = Vector2(3.0, 3.0)
	tank.max_health = 210.0
	tank.movement_speed = 1.0
	tank.turn_speed = 4.1
	tank.turn_acceleration = 0.25
	tank.movement_acceleration = 0.07
	tank.movement_deceleration = 0.17
	tank.collision_radius = 11.0
	registry.register_definition(tank, assets)
	var hovercraft: RwUnitDefinition = RwUnitDefinition.new()
	hovercraft.unit_name = "hovercraft"
	hovercraft.display_name = "Hovercraft"
	hovercraft.description = "Moves across land and water."
	hovercraft.body_image = "hovercraft.png"
	hovercraft.shadow_image = "hovercraft_shadow.png"
	hovercraft.render_rotation_offset_degrees = 90.0
	hovercraft.dead_image = "hovercraft_dead.png"
	hovercraft.draw_layer = 3
	hovercraft.dead_draw_layer = 0
	hovercraft.max_health = 450.0
	hovercraft.movement_speed = 0.9
	hovercraft.water_movement_speed = 1.2
	hovercraft.movement_type = "HOVER"
	hovercraft.turn_speed = 1.4
	hovercraft.water_turn_speed = 1.8
	hovercraft.turn_acceleration = 0.1
	hovercraft.movement_acceleration = 0.03
	hovercraft.movement_deceleration = 0.05
	hovercraft.collision_radius = 15.0
	hovercraft.push_mass = 12000.0
	registry.register_definition(hovercraft, assets)
	var sea_factory: RwUnitDefinition = RwUnitDefinition.new()
	sea_factory.unit_name = "seaFactory"
	sea_factory.display_name = "Sea factory"
	sea_factory.description = "Produces naval units."
	sea_factory.body_image = "sea_factory.png"
	sea_factory.dead_image = "sea_factory_dead.png"
	sea_factory.applies_spawn_rotation = false
	sea_factory.dead_draw_layer = 0
	sea_factory.selection_shape = RwUnitDefinition.SelectionShape.RECTANGLE
	sea_factory.max_health = 1000.0
	sea_factory.placement_requires_water = true
	sea_factory.collision_radius = 45.0
	sea_factory.blocks_movement = true
	sea_factory.structure_footprint_min = Vector2i(-1, -1)
	sea_factory.structure_footprint_max = Vector2i(1, 2)
	var produce_hovercraft: RwUnitActionDefinition = _action("hovercraft", "Hovercraft", "hovercraft.png")
	produce_hovercraft.kind = RwUnitActionDefinition.Kind.QUEUE_UNIT
	produce_hovercraft.network_action_id = "u_hovercraft"
	produce_hovercraft.target_unit_name = "hovercraft"
	produce_hovercraft.resource_costs = {"credits": 600.0,}
	produce_hovercraft.build_rate_per_frame = 0.003
	sea_factory.build_actions = [
		_action("builderShip", "Builder ship", "builder_ship.png"),
		_action("gunBoat", "Gun boat", "gun_boat.png"),
		_action("missileShip", "Missile ship", "ship.png"),
		produce_hovercraft,
		_action("battleShip", "Battleship", "battle_ship2.png"),
		_action("attackSubmarine", "Attack submarine", "attack_submarine.png"),
	]
	registry.register_definition(sea_factory, assets)
	RwVanillaBuildings.register_definitions(registry, assets)
	var tree: RwTreeDefinition = RwTreeDefinition.new()
	tree.unit_name = "tree"
	tree.display_name = "Tree"
	tree.description = "Map scenery."
	tree.body_image = "trees.png"
	tree.body_team_colored = false
	tree.applies_spawn_rotation = false
	tree.draw_layer = 3
	tree.dead_draw_layer = 0
	tree.max_health = 100.0
	tree.sight_range = 0
	registry.register_definition(tree, assets)
	return registry


static func _action(action_id: String, display_name: String, icon_image: String, icon_frames: int = 1) -> RwUnitActionDefinition:
	var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
	action.action_id = action_id
	action.display_name = display_name
	action.icon_image = icon_image
	action.icon_frames = icon_frames
	return action
