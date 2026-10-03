class_name RwUnitVisual
extends Node2D
## 根据单位状态绘制主体、阴影、武器和附加视觉层

const STATUS_BAR_HEIGHT: float = 4.0
const STATUS_BAR_GAP: float = 2.0
const FRIENDLY_HEALTH_COLOR: Color = Color(0.0, 150.0 / 255.0, 0.0, 200.0 / 255.0)
const FRIENDLY_HEALTH_BORDER_COLOR: Color = Color(0.0, 200.0 / 255.0, 0.0, 120.0 / 255.0)
const ENEMY_HEALTH_COLOR: Color = Color(183.0 / 255.0, 44.0 / 255.0, 44.0 / 255.0, 200.0 / 255.0)
const ENEMY_HEALTH_BORDER_COLOR: Color = Color(1.0, 60.0 / 255.0, 60.0 / 255.0, 120.0 / 255.0)
const BUILD_PROGRESS_COLOR: Color = Color(0.0, 0.0, 150.0 / 255.0, 200.0 / 255.0)
const BUILD_PROGRESS_BORDER_COLOR: Color = Color(0.0, 0.0, 150.0 / 255.0, 120.0 / 255.0)

var definition: RwUnitDefinition
var team_color: Color
var state: RwUnitState
var selected: bool
var relation: RwUnitTeamColors.Relation = RwUnitTeamColors.Relation.NEUTRAL

var _provider: RwUnitAssetProvider
var _alive_body_texture: Texture2D
var _body_textures_by_level: Dictionary
var _sprite_root: Node2D
var _body_sprite: Sprite2D
var _shadow_sprite: Sprite2D
var _back_sprite: Sprite2D
var _shield_sprite: Sprite2D
var _weapon_mounts: Array[Node2D]
var _weapon_definitions: Array[RwUnitWeaponDefinition]
var _weapon_textures_by_level: Array[Dictionary]
var _leg_sprites: Array[Sprite2D]
var _overlay_sprites: Array[Sprite2D]
var _footprint_tile_size: Vector2i = Vector2i(20, 20)


