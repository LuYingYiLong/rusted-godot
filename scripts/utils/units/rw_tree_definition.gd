class_name RwTreeDefinition
extends RwUnitDefinition


func configure_visual(visual: RwUnitVisual, provider: RwUnitAssetProvider, color: Color, spawn: Dictionary) -> void:
	var tree_type: int = 1
	var object_id: int = int(spawn.get("object_id", 1))
	var sub_type: int = RwVanillaRandom.initial_range(0, 4, object_id)
	var variant: String = str(spawn.get("variant", ""))
	if not variant.is_empty():
		var parts: PackedStringArray = variant.split(".")
		if parts[0].is_valid_int():
			tree_type = int(parts[0])
		if parts.size() > 1 and parts[1].is_valid_int():
			sub_type = clampi(int(parts[1]), 0, 4)
	var chosen: RwUnitDefinition = duplicate() as RwUnitDefinition
	if tree_type == 0:
		chosen.body_image = "palm_tree.png"
		chosen.body_region = Rect2i(1, 1, 27, 41)
	else:
		chosen.body_image = "trees_snow.png" if tree_type == 2 else "trees.png"
		chosen.body_region = Rect2i(0, sub_type * 30, 25, 30)
		var scale_maximum: int = 120 if sub_type == 0 else 200
		var tree_scale: float = float(RwVanillaRandom.initial_range(100, scale_maximum, object_id + 1)) / 100.0
		chosen.body_scale = Vector2.ONE * tree_scale
	visual.configure(chosen, provider, color)
