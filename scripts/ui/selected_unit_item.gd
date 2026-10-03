class_name RwSelectedUnitItem
extends MarginContainer

signal selected(unit_key: String)

@onready var unit_texture: TextureRect = %UnitTexture
@onready var unit_name_label: Label = %UnitNameLabel

var unit_key: String


func configure(key: String, unit_name: String, selected_unit_total: int, icon: Texture2D) -> void:
	unit_key = key
	unit_name_label.text = "%s(x%d)" % [unit_name, selected_unit_total]
	unit_texture.texture = icon


func set_focused(focused: bool) -> void:
	($Button as Button).button_pressed = focused


func _on_button_pressed() -> void:
	selected.emit(unit_key)
