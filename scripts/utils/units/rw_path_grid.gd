class_name RwPathGrid
extends RefCounted

const WATER: int = 1
const CLIFF: int = 2
const LARGE_OBJECT: int = 4
const LAVA: int = 8
const WATER_BRIDGE: int = 16
const RESOURCE_POOL: int = 32
const MAX_SEARCH_CELLS: int = 100_000
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

var size: Vector2i
var tile_size: Vector2i

var _land_costs: PackedInt32Array
var _building_costs: PackedInt32Array
var _hover_costs: PackedInt32Array
var _water_costs: PackedInt32Array
var _cliff_costs: PackedInt32Array
var _cliff_water_costs: PackedInt32Array
var _water_tiles: PackedByteArray
var _resource_pool_tiles: PackedByteArray
var _structure_blocks: PackedByteArray
var _object_costs: PackedByteArray
var _land_clearance: PackedByteArray
var _building_clearance: PackedByteArray
var _hover_clearance: PackedByteArray
var _water_clearance: PackedByteArray
var _cliff_clearance: PackedByteArray
var _cliff_water_clearance: PackedByteArray
var _tile_info: Dictionary


static func load_map(map_name: String) -> RwPathGrid:
	var document: RwXmlDocument = RwMapCatalog.load_map(map_name.get_file())
	if document == null:
		return null
	var parsed: Dictionary = RwTmxLoader.read_map_data(document)
	if not str(parsed.get("error", "")).is_empty():
		return null
	var grid: RwPathGrid = RwPathGrid.new()
	if not grid._initialize(parsed):
		return null
	return grid


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / float(tile_size.x)), floori(world_position.y / float(tile_size.y)))


func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(tile_size)


## 按建筑占地的中心把放置位置吸附到地图格
func snap_structure_position(world_position: Vector2, minimum_offset: Vector2i, maximum_offset: Vector2i) -> Vector2:
	var center_offset: Vector2 = _structure_center_offset(minimum_offset, maximum_offset)
	var anchor: Vector2i = Vector2i(
		roundi(world_position.x / float(tile_size.x) - center_offset.x),
		roundi(world_position.y / float(tile_size.y) - center_offset.y),
	)
	return (Vector2(anchor) + center_offset) * Vector2(tile_size)


## 返回建筑占地相对格子的锚点
func structure_anchor_cell(world_position: Vector2, minimum_offset: Vector2i, maximum_offset: Vector2i) -> Vector2i:
	var center_offset: Vector2 = _structure_center_offset(minimum_offset, maximum_offset)
	return Vector2i(
		roundi(world_position.x / float(tile_size.x) - center_offset.x),
		roundi(world_position.y / float(tile_size.y) - center_offset.y),
	)


func is_water_at(world_position: Vector2) -> bool:
	var cell: Vector2i = world_to_cell(world_position)
	return _is_in_bounds(cell) and _water_tiles[_cell_index(cell)] != 0


func is_passable(cell: Vector2i, movement_type: String) -> bool:
	return cost_at(cell, movement_type) >= 0


