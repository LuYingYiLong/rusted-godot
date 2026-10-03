class_name RwVanillaUnitAssets
extends RwUnitAssetProvider


func load_texture(image_name: String) -> Texture2D:
	if image_name.begins_with("builtin:"):
		return RwBuiltinUnitImageCatalog.load_texture(image_name.trim_prefix("builtin:"))
	return RwDrawableCatalog.load_texture(image_name)
