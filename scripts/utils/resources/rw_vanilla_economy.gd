extends RefCounted
class_name RwVanillaEconomy
## 保存各队的资金余额并执行原版收入和支出规则

signal balance_changed(team_slot: int, resource_id: String, balance: float, growth: float)

const INCOME_UPDATE_FRAMES: int = 10
const INCOME_RATE_PERIOD: float = 40.0
const COMMAND_CENTER_INCOME_RATE: float = 18.0
const EXTRACTOR_INCOME_RATE: float = 8.0
const MAX_CREDITS: float = 999_999_999.0

var _balances: Dictionary
var _team_income_multipliers: Dictionary[int, float]
var _command_center_counts: Dictionary
var _extractor_counts: Dictionary
var _income_sources: Dictionary
var _income_multiplier: float = 1.0
var _last_frame: int
var _sources_ready: bool


func clear() -> void:
	for object_id: int in _income_sources:
		var unit_state: RwUnitState = _income_sources[object_id]["state"]
		if unit_state.state_changed.is_connected(_on_income_state_changed):
			unit_state.state_changed.disconnect(_on_income_state_changed)
	_balances.clear()
	_team_income_multipliers.clear()
	_command_center_counts.clear()
	_extractor_counts.clear()
	_income_sources.clear()
	_income_multiplier = 1.0
	_last_frame = 0
	_sources_ready = false


func initialize(players: Array[Dictionary], income_multiplier: float) -> void:
	clear()
	_income_multiplier = RwGameMath.float32(maxf(income_multiplier, 0.0))
	for player: Dictionary in players:
		if bool(player.get("spectator", false)):
			continue
		var slot: int = int(player.get("slot", -1))
		if slot < 0:
			continue
		_balances[slot] = float(player.get("credits", 0))
		_team_income_multipliers[slot] = _ai_income_multiplier(player)
		_command_center_counts[slot] = 0
		_extractor_counts[slot] = 0


func set_extractors(counts: Dictionary) -> void:
	for slot: int in _balances:
		_extractor_counts[slot] = maxi(int(counts.get(slot, 0)), 0)


func add_extractor(team_slot: int) -> void:
	if not _balances.has(team_slot):
		return
	_extractor_counts[team_slot] = int(_extractor_counts.get(team_slot, 0)) + 1
	if _sources_ready:
		balance_changed.emit(team_slot, "credits", get_balance(team_slot, "credits"), get_income_rate(team_slot, "credits"))


## 注册独立计时的收入单位，包含指挥中心和内置 INI 收入建筑
func register_income_unit(unit_state: RwUnitState) -> void:
	if unit_state == null or unit_state.is_dead or not unit_state.team.is_valid_int() or not has_unit_income(unit_state):
		return
	var team_slot: int = unit_state.team.to_int()
	if not _balances.has(team_slot) or _income_sources.has(unit_state.object_id):
		return
	_income_sources[unit_state.object_id] = {"state": unit_state, "timer": 0.0, "rate": _active_extractor_rate(unit_state),}
	unit_state.state_changed.connect(_on_income_state_changed)
	if _sources_ready:
		balance_changed.emit(team_slot, "credits", get_balance(team_slot, "credits"), get_income_rate(team_slot, "credits"))


## 判断原生抽取器或内置 INI 单位是否定期产生资金
func has_unit_income(unit_state: RwUnitState) -> bool:
	if unit_state == null:
		return false
	if unit_state.source_id == "vanilla":
		return unit_state.unit_name in ["commandCenter", "extractor", "fabricator",]
	var spec: Dictionary = RwBuiltinUnitSpecs.SPECS.get(unit_state.unit_name, {})
	return float(spec.get("credit_income", 0.0)) > 0.0


## 移除收入单位并断开状态监听
func unregister_income_unit(object_id: int) -> void:
	if not _income_sources.has(object_id):
		return
	var source: Dictionary = _income_sources[object_id]
	var unit_state: RwUnitState = source["state"]
	var team_slot: int = unit_state.team.to_int()
	if unit_state.state_changed.is_connected(_on_income_state_changed):
		unit_state.state_changed.disconnect(_on_income_state_changed)
	_income_sources.erase(object_id)
	if _sources_ready:
		balance_changed.emit(team_slot, "credits", get_balance(team_slot, "credits"), get_income_rate(team_slot, "credits"))


## 原版形态转换保留收入计时，替换状态对象时重新连接监听
func replace_income_unit(unit_state: RwUnitState) -> void:
	var source: Dictionary = _income_sources.get(unit_state.object_id, {})
	var timer: float = float(source.get("timer", 0.0))
	unregister_income_unit(unit_state.object_id)
	register_income_unit(unit_state)
	if _income_sources.has(unit_state.object_id):
		_income_sources[unit_state.object_id]["timer"] = timer


