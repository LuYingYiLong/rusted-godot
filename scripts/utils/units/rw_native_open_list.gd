extends RefCounted
class_name RwNativeOpenList
## 按原版路径开放表的同分顺序返回网格节点

const MAX_SCORE: int = 2_147_483_647

var _current_score: int = MAX_SCORE
var _current: Array[Vector3i]
var _other: Array[Vector3i]


func has_next() -> bool:
	return not _current.is_empty() or not _other.is_empty()


func push(score: int, cell: Vector2i) -> void:
	var node: Vector3i = Vector3i(score, cell.x, cell.y)
	if score <= _current_score:
		if score < _current_score:
			_other.append_array(_current)
			_current.clear()
			_current_score = score
		_current.append(node)
	else:
		_other.append(node)


func pop_min() -> Vector3i:
	if not _current.is_empty():
		return _current.pop_back()
	var minimum: int = MAX_SCORE
	for node: Vector3i in _other:
		minimum = mini(minimum, node.x)
	for index: int in range(_other.size() - 1, -1, -1):
		if _other[index].x != minimum:
			continue
		_current.append(_other[index])
		_other[index] = _other.back()
		_other.pop_back()
	_current_score = minimum
	return _current.pop_back()
