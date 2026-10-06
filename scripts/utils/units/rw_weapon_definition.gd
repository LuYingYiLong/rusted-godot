class_name RwWeaponDefinition
extends Resource
## 描述可开火武器，与仅负责贴图拼接的 RwUnitWeaponDefinition 分离

## 发射的弹体定义
@export var projectile: RwProjectileDefinition
## 锁定空中目标时使用的弹体
@export var air_projectile: RwProjectileDefinition
## 锁定水下目标时使用的弹体
@export var submerged_projectile: RwProjectileDefinition
## 自动索敌与开火的最大距离
@export var attack_range: float
## 单位处于水面状态时的射程；小于零时使用通用射程
@export var surface_attack_range: float = -1.0
## 单位处于水下状态时的射程；小于零时使用通用射程
@export var submerged_attack_range: float = -1.0
@export var minimum_range: float
@export var reload_frames: int = 60
## 首次锁定目标后的预热同步帧数
@export var warmup_frames: int
## 每个同步帧可旋转的角度；零表示立即对准目标
@export var turn_speed_degrees: float
@export var aim_tolerance_degrees: float = 5.0
@export var rotation_state_index: int
## 炮口基点相对单位中心的偏移，随单位主体方向旋转
@export var muzzle_offset: Vector2
@export var muzzle_distance: float
@export var can_target_ground: bool = true
@export var can_target_water: bool
@export var can_target_air: bool
@export var can_target_air_when_submerged: bool = true
## 原版炮塔开火时播放的音效 ID
@export var shoot_sound_name: String
## 原版炮塔开火音效的线性音量
@export var shoot_sound_volume: float = 0.3
## 原版炮塔开火时生成的火焰与自定义特效列表
@export var shoot_flame: String
## 原版炮塔开火时的闪光颜色
@export var shoot_light_color: Color = Color.TRANSPARENT


## 按目标移动类型返回本次射击使用的弹体
func attack_range_for_source(is_submerged: bool) -> float:
	if is_submerged and submerged_attack_range >= 0.0:
		return submerged_attack_range
	if not is_submerged and surface_attack_range >= 0.0:
		return surface_attack_range
	return attack_range


func projectile_for_target(target: RwUnitState) -> RwProjectileDefinition:
	if target != null and target.movement_type == "AIR" and air_projectile != null:
		return air_projectile
	if target != null and target.submerged and submerged_projectile != null:
		return submerged_projectile
	return projectile
