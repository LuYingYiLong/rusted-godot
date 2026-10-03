extends Node2D
class_name RwBattleProjectileLayer
## 绘制战斗系统中的弹体；模拟状态由 RwBattleCombat 管理

var _projectiles: Array[RwProjectileState]
var _texture_cache: Dictionary
var _beam_flashes: Array[Dictionary]


func _process(delta: float) -> void:
	if _beam_flashes.is_empty():
		return
	for index: int in range(_beam_flashes.size() - 1, -1, -1):
		_beam_flashes[index]["time"] = float(_beam_flashes[index]["time"]) - delta
		if float(_beam_flashes[index]["time"]) <= 0.0:
			_beam_flashes.remove_at(index)
	queue_redraw()


func _draw() -> void:
	for beam: Dictionary in _beam_flashes:
		var beam_color: Color = beam["color"]
		draw_line(beam["origin"], beam["target"], beam_color, 3.0, false)
	for projectile: RwProjectileState in _projectiles:
		var definition: RwProjectileDefinition = projectile.definition
		if definition == null:
			continue
		if definition.texture_name.is_empty():
			draw_circle(projectile.world_position, definition.visual_radius, definition.visual_color)
			continue
		var texture: Texture2D = _get_texture(definition.texture_name)
		if texture == null:
			draw_circle(projectile.world_position, definition.visual_radius, definition.visual_color)
			continue
		var region: Rect2i = definition.texture_region
		if region.size == Vector2i.ZERO:
			region = Rect2i(Vector2i.ZERO, texture.get_size())
		var size: Vector2 = Vector2(region.size)
		var destination: Rect2 = Rect2(projectile.world_position - size * 0.5, size)
		draw_texture_rect_region(texture, destination, Rect2(region), definition.visual_color)


## 接收当前弹体列表并请求重绘
func set_projectiles(projectiles: Array[RwProjectileState]) -> void:
	_projectiles = projectiles
	queue_redraw()


## 将即时弹体的光束保留一小段可见时间
func show_impact(projectile: RwProjectileState, _target: RwUnitState) -> void:
	if projectile.definition == null or not projectile.definition.instant or not projectile.definition.beam:
		return
	_beam_flashes.append({
		"origin": projectile.origin_position,
		"target": projectile.world_position,
		"color": projectile.definition.visual_color,
		"time": 0.08,
	})
	queue_redraw()


func _get_texture(image_name: String) -> Texture2D:
	if not _texture_cache.has(image_name):
		_texture_cache[image_name] = RwDrawableCatalog.load_texture(image_name)
	return _texture_cache[image_name] as Texture2D
