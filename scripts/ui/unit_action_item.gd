class_name RwUnitActionItem
extends MarginContainer

signal activated(action_id: String)
signal hovered(item: RwUnitActionItem)
signal unhovered(item: RwUnitActionItem)

@onready var unit_texture: TextureRect = %UnitTexture
@onready var unit_name_label: Label = %UnitNameLabel

var action_id: String
var action_definition: RwUnitActionDefinition


func configure(action: RwUnitActionDefinition, icon: Texture2D) -> void:
	action_definition = action
	action_id = action.action_id
	unit_name_label.text = action.display_name
	unit_texture.texture = icon


func _on_button_pressed() -> void:
	activated.emit(action_id)


func _on_button_mouse_entered() -> void:
	hovered.emit(self)


func _on_button_mouse_exited() -> void:
	unhovered.emit(self)