func get_placement_error(world_position: Vector2, definition: RwUnitDefinition) -> String:
	var center: Vector2i = structure_anchor_cell(world_position, definition.structure_footprint_min, definition.structure_footprint_max)
	if not _is_in_bounds(center):
		return "Cannot place here"
	var center_index: int = _cell_index(center)
	if definition.placement_requires_resource_pool and _resource_pool_tiles[center_index] == 0:
		return "Requires a resource pool"
	if definition.placement_requires_water and _water_tiles[center_index] == 0:
		return "Requires water"
	for y: int in range(center.y + definition.structure_footprint_min.y, center.y + definition.structure_footprint_max.y + 1):
		for x: int in range(center.x + definition.structure_footprint_min.x, center.x + definition.structure_footprint_max.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_in_bounds(cell):
				return "Cannot place here"
			var index: int = _cell_index(cell)
			if _structure_blocks[index] != 0:
				return "Location is occupied"
			if definition.placement_requires_resource_pool and cell == center:
				continue
			if definition.placement_requires_water:
				if _hover_costs[index] < 0:
					return "Cannot place here"
			elif _land_costs[index] < 0:
				return "Cannot place here"
	return ""


func cost_at(cell: Vector2i, movement_type: String) -> int:
	if not _is_in_bounds(cell):
		return -1
	if movement_type == "AIR":
		return 0
	var index: int = _cell_index(cell)
	if _structure_blocks[index] != 0:
		return -1
	match movement_type:
		"BUILDING":
			return _building_costs[index]
		"HOVER":
			return _hover_costs[index]
		"WATER":
			return _water_costs[index]
		"OVER_CLIFF":
			return _cliff_costs[index]
		"OVER_CLIFF_WATER":
			return _cliff_water_costs[index]
		_:
			return _land_costs[index]


func block_structure(world_position: Vector2, minimum_offset: Vector2i, maximum_offset: Vector2i) -> void:
	var center: Vector2i = structure_anchor_cell(world_position, minimum_offset, maximum_offset)
	for y: int in range(center.y + minimum_offset.y, center.y + maximum_offset.y + 1):
		for x: int in range(center.x + minimum_offset.x, center.x + maximum_offset.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _is_in_bounds(cell):
				_structure_blocks[_cell_index(cell)] = 1
	_land_clearance.clear()
	_building_clearance.clear()
	_hover_clearance.clear()
	_water_clearance.clear()
	_cliff_clearance.clear()
	_cliff_water_clearance.clear()


## 建筑被摧毁后清除对应格子的动态阻挡
func unblock_structure(world_position: Vector2, minimum_offset: Vector2i, maximum_offset: Vector2i) -> void:
	var center: Vector2i = structure_anchor_cell(world_position, minimum_offset, maximum_offset)
	for y: int in range(center.y + minimum_offset.y, center.y + maximum_offset.y + 1):
		for x: int in range(center.x + minimum_offset.x, center.x + maximum_offset.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _is_in_bounds(cell):
				_structure_blocks[_cell_index(cell)] = 0
	_land_clearance.clear()
	_building_clearance.clear()
	_hover_clearance.clear()
	_water_clearance.clear()
	_cliff_clearance.clear()
	_cliff_water_clearance.clear()


func finalize_obstacles() -> void:
	_land_clearance = _build_clearance(_land_costs)
	_building_clearance = _build_clearance(_building_costs)
	_hover_clearance = _build_clearance(_hover_costs)
	_water_clearance = _build_clearance(_water_costs)
	_cliff_clearance = _build_clearance(_cliff_costs)
	_cliff_water_clearance = _build_clearance(_cliff_water_costs)


## 更新原版寻路使用的闲置单位动态代价
func update_object_costs(units: Dictionary, moving_unit_id: int) -> void:
	_object_costs.resize(size.x * size.y)
	_object_costs.fill(0)
	for object_id: int in units:
		if object_id == moving_unit_id:
			continue
		var unit_state: RwUnitState = units[object_id] as RwUnitState
		if unit_state == null or unit_state.is_dead or unit_state.movement_speed <= 0.0 or unit_state.movement_type == "AIR":
			continue
		if not unit_state.get_navigation_path().is_empty() or unit_state.is_exiting_factory():
			continue
		var center: Vector2i = world_to_cell(unit_state.world_position)
		var inner_radius: float = unit_state.collision_radius + 5.0
		var outer_radius: float = unit_state.collision_radius + 10.0
		var search_radius: int = 2 if outer_radius >= 20.0 else 1 if outer_radius >= 10.0 else 0
		for x: int in range(center.x - search_radius, center.x + search_radius + 1):
			for y: int in range(center.y - search_radius, center.y + search_radius + 1):
				var cell: Vector2i = Vector2i(x, y)
				if not _is_in_bounds(cell):
					continue
				var distance_squared: float = cell_to_world(cell).distance_squared_to(unit_state.world_position)
				var added_cost: int
				if distance_squared < inner_radius * inner_radius:
					added_cost = 6
				elif distance_squared < outer_radius * outer_radius:
					added_cost = 1
				if added_cost > 0:
					var index: int = _cell_index(cell)
					_object_costs[index] = mini(127, int(_object_costs[index]) + added_cost)


func find_path(start_position: Vector2, target_position: Vector2, movement_type: String, use_smoothing: bool = true, heading_degrees: float = 0.0, use_heading: bool = false, goal_radius_cells: int = 0) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	var start: Vector2i = world_to_cell(start_position)
	var goal: Vector2i = world_to_cell(target_position)
	if not _is_in_bounds(start) or not _is_in_bounds(goal):
		return waypoints
	if movement_type == "AIR":
		waypoints.append(target_position)
		return waypoints
	if use_smoothing and has_clear_line(start_position, target_position, movement_type):
		return _straight_line_waypoints(start_position, target_position)
	if use_heading:
		return _find_native_grid_path(start, goal, target_position, movement_type, heading_degrees, goal_radius_cells)
	var cell_count: int = size.x * size.y
	var scores: PackedInt32Array = PackedInt32Array()
	scores.resize(cell_count)
	scores.fill(2_147_483_647)
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(cell_count)
	parents.fill(-1)
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(cell_count)
	var incoming_directions: PackedByteArray = PackedByteArray()
	incoming_directions.resize(cell_count)
	incoming_directions.fill(255)
	var open_nodes: Array[Vector2i] = []
	var start_index: int = _cell_index(start)
	var best_index: int = start_index
	var best_distance: int = _heuristic(start, goal)
	scores[start_index] = 0
	if use_heading:
		incoming_directions[start_index] = _heading_sector(heading_degrees)
	_heap_push(open_nodes, Vector2i(best_distance, start_index))
	var searches: int = 0
	while not open_nodes.is_empty() and searches < MAX_SEARCH_CELLS:
		var entry: Vector2i = _heap_pop(open_nodes)
		var index: int = entry.y
		if visited[index] != 0:
			continue
		visited[index] = 1
		searches += 1
		@warning_ignore("integer_division")
		var cell: Vector2i = Vector2i(index % size.x, int(index / size.x))
		var distance: int = _heuristic(cell, goal)
		if distance < best_distance:
			best_distance = distance
			best_index = index
		if cell == goal:
			best_index = index
			break
		for direction_index: int in NEIGHBORS.size():
			var previous_direction: int = int(incoming_directions[index])
			if use_heading and index != start_index and _direction_difference(previous_direction, direction_index) > 2:
				continue
			var offset: Vector2i = NEIGHBORS[direction_index]
			var neighbor: Vector2i = cell + offset
			var tile_cost: int = cost_at(neighbor, movement_type)
			if tile_cost < 0:
				continue
			if offset.x != 0 and offset.y != 0:
				if not is_passable(cell + Vector2i(offset.x, 0), movement_type) or not is_passable(cell + Vector2i(0, offset.y), movement_type):
					continue
			var neighbor_index: int = _cell_index(neighbor)
			if visited[neighbor_index] != 0:
				continue
			var step_cost: int = 14 if offset.x != 0 and offset.y != 0 else 10
			var new_score: int = scores[index] + step_cost + 1 + tile_cost
			new_score += 4 - _clearance_at(neighbor, movement_type)
			if use_heading:
				new_score += _turn_penalty(previous_direction, direction_index)
			elif parents[index] >= 0:
				@warning_ignore("integer_division")
				var parent_cell: Vector2i = Vector2i(parents[index] % size.x, int(parents[index] / size.x))
				var parent_direction: int = NEIGHBORS.find(cell - parent_cell)
				if parent_direction >= 0:
					new_score += _turn_penalty(parent_direction, direction_index)
			if new_score >= scores[neighbor_index]:
				continue
			scores[neighbor_index] = new_score
			parents[neighbor_index] = index
			incoming_directions[neighbor_index] = direction_index
			_heap_push(open_nodes, Vector2i(new_score + _heuristic(neighbor, goal), neighbor_index))
	if best_index == start_index:
		# 原版无法离开起始格时仍保留格子中心作为路径点
		waypoints.append(cell_to_world(start))
		return waypoints
	var reverse_cells: Array[Vector2i] = []
	var current_index: int = best_index
	while current_index != start_index and current_index >= 0:
		@warning_ignore("integer_division")
		reverse_cells.append(Vector2i(current_index % size.x, int(current_index / size.x)))
		current_index = parents[current_index]
	if current_index != start_index:
		return waypoints
	reverse_cells.reverse()
	var raw_points: Array[Vector2] = []
	for cell: Vector2i in reverse_cells:
		raw_points.append(cell_to_world(cell))
	if reverse_cells.back() == goal and is_passable(goal, movement_type):
		raw_points.append(target_position)
	return _smooth_points(start_position, raw_points, movement_type) if use_smoothing else raw_points


func _find_native_grid_path(start: Vector2i, goal: Vector2i, target_position: Vector2, movement_type: String, heading_degrees: float, goal_radius_cells: int) -> Array[Vector2]:
	var roots: Array[Vector2i] = [start, goal,]
	var root_indices: Array[int] = [_cell_index(start), _cell_index(goal),]
	var queues: Array[RwNativeOpenList] = [RwNativeOpenList.new(), RwNativeOpenList.new(),]
	var scores: Array[Dictionary] = [{root_indices[0]: 0,}, {root_indices[1]: 0,},]
	var parents: Array[Dictionary] = [{}, {},]
	var directions: Array[Dictionary] = [{root_indices[0]: _heading_sector(heading_degrees),}, {root_indices[1]: 0,},]
	var closed: Array[Dictionary] = [{}, {},]
	queues[0].push(_heuristic(start, goal), start)
	queues[1].push(_heuristic(goal, start), goal)
	var reverse: bool
	var forward_end: int = -1
	var reverse_start: int = -1
	var best_forward_index: int = root_indices[0]
	var best_forward_distance: int = _heuristic(start, goal)
	for iteration: int in MAX_SEARCH_CELLS:
		if iteration >= 400:
			reverse = not reverse
		var side: int = 1 if reverse else 0
		if not queues[side].has_next():
			if not queues[1 - side].has_next():
				break
			continue
		var entry: Vector3i = queues[side].pop_min()
		var cell: Vector2i = Vector2i(entry.y, entry.z)
		var index: int = _cell_index(cell)
		if side == 0:
			var distance: int = _heuristic(cell, goal)
			if distance < best_forward_distance:
				best_forward_distance = distance
				best_forward_index = index
			if absi(cell.x - goal.x) <= goal_radius_cells and absi(cell.y - goal.y) <= goal_radius_cells:
				forward_end = index
				break
		if closed[1 - side].has(index):
			var previous_index: int = int(parents[side].get(index, index))
			if side == 0:
				forward_end = previous_index
				reverse_start = index
			else:
				forward_end = index
				reverse_start = previous_index
			break
		closed[side][index] = true
		var previous_direction: int = int(directions[side].get(index, 0))
		var maximum_turn: int = 1 if _clearance_at(cell, movement_type) > 1 else 2
		for direction_index: int in NEIGHBORS.size():
			if index != root_indices[side] and _direction_difference(previous_direction, direction_index) > maximum_turn:
				continue
			var offset: Vector2i = NEIGHBORS[direction_index]
			var neighbor: Vector2i = cell + offset
			var tile_cost: int = cost_at(neighbor, movement_type)
			if tile_cost < 0:
				continue
			if offset.x != 0 and offset.y != 0:
				if not is_passable(cell + Vector2i(offset.x, 0), movement_type) or not is_passable(cell + Vector2i(0, offset.y), movement_type):
					continue
			var neighbor_index: int = _cell_index(neighbor)
			if closed[side].has(neighbor_index):
				continue
			var step_cost: int = 15 if offset.x != 0 and offset.y != 0 else 11
			var object_cost: int = int(_object_costs[neighbor_index]) * 10 if not _object_costs.is_empty() else 0
			var new_score: int = int(scores[side][index]) + step_cost + tile_cost + object_cost + 4 - _clearance_at(neighbor, movement_type)
			if index != root_indices[side] or side == 0:
				new_score += _turn_penalty(previous_direction, direction_index)
			if new_score >= int(scores[side].get(neighbor_index, RwNativeOpenList.MAX_SCORE)):
				continue
			scores[side][neighbor_index] = new_score
			parents[side][neighbor_index] = index
			directions[side][neighbor_index] = direction_index
			queues[side].push(new_score + _heuristic(neighbor, roots[1 - side]), neighbor)
	if forward_end < 0:
		forward_end = best_forward_index
	var route_indices: Array[int] = []
	var current_index: int = forward_end
	while current_index >= 0:
		route_indices.append(current_index)
		current_index = int(parents[0].get(current_index, -1))
	route_indices.reverse()
	if reverse_start >= 0:
		current_index = reverse_start
		if route_indices.back() == current_index:
			current_index = int(parents[1].get(current_index, -1))
		while current_index >= 0:
			route_indices.append(current_index)
			current_index = int(parents[1].get(current_index, -1))
	if route_indices.size() > 1:
		route_indices.pop_front()
	var waypoints: Array[Vector2] = []
	for point_index: int in route_indices:
		@warning_ignore("integer_division")
		var point_cell: Vector2i = Vector2i(point_index % size.x, int(point_index / size.x))
		waypoints.append(target_position if point_cell == goal else cell_to_world(point_cell))
	return waypoints


## 将服务器预计算路径的末格替换为精确目标坐标
func path_from_cells(_start_position: Vector2, target_position: Vector2, cells: Array[Vector2i], _movement_type: String) -> Array[Vector2]:
	var raw_points: Array[Vector2] = []
	for index: int in maxi(cells.size() - 1, 0):
		raw_points.append(cell_to_world(cells[index]))
	if not cells.is_empty():
		raw_points.append(target_position)
	return raw_points


func has_clear_line(start_position: Vector2, end_position: Vector2, movement_type: String) -> bool:
	if not is_passable(world_to_cell(start_position), movement_type):
		return false
	var distance: float = start_position.distance_to(end_position)
	var step_length: float = float(mini(tile_size.x, tile_size.y)) * 0.25
	var steps: int = maxi(ceili(distance / step_length), 1)
	var previous_cell: Vector2i = world_to_cell(start_position)
	for step: int in range(1, steps + 1):
		var point: Vector2 = start_position.lerp(end_position, float(step) / float(steps))
		var cell: Vector2i = world_to_cell(point)
		if cell == previous_cell:
			continue
		if not is_passable(cell, movement_type):
			return false
		if cell.x != previous_cell.x and cell.y != previous_cell.y:
			if not is_passable(Vector2i(cell.x, previous_cell.y), movement_type) or not is_passable(Vector2i(previous_cell.x, cell.y), movement_type):
				return false
		previous_cell = cell
	return true


## 复现原版决定是否直接生成直线路径的格子检测
func has_source_direct_line(start_position: Vector2, end_position: Vector2, movement_type: String) -> bool:
	var start: Vector2i = world_to_cell(start_position)
	var target: Vector2i = world_to_cell(end_position)
	var difference: Vector2i = (target - start).abs()
	var step_x: int = 1 if target.x > start.x else -1
	var step_y: int = 1 if target.y > start.y else -1
	var remaining: int = 1 + difference.x + difference.y
	var balance: int = difference.x - difference.y
	var doubled_x: int = difference.x * 2
	var doubled_y: int = difference.y * 2
	var cell: Vector2i = start
	var cumulative_cost: int = 0
	var initial_cells_to_skip: int = 1
	while remaining > 0:
		var cell_cost: int = cost_at(cell, movement_type)
		if cell_cost < 0:
			return false
		if initial_cells_to_skip > 0:
			initial_cells_to_skip -= 1
		else:
			cumulative_cost += cell_cost
			if cumulative_cost >= 80:
				return false
		if balance > 0:
			cell.x += step_x
			balance -= doubled_y
		elif balance < 0:
			cell.y += step_y
			balance += doubled_x
		else:
			cell += Vector2i(step_x, step_y)
			balance += doubled_x - doubled_y
			remaining -= 1
		remaining -= 1
	return true


## 生成原版直线寻路点；路线不可直达时返回空数组
func source_direct_waypoints(start_position: Vector2, target_position: Vector2, movement_type: String) -> Array[Vector2]:
	if not has_source_direct_line(start_position, target_position, movement_type):
		return []
	return _straight_line_waypoints(start_position, target_position)


## 返回原版联机异步寻路结果至少等待的同步帧数
func network_path_delay_frames(start_position: Vector2, target_position: Vector2, movement_type: String) -> int:
	if movement_type == "AIR" or has_clear_line(start_position, target_position, movement_type):
		return 0
	var start: Vector2i = world_to_cell(start_position)
	var target: Vector2i = world_to_cell(target_position)
	var difference: Vector2i = (target - start).abs()
	if difference.x < 15 and difference.y < 15:
		return 12
	if difference.x < 50 and difference.y < 50:
		return 16
	if difference.x < 200 and difference.y < 200:
		return 24
	if difference.x < 400 and difference.y < 400:
		return 50
	if difference.x < 1000 and difference.y < 1000:
		return 100
	if difference.x < 2000 and difference.y < 2000:
		return 200
	return 300


## 复现原版直线可达时每隔 20 像素生成的中间路径点
func _straight_line_waypoints(start_position: Vector2, target_position: Vector2) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	var distance: float = start_position.distance_to(target_position)
	if distance <= 0.0:
		waypoints.append(target_position)
		return waypoints
	var direction: Vector2 = RwGameMath.path_direction(start_position, target_position)
	var segment_count: int = maxi(int(distance * 0.05 - 1.0), 0)
	var skip_first_segment: bool = segment_count >= 4
	var current_point: Vector2 = start_position
	for segment_index: int in mini(segment_count, 119):
		current_point += direction * 20.0
		if skip_first_segment and segment_index == 0:
			continue
		waypoints.append(current_point)
	if waypoints.size() < 119:
		waypoints.append(target_position)
	return waypoints


func _structure_center_offset(minimum_offset: Vector2i, maximum_offset: Vector2i) -> Vector2:
	return Vector2(
		1.0 if minimum_offset.x == 0 and maximum_offset.x == 1 else 0.5,
		1.0 if minimum_offset.y == 0 and maximum_offset.y == 1 else 0.5,
	)


func _smooth_points(start_position: Vector2, raw_points: Array[Vector2], movement_type: String) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	var anchor: Vector2 = start_position
	var next_index: int = 0
	while next_index < raw_points.size():
		var farthest_index: int = next_index
		for candidate_index: int in range(next_index + 1, raw_points.size()):
			if not has_clear_line(anchor, raw_points[candidate_index], movement_type):
				break
			farthest_index = candidate_index
		anchor = raw_points[farthest_index]
		waypoints.append(anchor)
		next_index = farthest_index + 1
	return waypoints


func _initialize(parsed: Dictionary) -> bool:
	size = parsed["size"]
	tile_size = parsed["tile_size"]
	var cell_count: int = size.x * size.y
	for tileset: Dictionary in parsed["tilesets"]:
		var first_gid: int = int(tileset["firstgid"])
		var properties_by_tile: Dictionary = tileset.get("unit_tiles", {})
		for tile_id: int in properties_by_tile:
			var properties: Dictionary = properties_by_tile[tile_id]
			var mask: int = 0
			if properties.has("water"):
				mask |= WATER
			if properties.has("cliff") or properties.has("cliff-soft") or properties.has("lava-cliff"):
				mask |= CLIFF
			if properties.has("large-cliff") or properties.has("trees"):
				mask |= LARGE_OBJECT
			if properties.has("lava") or properties.has("lava-cliff"):
				mask |= LAVA
			if properties.has("water-bridge"):
				mask |= WATER_BRIDGE
			if properties.has("res_pool"):
				mask |= RESOURCE_POOL
			var movement_cost: int
			if properties.has("large-rock") or properties.has("block-land"):
				movement_cost = -1
			elif properties.has("small-rock"):
				movement_cost = 40
			_tile_info[first_gid + tile_id] = Vector2i(mask, movement_cost)
	var ground_gids: PackedInt32Array = PackedInt32Array()
	var items_gids: PackedInt32Array = PackedInt32Array()
	var overlay_gids: PackedInt32Array = PackedInt32Array()
	for layer: Dictionary in parsed["layers"]:
		var layer_name: String = str(layer.get("name", "")).to_lower()
		if layer_name != "ground" and layer_name != "items" and layer_name != "objects" and layer_name != "pathingoverride":
			continue
		var gids: PackedInt32Array = _decode_gids(layer)
		if gids.size() != cell_count:
			return false
		match layer_name:
			"ground":
				ground_gids = gids
			"items", "objects":
				items_gids = gids
			"pathingoverride":
				overlay_gids = gids
	if ground_gids.size() != cell_count:
		return false
	_land_costs.resize(cell_count)
	_building_costs.resize(cell_count)
	_hover_costs.resize(cell_count)
	_water_costs.resize(cell_count)
	_cliff_costs.resize(cell_count)
	_cliff_water_costs.resize(cell_count)
	_water_tiles.resize(cell_count)
	_resource_pool_tiles.resize(cell_count)
	_structure_blocks.resize(cell_count)
	for index: int in cell_count:
		var ground_info: Vector2i = _tile_info.get(ground_gids[index], Vector2i.ZERO)
		var items_info: Vector2i
		if items_gids.size() == cell_count:
			items_info = _tile_info.get(items_gids[index], Vector2i.ZERO)
		var overlay_info: Vector2i
		if overlay_gids.size() == cell_count:
			overlay_info = _tile_info.get(overlay_gids[index], Vector2i.ZERO)
		_water_tiles[index] = 1 if ground_info.x & WATER else 0
		_resource_pool_tiles[index] = 1 if items_info.x & RESOURCE_POOL or ground_info.x & RESOURCE_POOL else 0
		var has_overlay: bool = overlay_gids.size() == cell_count and overlay_gids[index] != 0
		_land_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "LAND")
		_building_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "BUILDING")
		_hover_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "HOVER")
		_water_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "WATER")
		_cliff_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "OVER_CLIFF")
		_cliff_water_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "OVER_CLIFF_WATER")
	return true


