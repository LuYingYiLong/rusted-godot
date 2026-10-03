class_name RwWeaponDefinition
extends Resource
## 描述可开火武器，与仅负责贴图拼接的 RwUnitWeaponDefinition 分离

## 发射的弹体定义
@export var projectile: RwProjectileDefinition
## 自动索敌与开火的最大距离
@export var attack_range: float
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
