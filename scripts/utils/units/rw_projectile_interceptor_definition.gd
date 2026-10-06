extends Resource
class_name RwProjectileInterceptorDefinition
## 描述单位自动拦截弹体的筛选条件和发射配置

@export var turret_name: String
@export var projectile_tags: Array[String]
@export var target_ground_under_distance: float = -1.0
@export var projectile_under_distance: float
@export var projectile_over_height: float
@export var muzzle_offset: Vector2
@export var resource_usage: Dictionary
@export var projectile: RwProjectileDefinition
@export var shoot_sound_name: String
@export var shoot_sound_volume: float = 0.3
@export var shoot_flame: String
@export var shoot_light_color: Color = Color.TRANSPARENT