func set_command_centers(counts: Dictionary) -> void:
	for slot: int in _balances:
		_command_center_counts[slot] = maxi(int(counts.get(slot, 0)), 0)
	_sources_ready = true
	for slot: int in _balances:
		balance_changed.emit(slot, "credits", get_balance(slot, "credits"), get_income_rate(slot, "credits"))


## 指挥中心被摧毁时更新该队的资金增长率
func remove_command_center(team_slot: int) -> void:
	if not _command_center_counts.has(team_slot):
		return
	_command_center_counts[team_slot] = maxi(int(_command_center_counts[team_slot]) - 1, 0)


## 指挥中心建成时更新该队的资金增长率
func add_command_center(team_slot: int) -> void:
	_command_center_counts[team_slot] = int(_command_center_counts.get(team_slot, 0)) + 1
	if _sources_ready:
		balance_changed.emit(team_slot, "credits", get_balance(team_slot, "credits"), get_income_rate(team_slot, "credits"))


func set_income_multiplier(income_multiplier: float) -> void:
	var next_multiplier: float = RwGameMath.float32(maxf(income_multiplier, 0.0))
	if next_multiplier == _income_multiplier:
		return
	_income_multiplier = next_multiplier
	if _sources_ready:
		for slot: int in _balances:
			balance_changed.emit(slot, "credits", get_balance(slot, "credits"), get_income_rate(slot, "credits"))


func advance_to(frame: int) -> void:
	if not _sources_ready or frame <= _last_frame:
		return
	@warning_ignore("integer_division")
	var previous_payout: int = int(_last_frame / INCOME_UPDATE_FRAMES)
	@warning_ignore("integer_division")
	var current_payout: int = int(frame / INCOME_UPDATE_FRAMES)
	var payout_count: int = current_payout - previous_payout
	_last_frame = frame
	var payouts: Dictionary = {}
	for slot: int in _balances:
		var pooled_rate: float = _pooled_income_rate(slot)
		if pooled_rate > 0.0 and payout_count > 0:
			payouts[slot] = pooled_rate * float(INCOME_UPDATE_FRAMES * payout_count) / INCOME_RATE_PERIOD
	for slot: int in payouts:
		var income: float = RwGameMath.float32(RwGameMath.float32(float(payouts[slot]) * float(_team_income_multipliers.get(slot, 1.0))) * _income_multiplier)
		_balances[slot] = minf(float(_balances[slot]) + income, MAX_CREDITS)
		balance_changed.emit(slot, "credits", float(_balances[slot]), get_income_rate(slot, "credits"))


## 在当前单位更新时推进收入计时，施工完成当帧即可计入第一步
func advance_unit_income(unit_state: RwUnitState, step_delta: float) -> void:
	var source: Dictionary = _income_sources.get(unit_state.object_id, {})
	if source.is_empty():
		return
	# 转换发生在本步的生产阶段，收入需使用转换后的状态与定义
	unit_state = source["state"]
	if unit_state.is_dead or unit_state.build_progress < 1.0:
		return
	var delay: float = float(INCOME_UPDATE_FRAMES)
	var amount: float = RwGameMath.float32(_active_extractor_rate(unit_state) * 0.25)
	if unit_state.source_id == "custom":
		var spec: Dictionary = RwBuiltinUnitSpecs.SPECS.get(unit_state.unit_name, {})
		delay = float(spec.get("income_delay", 40))
		amount = RwGameMath.float32(float(spec.get("credit_income", 0.0)))
	var timer: float = RwGameMath.float32(float(source["timer"]) + step_delta)
	if timer > RwGameMath.float32(delay - RwGameMath.float32(0.1)):
		timer = RwGameMath.float32(timer - delay)
		var slot: int = unit_state.team.to_int()
		var income: float = RwGameMath.float32(RwGameMath.float32(amount * float(_team_income_multipliers.get(slot, 1.0))) * _income_multiplier)
		_balances[slot] = minf(float(_balances[slot]) + income, MAX_CREDITS)
		balance_changed.emit(slot, "credits", float(_balances[slot]), get_income_rate(slot, "credits"))
	source["timer"] = timer


func has_team(team_slot: int) -> bool:
	return _balances.has(team_slot)


## 返回已初始化的队伍编号，供帧末探针记录资金
func get_team_slots() -> Array[int]:
	var slots: Array[int]
	slots.assign(_balances.keys())
	slots.sort()
	return slots


