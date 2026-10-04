extends SceneTree
## 对照原版联机第 903 帧的生产出口目标校验值


func _initialize() -> void:
	var target: Vector2 = RwGameMath.factory_exit_target(Vector2(990.0, 1670.0), 30.0)
	if int(target.x * 1000.0) != 988965:
		push_error("Factory exit X differs from vanilla checksum: %s" % target)
		quit(1)
		return
	if absf(target.y - 1760.0) > 0.01:
		push_error("Factory exit Y differs from source formula: %s" % target)
		quit(1)
		return
	print("Factory exit reference passed: %s" % target)
	quit(0)
