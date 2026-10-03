class_name RwTmxLoader
extends RefCounted

const MAX_MAP_CELLS: int = 1_000_000
const TILE_GID_MASK: int = 0x1FFFFFFF
const TILE_FLIP_H: int = 0x80000000
const TILE_FLIP_V: int = 0x40000000
const TILE_FLIP_D: int = 0x20000000


static func load_skirmish_map(parent: Node2D, map_name: String) -> Dictionary:
	var file_name: String = map_name.replace("\\", "/").get_file()
	if file_name.is_empty() or not file_name.to_lower().ends_with(".tmx"):
		return {"error": "The room did not provide a stock TMX map name",}
	var map_document: RwXmlDocument = RwMapCatalog.load_map(file_name)
	if map_document == null:
		return {"error": "Map is not in the catalog: %s" % file_name,}
	var parsed: Dictionary = read_map_data(map_document)
	if not str(parsed.get("error", "")).is_empty():
		return parsed
	var map_size: Vector2i = parsed["size"]
	var tile_size: Vector2i = parsed["tile_size"]
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = tile_size
	var tilesets: Array = parsed["tilesets"]
	for tileset_info: Dictionary in tilesets:
		var texture_name: String = str(tileset_info.get("image", "")).get_file()
		var texture: Texture2D = RwMapCatalog.load_texture(texture_name)
		if texture == null:
			return {"error": "Map texture is not in the catalog: %s" % texture_name,}
		var image: Image = texture.get_image()
		if image == null:
			return {"error": "Could not decode map texture: %s" % texture_name,}
		_apply_transparency(image, str(tileset_info.get("trans", "")))
		var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
		atlas.texture = ImageTexture.create_from_image(image)
		atlas.texture_region_size = Vector2i(int(tileset_info.get("tile_width", tile_size.x)), int(tileset_info.get("tile_height", tile_size.y)))
		var margin: int = int(tileset_info.get("margin", 0))
		var spacing: int = int(tileset_info.get("spacing", 0))
		atlas.margins = Vector2i(margin, margin)
		atlas.separation = Vector2i(spacing, spacing)
		var columns: int = int(tileset_info.get("columns", 0))
		if columns <= 0:
			@warning_ignore("integer_division")
			columns = int((image.get_width() - 2 * margin + spacing) / (atlas.texture_region_size.x + spacing))
		if columns <= 0:
			return {"error": "Invalid tileset width: %s" % texture_name,}
		tileset_info["columns"] = columns
		tileset_info["atlas"] = atlas
		tile_set.add_source(atlas, int(tileset_info["firstgid"]))
	var created_tiles: Dictionary
	var rendered_layers: int = 0
	var flipped_tiles: int = 0
	var missing_tiles: int = 0
	for layer_info: Dictionary in parsed["layers"]:
		var layer_name: String = str(layer_info.get("name", ""))
		if str(layer_info.get("visible", "1")) == "0" or layer_name.to_lower() in ["units", "set", "set-disabled", "pathingoverride",]:
			continue
		var layer: TileMapLayer = TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tile_set
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.z_index = rendered_layers
		layer.modulate.a = float(layer_info.get("opacity", 1.0))
		parent.add_child(layer)
		var decoded: PackedByteArray = decode_layer(layer_info, map_size)
		if decoded.size() != map_size.x * map_size.y * 4:
			layer.queue_free()
			return {"error": "Invalid map layer data: %s" % layer_name,}
		for cell_index: int in map_size.x * map_size.y:
			var offset: int = cell_index * 4
			var raw_gid: int = decoded[offset] | (decoded[offset + 1] << 8) | (decoded[offset + 2] << 16) | (decoded[offset + 3] << 24)
			var gid: int = raw_gid & TILE_GID_MASK
			if gid == 0:
				continue
			if raw_gid != gid:
				flipped_tiles += 1
			var tileset_info: Dictionary = _find_tileset(tilesets, gid)
			if tileset_info.is_empty():
				missing_tiles += 1
				continue
			if layer_name.to_lower() == "items" and str(tileset_info.get("image", "")).get_file().to_lower() == "units.png":
				continue
			var first_gid: int = int(tileset_info["firstgid"])
			var local_id: int = gid - first_gid
			var atlas: TileSetAtlasSource = tileset_info["atlas"]
			var columns: int = int(tileset_info["columns"])
			@warning_ignore("integer_division")
			var atlas_coords: Vector2i = Vector2i(local_id % columns, int(local_id / columns))
			var tile_key: String = "%d:%d" % [first_gid, local_id]
			if not created_tiles.has(tile_key):
				if not atlas.has_room_for_tile(atlas_coords, Vector2i.ONE, 1, Vector2i.ZERO, 1):
					missing_tiles += 1
					continue
				atlas.create_tile(atlas_coords)
				created_tiles[tile_key] = true
			var alternative_tile: int = 0
			if raw_gid & TILE_FLIP_H:
				alternative_tile |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if raw_gid & TILE_FLIP_V:
				alternative_tile |= TileSetAtlasSource.TRANSFORM_FLIP_V
			if raw_gid & TILE_FLIP_D:
				alternative_tile |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
			@warning_ignore("integer_division")
			layer.set_cell(Vector2i(cell_index % map_size.x, int(cell_index / map_size.x)), first_gid, atlas_coords, alternative_tile)
		rendered_layers += 1
	return {
		"error": "",
		"size": map_size,
		"tile_size": tile_size,
		"layer_count": rendered_layers,
		"flipped_tiles": flipped_tiles,
		"missing_tiles": missing_tiles,
		"source_path": file_name,
	}


