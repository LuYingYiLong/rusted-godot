class_name RwUnitWeaponDefinition
extends Resource

@export var image: String
## 升级后替换的炮塔纹理，键为科技等级
@export var images_by_level: Dictionary
@export var team_colored: bool
@export var mount_offset: Vector2
@export var mount_follows_body: bool = true
@export var sprite_offset: Vector2
@export var sprite_scale: Vector2 = Vector2.ONE
@export var parent_part_index: int = -1
@export var rotation_offset_degrees: float
@export var rotation_state_index: int
@export var aim_follows_body: bool
@export var draw_order: int = 1
## 无目标时每同步帧旋转的角度
@export var idle_spin_degrees: float
## 无目标时相对单位朝向的复位角度
@export var idle_direction_degrees: float
@export var reset_when_idle: bool = true
@export var idle_turn_speed_degrees: float
