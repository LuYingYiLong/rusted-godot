class_name RwBattleVfxLayer
extends Node2D

const BUILD_BEAM_COUNT: int = 6
const BUILD_BEAM_COLOR: Color = Color(0.0, 1.0, 0.0, 40.0 / 255.0)
const BUILD_CONTACT_COLOR: Color = Color(1.0, 1.0, 1.0, 60.0 / 255.0)

var _builder_beams: Dictionary
var _frame: int
var _charge_texture: Texture2D


func _ready() -> void:
	_charge_texture = RwDrawableCatalog.load_texture("builder_charge.png")


func _draw() -> void:
	for builder_id: int in _builder_beams:
		var beam: Dictionary = _builder_beams[builder_id]
		var origin: Vector2 = beam["origin"]
		var target: Vector2 = beam["target"]
		var radius: float = float(beam["radius"]) * 0.75
		for point_index: int in BUILD_BEAM_COUNT:
			var phase: float = float(_frame) * 0.07 + float(builder_id % 1024) * 0.71 + float(point_index) * 2.39
			var offset: Vector2 = Vector2(sin(phase * 1.41), cos(phase * 1.73)) * radius
			var endpoint: Vector2 = target + offset
			draw_line(origin + offset * 0.15, endpoint, BUILD_BEAM_COLOR, 2.0, false)
			_draw_charge(endpoint, 0.5, BUILD_CONTACT_COLOR)
		_draw_charge(origin, 0.6, Color(1.0, 1.0, 1.0, 0.7))


func set_builder_beams(beams: Dictionary, frame: int) -> void:
	_builder_beams = beams.duplicate(true)
	_frame = frame
	queue_redraw()


func get_builder_beam_count() -> int:
	return _builder_beams.size()


func _draw_charge(point: Vector2, scale_factor: float, tint: Color) -> void:
	if _charge_texture == null:
		return
	var size: Vector2 = Vector2(_charge_texture.get_size()) * scale_factor
	draw_texture_rect(_charge_texture, Rect2(point - size * 0.5, size), false, tint)
