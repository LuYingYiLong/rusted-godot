class_name RwVanillaEconomy
extends RefCounted

signal balance_changed(team_slot: int, resource_id: String, balance: float, growth: float)

const INCOME_UPDATE_FRAMES: int = 10
const INCOME_RATE_PERIOD: float = 40.0
const COMMAND_CENTER_INCOME_RATE: float = 18.0
const MAX_CREDITS: float = 999_999_999.0

var _balances: Dictionary
var _command_center_counts: Dictionary
var _income_multiplier: float = 1.0
var _last_frame: int
var _sources_ready: bool


func clear() -> void:
	_balances.clear()
	_command_center_counts.clear()
	_income_multiplier = 1.0
	_last_frame = 0
	_sources_ready = false


func initialize(players: Array[Dictionary], income_multiplier: float) -> void:
	clear()
	_income_multiplier = maxf(income_multiplier, 0.0)
	for player: Dictionary in players:
		if bool(player.get("spectator", false)):
			continue
		var slot: int = int(player.get("slot", -1))
		if slot < 0:
			continue
		_balances[slot] = float(player.get("credits", 0))
		_command_center_counts[slot] = 0


func set_command_centers(counts: Dictionary) -> void:
	for slot: int in _balances:
		_command_center_counts[slot] = maxi(int(counts.get(slot, 0)), 0)
	_sources_ready = true
	for slot: int in _balances:
		balance_changed.emit(slot, "credits", get_balance(slot, "credits"), get_income_rate(slot, "credits"))


func set_income_multiplier(income_multiplier: float) -> void:
	var next_multiplier: float = maxf(income_multiplier, 0.0)
	if is_equal_approx(next_multiplier, _income_multiplier):
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
	if payout_count <= 0:
		return
	for slot: int in _balances:
		var center_count: int = int(_command_center_counts.get(slot, 0))
		if center_count <= 0:
			continue
		var payout: float = COMMAND_CENTER_INCOME_RATE * center_count * _income_multiplier * float(INCOME_UPDATE_FRAMES) / INCOME_RATE_PERIOD
		_balances[slot] = minf(float(_balances[slot]) + payout * payout_count, MAX_CREDITS)
		balance_changed.emit(slot, "credits", float(_balances[slot]), get_income_rate(slot, "credits"))


func has_team(team_slot: int) -> bool:
	return _balances.has(team_slot)


func get_balance(team_slot: int, resource_id: String) -> float:
	if resource_id != "credits":
		return 0.0
	return float(_balances.get(team_slot, 0.0))


func get_income_rate(team_slot: int, resource_id: String) -> float:
	if resource_id != "credits" or not _sources_ready:
		return 0.0
	var count: int = int(_command_center_counts.get(team_slot, 0))
	return float(int(COMMAND_CENTER_INCOME_RATE * count * _income_multiplier))
