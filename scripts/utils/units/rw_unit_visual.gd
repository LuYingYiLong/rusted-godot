class_name RwUnitVisual
extends Node2D

var definition: RwUnitDefinition
var team_color: Color
var state: RwUnitState
var selected: bool
var relation: RwUnitTeamColors.Relation = RwUnitTeamColors.Relation.NEUTRAL

var _provider: RwUnitAssetProvider
var _alive_body_texture: Texture2D
var _weapon_mounts: Array[Node2D]
var _weapon_definitions: Array[RwUnitWeaponDefinition]


func configure(unit_definition: RwUnitDefinition, provider: RwUnitAssetProvider, color: Color) -> void:
	definition = unit_definition
	team_color = color
	_provider = provider
	name = unit_definition.unit_name
	if not unit_definition.shadow_image.is_empty():
		var shadow: Sprite2D = _make_sprite(provider.load_cached_texture(unit_definition.shadow_image), "Shadow")
		shadow.position = unit_definition.shadow_offset
		shadow.modulate.a = 0.5
		add_child(shadow)
	elif unit_definition.generates_shadow:
		var generated_shadow: Sprite2D = _make_sprite(provider.load_cached_texture(unit_definition.body_image), "Shadow")
		generated_shadow.hframes = unit_definition.body_frames
		generated_shadow.position = Vector2(2.0, 2.0)
		generated_shadow.modulate = Color(0.0, 0.0, 0.0, 0.4)
		add_child(generated_shadow)
	if not unit_definition.back_image.is_empty():
		add_child(_make_sprite(provider.load_cached_texture(unit_definition.back_image), "Back"))
	var body_texture: Texture2D = provider.load_team_texture(unit_definition.body_image, color) if unit_definition.body_team_colored else provider.load_cached_texture(unit_definition.body_image)
	_alive_body_texture = body_texture
	var body: Sprite2D = _make_sprite(body_texture, "Body")
	body.hframes = unit_definition.body_frames
	body.scale = unit_definition.body_scale
	if unit_definition.body_region.size != Vector2i.ZERO:
		body.region_enabled = true
		body.region_rect = Rect2(unit_definition.body_region)
	add_child(body)
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
		mount.add_child(weapon_sprite)
		add_child(mount)
		_weapon_mounts.append(mount)
	if body_texture == null:
		configure_placeholder(unit_definition.unit_name, color)


func bind_state(unit_state: RwUnitState) -> void:
	state = unit_state
	state.state_changed.connect(_on_state_changed)
	_on_state_changed(state)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_relation(value: RwUnitTeamColors.Relation) -> void:
	relation = value
	queue_redraw()


func get_hit_radius() -> float:
	var body: Sprite2D = get_node_or_null("Body") as Sprite2D
	if body == null or body.texture == null:
		return 10.0
	var body_size: Vector2 = body.get_rect().size * body.scale
	return maxf(body_size.x, body_size.y) * 0.5


func get_icon_texture() -> Texture2D:
	var body: Sprite2D = get_node_or_null("Body") as Sprite2D
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
	var body: Sprite2D = get_node_or_null("Body") as Sprite2D
	if body == null or body.texture == null:
		draw_circle(Vector2.ZERO, 5.0, team_color)
		draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color.BLACK, 1.0)
	if state == null:
		return
	var body_size: Vector2 = body.get_rect().size * body.scale if body != null and body.texture != null else Vector2(16.0, 16.0)
	if selected:
		if definition != null and definition.attack_range > 0.0 and not state.is_dead:
			draw_circle(Vector2.ZERO, definition.attack_range, Color(1.0, 1.0, 1.0, 0.05), false)
			draw_arc(Vector2.ZERO, definition.attack_range, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.45), 1.0)
		var selection_color: Color = RwUnitTeamColors.relation_color(relation)
		if definition != null and definition.selection_shape == RwUnitDefinition.SelectionShape.RECTANGLE:
			var half_size: Vector2 = body_size * 0.5 + Vector2(4.0, 4.0)
			draw_rect(Rect2(-half_size, half_size * 2.0), selection_color, false)
		else:
			var selection_radius: float = maxf(body_size.x, body_size.y) * 0.5 + 4.0
			draw_arc(Vector2.ZERO, selection_radius, 0.0, TAU, 32, selection_color)
	if not state.is_dead and state.health < state.max_health:
		var health_ratio: float = state.health / state.max_health if state.max_health > 0.0 else 0.0
		var bar_width: float = clampf(body_size.x, 24.0, 70.0)
		var bar_y: float = maxf(body_size.y * 0.5, 8.0) + 5.0
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 4.0), Color.BLACK)
		draw_rect(Rect2(-bar_width * 0.5 + 1.0, bar_y + 1.0, (bar_width - 2.0) * health_ratio, 2.0), Color.GREEN if health_ratio > 0.5 else Color.ORANGE_RED)


func _on_state_changed(unit_state: RwUnitState) -> void:
	position = unit_state.world_position
	modulate.a = lerpf(0.55, 1.0, unit_state.build_progress)
	var render_rotation_offset: float = definition.render_rotation_offset_degrees if definition != null else 0.0
	rotation_degrees = unit_state.body_rotation_degrees + render_rotation_offset
	if definition != null:
		z_index = definition.dead_draw_layer if unit_state.is_dead and definition.dead_draw_layer >= 0 else definition.draw_layer
	var body: Sprite2D = get_node_or_null("Body") as Sprite2D
	if body != null and definition != null:
		if unit_state.is_dead and not definition.dead_image.is_empty():
			body.texture = _provider.load_cached_texture(definition.dead_image)
			body.hframes = 1
			body.region_enabled = false
		else:
			body.texture = _alive_body_texture
			body.hframes = definition.body_frames
			body.region_enabled = definition.body_region.size != Vector2i.ZERO
			body.frame = mini(unit_state.animation_frame, body.hframes - 1)
	for index: int in _weapon_mounts.size():
		var mount: Node2D = _weapon_mounts[index]
		var weapon: RwUnitWeaponDefinition = _weapon_definitions[index]
		mount.visible = not unit_state.is_dead
		mount.position = weapon.mount_offset if weapon.mount_follows_body else weapon.mount_offset.rotated(-rotation)
		var weapon_angle: float = unit_state.body_rotation_degrees if weapon.aim_follows_body else unit_state.get_weapon_rotation(weapon.rotation_state_index)
		mount.rotation_degrees = weapon_angle + weapon.rotation_offset_degrees - rotation_degrees
	var shadow: Sprite2D = get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		shadow.visible = not unit_state.is_dead
	queue_redraw()


func _make_sprite(texture: Texture2D, sprite_name: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	return sprite
