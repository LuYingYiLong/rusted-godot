class_name RwVanillaUnitAssets
extends RwUnitAssetProvider


func load_texture(image_name: String) -> Texture2D:
	return RwDrawableCatalog.load_texture(image_name)
