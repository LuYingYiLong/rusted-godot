class_name RwUnitBehavior
extends Resource
## 单位行为接口，Resource 实例应保持无状态；逐单位状态由战斗系统保存


## 单位加入战场时调用
func on_spawned(_unit_state: RwUnitState, _definition: RwUnitDefinition, _context: RwCombatContext) -> void:
	pass


## 单位收到同步命令时调用
func on_ordered(
	_unit_state: RwUnitState,
	_definition: RwUnitDefinition,
	_order_type: String,
	_order: Dictionary,
	_context: RwCombatContext
) -> void:
	pass


## 每个同步帧调用一次
func advance_frame(_unit_state: RwUnitState, _definition: RwUnitDefinition, _context: RwCombatContext) -> void:
	pass


## 计算单位实际承受的伤害，可用于护盾或抗性
func filter_damage(_unit_state: RwUnitState, incoming_damage: float, _context: RwCombatContext) -> float:
	return incoming_damage


## 单位生命值减少后调用，参数为实际扣除的生命值
func on_damaged(_unit_state: RwUnitState, _damage: float, _context: RwCombatContext) -> void:
	pass


## 单位首次死亡时调用
func on_destroyed(_unit_state: RwUnitState, _definition: RwUnitDefinition, _context: RwCombatContext) -> void:
	pass
