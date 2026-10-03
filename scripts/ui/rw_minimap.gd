class_name RwMinimap
extends TextureRect

signal position_chosen(world_position: Vector2)

const TEXTURE_SIZE: int = 160
const TERRAIN_BRIGHTNESS: float = 200.0 / 255.0
const SAMPLE_COUNT: int = 2

var _world_size: Vector2
var _camera_world_rect: Rect2
var _resource_points: Array[Vector2]
var _unit_states: Dictionary
var _players: Array[Dictionary]
var _local_slot: int = -1
var _fog: RwFogOfWar


func _draw() -> void:
	if texture == null or _world_size == Vector2.ZERO:
		return
	if _fog != null and _fog.minimap_texture != null:
		draw_texture_rect(_fog.minimap_texture, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.39, 0.39, 0.39), false, 1.0)
	for world_position: Vector2 in _resource_points:
		if _fog != null and not _fog.is_visible_at(world_position):
			continue
		var point: Vector2 = _world_to_local(world_position).floor()
		draw_rect(Rect2(point, Vector2(2.0, 2.0)), Color(1.0, 1.0, 1.0, 0.82))
	for unit_state: RwUnitState in _unit_states.values():
		if unit_state.is_dead or unit_state.unit_name == "tree":
			continue
		if _fog != null and not _fog.is_unit_visible(unit_state, _local_slot):
			continue
		var point: Vector2 = _world_to_local(unit_state.world_position).floor()
		var relation: RwUnitTeamColors.Relation = RwUnitTeamColors.relation_for_team(unit_state.team, _players, _local_slot)
		var marker_color: Color = RwUnitTeamColors.for_team(unit_state.team, _players)
		match relation:
			RwUnitTeamColors.Relation.OWN:
				marker_color = Color.GREEN
			RwUnitTeamColors.Relation.ALLY:
				marker_color = Color.YELLOW
			RwUnitTeamColors.Relation.ENEMY:
				marker_color = Color.RED
		draw_rect(Rect2(point - Vector2.ONE, Vector2(3.0, 3.0)), marker_color)
	if _camera_world_rect.has_area():
		var top_left: Vector2 = _world_to_local(_camera_world_rect.position).floor()
		var bottom_right: Vector2 = _world_to_local(_camera_world_rect.end).ceil()
		var frame_size: Vector2 = (bottom_right - top_left).max(Vector2.ONE)
		draw_rect(Rect2(top_left + Vector2(0.5, 0.5), frame_size - Vector2.ONE), Color.WHITE, false, 1.0, false)


func _gui_input(event: InputEvent) -> void:
	if _world_size == Vector2.ZERO or size.x <= 0.0 or size.y <= 0.0:
		return
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			position_chosen.emit(_local_to_world(button_event.position))
			accept_event()
	elif event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event
		if motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			position_chosen.emit(_local_to_world(motion_event.position))
			accept_event()


func _on_resized() -> void:
	queue_redraw()


func configure(map_name: String, world_size: Vector2, unit_states: Dictionary, players: Array[Dictionary], local_slot: int) -> String:
	var document: RwXmlDocument = RwMapCatalog.load_map(map_name)
	if document == null:
		return "Minimap map is not in the catalog"
	var parsed: Dictionary = RwTmxLoader.read_map_data(document)
	if not str(parsed.get("error", "")).is_empty():
		return str(parsed["error"])
	_world_size = world_size
	_unit_states = unit_states
	_players = players
	_local_slot = local_slot
	_resource_points = _find_resource_points(parsed)
	texture = _build_terrain_texture(parsed)
	if texture == null:
		return "Could not render the minimap ground layer"
	queue_redraw()
	return ""


func update_view(camera_position: Vector2, camera_zoom: float, viewport_size: Vector2) -> void:
	if _world_size == Vector2.ZERO:
		return
	var half_view: Vector2 = viewport_size * 0.5 / maxf(camera_zoom, 0.001)
	var new_rect: Rect2 = Rect2(camera_position - half_view, half_view * 2.0)
	new_rect = new_rect.intersection(Rect2(Vector2.ZERO, _world_size))
	if new_rect != _camera_world_rect:
		_camera_world_rect = new_rect
		queue_redraw()


