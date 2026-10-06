class_name RwCombatContext
extends RefCounted
## 向单位行为暴露战斗操作，避免行为直接依赖地图场景

## 推进单位的通用武器逻辑，具体实现由战斗系统提供
func advance_weapons(_unit_state: RwUnitState, _definition: RwUnitDefinition) -> void:
	pass


## 推进原版激光防御的充能并尝试拦截一枚弹体
func advance_laser_defense(_unit_state: RwUnitState, _definition: RwUnitDefinition) -> void:
	pass


## 根据对象编号查找战场单位
func find_unit(_object_id: int) -> RwUnitState:
	return null


## 向目标单位发射弹体，失败时返回 null
func spawn_projectile(
	_source: RwUnitState,
	_target: RwUnitState,
	_weapon: RwWeaponDefinition,
	_angle_degrees: float
) -> RwProjectileState:
	return null


## 向地面位置发射弹体，可供范围武器和特殊能力使用
func spawn_projectile_at(
	_source: RwUnitState,
	_target_position: Vector2,
	_weapon: RwWeaponDefinition,
	_angle_degrees: float
) -> RwProjectileState:
	return null


## 对指定单位直接造成伤害，可供射线武器使用
func deal_damage(_target: RwUnitState, _amount: float) -> void:
	pass
