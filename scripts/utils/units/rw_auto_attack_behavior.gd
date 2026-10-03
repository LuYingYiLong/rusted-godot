class_name RwAutoAttackBehavior
extends RwUnitBehavior
## 使用战斗系统的通用索敌、瞄准和开火行为

## 在每个同步帧推进当前单位的武器
func advance_frame(unit_state: RwUnitState, definition: RwUnitDefinition, context: RwCombatContext) -> void:
	context.advance_weapons(unit_state, definition)
