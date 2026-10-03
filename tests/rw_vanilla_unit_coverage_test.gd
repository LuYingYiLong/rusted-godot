extends SceneTree
## 校验全部原生单位和游戏自带 INI 单位的注册与贴图解析


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: RwUnitRegistry = RwVanillaUnitDefinitions.create_registry()
	var assets: RwVanillaUnitAssets = RwVanillaUnitAssets.new()
	var failures: Array[String]
	for unit_name: String in RwVanillaUnitCatalog.NATIVE_TYPES:
		_check_definition(registry, assets, "vanilla", unit_name, failures)
	for unit_name: String in RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS:
		_check_definition(registry, assets, "custom", unit_name, failures)
	var spider: RwUnitDefinition = registry.find_definition("custom", "experimentalSpider")
	if spider == null or spider.leg_parts.size() != 6 or spider.weapon_parts.size() < 4:
		failures.append("Experimental spider assembly is incomplete")
	var tank: RwUnitDefinition = registry.find_definition("custom", "c_tank")
	if tank == null or tank.body_frames != 3 or tank.moving_animation_end != 2 or tank.weapon_parts.size() != 1:
		failures.append("Tank sprite animation or turret assembly is incomplete")
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RW unit coverage: %d native and %d bundled custom definitions with valid visuals" % [RwVanillaUnitCatalog.NATIVE_TYPES.size(), RwVanillaUnitCatalog.BUILTIN_CUSTOM_UNITS.size()])
	quit(0 if failures.is_empty() else 1)


func _check_definition(registry: RwUnitRegistry, assets: RwVanillaUnitAssets, source_id: String, unit_name: String, failures: Array[String]) -> void:
	var definition: RwUnitDefinition = registry.find_definition(source_id, unit_name)
	if definition == null:
		failures.append("Missing definition: %s:%s" % [source_id, unit_name])
		return
	if definition.visual_hidden:
		return
	var visual: RwUnitVisual = registry.create_visual({"source_id": source_id, "unit_name": unit_name,}, Color.GREEN)
	var body: Sprite2D = visual.get_node_or_null("SpriteRoot/Body") as Sprite2D
	if body == null or body.texture == null:
		failures.append("Visual has no body: %s:%s" % [source_id, unit_name])
	elif body.texture.get_width() % maxi(definition.body_frames, 1) != 0:
		failures.append("Body frames do not divide texture width: %s:%s" % [source_id, unit_name])
	visual.free()
	for image_name: String in [definition.body_image, definition.dead_image, definition.shadow_image, definition.back_image,]:
		if image_name.is_empty():
			continue
		if assets.load_cached_texture(image_name) == null:
			failures.append("Missing texture: %s:%s -> %s" % [source_id, unit_name, image_name])
	for weapon: RwUnitWeaponDefinition in definition.weapon_parts:
		if weapon != null and not weapon.image.is_empty() and assets.load_cached_texture(weapon.image) == null:
			failures.append("Missing weapon texture: %s:%s -> %s" % [source_id, unit_name, weapon.image])
	for leg: RwUnitLegDefinition in definition.leg_parts:
		for image_name: String in [leg.leg_image, leg.foot_image, leg.foot_shadow_image,]:
			if not image_name.is_empty() and assets.load_cached_texture(image_name) == null:
				failures.append("Missing leg texture: %s:%s -> %s" % [source_id, unit_name, image_name])
	if definition.visual_profile != null:
		for overlay: RwVisualOverlayDefinition in definition.visual_profile.overlays:
			if overlay != null and not overlay.image.is_empty() and assets.load_cached_texture(overlay.image) == null:
				failures.append("Missing overlay texture: %s:%s -> %s" % [source_id, unit_name, overlay.image])