func _decode_gids(layer: Dictionary) -> PackedInt32Array:
	var raw: PackedByteArray = RwTmxLoader.decode_layer(layer, size)
	var gids: PackedInt32Array = PackedInt32Array()
	if raw.size() != size.x * size.y * 4:
		return gids
	gids.resize(size.x * size.y)
	for index: int in gids.size():
		var offset: int = index * 4
		gids[index] = (raw[offset] | (raw[offset + 1] << 8) | (raw[offset + 2] << 16) | (raw[offset + 3] << 24)) & RwTmxLoader.TILE_GID_MASK
	return gids


func _tile_cost(ground: Vector2i, items: Vector2i, overlay: Vector2i, has_overlay: bool, movement_type: String) -> int:
	var cost: int = _terrain_cost(ground.x, movement_type)
	if movement_type == "LAND" and items.x & RESOURCE_POOL:
		cost = -1
	if items.x & LARGE_OBJECT and movement_type not in ["OVER_CLIFF", "OVER_CLIFF_WATER",]:
		cost = -1
	if cost == 0:
		cost = items.y
	if cost == 0:
		cost = ground.y
	if has_overlay:
		cost = _terrain_cost(overlay.x, movement_type)
		if cost == 0:
			cost = overlay.y
	return cost


func _terrain_cost(mask: int, movement_type: String) -> int:
	if mask & LAVA:
		return -1
	if mask & LARGE_OBJECT and movement_type not in ["OVER_CLIFF", "OVER_CLIFF_WATER",]:
		return -1
	if mask & WATER and movement_type not in ["WATER", "HOVER", "OVER_CLIFF_WATER",]:
		return -1
	if mask & CLIFF and movement_type not in ["HOVER", "OVER_CLIFF", "OVER_CLIFF_WATER",]:
		return -1
	if movement_type == "WATER" and not (mask & (WATER | WATER_BRIDGE)):
		return -1
	return 0


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _cell_index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func _heuristic(cell: Vector2i, goal: Vector2i) -> int:
	var dx: int = absi(cell.x - goal.x)
	var dy: int = absi(cell.y - goal.y)
	return 11 * maxi(dx, dy) + 4 * mini(dx, dy)


