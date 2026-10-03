class_name RwTmxUnitReader
extends RefCounted


static func read_spawns(map_name: String) -> Dictionary:
	var document: RwXmlDocument = RwMapCatalog.load_map(map_name)
	if document == null:
		return {"error": "Map is not in the catalog: %s" % map_name,}
	var parsed: Dictionary = RwTmxLoader.read_map_data(document)
	if not str(parsed.get("error", "")).is_empty():
		return parsed
	var map_size: Vector2i = parsed["size"]
	var tile_size: Vector2i = parsed["tile_size"]
	var spawns: Array[Dictionary] = []
	for layer_info: Dictionary in parsed["layers"]:
		var layer_name: String = str(layer_info.get("name", "")).to_lower()
		if layer_name == "set" or layer_name == "set-disabled":
			continue
		var decoded: PackedByteArray = RwTmxLoader.decode_layer(layer_info, map_size)
		if decoded.size() != map_size.x * map_size.y * 4:
			return {"error": "Invalid unit layer data: %s" % layer_info.get("name", ""),}
		for cell_index: int in map_size.x * map_size.y:
			var offset: int = cell_index * 4
			var gid: int = (decoded[offset] | (decoded[offset + 1] << 8) | (decoded[offset + 2] << 16) | (decoded[offset + 3] << 24)) & RwTmxLoader.TILE_GID_MASK
			if gid == 0:
				continue
			var properties: Dictionary = _properties_for_gid(parsed["tilesets"], gid)
			if not properties.has("unit") and not properties.has("customUnit"):
				continue
			@warning_ignore("integer_division")
			var tile: Vector2i = Vector2i(cell_index % map_size.x, int(cell_index / map_size.x))
			var center: Vector2 = Vector2(tile * tile_size) + Vector2(tile_size) * 0.5
			spawns.append(_spawn_from_properties(properties, center, 0.0))
	for object_info: Dictionary in parsed["objects"]:
		var properties: Dictionary = object_info.get("properties", {})
		if not properties.has("unit") and not properties.has("customUnit"):
			continue
		var object_position: Vector2 = Vector2(float(object_info.get("x", 0.0)), float(object_info.get("y", 0.0)))
		var object_size: Vector2 = Vector2(float(object_info.get("width", 0.0)), float(object_info.get("height", 0.0)))
		var center: Vector2 = object_position + object_size * 0.5
		var rotation_degrees: float
		if object_info.has("rotation"):
			rotation_degrees = float(object_info["rotation"]) - 90.0
		spawns.append(_spawn_from_properties(properties, center, rotation_degrees))
	return {"error": "", "spawns": spawns,}


static func _properties_for_gid(tilesets: Array, gid: int) -> Dictionary:
	for index: int in range(tilesets.size() - 1, -1, -1):
		var tileset: Dictionary = tilesets[index]
		var first_gid: int = int(tileset["firstgid"])
		if gid >= first_gid:
			var unit_tiles: Dictionary = tileset.get("unit_tiles", {})
			return unit_tiles.get(gid - first_gid, {})
	return {}


static func _spawn_from_properties(properties: Dictionary, world_position: Vector2, rotation_degrees: float) -> Dictionary:
	var is_custom: bool = properties.has("customUnit")
	return {
		"source_id": "custom" if is_custom else "vanilla",
		"unit_name": str(properties.get("customUnit" if is_custom else "unit", "")),
		"team": str(properties.get("team", "")),
		"variant": str(properties.get("type", "")),
		"position": world_position,
		"rotation_degrees": rotation_degrees,
	}
