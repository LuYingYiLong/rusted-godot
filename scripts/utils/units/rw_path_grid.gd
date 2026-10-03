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
var _hover_costs: PackedInt32Array
var _water_costs: PackedInt32Array
var _water_tiles: PackedByteArray
var _resource_pool_tiles: PackedByteArray
var _structure_blocks: PackedByteArray
var _land_clearance: PackedByteArray
var _hover_clearance: PackedByteArray
var _water_clearance: PackedByteArray
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
		"HOVER":
			return _hover_costs[index]
		"WATER":
			return _water_costs[index]
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
	_hover_clearance.clear()
	_water_clearance.clear()


## 建筑被摧毁后清除对应格子的动态阻挡
func unblock_structure(world_position: Vector2, minimum_offset: Vector2i, maximum_offset: Vector2i) -> void:
	var center: Vector2i = structure_anchor_cell(world_position, minimum_offset, maximum_offset)
	for y: int in range(center.y + minimum_offset.y, center.y + maximum_offset.y + 1):
		for x: int in range(center.x + minimum_offset.x, center.x + maximum_offset.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _is_in_bounds(cell):
				_structure_blocks[_cell_index(cell)] = 0
	_land_clearance.clear()
	_hover_clearance.clear()
	_water_clearance.clear()


func finalize_obstacles() -> void:
	_land_clearance = _build_clearance(_land_costs)
	_hover_clearance = _build_clearance(_hover_costs)
	_water_clearance = _build_clearance(_water_costs)


func find_path(start_position: Vector2, target_position: Vector2, movement_type: String) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	var start: Vector2i = world_to_cell(start_position)
	var goal: Vector2i = world_to_cell(target_position)
	if not _is_in_bounds(start) or not _is_in_bounds(goal):
		return waypoints
	if movement_type == "AIR" or has_clear_line(start_position, target_position, movement_type):
		waypoints.append(target_position)
		return waypoints
	var cell_count: int = size.x * size.y
	var scores: PackedInt32Array = PackedInt32Array()
	scores.resize(cell_count)
	scores.fill(2_147_483_647)
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(cell_count)
	parents.fill(-1)
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(cell_count)
	var open_nodes: Array[Vector2i] = []
	var start_index: int = _cell_index(start)
	var best_index: int = start_index
	var best_distance: int = _heuristic(start, goal)
	scores[start_index] = 0
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
			if parents[index] >= 0:
				@warning_ignore("integer_division")
				var parent_cell: Vector2i = Vector2i(parents[index] % size.x, int(parents[index] / size.x))
				var previous_direction: int = NEIGHBORS.find(cell - parent_cell)
				if previous_direction >= 0:
					new_score += _turn_penalty(previous_direction, direction_index)
			if new_score >= scores[neighbor_index]:
				continue
			scores[neighbor_index] = new_score
			parents[neighbor_index] = index
			_heap_push(open_nodes, Vector2i(new_score + _heuristic(neighbor, goal), neighbor_index))
	if best_index == start_index:
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
	return _smooth_points(start_position, raw_points, movement_type)


func path_from_cells(start_position: Vector2, target_position: Vector2, cells: Array[Vector2i], movement_type: String) -> Array[Vector2]:
	var raw_points: Array[Vector2] = []
	for cell: Vector2i in cells:
		if not is_passable(cell, movement_type):
			return []
		raw_points.append(cell_to_world(cell))
	if not raw_points.is_empty() and has_clear_line(raw_points.back(), target_position, movement_type):
		raw_points.append(target_position)
	return _smooth_points(start_position, raw_points, movement_type)


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
	_hover_costs.resize(cell_count)
	_water_costs.resize(cell_count)
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
		_hover_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "HOVER")
		_water_costs[index] = _tile_cost(ground_info, items_info, overlay_info, has_overlay, "WATER")
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
	if items.x & LARGE_OBJECT:
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
	if mask & LAVA or mask & LARGE_OBJECT:
		return -1
	if movement_type == "LAND" and mask & (WATER | CLIFF):
		return -1
	if movement_type == "WATER" and (mask & CLIFF or not (mask & (WATER | WATER_BRIDGE))):
		return -1
	return 0


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _cell_index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func _heuristic(cell: Vector2i, goal: Vector2i) -> int:
	var dx: int = absi(cell.x - goal.x)
	var dy: int = absi(cell.y - goal.y)
	return 10 * maxi(dx, dy) + 4 * mini(dx, dy)


func _clearance_at(cell: Vector2i, movement_type: String) -> int:
	if movement_type == "AIR":
		return 4
	if _land_clearance.is_empty():
		finalize_obstacles()
	var index: int = _cell_index(cell)
	match movement_type:
		"HOVER":
			return _hover_clearance[index]
		"WATER":
			return _water_clearance[index]
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
	var difference: int = absi(previous_direction - next_direction)
	difference = mini(difference, 8 - difference)
	if difference == 0:
		return 0
	if difference == 1:
		return 4
	if difference == 2:
		return 21
	return 25


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
	return left.x < right.x or left.x == right.x and left.y < right.y