func refresh_units() -> void:
	if texture != null:
		queue_redraw()


func set_fog(fog: RwFogOfWar) -> void:
	_fog = fog
	queue_redraw()


func update_team_view(players: Array[Dictionary], local_slot: int) -> void:
	_players = players
	_local_slot = local_slot
	queue_redraw()


func _world_to_local(world_position: Vector2) -> Vector2:
	return world_position / _world_size * size


func _local_to_world(local_position: Vector2) -> Vector2:
	return (local_position / size * _world_size).clamp(Vector2.ZERO, _world_size)


func _build_terrain_texture(parsed: Dictionary) -> Texture2D:
	var map_size: Vector2i = parsed["size"]
	var ground_gids: PackedInt32Array
	for layer: Dictionary in parsed["layers"]:
		if str(layer.get("name", "")).to_lower() == "ground":
			ground_gids = _decode_gids(layer, map_size)
			break
	if ground_gids.size() != map_size.x * map_size.y:
		return null
	var tilesets: Array[Dictionary] = _load_tileset_images(parsed)
	var tile_sources: Dictionary = {}
	var minimap_image: Image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in TEXTURE_SIZE:
		for x: int in TEXTURE_SIZE:
			var sampled_color: Color = Color(0.0, 0.0, 0.0)
			for sample_y: int in SAMPLE_COUNT:
				for sample_x: int in SAMPLE_COUNT:
					var map_position: Vector2 = Vector2(
						(float(x) + (float(sample_x) + 0.5) / float(SAMPLE_COUNT)) * float(map_size.x) / float(TEXTURE_SIZE),
						(float(y) + (float(sample_y) + 0.5) / float(SAMPLE_COUNT)) * float(map_size.y) / float(TEXTURE_SIZE),
					)
					var cell: Vector2i = Vector2i(map_position.floor()).min(map_size - Vector2i.ONE)
					var gid: int = ground_gids[cell.y * map_size.x + cell.x]
					if not tile_sources.has(gid):
						tile_sources[gid] = _find_tile_source(gid, tilesets)
					sampled_color += _sample_tile(tile_sources[gid], map_position - Vector2(cell))
			var average: Color = sampled_color / float(SAMPLE_COUNT * SAMPLE_COUNT)
			minimap_image.set_pixel(x, y, Color(
				average.r * TERRAIN_BRIGHTNESS,
				average.g * TERRAIN_BRIGHTNESS,
				average.b * TERRAIN_BRIGHTNESS,
			))
	return ImageTexture.create_from_image(minimap_image)


func _load_tileset_images(parsed: Dictionary) -> Array[Dictionary]:
	var tilesets: Array[Dictionary] = []
	var map_tile_size: Vector2i = parsed["tile_size"]
	for tileset: Dictionary in parsed["tilesets"]:
		var texture_name: String = str(tileset.get("image", "")).get_file()
		var source_texture: Texture2D = RwMapCatalog.load_texture(texture_name)
		if source_texture == null:
			continue
		var image: Image = source_texture.get_image()
		if image == null:
			continue
		if image.is_compressed() and image.decompress() != OK:
			continue
		image.convert(Image.FORMAT_RGBA8)
		var tile_size: Vector2i = Vector2i(int(tileset.get("tile_width", map_tile_size.x)), int(tileset.get("tile_height", map_tile_size.y)))
		var margin: int = int(tileset.get("margin", 0))
		var spacing: int = int(tileset.get("spacing", 0))
		var transparent_color: String = str(tileset.get("trans", ""))
		var transparent_key: Color = Color.html("#" + transparent_color) if transparent_color.length() == 6 else Color(-1.0, -1.0, -1.0)
		var columns: int = int(tileset.get("columns", 0))
		if columns <= 0:
			@warning_ignore("integer_division")
			columns = int((image.get_width() - 2 * margin + spacing) / (tile_size.x + spacing))
		if columns <= 0:
			continue
		tilesets.append({
			"firstgid": int(tileset["firstgid"]),
			"image": image,
			"tile_size": tile_size,
			"margin": margin,
			"spacing": spacing,
			"columns": columns,
			"transparent_key": transparent_key,
		})
	return tilesets


