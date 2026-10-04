class_name RwBattleTimeline
extends RefCounted

signal frame_advanced(frame: int, next_blocking_frame: int)
signal commands_reached(frame: int, commands: Array[Dictionary])

const TICKS_PER_SECOND: float = 60.0
const MAX_STEPS_PER_UPDATE: int = 120
const MAX_FRAME_LEAD: int = 216_000

var current_frame: int
var next_blocking_frame: int
## 原版同步步长，数值为 2.0 时每秒推进约 30 帧
var step_rate: float = 1.0

var _fractional_frames: float
var _pending_commands: Dictionary


func reset() -> void:
	current_frame = 0
	next_blocking_frame = 0
	step_rate = 1.0
	_fractional_frames = 0.0
	_pending_commands.clear()
	frame_advanced.emit(current_frame, next_blocking_frame)


func receive_sync_packet(payload: PackedByteArray) -> String:
	var packet: Dictionary = RwBattleCommandReader.read_frame_packet(payload)
	var error: String = str(packet.get("error", ""))
	if not error.is_empty():
		return error
	var new_boundary: int = int(packet["next_blocking_frame"])
	if new_boundary <= next_blocking_frame or new_boundary > current_frame + MAX_FRAME_LEAD:
		return "Sync frame boundary is out of range"
	var commands: Array[Dictionary] = packet["commands"]
	if not commands.is_empty():
		_pending_commands[next_blocking_frame] = commands
	next_blocking_frame = new_boundary
	frame_advanced.emit(current_frame, next_blocking_frame)
	return ""


func advance(delta: float) -> void:
	if current_frame >= next_blocking_frame:
		_fractional_frames = 0.0
		return
	_fractional_frames += minf(delta, 0.25) * TICKS_PER_SECOND / step_rate
	var steps: int = 0
	while _fractional_frames >= 1.0 and current_frame < next_blocking_frame and steps < MAX_STEPS_PER_UPDATE:
		if _pending_commands.has(current_frame):
			var commands: Array[Dictionary] = _pending_commands[current_frame]
			_pending_commands.erase(current_frame)
			commands_reached.emit(current_frame, commands)
		current_frame += 1
		_fractional_frames -= 1.0
		steps += 1
		frame_advanced.emit(current_frame, next_blocking_frame)


## 应用服务器同步命令中的步长变化
func set_step_rate(value: float) -> void:
	if value >= 0.1:
		step_rate = value
