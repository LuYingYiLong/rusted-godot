class_name RwProductionQueue
extends RefCounted

var items: Array[RwUnitActionDefinition]
var progress: float


func enqueue(action: RwUnitActionDefinition) -> void:
	items.append(action)


func cancel_one(action_id: String) -> RwUnitActionDefinition:
	for index: int in range(items.size() - 1, -1, -1):
		if items[index].action_id != action_id:
			continue
		var cancelled_action: RwUnitActionDefinition = items[index]
		items.remove_at(index)
		if index == 0:
			progress = 0.0
		return cancelled_action
	return null


func advance(frame_count: int) -> Array[RwUnitActionDefinition]:
	var completed: Array[RwUnitActionDefinition] = []
	for frame: int in maxi(frame_count, 0):
		if items.is_empty():
			break
		progress += items[0].build_rate_per_frame
		if progress < 1.0:
			continue
		completed.append(items.pop_front())
		progress = 0.0
	return completed
