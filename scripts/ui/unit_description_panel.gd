class_name RwUnitDescriptionPanel
extends PanelContainer

@onready var unit_texture: TextureRect = %UnitTexture
@onready var unit_name_label: Label = %UnitNameLabel
@onready var description_label: Label = %DescriptionLabel


func configure(icon: Texture2D, unit_name: String, description: String) -> void:
	unit_texture.texture = icon
	unit_name_label.text = unit_name
	description_label.text = description
