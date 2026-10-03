class_name RwUnitActionItem
extends MarginContainer

signal activated(action_id: String)
signal cancelled(action_id: String)
signal hovered(item: RwUnitActionItem)
signal unhovered(item: RwUnitActionItem)

const CANCEL_HOLD_DELAY: float = 0.5
const CANCEL_REPEAT_INTERVAL: float = 0.08

@onready var unit_texture: TextureRect = %UnitTexture
@onready var unit_name_label: Label = %UnitNameLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var disabled_color_rect: ColorRect = %DisabledColorRect

var action_id: String
var action_definition: RwUnitActionDefinition
var _is_affordable: bool = true
var _queue_count: int
var _pending_cancellations: int
var _right_held: bool
var _hold_elapsed: float
var _repeat_elapsed: float


func _process(delta: float) -> void:
	if not _right_held:
		return
	var previous_elapsed: float = _hold_elapsed
	_hold_elapsed += delta
	if _hold_elapsed < CANCEL_HOLD_DELAY:
		return
	_repeat_elapsed += _hold_elapsed - maxf(previous_elapsed, CANCEL_HOLD_DELAY)
	while _repeat_elapsed >= CANCEL_REPEAT_INTERVAL and _pending_cancellations < _queue_count:
		_repeat_elapsed -= CANCEL_REPEAT_INTERVAL
		_request_cancellation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_right_held = false


func configure(action: RwUnitActionDefinition, icon: Texture2D) -> void:
	action_definition = action
	action_id = action.action_id
	unit_name_label.text = action.display_name
	unit_texture.texture = icon
	_pending_cancellations = 0
	_queue_count = 0


func set_production_status(queue_count: int, progress: float, is_active: bool) -> void:
	if queue_count < _queue_count:
		_pending_cancellations = maxi(_pending_cancellations - (_queue_count - queue_count), 0)
	_queue_count = queue_count
	if queue_count <= 0:
		_pending_cancellations = 0
		unit_name_label.text = action_definition.display_name
		progress_bar.hide()
		_refresh_disabled_state()
		return
	unit_name_label.text = "%s x%d" % [action_definition.display_name, queue_count]
	progress_bar.visible = is_active
	progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	_refresh_disabled_state()


func set_affordable(is_affordable: bool) -> void:
	_is_affordable = is_affordable
	_refresh_disabled_state()


func _on_button_pressed() -> void:
	if _is_affordable and (action_definition.kind != RwUnitActionDefinition.Kind.UPGRADE_UNIT or _queue_count == 0):
		activated.emit(action_id)


func _on_button_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	_right_held = mouse_event.pressed
	_hold_elapsed = 0.0
	_repeat_elapsed = 0.0
	if mouse_event.pressed:
		_request_cancellation()
	accept_event()


func _request_cancellation() -> void:
	if _pending_cancellations >= _queue_count:
		return
	_pending_cancellations += 1
	cancelled.emit(action_id)


func _on_button_mouse_entered() -> void:
	hovered.emit(self)


func _on_button_mouse_exited() -> void:
	_right_held = false
	unhovered.emit(self)


func _refresh_disabled_state() -> void:
	disabled_color_rect.visible = not _is_affordable or (action_definition.kind == RwUnitActionDefinition.Kind.UPGRADE_UNIT and _queue_count > 0)