func configure(unit_definition: RwUnitDefinition, provider: RwUnitAssetProvider, color: Color) -> void:
	definition = unit_definition
	team_color = color
	_provider = provider
	name = unit_definition.unit_name
	visible = not unit_definition.visual_hidden
	var profile: RwUnitVisualProfile = unit_definition.visual_profile
	var shadow_alpha: float = profile.shadow_alpha if profile != null else 0.5
	if not unit_definition.shadow_image.is_empty():
		_shadow_sprite = _make_sprite(provider.load_cached_texture(unit_definition.shadow_image), "Shadow")
		_shadow_sprite.position = unit_definition.shadow_offset
		_shadow_sprite.modulate = Color(0.0, 0.0, 0.0, shadow_alpha) if unit_definition.shadow_is_silhouette else Color(1.0, 1.0, 1.0, shadow_alpha)
		_shadow_sprite.z_index = -2
		add_child(_shadow_sprite)
	elif unit_definition.generates_shadow:
		_shadow_sprite = _make_sprite(provider.load_cached_texture(unit_definition.body_image), "Shadow")
		_shadow_sprite.hframes = unit_definition.body_frames
		_shadow_sprite.position = Vector2(2.0, 2.0)
		_shadow_sprite.modulate = Color(0.0, 0.0, 0.0, shadow_alpha)
		_shadow_sprite.z_index = -2
		add_child(_shadow_sprite)
	_sprite_root = Node2D.new()
	_sprite_root.name = "SpriteRoot"
	add_child(_sprite_root)
	for leg_definition: RwUnitLegDefinition in unit_definition.leg_parts:
		_add_leg_sprites(leg_definition, provider, color)
	if not unit_definition.back_image.is_empty():
		_back_sprite = _make_sprite(provider.load_cached_texture(unit_definition.back_image), "Back")
		_back_sprite.z_index = -1
		_sprite_root.add_child(_back_sprite)
	var body_texture: Texture2D = provider.load_team_texture(unit_definition.body_image, color) if unit_definition.body_team_colored else provider.load_cached_texture(unit_definition.body_image)
	_alive_body_texture = body_texture
	_body_textures_by_level.clear()
	for level: int in unit_definition.body_images_by_level:
		var image_name: String = str(unit_definition.body_images_by_level[level])
		_body_textures_by_level[level] = provider.load_team_texture(image_name, color) if unit_definition.body_team_colored else provider.load_cached_texture(image_name)
	_body_sprite = _make_sprite(body_texture, "Body")
	_body_sprite.hframes = unit_definition.body_frames
	_body_sprite.scale = unit_definition.body_scale
	if unit_definition.body_region.size != Vector2i.ZERO:
		_body_sprite.region_enabled = true
		_body_sprite.region_rect = Rect2(unit_definition.body_region)
	_sprite_root.add_child(_body_sprite)
	_weapon_definitions.clear()
	for weapon_part: RwUnitWeaponDefinition in unit_definition.weapon_parts:
		if weapon_part != null:
			_weapon_definitions.append(weapon_part)
	if _weapon_definitions.is_empty() and not unit_definition.turret_image.is_empty():
		var legacy_weapon: RwUnitWeaponDefinition = RwUnitWeaponDefinition.new()
		legacy_weapon.image = unit_definition.turret_image
		legacy_weapon.team_colored = unit_definition.turret_team_colored
		legacy_weapon.rotation_offset_degrees = unit_definition.render_rotation_offset_degrees
		_weapon_definitions.append(legacy_weapon)
	for index: int in _weapon_definitions.size():
		var weapon: RwUnitWeaponDefinition = _weapon_definitions[index]
		var mount: Node2D = Node2D.new()
		mount.name = "Weapon%d" % index
		mount.z_index = weapon.draw_order
		var weapon_texture: Texture2D = provider.load_team_texture(weapon.image, color) if weapon.team_colored else provider.load_cached_texture(weapon.image)
		var weapon_sprite: Sprite2D = _make_sprite(weapon_texture, "Sprite")
		weapon_sprite.position = weapon.sprite_offset
		weapon_sprite.scale = weapon.sprite_scale
		mount.add_child(weapon_sprite)
		var parent_index: int = weapon.parent_part_index
		if parent_index >= 0 and parent_index < _weapon_mounts.size():
			_weapon_mounts[parent_index].add_child(mount)
		else:
			_sprite_root.add_child(mount)
		_weapon_mounts.append(mount)
		var level_textures: Dictionary
		for level: int in weapon.images_by_level:
			var level_image: String = str(weapon.images_by_level[level])
			level_textures[level] = provider.load_team_texture(level_image, color) if weapon.team_colored else provider.load_cached_texture(level_image)
		_weapon_textures_by_level.append(level_textures)
	if profile != null:
		for index: int in profile.overlays.size():
			var overlay: RwVisualOverlayDefinition = profile.overlays[index]
			if overlay == null:
				continue
			var texture: Texture2D = provider.load_team_texture(overlay.image, color) if overlay.team_colored else provider.load_cached_texture(overlay.image)
			var overlay_sprite: Sprite2D = _make_sprite(texture, "Overlay%d" % index)
			overlay_sprite.position = overlay.offset
			overlay_sprite.z_index = overlay.draw_order
			overlay_sprite.hframes = maxi(overlay.frames, 1)
			overlay_sprite.modulate.a = overlay.opacity
			if overlay.ground_shadow:
				add_child(overlay_sprite)
			else:
				_sprite_root.add_child(overlay_sprite)
			_overlay_sprites.append(overlay_sprite)
		if not profile.shield_image.is_empty():
			_shield_sprite = _make_sprite(provider.load_cached_texture(profile.shield_image), "Shield")
			_shield_sprite.scale = profile.shield_scale
			_shield_sprite.z_index = 5
			_sprite_root.add_child(_shield_sprite)
	if body_texture == null and not unit_definition.visual_hidden:
		configure_placeholder(unit_definition.unit_name, color)


