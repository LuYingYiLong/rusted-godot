extends Resource
class_name RwUnitDefinition
## 统一保存单位的外观、移动、生产和战斗定义

enum SelectionShape {
	CIRCLE,
	RECTANGLE,
}

@export var source_id: String = "vanilla"
@export var unit_name: String
@export var display_name: String
@export_multiline var description: String
@export var body_image: String
@export var visual_hidden: bool
@export var body_images_by_level: Dictionary
## 可复用的高度、护盾和附加层表现配置
@export var visual_profile: RwUnitVisualProfile
@export var back_image: String
@export var turret_image: String
@export var weapon_parts: Array[RwUnitWeaponDefinition]
## 原版状态中包含的炮口角度数量，可多于可见武器挂件
@export var weapon_state_count: int = 1
@export var leg_parts: Array[RwUnitLegDefinition]
## 可开火武器列表，索引不必与绘制挂件相同
@export var combat_weapons: Array[RwWeaponDefinition]
## 每同步帧执行的单位行为，可由原版单位或模组提供
@export var behavior: RwUnitBehavior
@export var shadow_image: String
@export var dead_image: String
@export var hide_on_death: bool
@export var shadow_is_silhouette: bool
@export var body_region: Rect2i
@export var body_scale: Vector2 = Vector2.ONE
@export var render_rotation_offset_degrees: float
@export var applies_spawn_rotation: bool = true
## 地图没有方向时用于模拟原版单位内部朝向
@export var default_body_rotation_degrees: float
## 原生炮塔创建时为炮口指定一次稳定的初始角度
@export var randomize_initial_weapon_rotation: bool
@export var draw_layer: int = 2
@export var dead_draw_layer: int = -1
@export var max_health: float = 1.0
@export var tech_level: int = 1
@export var resource_costs: Dictionary
@export var build_rate_per_frame: float
## 建造或维修开始前的原版武器预热时间
@export var construction_warmup: float
## 非工作状态下每同步步冷却的建造预热量
@export var construction_warmup_decay: float = 4.0
## 护盾最大值，由单位行为负责吸收伤害和恢复
@export var max_shield: float
@export var movement_speed: float
@export var water_movement_speed: float
@export var movement_type: String = "LAND"
@export var turn_speed: float
@export var water_turn_speed: float
@export var turn_acceleration: float
@export var movement_acceleration: float
@export var movement_deceleration: float
## 使用独立速度向量滑行，不将当前移动速度直接绑定机身角
@export var movement_sliding: bool
## 移动方向直接朝向路径点，允许机身转向与位移方向不同
@export var movement_ignores_body: bool
@export var collision_radius: float
## 原版建筑类型额外提供给建造者的施工距离
@export var construction_range_bonus: float
@export var push_mass: float = 3000.0
## 原版软碰撞优先级，数值越大推开速度越慢
@export var soft_collision_on_all: int
## 工厂生产单位时的出生偏移和离厂目标距离
@export var factory_exit_offset: Vector2 = Vector2(0.0, 9.0)
@export var factory_exit_move_away: float = 70.0
@export var blocks_movement: bool
@export var structure_footprint_min: Vector2i
@export var structure_footprint_max: Vector2i
## 放置检查包含工厂出口等预留区域，空矩形时沿用实际占地
@export var construction_footprint: Rect2i
@export var placement_requires_resource_pool: bool
@export var placement_requires_water: bool
@export var attack_range: float
@export var selection_shape: SelectionShape
@export var sight_range: int = 15
@export var can_reclaim: bool
@export var build_actions: Array[RwUnitActionDefinition]
@export_range(1, 32, 1) var body_frames: int = 1
@export var animation_step_frames: int
@export var animation_ping_pong: bool
@export var animation_speed_follows_tech_level: bool
@export var idle_animation_start: int
@export var idle_animation_end: int
@export var idle_animation_step: float
@export var idle_animation_ping_pong: bool
@export var moving_animation_start: int
@export var moving_animation_end: int
@export var moving_animation_step: float
@export var moving_animation_ping_pong: bool
@export var shadow_offset: Vector2
@export var body_team_colored: bool = true
@export var turret_team_colored: bool
@export var generates_shadow: bool


func key() -> String:
	return "%s:%s" % [source_id, unit_name]


## 返回放置时检查的格子范围，实际寻路阻挡仍使用建筑占地
func get_construction_footprint() -> Rect2i:
	if construction_footprint.has_area():
		return construction_footprint
	return Rect2i(structure_footprint_min, structure_footprint_max - structure_footprint_min + Vector2i.ONE)


## 判断单位是否需要按同步帧更新外观动画
func needs_visual_ticks() -> bool:
	return (
		animation_step_frames > 0 and body_frames > 1
		or idle_animation_step > 0.0 and idle_animation_end > idle_animation_start
		or moving_animation_step > 0.0 and moving_animation_end > moving_animation_start
		or visual_profile != null and visual_profile.is_animated()
		or max_shield > 0.0
	)


func configure_visual(visual: RwUnitVisual, provider: RwUnitAssetProvider, color: Color, _spawn: Dictionary) -> void:
	visual.configure(self, provider, color)
