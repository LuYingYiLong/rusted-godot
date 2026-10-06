class_name RwProjectileDefinition
extends Resource
## 描述弹体的伤害、飞行方式和绘制资源

## 命中时对目标造成的基础伤害
@export var damage: float
## 原版激光防御拦截弹体所需的命中次数；小于 0.5 时不可被拦截
@export var deflection_power: float = 1.0
## 原版弹药是否跳过发射单位的 shootDamageMultiplier
@export var ignore_parent_shoot_damage_multiplier: bool
## 原版弹体渲染类别：0 为默认图集，1 为大型图集，2 为第二图集
@export var draw_type: int
## 原版弹体阴影使用的图集帧，-1 表示不绘制
@export var shadow_frame: int = -1
## 原版弹体是否隐藏自身图像
@export var invisible: bool
## 原版弹体是否绘制在单位下方
@export var draw_under_units: bool
## 原版命中时是否触发大型爆炸表现
@export var large_hit_effect: bool
## 原版核弹弹体使用专属命中表现并绕过普通雾中可见性检查
@export var nuke_weapon: bool
## 原版弹体是否在雾中始终可见
@export var always_visible_in_fog: bool
## 原版弹体移动时是否揭示战争迷雾
@export var should_reveal_fog: bool
## 原版命中时是否播放默认命中音效
@export var hit_sound: bool = true
## 原版命中时是否生成火焰武器特效
@export var flame_weapon: bool
## 原版弹体命中时播放的自定义爆炸效果名称
@export var explode_effect: String
## 原版弹体命中护盾时播放的自定义效果名称
@export var explode_effect_on_shield: String
## 原版弹体生成时播放的自定义效果名称
@export var effect_on_create: String
## 此弹药所属单位声明的原版自定义特效定义
@export var effect_profiles: Dictionary
## 用于查找单位自定义特效的内置单位名
@export var effect_owner_name: String
## 原版弹体命中后是否将发射单位传送到命中位置
@export var teleport_source: bool
## 原版弹体命中后是否将目标转换到发射单位阵营
@export var convert_hit_to_source_team: bool
## 原版弹体贴图按单位配置文件路径索引的资源键
@export var shadow_texture_name: String
## 原版光束主图、起点图和终点图资源键
@export var beam_texture_name: String
@export var beam_start_texture_name: String
@export var beam_end_texture_name: String
## 原版光束纹理偏移速度
@export var beam_image_offset_rate: float
@export var beam_start_rotated: bool
@export var beam_end_rotated: bool
## 原版弹体颜色中来源颜色和队伍颜色的混合比例
@export var team_color_ratio: float
@export var team_color_source_ratio: float = 1.0
## 原版弹体标签，用于防空拦截筛选
@export var tags: Array[String]
## 拦截命中时只将目标弹体的剩余寿命归零
@export var intercept_projectile_remove_target_life_only: bool
## 范围伤害与直接伤害分别结算
@export var splash_damage: float
## 每个同步帧移动的世界距离
@export var speed_per_frame: float
## 目标速度和加速度，用于导弹等逐渐提速的弹体
@export var target_speed_per_frame: float
@export var speed_acceleration_per_frame: float
## 每帧最大转向角；负值表示直接追踪目标
@export var turn_speed_degrees: float = -1.0
## 距目标 15 世界单位内使用的转向速度
@export var turn_speed_near_degrees: float = -1.0
@export var lifetime_frames: int = 60
@export var hit_radius: float = 2.0
@export var splash_radius: float
## 原版默认按距爆炸中心的距离衰减范围伤害
@export var area_damage_no_falloff: bool
@export var area_radius_from_edge: bool
@export var area_minimum_distance: float
## 范围伤害是否同时命中空中与地面单位
@export var area_hit_air_and_land_at_same_time: bool
## 范围伤害是否始终命中水下单位
@export var area_hit_underwater_always: bool
## 立即命中并用于激光等即时弹体
@export var instant: bool
## 立即命中时绘制短暂的光束
@export var beam: bool
## 使用抖动射线绘制瞬发攻击
@export var render_jitter: bool
## 飞行中是否显示弹体本身
@export var visible_in_flight: bool = true
## 飞向发射时的地面坐标，而不继续跟踪目标
@export var target_ground: bool
## 射向地面时是否把目标单位高度纳入弹着点高度
@export var target_ground_include_target_height: bool
## 射向地面的随机散布半径
@export var target_ground_spread: float
## 射向地面的高度偏移
@export var target_ground_height_offset: float
## 弹体使用原版抛物线弹道
@export var ballistic: bool
## 开火前按目标速度预判拦截位置
@export var lead_target: bool
## 大于零时覆盖用于预判的飞行速度
@export var lead_target_speed_calculation: float
## 复用同一炮塔上一个尚未结束的即时弹体
@export var instant_reuse_last: bool
## 复用即时弹体时同步更新炮塔瞄准
@export var instant_reuse_last_also_change_turret_aim: bool
## 复用即时弹体时保留已受范围伤害的对象列表
@export var instant_reuse_last_keep_area_damage_list: bool
## 弹体在飞行时跟随发射单位移动
@export var move_with_parent: bool
## 原版弹体目标扫动速度，源码当前帧更新路径未读取此值
@export var sweep_speed: float
## 弹着点扫动偏移
@export var sweep_offset: float
## 按目标碰撞半径缩放的扫动偏移
@export var sweep_offset_from_target_radius: float
## 弹体创建后暂停移动的帧数
@export var delayed_start_frames: float
## 弹体移动时的初始附加速度
@export var initial_unguided_velocity: Vector2
@export var initial_velocity: Vector2
## 初速度沿发射方向的随机波动范围
@export var speed_spread: float
## 弹体初始高度方向速度
@export var initial_height_velocity: float
## 原版弹道弹体未指定独立升降速度时使用当前水平弹速
@export var ballistic_vertical_speed: float = -1.0
## 弹体高度方向重力
@export var gravity_per_frame: float
## 弹体高度方向额外重力
@export var true_gravity_per_frame: float
## 抛物线轨迹的最高点
@export var ballistic_height: float = -1.0
## 抛物线弹体延迟移动高度变化的帧数
@export var ballistic_delay_move_height: float = -1.0
## 原版升降弹体开始水平移动的高度
@export var altitude_move_start: float
## 原版升降弹体的飞行高度上限
@export var altitude_maximum: float
## 原版升降弹体每帧升降距离
@export var altitude_change_per_frame: float
## 接近目标后开始下降的距离
@export var altitude_descent_range: float = 20.0
## 爆炸范围从中心向外扩张所需的同步帧数
@export var area_expand_time: float
## 高度轨迹弹体的命中高度容差
@export var altitude_hit_tolerance: float = 3.0
## 目标单位被摧毁或消失时立即引爆
@export var detonate_on_target_loss: bool
## 目标单位失效时在附近重新寻找敌方单位
@export var retarget_on_target_loss: bool
## 目标失效且未能重新锁定时移除弹体
@export var remove_on_target_loss: bool = true
## 失去目标后搜索新目标的半径
@export var target_loss_retarget_range: float = 120.0
## 原版重索敌时沿飞行方向前置搜索中心的距离
@export var target_loss_retarget_lead_distance: float = 15.0
## 飞行中周期性搜索新目标
@export var retarget_in_flight: bool
## 飞行中重新索敌的间隔帧数
@export var retarget_in_flight_search_delay: float = 5.0
## 飞行中重新索敌的搜索半径
@export var retarget_in_flight_search_range: float = 120.0
## 原版飞行中重索敌时沿飞行方向前置搜索中心的距离
@export var retarget_in_flight_lead_distance: float = 15.0
## 命中判定是否加上目标碰撞半径
@export var include_target_collision_radius: bool = true
## 使用原版按目标尺寸和当前生命值计算的命中判定
@export var native_target_collision_rules: bool
## 原版弹体命中目标时使用的最小有效半径
@export var native_minimum_target_hit_radius: float = 6.0
## 原版建筑弹体命中半径系数
@export var native_building_radius_scale: float = 0.8
## 目标生命值高于伤害阈值时使用的碰撞半径系数
@export var native_high_health_radius_scale: float = 1.1
## 原版在伤害值外额外使用的生命值阈值
@export var native_health_damage_threshold: float = 10.0
## 按原版模板处理目标高度与弹体高度的碰撞容差
@export var native_altitude_collision_rules: bool
## 飞行摆动幅度与周期
@export var wobble_amplitude: float
@export var wobble_frequency: float
## 绘制飞行尾迹
@export var trail_length_frames: int
## 烟尘离开发射弹体后保留的同步帧数
@export var trail_particle_lifetime_frames: float = 70.0
@export var trail_width: float
@export var trail_color: Color = Color.TRANSPARENT
## 将尾迹绘制为烟尘粒子
@export var trail_as_particles: bool
## 原版由 trailEffect 指定的自定义尾迹效果
@export var trail_effect_name: String
@export var trail_emission_interval_frames: float = 1.0
@export var trail_texture_name: String
@export var trail_texture_frame_size: Vector2i = Vector2i(20, 20)
## 尾迹图集帧的起始像素坐标
@export var trail_texture_frame_offset: Vector2i
## 尾迹图集每帧之间的像素间距
@export var trail_texture_frame_step: Vector2i
@export var trail_texture_scale: float = 0.25
## 是否按粒子年龄切换尾迹图集帧
@export var trail_animate_frames: bool = true
## 尾迹粒子生命周期起始缩放
@export var trail_particle_scale_from: float = 0.75
## 尾迹粒子生命周期结束缩放
@export var trail_particle_scale_to: float = 1.0
## 尾迹粒子在生命周期末尾的淡出帧数
@export var trail_particle_fade_duration_frames: float
## 尾迹粒子出现时的淡入帧数
@export var trail_particle_fade_in_duration_frames: float
## 尾迹粒子每同步帧的纵向漂移距离
@export var trail_particle_drift_y_per_frame: float
## 绘制尾迹粒子的地面阴影
@export var trail_particle_shadow: bool
@export var trail_during_stationary: bool
## 弹体到期时是否产生一次爆炸结算
@export var explode_on_end_of_life: bool
## 弹体寿命结束时要生成的后续弹体
@export var spawn_on_end_of_life: Array[Dictionary]
## 弹体生成时要生成的后续弹体
@export var spawn_on_create: Array[Dictionary]
## 弹体爆炸时要生成的后续弹体
@export var spawn_on_explode: Array[Dictionary]
## 弹体爆炸时要生成的单位
@export var spawn_units_on_explode: Array[Dictionary]
## 命中时播放的横向爆炸图集
@export var impact_texture_name: String
@export var impact_frame_size: Vector2i = Vector2i(40, 49)
## 命中图集帧的起始像素坐标
@export var impact_frame_offset: Vector2i
## 命中图集每帧之间的像素间距
@export var impact_frame_step: Vector2i
@export var impact_frame_count: int = 14
@export var impact_duration: float = 0.42
## 命中图集动画播放时长
@export var impact_animation_duration: float
@export var impact_scale: float = 1.0
## 命中图集缩放的随机波动范围
@export var impact_scale_variance: float
## 随机旋转命中图集
@export var impact_random_rotation: bool
## 没有命中图集时使用的短暂命中闪光半径
@export var impact_radius: float
## 没有命中图集时使用的命中闪光颜色
@export var impact_color: Color = Color.TRANSPARENT
## 范围伤害是否影响友方单位
@export var friendly_fire: bool
@export var friendly_fire_mode: String
## 对建筑造成的伤害倍率
@export var building_damage_multiplier: float = 1.0
## 对空中单位造成的伤害倍率
@export var air_damage_multiplier: float = 1.0
## 应用于单位生命值的最终伤害倍率
@export var global_damage_multiplier: float = 1.0
## 对护盾造成的伤害倍率
@export var shield_damage_multiplier: float = 1.0
## 护盾吸收后仍传递到生命值的伤害比例
@export var shield_deflection_multiplier: float = 1.0
## 对单位本体造成的伤害倍率
@export var hull_damage_multiplier: float = 1.0
## 命中时忽略的护甲值
@export var armor_ignore: float
## 命中时施加的推力
@export var push_force: float
## 命中时施加的固定速度推力
@export var push_velocity: float
## 开启后每帧朝仍存活的目标调整飞行方向
@export var homing: bool = true
## 留空时绘制纯色圆形，否则从纹理目录加载贴图
@export var texture_name: String
@export var texture_region: Rect2i
## 纹理绘制缩放和相对飞行方向的角度偏移
@export var texture_scale: float = 2.0
@export var texture_rotation_offset_degrees: float
## 原版投影绘制
@export var render_shadow: bool = true
## 原版弹体发光半径
@export var glow_radius: float
## 沿弹体附着绘制的原版动态光效颜色
@export var attached_light_color: Color = Color.TRANSPARENT
## 沿弹体附着绘制的原版动态光效缩放
@export var attached_light_scale: float = 0.5
## 沿弹体附着绘制的原版动态光效透明度
@export var attached_light_alpha: float = 0.3
## 沿弹体绘制的原版动态光效是否固定在地面高度
@export var attached_light_cast_on_ground: bool
## 原版命中时使用小型爆炸效果
@export var small_explosion: bool
@export var visual_radius: float = 3.0
@export var visual_color: Color = Color.WHITE
