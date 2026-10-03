class_name RwUnitVisual
extends Node2D

var definition: RwUnitDefinition
var team_color: Color
var state: RwUnitState
var selected: bool
var relation: RwUnitTeamColors.Relation = RwUnitTeamColors.Relation.NEUTRAL

var _provider: RwUnitAssetProvider
var _alive_body_texture: Texture2D


func configure(unit_definition: RwUnitDefinition, provider: RwUnitAssetProvider, color: Color) -> void:
	definition = unit_definition
	team_color = color
	_provider = provider
	name = unit_definition.unit_name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if not unit_definition.turret_image.is_empty():
		var turret_texture: Texture2D = provider.load_team_texture(unit_definition.turret_image, color) if unit_definition.turret_team_colored else provider.load_cached_texture(unit_definition.turret_image)
		add_child(_make_sprite(turret_texture, "Turret"))
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
		var selection_radius: float = maxf(body_size.x, body_size.y) * 0.5 + 4.0
		draw_arc(Vector2.ZERO, selection_radius, 0.0, TAU, 32, RwUnitTeamColors.relation_color(relation), 1.5)
	if not state.is_dead and state.health < state.max_health:
		var health_ratio: float = state.health / state.max_health if state.max_health > 0.0 else 0.0
		var bar_width: float = clampf(body_size.x, 24.0, 70.0)
		var bar_y: float = maxf(body_size.y * 0.5, 8.0) + 5.0
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 4.0), Color.BLACK)
		draw_rect(Rect2(-bar_width * 0.5 + 1.0, bar_y + 1.0, (bar_width - 2.0) * health_ratio, 2.0), Color.GREEN if health_ratio > 0.5 else Color.ORANGE_RED)


func _on_state_changed(unit_state: RwUnitState) -> void:
	position = unit_state.world_position
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
	var turret: Sprite2D = get_node_or_null("Turret") as Sprite2D
	if turret != null:
		turret.visible = not unit_state.is_dead
		turret.rotation_degrees = unit_state.turret_rotation_degrees
	var shadow: Sprite2D = get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		shadow.visible = not unit_state.is_dead
	queue_redraw()


func _make_sprite(texture: Texture2D, sprite_name: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	return sprite