func _add_leg_sprites(leg: RwUnitLegDefinition, provider: RwUnitAssetProvider, color: Color) -> void:
	var z_order: int = 2 if leg.draw_over_body else -2
	if not leg.foot_shadow_image.is_empty():
		var shadow_texture: Texture2D = provider.load_cached_texture(leg.foot_shadow_image)
		if shadow_texture != null:
			var foot_shadow: Sprite2D = _make_sprite(shadow_texture, "FootShadow")
			foot_shadow.position = leg.foot_position + Vector2(2.0, 2.0)
			foot_shadow.modulate = Color(0.0, 0.0, 0.0, 0.4)
			foot_shadow.z_index = -3
			_sprite_root.add_child(foot_shadow)
			_leg_sprites.append(foot_shadow)
	if not leg.leg_image.is_empty():
		var leg_texture: Texture2D = provider.load_team_texture(leg.leg_image, color) if leg.team_colored else provider.load_cached_texture(leg.leg_image)
		if leg_texture != null:
			var leg_sprite: Sprite2D = _make_sprite(leg_texture, "Leg")
			var direction: Vector2 = leg.foot_position - leg.attachment
			leg_sprite.position = (leg.foot_position + leg.attachment) * 0.5
			leg_sprite.rotation = direction.angle() - PI * 0.5
			leg_sprite.scale.y = direction.length() / float(leg_texture.get_height())
			leg_sprite.z_index = z_order
			_sprite_root.add_child(leg_sprite)
			_leg_sprites.append(leg_sprite)
	if not leg.foot_image.is_empty():
		var foot_texture: Texture2D = provider.load_team_texture(leg.foot_image, color) if leg.team_colored else provider.load_cached_texture(leg.foot_image)
		if foot_texture != null:
			var foot_sprite: Sprite2D = _make_sprite(foot_texture, "Foot")
			foot_sprite.position = leg.foot_position
			foot_sprite.z_index = z_order + 1
			_sprite_root.add_child(foot_sprite)
			_leg_sprites.append(foot_sprite)


func bind_state(unit_state: RwUnitState) -> void:
	state = unit_state
	state.state_changed.connect(_on_state_changed)
	_on_state_changed(state)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## 设置地图瓦片尺寸，使建筑选中框与占地范围一致
func set_footprint_tile_size(tile_size: Vector2i) -> void:
	_footprint_tile_size = tile_size
	queue_redraw()


func set_relation(value: RwUnitTeamColors.Relation) -> void:
	relation = value
	queue_redraw()


func get_hit_radius() -> float:
	var body: Sprite2D = _body_sprite
	if body == null or body.texture == null:
		return 10.0
	var body_size: Vector2 = body.get_rect().size * body.scale
	return maxf(body_size.x, body_size.y) * 0.5


func get_icon_texture() -> Texture2D:
	var body: Sprite2D = _body_sprite
	if body == null or body.texture == null:
		return null
	var region: Rect2
	if body.region_enabled:
		region = body.region_rect
	elif body.hframes > 1 or body.vframes > 1:
		var frame_size: Vector2 = Vector2(body.texture.get_size()) / Vector2(body.hframes, body.vframes)
		region = Rect2(Vector2(body.frame_coords) * frame_size, frame_size)
	else:
		return body.texture
	var icon: AtlasTexture = AtlasTexture.new()
	icon.atlas = body.texture
	icon.region = region
	return icon


func configure_placeholder(unit_name: String, color: Color) -> void:
	name = unit_name
	team_color = color
	var title: Label = Label.new()
	title.text = unit_name
	title.position = Vector2(7.0, -11.0)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(title)
	queue_redraw()


