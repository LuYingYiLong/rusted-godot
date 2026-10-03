class_name RwUnitActionDefinition
extends Resource

enum Kind {
	UNSUPPORTED,
	QUEUE_UNIT,
	PLACE_BUILDING,
	UPGRADE_UNIT,
	CONVERT_UNIT,
	QUEUE_RESOURCE,
}

@export var action_id: String
@export var display_name: String
@export_multiline var description: String
@export var icon_image: String
@export var icon_frames: int = 1
@export var kind: Kind
@export var network_action_id: String
@export var network_build_index: int = -1
@export var network_build_custom_name: String
@export var target_source_id: String = "vanilla"
@export var target_unit_name: String
@export var resource_costs: Dictionary
@export var resource_delta: Dictionary
@export var max_stockpile: int
@export var build_rate_per_frame: float
@export var required_tech_level: int
@export var result_tech_level: int
@export var is_visible: bool = true
