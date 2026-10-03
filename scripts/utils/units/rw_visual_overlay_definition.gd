class_name RwVisualOverlayDefinition
extends Resource
## 定义旋翼、光效等独立于主体纹理的视觉挂件

## 纹理目录键
@export var image: String
## 是否套用队伍颜色
@export var team_colored: bool
## 为 true 时层固定在地面而不跟随单位高度
@export var ground_shadow: bool
## 相对于主体或地面中心的位移
@export var offset: Vector2
## 相对于主体的绘制顺序
@export var draw_order: int = 2
## 每同步帧旋转的角度
@export var rotation_speed_degrees: float
## 横向精灵帧数
@export_range(1, 32, 1) var frames: int = 1
## 每帧纹理持续的同步帧数
@export var frame_step_frames: int
## 视觉层不透明度
@export var opacity: float = 1.0