func _draw() -> void:
	var body: Sprite2D = _body_sprite
	if body == null or body.texture == null:
		draw_circle(Vector2.ZERO, 5.0, team_color)
		draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color.BLACK)
	if state == null:
		return
	var body_size: Vector2 = body.get_rect().size * body.scale if body != null and body.texture != null else Vector2(16.0, 16.0)
	if selected:
		if definition != null and definition.attack_range > 0.0 and not state.is_dead:
			draw_circle(Vector2.ZERO, definition.attack_range, Color(1.0, 1.0, 1.0, 0.05), false)
			draw_arc(Vector2.ZERO, definition.attack_range, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.45))
		var selection_color: Color = RwUnitTeamColors.relation_color(relation)
		if definition != null and definition.selection_shape == RwUnitDefinition.SelectionShape.RECTANGLE:
			draw_rect(_get_footprint_rect(), selection_color, false)
		else:
			var selection_radius: float = maxf(body_size.x, body_size.y) * 0.5 + 4.0
			draw_arc(Vector2.ZERO, selection_radius, 0.0, TAU, 32, selection_color)
	var progress: float = state.build_progress if state.build_progress < 1.0 else state.production_progress
	if not state.is_dead and (state.health < state.max_health or progress >= 0.0):
		var bar_width: float = maxf(state.collision_radius * 2.0, 20.0)
		var bar_y: float = maxf(body_size.y * 0.5, state.collision_radius) + 5.0 - _get_visual_height()
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		if state.health < state.max_health:
			var health_ratio: float = state.health / state.max_health if state.max_health > 0.0 else 0.0
			var health_color: Color = ENEMY_HEALTH_COLOR if relation == RwUnitTeamColors.Relation.ENEMY else FRIENDLY_HEALTH_COLOR
			var health_border_color: Color = ENEMY_HEALTH_BORDER_COLOR if relation == RwUnitTeamColors.Relation.ENEMY else FRIENDLY_HEALTH_BORDER_COLOR
			_draw_status_bar(Rect2(-bar_width * 0.5, bar_y, bar_width, STATUS_BAR_HEIGHT), health_ratio, health_color, health_border_color)
			bar_y += STATUS_BAR_HEIGHT + STATUS_BAR_GAP
		if progress >= 0.0:
			_draw_status_bar(Rect2(-bar_width * 0.5, bar_y, bar_width, STATUS_BAR_HEIGHT), progress, BUILD_PROGRESS_COLOR, BUILD_PROGRESS_BORDER_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_footprint_rect() -> Rect2:
	var tile_size: Vector2 = Vector2(_footprint_tile_size)
	var minimum: Vector2 = Vector2(definition.structure_footprint_min) - Vector2(0.5, 0.5)
	var tile_count: Vector2 = Vector2(definition.structure_footprint_max - definition.structure_footprint_min + Vector2i.ONE)
	return Rect2(minimum * tile_size, tile_count * tile_size)


func _draw_status_bar(bounds: Rect2, ratio: float, fill_color: Color, border_color: Color) -> void:
	var fill_width: float = bounds.size.x * clampf(ratio, 0.0, 1.0)
	if fill_width > 0.0:
		draw_rect(Rect2(bounds.position, Vector2(fill_width, bounds.size.y)), fill_color)
	draw_rect(bounds, border_color, false, 1.0, false)


func _on_state_changed(unit_state: RwUnitState) -> void:
	position = unit_state.world_position
	var profile: RwUnitVisualProfile = definition.visual_profile if definition != null else null
	var build_tint: Color = Color.WHITE
	if not unit_state.is_dead and unit_state.build_progress < 1.0:
		build_tint = Color(140.0 / 255.0, 1.0, 140.0 / 255.0, (20.0 + unit_state.build_progress * 220.0) / 255.0)
	if profile != null and not unit_state.is_dead and (unit_state.submerged or unit_state.altitude < profile.submerged_below):
		build_tint *= profile.submerged_tint
	var render_rotation_offset: float = definition.render_rotation_offset_degrees if definition != null else 0.0
	rotation_degrees = unit_state.body_rotation_degrees + render_rotation_offset
	if definition != null:
		z_index = definition.dead_draw_layer if unit_state.is_dead and definition.dead_draw_layer >= 0 else definition.draw_layer
	if _sprite_root != null:
		_sprite_root.position = Vector2(0.0, -_get_visual_height()).rotated(-rotation)
		_sprite_root.modulate = build_tint
	var body: Sprite2D = _body_sprite
	if body != null and definition != null:
		body.visible = not unit_state.is_dead or not definition.hide_on_death
		if unit_state.is_dead and not definition.dead_image.is_empty():
			body.texture = _provider.load_cached_texture(definition.dead_image)
			body.hframes = 1
			body.region_enabled = false
		else:
			body.texture = _body_textures_by_level.get(unit_state.tech_level, _alive_body_texture)
			body.hframes = definition.body_frames
			body.region_enabled = definition.body_region.size != Vector2i.ZERO
			body.frame = mini(unit_state.animation_frame, body.hframes - 1)
	for index: int in _weapon_mounts.size():
		var mount: Node2D = _weapon_mounts[index]
		var weapon: RwUnitWeaponDefinition = _weapon_definitions[index]
		mount.visible = not unit_state.is_dead
		mount.position = weapon.mount_offset if weapon.mount_follows_body or weapon.parent_part_index >= 0 else weapon.mount_offset.rotated(-rotation)
		var weapon_angle: float = unit_state.body_rotation_degrees if weapon.aim_follows_body else unit_state.get_weapon_rotation(weapon.rotation_state_index)
		mount.global_rotation_degrees = weapon_angle + weapon.rotation_offset_degrees
		var weapon_sprite: Sprite2D = mount.get_node_or_null("Sprite") as Sprite2D
		if weapon_sprite != null:
			var level_textures: Dictionary = _weapon_textures_by_level[index]
			if level_textures.has(unit_state.tech_level):
				weapon_sprite.texture = level_textures[unit_state.tech_level]
			else:
				weapon_sprite.texture = _provider.load_team_texture(weapon.image, team_color) if weapon.team_colored else _provider.load_cached_texture(weapon.image)
	if _shadow_sprite != null:
		_shadow_sprite.visible = not unit_state.is_dead and not unit_state.submerged and (profile == null or unit_state.altitude >= profile.submerged_below)
	if _back_sprite != null:
		_back_sprite.visible = not unit_state.is_dead
	for leg_sprite: Sprite2D in _leg_sprites:
		leg_sprite.visible = not unit_state.is_dead
	if profile != null:
		var overlay_index: int = 0
		for overlay: RwVisualOverlayDefinition in profile.overlays:
			if overlay == null:
				continue
			var overlay_sprite: Sprite2D = _overlay_sprites[overlay_index]
			overlay_index += 1
			overlay_sprite.visible = not unit_state.is_dead and not unit_state.submerged and unit_state.altitude >= profile.submerged_below
			overlay_sprite.rotation_degrees = float(unit_state.visual_frame) * overlay.rotation_speed_degrees
			if overlay.frames > 1 and overlay.frame_step_frames > 0:
				overlay_sprite.frame = floori(float(unit_state.visual_frame) / float(overlay.frame_step_frames)) % overlay.frames
	if _shield_sprite != null and profile != null:
		_shield_sprite.visible = not unit_state.is_dead and unit_state.max_shield > 0.0 and (unit_state.shield > 0.0 or unit_state.shield_flash_frames > 0)
		var shield_ratio: float = unit_state.shield / unit_state.max_shield if unit_state.max_shield > 0.0 else 0.0
		var flash_alpha: float = float(unit_state.shield_flash_frames) / 12.0
		_shield_sprite.modulate.a = clampf(profile.shield_alpha_at_full * shield_ratio + flash_alpha * 0.45, 0.0, 1.0)
	queue_redraw()


func _get_visual_height() -> float:
	if state == null or state.is_dead:
		return 0.0
	var height: float = state.altitude
	var profile: RwUnitVisualProfile = definition.visual_profile if definition != null else null
	if profile != null and profile.bob_amplitude != 0.0:
		height += sin(deg_to_rad(float(state.visual_frame) * profile.bob_speed_degrees)) * profile.bob_amplitude
	return height


func _make_sprite(texture: Texture2D, sprite_name: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	return sprite