func _find_tile_source(gid: int, tilesets: Array[Dictionary]) -> Dictionary:
	for index: int in range(tilesets.size() - 1, -1, -1):
		var tileset: Dictionary = tilesets[index]
		var first_gid: int = int(tileset["firstgid"])
		if gid < first_gid:
			continue
		var tile_id: int = gid - first_gid
		var columns: int = int(tileset["columns"])
		var tile_size: Vector2i = tileset["tile_size"]
		var margin: int = int(tileset["margin"])
		var spacing: int = int(tileset["spacing"])
		var image: Image = tileset["image"]
		@warning_ignore("integer_division")
		var tile_origin: Vector2i = Vector2i(
			margin + (tile_id % columns) * (tile_size.x + spacing),
			margin + int(tile_id / columns) * (tile_size.y + spacing),
		)
		if tile_origin.x + tile_size.x > image.get_width() or tile_origin.y + tile_size.y > image.get_height():
			break
		return {
			"image": image,
			"origin": tile_origin,
			"size": tile_size,
			"transparent_key": tileset["transparent_key"],
		}
	return {}


func _sample_tile(tile_source: Dictionary, tile_position: Vector2) -> Color:
	if tile_source.is_empty():
		return Color.BLACK
	var image: Image = tile_source["image"]
	var origin: Vector2i = tile_source["origin"]
	var tile_size: Vector2i = tile_source["size"]
	var pixel: Vector2i = origin + Vector2i(
		mini(int(tile_position.x * float(tile_size.x)), tile_size.x - 1),
		mini(int(tile_position.y * float(tile_size.y)), tile_size.y - 1),
	)
	var color: Color = image.get_pixelv(pixel)
	var transparent_key: Color = tile_source["transparent_key"]
	if color.r == transparent_key.r and color.g == transparent_key.g and color.b == transparent_key.b:
		return Color.BLACK
	return Color(color.r * color.a, color.g * color.a, color.b * color.a)


func _find_resource_points(parsed: Dictionary) -> Array[Vector2]:
	var map_size: Vector2i = parsed["size"]
	var tile_size: Vector2i = parsed["tile_size"]
	var resource_points: Array[Vector2] = []
	var seen_cells: Dictionary = {}
	var resource_cache: Dictionary = {}
	for layer: Dictionary in parsed["layers"]:
		var gids: PackedInt32Array = _decode_gids(layer, map_size)
		for cell_index: int in gids.size():
			var gid: int = gids[cell_index]
			if gid == 0 or seen_cells.has(cell_index):
				continue
			if not resource_cache.has(gid):
				resource_cache[gid] = _is_resource_tile(gid, parsed["tilesets"])
			if not bool(resource_cache[gid]):
				continue
			seen_cells[cell_index] = true
			@warning_ignore("integer_division")
			var cell: Vector2i = Vector2i(cell_index % map_size.x, int(cell_index / map_size.x))
			resource_points.append((Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(tile_size))
	return resource_points


func _is_resource_tile(gid: int, tilesets: Array) -> bool:
	for index: int in range(tilesets.size() - 1, -1, -1):
		var tileset: Dictionary = tilesets[index]
		var first_gid: int = int(tileset["firstgid"])
		if gid >= first_gid:
			var properties: Dictionary = (tileset.get("unit_tiles", {}) as Dictionary).get(gid - first_gid, {})
			return properties.has("res_pool")
	return false


func _decode_gids(layer: Dictionary, map_size: Vector2i) -> PackedInt32Array:
	var data: PackedByteArray = RwTmxLoader.decode_layer(layer, map_size)
	var gids: PackedInt32Array = PackedInt32Array()
	if data.size() != map_size.x * map_size.y * 4:
		return gids
	gids.resize(map_size.x * map_size.y)
	for index: int in gids.size():
		var offset: int = index * 4
		gids[index] = (data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)) & RwTmxLoader.TILE_GID_MASK
	return gids
