class_name RwUnitActionDefinition
extends Resource

enum Kind {
	UNSUPPORTED,
	QUEUE_UNIT,
	PLACE_BUILDING,
}

@export var action_id: String
@export var display_name: String
@export_multiline var description: String
@export var icon_image: String
@export var icon_frames: int = 1
@export var kind: Kind
@export var network_action_id: String
@export var network_build_index: int = -1
@export var target_source_id: String = "vanilla"
@export var target_unit_name: String
@export var resource_costs: Dictionary
@export var build_rate_per_frame: float
