class_name RwResourceLabel
extends Label

@export var resource_id: String = "credits"
@export var display_rounded_down: bool = true


func _ready() -> void:
	set_values(0.0, 0.0)


func set_values(current_resource: float, resource_growth: float) -> void:
	var growth_sign: String = "+" if resource_growth >= 0.0 else "-"
	text = "%s(%s%s)" % [
		_format_amount(current_resource),
		growth_sign,
		_format_amount(absf(resource_growth)),
	]


func _format_amount(amount: float) -> String:
	if display_rounded_down:
		return str(floori(amount))
	if is_equal_approx(amount, roundf(amount)):
		return str(roundi(amount))
	return str(snappedf(amount, 0.01))
