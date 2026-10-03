class_name RwUnitAssetProvider
extends RefCounted

var _texture_cache: Dictionary
var _team_texture_cache: Dictionary


func load_texture(_image_name: String) -> Texture2D:
	return null


func load_team_texture(image_name: String, team_color: Color) -> Texture2D:
	var cache_key: String = "%s:%s" % [image_name, team_color.to_html(false)]
	if _team_texture_cache.has(cache_key):
		return _team_texture_cache[cache_key]
	var texture: Texture2D = load_texture(image_name)
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return texture
	if image.is_compressed():
		if image.decompress() != OK:
			return texture
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a8 == 0 or pixel.r8 != pixel.b8 or pixel.g8 <= pixel.r8:
				continue
			var red: int
			var green: int
			var blue: int
			if pixel.r8 == 0:
				red = (team_color.r8 * pixel.g8) >> 8
				green = (team_color.g8 * pixel.g8) >> 8
				blue = (team_color.b8 * pixel.g8) >> 8
			else:
				var amount: float = float(pixel.g8 - pixel.r8) / 255.0
				red = clampi(int(float(pixel.r8) + float(team_color.r8) * amount), 0, 255)
				green = clampi(int(float(pixel.r8) + float(team_color.g8) * amount), 0, 255)
				blue = clampi(int(float(pixel.r8) + float(team_color.b8) * amount), 0, 255)
			image.set_pixel(x, y, Color8(red, green, blue, pixel.a8))
	var colored: Texture2D = ImageTexture.create_from_image(image)
	_team_texture_cache[cache_key] = colored
	return colored


func load_cached_texture(image_name: String) -> Texture2D:
	if _texture_cache.has(image_name):
		return _texture_cache[image_name]
	var texture: Texture2D = load_texture(image_name)
	_texture_cache[image_name] = texture
	return texture