func _clearance_at(cell: Vector2i, movement_type: String) -> int:
	if movement_type == "AIR":
		return 4
	if _land_clearance.is_empty():
		finalize_obstacles()
	var index: int = _cell_index(cell)
	match movement_type:
		"BUILDING":
			return _building_clearance[index]
		"HOVER":
			return _hover_clearance[index]
		"WATER":
			return _water_clearance[index]
		"OVER_CLIFF":
			return _cliff_clearance[index]
		"OVER_CLIFF_WATER":
			return _cliff_water_clearance[index]
		_:
			return _land_clearance[index]


func _build_clearance(costs: PackedInt32Array) -> PackedByteArray:
	var distances: PackedByteArray = PackedByteArray()
	distances.resize(size.x * size.y)
	distances.fill(4)
	for y: int in size.y:
		for x: int in size.x:
			var index: int = y * size.x + x
			if costs[index] < 0 or _structure_blocks[index] != 0:
				distances[index] = 0
				continue
			var clearance: int = mini(4, x + 1)
			clearance = mini(clearance, y + 1)
			clearance = mini(clearance, size.x - x)
			clearance = mini(clearance, size.y - y)
			if x > 0:
				clearance = mini(clearance, distances[index - 1] + 1)
			if y > 0:
				clearance = mini(clearance, distances[index - size.x] + 1)
				if x > 0:
					clearance = mini(clearance, distances[index - size.x - 1] + 1)
				if x + 1 < size.x:
					clearance = mini(clearance, distances[index - size.x + 1] + 1)
			distances[index] = clearance
	for y: int in range(size.y - 1, -1, -1):
		for x: int in range(size.x - 1, -1, -1):
			var index: int = y * size.x + x
			var clearance: int = distances[index]
			if x + 1 < size.x:
				clearance = mini(clearance, distances[index + 1] + 1)
			if y + 1 < size.y:
				clearance = mini(clearance, distances[index + size.x] + 1)
				if x > 0:
					clearance = mini(clearance, distances[index + size.x - 1] + 1)
				if x + 1 < size.x:
					clearance = mini(clearance, distances[index + size.x + 1] + 1)
			distances[index] = clearance
	return distances


