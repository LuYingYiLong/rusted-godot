class_name RwUnitVisualProfile
extends Resource
## 描述单位高度、悬浮、潜水、护盾和附加视觉层

## 地图或生产生成时的默认高度
@export var spawn_altitude: float
## 只影响绘制的上下起伏幅度
@export var bob_amplitude: float
@export var bob_speed_degrees: float
## 低于此高度时进入潜水外观
@export var submerged_below: float = -1.0
## 潜水时的主体颜色和透明度
@export var submerged_tint: Color = Color(0.7, 0.85, 1.0, 0.55)
## 地面阴影的不透明度
@export var shadow_alpha: float = 0.5
## 护盾外圈纹理的目录键
@export var shield_image: String
## 护盾纹理缩放
@export var shield_scale: Vector2 = Vector2.ONE
## 满护盾时的基础不透明度
@export var shield_alpha_at_full: float = 0.5
## 随同步帧变化的附加视觉层
@export var overlays: Array[RwVisualOverlayDefinition]


## 判断是否需要每同步帧推进视觉时间
func is_animated() -> bool:
	if bob_amplitude != 0.0 and bob_speed_degrees != 0.0:
		return true
	for overlay: RwVisualOverlayDefinition in overlays:
		if overlay != null and (overlay.rotation_speed_degrees != 0.0 or overlay.frame_step_frames > 0):
			return true
	return false
