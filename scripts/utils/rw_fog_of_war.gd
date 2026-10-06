class_name RwFogOfWar
extends RefCounted

enum Mode {
	NO_FOG,
	BASIC_FOG,
	LOS_FOG,
}

const EXPLORED_FOG_ALPHA: float = 125.0 / 255.0
const REVEALED_SHROUD_ALPHA: float = 1.0 - (1.0 - EXPLORED_FOG_ALPHA) * (1.0 - 175.0 / 255.0)

var mode: Mode
var map_size: Vector2i
var tile_size: Vector2i
var revealed_map: bool
var texture: Texture2D
var minimap_texture: Texture2D

var _cells: PackedByteArray
var _working_cells: PackedByteArray
var _temporary_reveals: Array[Dictionary]


func configure(size_in_tiles: Vector2i, world_tile_size: Vector2i, fog_mode: int, is_map_revealed: bool) -> void:
	map_size = size_in_tiles
	tile_size = world_tile_size
	mode = clampi(fog_mode, Mode.NO_FOG, Mode.LOS_FOG) as Mode
	revealed_map = is_map_revealed
	_temporary_reveals.clear()
	_cells.resize(map_size.x * map_size.y)
	_cells.fill(10)
	_rebuild_textures()


func update_visibility(unit_states: Dictionary, players: Array[Dictionary], local_slot: int) -> bool:
	if mode == Mode.NO_FOG or local_slot < 0:
		return false
	_working_cells = _cells.duplicate()
	if mode == Mode.LOS_FOG:
		for index: int in _working_cells.size():
			if _working_cells[index] < 5:
				_working_cells[index] = 5
	for unit_state: RwUnitState in unit_states.values():
		if unit_state.is_dead or unit_state.sight_range <= 0:
			continue
		var relation: RwUnitTeamColors.Relation = RwUnitTeamColors.relation_for_team(
			unit_state.team, players, local_slot
		)
		if relation == RwUnitTeamColors.Relation.OWN or relation == RwUnitTeamColors.Relation.ALLY:
			_reveal_circle(unit_state.world_position, unit_state.sight_range)
	for reveal: Dictionary in _temporary_reveals:
		var reveal_relation: RwUnitTeamColors.Relation = RwUnitTeamColors.relation_for_team(
			str(reveal["team"]), players, local_slot
		)
		if reveal_relation == RwUnitTeamColors.Relation.OWN or reveal_relation == RwUnitTeamColors.Relation.ALLY:
			_reveal_circle(reveal["position"], int(reveal["sight_range"]))
	if _working_cells == _cells:
		return false
	_cells = _working_cells
	_rebuild_textures()
	return true


func is_visible_at(world_position: Vector2) -> bool:
	if mode == Mode.NO_FOG:
		return true
	var cell: Vector2i = Vector2i((world_position / Vector2(tile_size)).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return false
	return _cells[cell.y * map_size.x + cell.x] < 5


## 添加持续指定同步帧的原版弹药视野源
func add_temporary_reveal(world_position: Vector2, team: String, sight_range: int, duration_frames: float) -> void:
	if duration_frames <= 0.0 or sight_range <= 0:
		return
	_temporary_reveals.append({
		"position": world_position,
		"team": team,
		"sight_range": sight_range,
		"remaining_frames": duration_frames,
	})


## 按同步步长推进弹药视野源的生命周期
func advance_temporary_reveals(simulation_delta: float) -> void:
	var step: float = maxf(simulation_delta, 0.0)
	for index: int in range(_temporary_reveals.size() - 1, -1, -1):
		var reveal: Dictionary = _temporary_reveals[index]
		reveal["remaining_frames"] = float(reveal["remaining_frames"]) - step
		if float(reveal["remaining_frames"]) <= 0.0:
			_temporary_reveals.remove_at(index)


func is_unit_visible(unit_state: RwUnitState, local_slot: int) -> bool:
	return mode == Mode.NO_FOG or unit_state.team == str(local_slot) or is_visible_at(unit_state.world_position)


func _reveal_circle(world_position: Vector2, radius: int) -> void:
	var center: Vector2 = world_position / Vector2(tile_size)
	var inner_radius: float = float(maxi(radius - 3, 0))
	var inner_squared: float = inner_radius * inner_radius
	var outer_squared: float = float(radius * radius)
	var gradient_range: float = maxf(outer_squared - inner_squared, 1.0)
	var start_x: int = maxi(int(floorf(center.x)) - radius + 1, 0)
	var start_y: int = maxi(int(floorf(center.y)) - radius + 1, 0)
	var end_x: int = mini(int(floorf(center.x)) + radius - 1, map_size.x - 1)
	var end_y: int = mini(int(floorf(center.y)) + radius - 1, map_size.y - 1)
	for y: int in range(start_y, end_y + 1):
		for x: int in range(start_x, end_x + 1):
			var distance_squared: float = center.distance_squared_to(Vector2(float(x), float(y)))
			if distance_squared > outer_squared:
				continue
			var fog_value: int = 0
			if distance_squared > inner_squared:
				fog_value = clampi(int((distance_squared - inner_squared) * 10.0 / gradient_range), 0, 10)
			var index: int = y * map_size.x + x
			if fog_value < _working_cells[index]:
				_working_cells[index] = fog_value


func _rebuild_textures() -> void:
	if mode == Mode.NO_FOG:
		texture = null
		minimap_texture = null
		return
	var world_image: Image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	var minimap_image: Image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	for y: int in map_size.y:
		for x: int in map_size.x:
			var fog_value: int = _cells[y * map_size.x + x]
			var world_alpha: float = float(fog_value) * 25.0 / 255.0
			var minimap_alpha: float = EXPLORED_FOG_ALPHA
			if fog_value == 0:
				minimap_alpha = 0.0
			elif fog_value == 10:
				world_alpha = REVEALED_SHROUD_ALPHA if revealed_map else 1.0
				minimap_alpha = world_alpha
			world_image.set_pixel(x, y, Color(0.0, 0.0, 0.0, world_alpha))
			minimap_image.set_pixel(x, y, Color(0.0, 0.0, 0.0, minimap_alpha))
	texture = ImageTexture.create_from_image(world_image)
	minimap_texture = ImageTexture.create_from_image(minimap_image)
