extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_native_completion_frames(failures)
	_check_cancellation_and_order(failures)
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RW production queue: 1.15 completion frames, cancellation and FIFO order verified")
	quit(0 if failures.is_empty() else 1)


func _check_native_completion_frames(failures: Array[String]) -> void:
	for native_name: String in RwNativeProductionSpecs.SPECS:
		var spec: Dictionary = RwNativeProductionSpecs.SPECS[native_name]
		var rate: float = float(spec["rate"])
		if rate <= 0.0:
			failures.append("Native production rate is invalid: %s" % native_name)
			continue
		var expected_frames: int = int(spec["completion_frames"])
		var action: RwUnitActionDefinition = RwUnitActionDefinition.new()
		action.action_id = native_name
		action.build_rate_per_frame = rate
		var queue: RwProductionQueue = RwProductionQueue.new()
		queue.enqueue(action)
		var completed: Array[RwUnitActionDefinition] = queue.advance(expected_frames - 1)
		if not completed.is_empty() or queue.items.size() != 1 or queue.progress >= 1.0:
			failures.append("Native production completed before stock frame for %s" % native_name)
			continue
		completed = queue.advance(1)
		if completed.size() != 1 or completed[0] != action or not queue.items.is_empty():
			failures.append("Native production did not complete at stock frame for %s: expected=%d completed=%d items=%d progress=%.12f rate=%.12f" % [native_name, expected_frames, completed.size(), queue.items.size(), queue.progress, rate,])


func _check_cancellation_and_order(failures: Array[String]) -> void:
	var first: RwUnitActionDefinition = RwUnitActionDefinition.new()
	first.action_id = "first"
	first.build_rate_per_frame = 0.5
	var second: RwUnitActionDefinition = RwUnitActionDefinition.new()
	second.action_id = "second"
	second.build_rate_per_frame = 1.0
	var queue: RwProductionQueue = RwProductionQueue.new()
	queue.enqueue(first)
	queue.enqueue(second)
	queue.advance(1)
	if not is_equal_approx(queue.progress, 0.5):
		failures.append("Production progress did not advance by one simulation frame")
	var cancelled: RwUnitActionDefinition = queue.cancel_one("second")
	if cancelled != second or queue.items != [first,] or not is_equal_approx(queue.progress, 0.5):
		failures.append("Cancelling a queued item changed the active production item")
	cancelled = queue.cancel_one("first")
	if cancelled != first or not queue.items.is_empty() or queue.progress != 0.0:
		failures.append("Cancelling the active item did not clear its progress")
	queue.enqueue(first)
	queue.enqueue(second)
	var completed: Array[RwUnitActionDefinition] = queue.advance(2)
	if completed != [first,] or queue.items != [second,] or queue.progress != 0.0:
		failures.append("Production queue did not preserve FIFO completion")
	completed = queue.advance(1)
	if completed != [second,] or not queue.items.is_empty():
		failures.append("Production queue did not complete the next item after the active item")
