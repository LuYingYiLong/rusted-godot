class_name RwResourceDefinition
extends Resource

enum Scope {
	TEAM,
	UNIT,
}

@export var resource_id: String
@export var display_name: String
@export var scope: Scope
@export var display_in_hud: bool = true
@export var display_when_zero: bool
@export var display_position: int
@export var display_rounded_down: bool
@export var icon: Texture2D


static func custom_resource_id(code_name: String, resource_scope: Scope) -> String:
	var prefix: String = "g_" if resource_scope == Scope.TEAM else "l_"
	return prefix + code_name


func format_balance(amount: float) -> String:
	var value: String
	if display_rounded_down:
		value = str(floori(amount))
	elif is_equal_approx(amount, roundf(amount)):
		value = str(roundi(amount))
	else:
		value = str(amount)
	return "%s: %s" % [display_name, value]
