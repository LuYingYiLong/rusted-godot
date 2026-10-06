extends RwUnitBehavior
class_name RwLaserDefenseBehavior
## 按原版激光防御规则为建筑充能并拦截弹体


## 在每个同步帧推进充能并尝试拦截一枚弹体
func advance_frame(unit_state: RwUnitState, definition: RwUnitDefinition, context: RwCombatContext) -> void:
	context.advance_laser_defense(unit_state, definition)