static func read_map_data(document: RwXmlDocument) -> Dictionary:
	var parser: XMLParser = _open_xml_parser(document)
	if parser == null:
		return {"error": "Could not parse the TMX map",}
	var parsed: Dictionary = {
		"error": "",
		"size": Vector2i.ZERO,
		"tile_size": Vector2i.ZERO,
		"tilesets": [],
		"layers": [],
		"objects": [],
	}
	var current_tileset: Dictionary
	var current_layer: Dictionary
	var current_object: Dictionary
	var current_tile_id: int = -1
	var object_group_name: String
	var in_data: bool
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name: String = parser.get_node_name()
				var attributes: Dictionary = _attributes(parser)
				match node_name:
					"map":
						if str(attributes.get("orientation", "")) != "orthogonal":
							return {"error": "Only orthogonal TMX maps are supported",}
						parsed["size"] = Vector2i(int(attributes.get("width", 0)), int(attributes.get("height", 0)))
						parsed["tile_size"] = Vector2i(int(attributes.get("tilewidth", 0)), int(attributes.get("tileheight", 0)))
					"tileset":
						current_tileset = attributes
						current_tileset["unit_tiles"] = {}
						if parser.is_empty():
							var resolved: Dictionary = _resolve_tileset(current_tileset)
							if not str(resolved.get("error", "")).is_empty():
								return resolved
							parsed["tilesets"].append(resolved)
							current_tileset = {}
					"image":
						if not current_tileset.is_empty():
							current_tileset["image"] = attributes.get("source", "")
							current_tileset["trans"] = attributes.get("trans", "")
					"tile":
						if not current_tileset.is_empty():
							current_tile_id = int(attributes.get("id", -1))
					"objectgroup":
						object_group_name = str(attributes.get("name", ""))
					"object":
						current_object = attributes
						current_object["group"] = object_group_name
						current_object["properties"] = {}
					"property":
						var property_name: String = str(attributes.get("name", ""))
						var property_value: String = str(attributes.get("value", ""))
						if not current_object.is_empty():
							current_object["properties"][property_name] = property_value
						elif current_tile_id >= 0:
							var unit_tiles: Dictionary = current_tileset["unit_tiles"]
							if not unit_tiles.has(current_tile_id):
								unit_tiles[current_tile_id] = {}
							unit_tiles[current_tile_id][property_name] = property_value
					"layer":
						current_layer = attributes
						current_layer["data"] = ""
					"data":
						if not current_layer.is_empty():
							current_layer["encoding"] = attributes.get("encoding", "")
							current_layer["compression"] = attributes.get("compression", "")
							in_data = true
			XMLParser.NODE_TEXT:
				if in_data:
					current_layer["data"] += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				match parser.get_node_name():
					"tileset":
						if not current_tileset.is_empty():
							parsed["tilesets"].append(current_tileset)
							current_tileset = {}
							current_tile_id = -1
					"tile":
						current_tile_id = -1
					"object":
						if not current_object.is_empty():
							parsed["objects"].append(current_object)
							current_object = {}
					"objectgroup":
						object_group_name = ""
					"data":
						in_data = false
					"layer":
						parsed["layers"].append(current_layer)
						current_layer = {}
	var map_size: Vector2i = parsed["size"]
	var tile_size: Vector2i = parsed["tile_size"]
	if map_size.x <= 0 or map_size.y <= 0 or map_size.x * map_size.y > MAX_MAP_CELLS or tile_size.x <= 0 or tile_size.y <= 0:
		return {"error": "Invalid TMX map dimensions",}
	return parsed