func _turn_penalty(previous_direction: int, next_direction: int) -> int:
	var difference: int = _direction_difference(previous_direction, next_direction)
	if difference == 0:
		return 0
	if difference == 1:
		return 4
	if difference == 2:
		return 21
	return 25


func _direction_difference(previous_direction: int, next_direction: int) -> int:
	var difference: int = absi(previous_direction - next_direction)
	return mini(difference, 8 - difference)


func _heading_sector(heading_degrees: float) -> int:
	return wrapi(int(heading_degrees / 360.0 * 8.0 + 0.5), 0, 8)


func _heap_push(heap: Array[Vector2i], value: Vector2i) -> void:
	heap.append(value)
	var index: int = heap.size() - 1
	while index > 0:
		@warning_ignore("integer_division")
		var parent_index: int = int((index - 1) / 2)
		if not _heap_less(value, heap[parent_index]):
			break
		heap[index] = heap[parent_index]
		index = parent_index
	heap[index] = value


func _heap_pop(heap: Array[Vector2i]) -> Vector2i:
	var first: Vector2i = heap[0]
	var last: Vector2i = heap.pop_back()
	if heap.is_empty():
		return first
	var index: int = 0
	while index * 2 + 1 < heap.size():
		var child_index: int = index * 2 + 1
		if child_index + 1 < heap.size() and _heap_less(heap[child_index + 1], heap[child_index]):
			child_index += 1
		if not _heap_less(heap[child_index], last):
			break
		heap[index] = heap[child_index]
		index = child_index
	heap[index] = last
	return first


func _heap_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x != right.x:
		return left.x < right.x
	var left_x: int = left.y % size.x
	var right_x: int = right.y % size.x
	if left_x != right_x:
		return left_x < right_x
	@warning_ignore("integer_division")
	return int(left.y / size.x) < int(right.y / size.x)