func get_balance(team_slot: int, resource_id: String) -> float:
	if resource_id != "credits":
		return 0.0
	return float(_balances.get(team_slot, 0.0))


func try_spend_credits(team_slot: int, amount: float) -> bool:
	if amount < 0.0 or not _balances.has(team_slot) or float(_balances[team_slot]) < amount:
		return false
	_balances[team_slot] = float(_balances[team_slot]) - amount
	balance_changed.emit(team_slot, "credits", float(_balances[team_slot]), get_income_rate(team_slot, "credits"))
	return true


func refund_credits(team_slot: int, amount: float) -> void:
	if amount <= 0.0 or not _balances.has(team_slot):
		return
	_balances[team_slot] = minf(float(_balances[team_slot]) + amount, MAX_CREDITS)
	balance_changed.emit(team_slot, "credits", float(_balances[team_slot]), get_income_rate(team_slot, "credits"))


func get_income_rate(team_slot: int, resource_id: String) -> float:
	if resource_id != "credits" or not _sources_ready:
		return 0.0
	return float(int(_base_income_rate(team_slot) * float(_team_income_multipliers.get(team_slot, 1.0)) * _income_multiplier))


func _base_income_rate(team_slot: int) -> float:
	var income_rate: float = _pooled_income_rate(team_slot)
	for object_id: int in _income_sources:
		var unit_state: RwUnitState = _income_sources[object_id]["state"]
		if unit_state.team == str(team_slot):
			var rate: float = _active_extractor_rate(unit_state)
			if unit_state.source_id == "custom":
				var spec: Dictionary = RwBuiltinUnitSpecs.SPECS.get(unit_state.unit_name, {})
				rate *= RwGameMath.float32(INCOME_RATE_PERIOD / float(spec.get("income_delay", 40)))
			income_rate += rate
	return income_rate


## 原版 n.E 根据 AI 难度增加收入，实际余额仍使用 double 保存
func _ai_income_multiplier(player: Dictionary) -> float:
	if not bool(player.get("ai", false)):
		return 1.0
	var difficulty: int = int(player.get("ai_difficulty", 0))
	var coefficient: float = RwGameMath.float32(0.4 if difficulty > 0 else 0.3)
	var multiplier: float = RwGameMath.float32(1.0 + RwGameMath.float32(float(difficulty) * coefficient))
	if difficulty == 3:
		multiplier = RwGameMath.float32(multiplier + 1.0)
	return maxf(multiplier, RwGameMath.float32(0.1))


func _pooled_income_rate(team_slot: int) -> float:
	var registered_centers: int
	for source: Dictionary in _income_sources.values():
		var unit_state: RwUnitState = source["state"]
		if unit_state.unit_name == "commandCenter" and unit_state.team == str(team_slot):
			registered_centers += 1
	return COMMAND_CENTER_INCOME_RATE * maxi(int(_command_center_counts.get(team_slot, 0)) - registered_centers, 0) + EXTRACTOR_INCOME_RATE * int(_extractor_counts.get(team_slot, 0))


func _extractor_rate(level: int) -> float:
	if level >= 3:
		return 18.0
	if level == 2:
		return 12.0
	return EXTRACTOR_INCOME_RATE


func _active_extractor_rate(unit_state: RwUnitState) -> float:
	if unit_state.is_dead or unit_state.build_progress < 1.0:
		return 0.0
	if unit_state.source_id == "custom":
		var spec: Dictionary = RwBuiltinUnitSpecs.SPECS.get(unit_state.unit_name, {})
		return float(spec.get("credit_income", 0.0))
	if unit_state.unit_name == "commandCenter":
		return COMMAND_CENTER_INCOME_RATE
	if unit_state.unit_name == "fabricator":
		if unit_state.tech_level >= 3:
			return 14.0
		return 7.0 if unit_state.tech_level == 2 else 2.0
	return _extractor_rate(unit_state.tech_level)


func _on_income_state_changed(unit_state: RwUnitState) -> void:
	if unit_state.is_dead:
		unregister_income_unit(unit_state.object_id)
		return
	var source: Dictionary = _income_sources.get(unit_state.object_id, {})
	if source.is_empty():
		return
	var next_rate: float = _active_extractor_rate(unit_state)
	if is_equal_approx(float(source["rate"]), next_rate):
		return
	source["rate"] = next_rate
	if _sources_ready:
		var team_slot: int = unit_state.team.to_int()
		balance_changed.emit(team_slot, "credits", get_balance(team_slot, "credits"), get_income_rate(team_slot, "credits"))
