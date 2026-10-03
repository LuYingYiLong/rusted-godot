class_name RwShieldBehavior
extends RwUnitBehavior
## 先由护盾吸收伤害，并在同步帧中恢复护盾

## 每同步帧恢复的护盾值
@export var regeneration_per_frame: float = 0.25


func advance_frame(unit_state: RwUnitState, definition: RwUnitDefinition, context: RwCombatContext) -> void:
	if unit_state.shield < unit_state.max_shield:
		unit_state.set_shield(unit_state.shield + regeneration_per_frame)
	if not definition.combat_weapons.is_empty():
		context.advance_weapons(unit_state, definition)


func filter_damage(unit_state: RwUnitState, incoming_damage: float, _context: RwCombatContext) -> float:
	var absorbed: float = minf(unit_state.shield, incoming_damage)
	if absorbed > 0.0:
		unit_state.set_shield(unit_state.shield - absorbed)
	return incoming_damage - absorbed
