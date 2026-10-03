class_name RwProjectileDefinition
extends Resource
## 描述弹体的伤害、飞行方式和绘制资源

## 命中时对目标造成的基础伤害
@export var damage: float
## 每个同步帧移动的世界距离
@export var speed_per_frame: float
@export var lifetime_frames: int = 60
@export var hit_radius: float = 2.0
@export var splash_radius: float
## 开启后每帧朝仍存活的目标调整飞行方向
@export var homing: bool = true
## 留空时绘制纯色圆形，否则从纹理目录加载贴图
@export var texture_name: String
@export var texture_region: Rect2i
@export var visual_radius: float = 3.0
@export var visual_color: Color = Color.WHITE
