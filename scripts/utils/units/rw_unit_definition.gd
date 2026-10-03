class_name RwUnitDefinition
extends Resource

enum SelectionShape {
	CIRCLE,
	RECTANGLE,
}

@export var source_id: String = "vanilla"
@export var unit_name: String
@export var display_name: String
@export_multiline var description: String
@export var body_image: String
@export var back_image: String
@export var turret_image: String
@export var shadow_image: String
@export var dead_image: String
@export var body_region: Rect2i
@export var body_scale: Vector2 = Vector2.ONE
@export var render_rotation_offset_degrees: float
@export var applies_spawn_rotation: bool = true
@export var draw_layer: int = 2
@export var dead_draw_layer: int = -1
@export var max_health: float = 1.0
@export var movement_speed: float
@export var water_movement_speed: float
@export var movement_type: String = "LAND"
@export var turn_speed: float
@export var water_turn_speed: float
@export var turn_acceleration: float
@export var movement_acceleration: float
@export var movement_deceleration: float
@export var collision_radius: float
@export var attack_range: float
@export var selection_shape: SelectionShape
@export var sight_range: int = 15
@export var can_reclaim: bool
@export var build_actions: Array[RwUnitActionDefinition]
@export_range(1, 32, 1) var body_frames: int = 1
@export var shadow_offset: Vector2
@export var body_team_colored: bool = true
@export var turret_team_colored: bool
@export var generates_shadow: bool


func key() -> String:
	return "%s:%s" % [source_id, unit_name]


func configure_visual(visual: RwUnitVisual, provider: RwUnitAssetProvider, color: Color, _spawn: Dictionary) -> void:
	visual.configure(self, provider, color)
