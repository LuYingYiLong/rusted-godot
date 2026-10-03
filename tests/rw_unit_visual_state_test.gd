extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var helicopter: Dictionary = _create_unit(registry, "helicopter", 1)
	var helicopter_state: RwUnitState = helicopter["state"]
	var helicopter_visual: RwUnitVisual = helicopter["visual"]
	var airborne_body: Node2D = helicopter_visual.get_node("SpriteRoot") as Node2D
	var rotor: Sprite2D = helicopter_visual.get_node("SpriteRoot/Overlay0") as Sprite2D
	var ground_shadow: Sprite2D = helicopter_visual.get_node("Shadow") as Sprite2D
	assert(helicopter_state.altitude == 20.0)
	assert(ground_shadow.global_position.y == helicopter_visual.global_position.y)
	assert(is_equal_approx(airborne_body.global_position.y, helicopter_visual.global_position.y - 20.0))
	helicopter_state.advance_visual_animation(2)
	assert(is_equal_approx(rotor.rotation_degrees, 70.0))
	assert(airborne_body.global_position.y < helicopter_visual.global_position.y - 20.0)
	helicopter_state.apply_snapshot({"is_dead": true,})
	assert(not rotor.visible and not ground_shadow.visible)
	assert(airborne_body.position == Vector2.ZERO)
	var hovercraft: Dictionary = _create_unit(registry, "hovercraft", 5)
	var hover_state: RwUnitState = hovercraft["state"]
	var hover_visual: RwUnitVisual = hovercraft["visual"]
	var hover_body: Node2D = hover_visual.get_node("SpriteRoot") as Node2D
	assert(hover_state.altitude == 3.0)
	hover_state.advance_visual_animation(20)
	assert(hover_body.global_position.y < hover_visual.global_position.y - 3.0)
	var submarine: Dictionary = _create_unit(registry, "attackSubmarine", 2)
	var submarine_state: RwUnitState = submarine["state"]
	var submarine_visual: RwUnitVisual = submarine["visual"]
	var submarine_sprites: Node2D = submarine_visual.get_node("SpriteRoot") as Node2D
	assert(submarine_state.submerged)
	assert(submarine_sprites.modulate.a < 1.0)
	submarine_state.apply_snapshot({"altitude": 0.0,})
	assert(not submarine_state.submerged)
	assert(is_equal_approx(submarine_sprites.modulate.a, 1.0))
	var shield_unit: Dictionary = _create_unit(registry, "experimentalHoverTank", 3)
	var shield_state: RwUnitState = shield_unit["state"]
	var shield_visual: RwUnitVisual = shield_unit["visual"]
	var shield_sprite: Sprite2D = shield_visual.get_node("SpriteRoot/Shield") as Sprite2D
	assert(shield_sprite.visible and shield_state.shield == 5000.0)
	var original_alpha: float = shield_sprite.modulate.a
	shield_state.set_shield(4000.0)
	assert(shield_sprite.modulate.a > original_alpha)
	shield_state.advance_visual_animation(12)
	assert(shield_state.shield_flash_frames == 0)
	assert(shield_sprite.modulate.a < original_alpha)
	var shield_behavior: RwShieldBehavior = registry.find_definition("vanilla", "experimentalHoverTank").behavior as RwShieldBehavior
	assert(shield_behavior.filter_damage(shield_state, 1000.0, null) == 0.0)
	assert(shield_state.shield == 3000.0)
	shield_behavior.advance_frame(shield_state, registry.find_definition("vanilla", "experimentalHoverTank"), null)
	assert(shield_state.shield > 3000.0)
	shield_state.set_shield(0.0)
	assert(shield_sprite.visible)
	shield_state.advance_visual_animation(12)
	assert(not shield_sprite.visible)
	var turret_unit: Dictionary = _create_unit(registry, "turret", 4)
	var turret_state: RwUnitState = turret_unit["state"]
	var turret_visual: RwUnitVisual = turret_unit["visual"]
	var turret_sprite: Sprite2D = turret_visual.get_node("SpriteRoot/Weapon0/Sprite") as Sprite2D
	var first_texture: Texture2D = turret_sprite.texture
	turret_state.apply_snapshot({"tech_level": 2,})
	assert(turret_sprite.texture != first_texture)
	print("VISUAL_STATE_CHECK_OK")
	quit()


func _create_unit(registry: RwUnitRegistry, unit_name: String, object_id: int) -> Dictionary:
	var spawn: Dictionary = {
		"object_id": object_id,
		"source_id": "vanilla",
		"unit_name": unit_name,
		"team": "1",
		"position": Vector2(100.0, 100.0),
	}
	var definition: RwUnitDefinition = registry.find_definition("vanilla", unit_name)
	assert(definition != null)
	var visual: RwUnitVisual = registry.create_visual(spawn, Color.GREEN)
	var unit_state: RwUnitState = RwUnitState.new()
	unit_state.initialize_from_spawn(spawn, definition)
	root.add_child(visual)
	visual.bind_state(unit_state)
	return {"state": unit_state, "visual": visual,}
