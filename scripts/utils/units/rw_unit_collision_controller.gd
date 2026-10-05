extends RefCounted
class_name RwUnitCollisionController
## 按原版的空间格顺序、十个候选上限和毫秒计时释放碰撞对

const MAX_CANDIDATES: int = 10
const SPATIAL_GRID_SIZE: int = 32

var _time_ms: int
var _spatial_scale: Vector2
var _buckets: Dictionary[Vector2i, Array]
var _unit_cells: Dictionary[int, Vector2i]
var _candidates: Dictionary[int, Array]
var _next_refresh: Dictionary[int, int]
var _refresh_requested: Dictionary[int, bool]


## 每个同步步只刷新到期的候选，再按原版主体顺序返回待处理碰撞对
func advance(units: Dictionary, mobile_units: Array[RwUnitState], world_size: Vector2, simulation_delta: float) -> Array[Vector2i]:
	_time_ms = int(RwGameMath.float32(float(_time_ms) + RwGameMath.float32(simulation_delta * 16.666666)))
	@warning_ignore("integer_division")
	var bucket_size: Vector2 = Vector2(maxf(float(int(world_size.x) / SPATIAL_GRID_SIZE), 1.0), maxf(float(int(world_size.y) / SPATIAL_GRID_SIZE), 1.0))
	_spatial_scale = Vector2(1.0 / bucket_size.x, 1.0 / bucket_size.y)
	_update_spatial_index(units)
	var indices: Dictionary[int, int] = {}
	var index: int
	for object_id: int in units:
		indices[object_id] = index
		index += 1
	for unit: RwUnitState in mobile_units:
		if not _is_active(unit):
			continue
		var object_id: int = unit.object_id
		if not unit.collision_step_active and not bool(_refresh_requested.get(object_id, false)):
			continue
		if int(_next_refresh.get(object_id, 0)) > _time_ms:
			continue
		_refresh_requested[object_id] = false
		unit.collision_step_active = true
		var previous_count: int = (_candidates.get(object_id, []) as Array).size()
		var moving_path: bool = unit.navigation_path_active
		var stagger: int = int(indices.get(object_id, 0)) % 50
		_next_refresh[object_id] = _time_ms + (200 if previous_count > 9 else 50) + stagger if moving_path else _time_ms + 250 + stagger
		var radius: float = unit.collision_radius + (7.0 if moving_path else 5.0)
		_refresh_candidates(unit, radius, units)
	var pairs: Array[Vector2i] = []
	for unit: RwUnitState in mobile_units:
		if not unit.collision_step_active or not _is_active(unit):
			continue
		var candidates: Array = _candidates.get(unit.object_id, [])
		if not candidates.is_empty():
			_refresh_requested[unit.object_id] = true
		for other_id: int in candidates:
			var other: RwUnitState = units.get(other_id) as RwUnitState
			if _is_pair_allowed(unit, other):
				pairs.append(Vector2i(unit.object_id, other_id))
	return pairs


## 返回候选缓存及下一次刷新时刻，供逐帧原版探针对照
func debug_state(object_id: int) -> Dictionary:
	return {
		"time_ms": _time_ms,
		"next_refresh": int(_next_refresh.get(object_id, 0)),
		"refresh_requested": bool(_refresh_requested.get(object_id, false)),
		"candidates": (_candidates.get(object_id, []) as Array).duplicate(),
	}


func _update_spatial_index(units: Dictionary) -> void:
	for previous_id: int in _unit_cells.keys():
		if units.has(previous_id):
			continue
		(_buckets[_unit_cells[previous_id]] as Array).erase(previous_id)
		_unit_cells.erase(previous_id)
		_candidates.erase(previous_id)
		_next_refresh.erase(previous_id)
		_refresh_requested.erase(previous_id)
	for object_id: int in units:
		var unit: RwUnitState = units[object_id] as RwUnitState
		if unit == null:
			continue
		var cell: Vector2i = _spatial_cell(unit.world_position)
		if _unit_cells.has(object_id) and (_unit_cells[object_id] == cell and not unit.is_dead):
			continue
		if _unit_cells.has(object_id):
			var previous: Array = _buckets[_unit_cells[object_id]]
			previous.erase(object_id)
			_unit_cells.erase(object_id)
		if unit.is_dead:
			continue
		if not _buckets.has(cell):
			_buckets[cell] = []
		(_buckets[cell] as Array).append(object_id)
		_unit_cells[object_id] = cell


func _refresh_candidates(unit: RwUnitState, radius: float, units: Dictionary) -> void:
	var object_id: int = unit.object_id
	var candidates: Array[int] = []
	var scores: Array[float] = []
	scores.resize(MAX_CANDIDATES)
	var minimum: Vector2 = unit.world_position - Vector2.ONE * radius
	var maximum: Vector2 = unit.world_position + Vector2.ONE * radius
	var first_cell: Vector2i = _spatial_cell(minimum - Vector2.ONE * 50.0)
	var last_cell: Vector2i = _spatial_cell(maximum + Vector2.ONE * 50.0)
	for x: int in range(first_cell.x, last_cell.x + 1):
		for y: int in range(first_cell.y, last_cell.y + 1):
			for other_id: int in _buckets.get(Vector2i(x, y), []):
				var other: RwUnitState = units.get(other_id) as RwUnitState
				if not _is_pair_allowed(unit, other):
					continue
				var other_position: Vector2 = other.world_position
				var other_radius: float = other.collision_radius
				if other_position.x < minimum.x - other_radius or other_position.x > maximum.x + other_radius or other_position.y < minimum.y - other_radius or other_position.y > maximum.y + other_radius:
					continue
				if (_candidates.get(other_id, []) as Array).has(object_id):
					continue
				var separation: Vector2 = (other_position + other.collision_push_offset) - (unit.world_position + unit.collision_push_offset)
				var score: float = separation.length_squared()
				var combined_radius: float = unit.collision_radius + other_radius
				if score < combined_radius * combined_radius:
					score = 0.0
				var insertion: int = candidates.size()
				for candidate_index: int in candidates.size():
					if score < scores[candidate_index]:
						insertion = candidate_index
						break
				if insertion >= MAX_CANDIDATES:
					continue
				candidates.insert(insertion, other_id)
				if candidates.size() > MAX_CANDIDATES:
					candidates.resize(MAX_CANDIDATES)
				# 原版只移动候选数组，评分数组在插入后只写当前槽位
				scores[insertion] = score
	_candidates[object_id] = candidates


func _spatial_cell(position: Vector2) -> Vector2i:
	return Vector2i(clampi(int(position.x * _spatial_scale.x), 0, SPATIAL_GRID_SIZE - 1), clampi(int(position.y * _spatial_scale.y), 0, SPATIAL_GRID_SIZE - 1))


func _is_active(unit: RwUnitState) -> bool:
	return unit != null and not unit.is_dead and unit.build_progress >= 1.0 and unit.movement_speed > 0.0 and unit.collision_radius > 0.0


func _is_pair_allowed(first: RwUnitState, second: RwUnitState) -> bool:
	if first == second or second == null or second.is_dead or second.collision_radius <= 0.0:
		return false
	if not _is_active(second) and second.unit_name != "tree":
		return false
	if _collision_group(first) != _collision_group(second):
		return false
	if first.order_type in ["loadInto", "loadUp",] and first.order_target_id == second.object_id:
		return false
	if second.order_type in ["loadInto", "loadUp",] and second.order_target_id == first.object_id:
		return false
	return true


func _collision_group(unit: RwUnitState) -> int:
	match unit.movement_type:
		"AIR":
			return 3
		"WATER":
			return 2
		_:
			return 1
