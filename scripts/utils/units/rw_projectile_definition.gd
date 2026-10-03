class_name RwProjectileDefinition
extends Resource
## 描述弹体的伤害、飞行方式和绘制资源

## 命中时对目标造成的基础伤害
@export var damage: float
## 范围伤害与直接伤害分别结算
@export var splash_damage: float
## 每个同步帧移动的世界距离
@export var speed_per_frame: float
## 目标速度和加速度，用于导弹等逐渐提速的弹体
@export var target_speed_per_frame: float
@export var speed_acceleration_per_frame: float
## 每帧最大转向角；负值表示直接追踪目标
@export var turn_speed_degrees: float = -1.0
@export var lifetime_frames: int = 60
@export var hit_radius: float = 2.0
@export var splash_radius: float
## 原版默认按距爆炸中心的距离衰减范围伤害
@export var area_damage_no_falloff: bool = true
@export var area_radius_from_edge: bool
@export var area_minimum_distance: float
## 立即命中并用于激光等即时弹体
@export var instant: bool
## 立即命中时绘制短暂的光束
@export var beam: bool
## 飞向发射时的地面坐标，而不继续跟踪目标
@export var target_ground: bool
## 范围伤害是否影响友方单位
@export var friendly_fire: bool
## 开启后每帧朝仍存活的目标调整飞行方向
@export var homing: bool = true
## 留空时绘制纯色圆形，否则从纹理目录加载贴图
@export var texture_name: String
@export var texture_region: Rect2i
@export var visual_radius: float = 3.0
@export var visual_color: Color = Color.WHITE
