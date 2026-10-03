class_name RwUnitActionItem
extends MarginContainer

signal activated(action_id: String)

@onready var unit_texture: TextureRect = %UnitTexture
@onready var unit_name_label: Label = %UnitNameLabel

var action_id: String


func configure(action: RwUnitActionDefinition, icon: Texture2D) -> void:
	action_id = action.action_id
	unit_name_label.text = action.display_name
	unit_texture.texture = icon


func _on_button_pressed() -> void:
	activated.emit(action_id)
