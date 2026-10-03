class_name RwVanillaUnitDefinitions
extends RefCounted


static func create_registry() -> RwUnitRegistry:
	var registry: RwUnitRegistry = RwUnitRegistry.new()
	var assets: RwVanillaUnitAssets = RwVanillaUnitAssets.new()
	var command_center: RwUnitDefinition = RwUnitDefinition.new()
	command_center.unit_name = "commandCenter"
	command_center.body_image = "base.png"
	command_center.back_image = "base_back.png"
	command_center.dead_image = "base_dead.png"
	command_center.applies_spawn_rotation = false
	command_center.draw_layer = 3
	command_center.dead_draw_layer = 0
	command_center.body_frames = 4
	command_center.max_health = 4000.0
	registry.register_definition(command_center, assets)
	var builder: RwUnitDefinition = RwUnitDefinition.new()
	builder.unit_name = "builder"
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
	registry.register_definition(builder, assets)
	var tank: RwUnitDefinition = RwUnitDefinition.new()
	tank.unit_name = "tank"
	tank.body_image = "tank2.png"
	tank.turret_image = "tank2_turret.png"
	tank.render_rotation_offset_degrees = 90.0
	tank.shadow_image = "tank2_shadow.png"
	tank.dead_image = "tank2_dead.png"
	tank.dead_draw_layer = 0
	tank.body_frames = 3
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
	registry.register_definition(hovercraft, assets)
	var sea_factory: RwUnitDefinition = RwUnitDefinition.new()
	sea_factory.unit_name = "seaFactory"
	sea_factory.body_image = "sea_factory.png"
	sea_factory.dead_image = "sea_factory_dead.png"
	sea_factory.applies_spawn_rotation = false
	sea_factory.dead_draw_layer = 0
	sea_factory.max_health = 1000.0
	registry.register_definition(sea_factory, assets)
	var tree: RwTreeDefinition = RwTreeDefinition.new()
	tree.unit_name = "tree"
	tree.body_image = "trees.png"
	tree.body_team_colored = false
	tree.applies_spawn_rotation = false
	tree.draw_layer = 3
	tree.dead_draw_layer = 0
	tree.max_health = 100.0
	registry.register_definition(tree, assets)
	return registry