static func _resolve_tileset(tileset_info: Dictionary) -> Dictionary:
	var source: String = str(tileset_info.get("source", ""))
	if source.is_empty():
		return tileset_info
	var tileset_document: RwXmlDocument = RwMapCatalog.load_tileset(source)
	if tileset_document == null:
		return {"error": "Tileset is not in the catalog: %s" % source,}
	var parser: XMLParser = _open_xml_parser(tileset_document)
	if parser == null:
		return {"error": "Could not parse tileset: %s" % source,}
	var resolved: Dictionary = {"firstgid": tileset_info["firstgid"], "unit_tiles": {},}
	var current_tile_id: int = -1
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var attributes: Dictionary = _attributes(parser)
				match parser.get_node_name():
					"tileset":
						resolved.merge(attributes)
					"image":
						resolved["image"] = attributes.get("source", "")
						resolved["trans"] = attributes.get("trans", "")
					"tile":
						current_tile_id = int(attributes.get("id", -1))
					"property":
						if current_tile_id >= 0:
							var unit_tiles: Dictionary = resolved["unit_tiles"]
							if not unit_tiles.has(current_tile_id):
								unit_tiles[current_tile_id] = {}
							unit_tiles[current_tile_id][str(attributes.get("name", ""))] = str(attributes.get("value", ""))
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "tile":
					current_tile_id = -1
	if str(resolved.get("image", "")).is_empty():
		return {"error": "Tileset has no texture: %s" % source,}
	return resolved


static func _open_xml_parser(document: RwXmlDocument) -> XMLParser:
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(document.xml_text.to_utf8_buffer()) != OK:
		return null
	return parser


static func _attributes(parser: XMLParser) -> Dictionary:
	var attributes: Dictionary
	for index: int in parser.get_attribute_count():
		attributes[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
	return attributes


static func decode_layer(layer_info: Dictionary, map_size: Vector2i) -> PackedByteArray:
	if str(layer_info.get("encoding", "")) != "base64" or str(layer_info.get("compression", "")) != "gzip":
		return PackedByteArray()
	var encoded: String = str(layer_info.get("data", "")).replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
	var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
	return compressed.decompress(map_size.x * map_size.y * 4, FileAccess.COMPRESSION_GZIP)


static func _find_tileset(tilesets: Array, gid: int) -> Dictionary:
	for index: int in range(tilesets.size() - 1, -1, -1):
		var tileset_info: Dictionary = tilesets[index]
		if gid >= int(tileset_info["firstgid"]):
			return tileset_info
	return {}


static func _apply_transparency(image: Image, transparent_color: String) -> void:
	if transparent_color.length() != 6:
		return
	image.convert(Image.FORMAT_RGBA8)
	var key: Color = Color.html("#" + transparent_color)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r == key.r and pixel.g == key.g and pixel.b == key.b:
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
