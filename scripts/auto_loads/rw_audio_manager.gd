class_name RwAudioManager
extends Node
## 播放循环音乐、玩家反馈和战场音效池
## 将其场景添加为 AudioManager 自动加载，以便在场景之间共享语音池

## 在音乐开始播放后触发
signal music_started(track_id: StringName)
## 当前音乐曲目播放完或被停止时触发
signal music_stopped()

## 最大同时 UI 声音数量；达到上限时会重用最旧的声音
@export_range(1, 32, 1) var ui_voice_limit: int
## 最大同时发声单元；当达到上限时，会重复使用最旧的声音
@export_range(1, 64, 1) var unit_voice_limit: int
## 音乐的基础音量，单位为分贝
@export var music_volume_db: float
## 用户界面反馈的基础音量，单位为分贝
@export var ui_volume_db: float
## 战场声音的基础音量，单位是分贝
@export var unit_volume_db: float

@onready var music_player: AudioStreamPlayer = %MusicPlayer
@onready var ui_pool: Node = %UiPool
@onready var unit_pool: Node = %UnitPool

var _ui_voices: Array[AudioStreamPlayer]
var _unit_voices: Array[AudioStreamPlayer]
var _voice_started_at: Dictionary
var _voice_serial: int
var _music_track_id: StringName
var _music_loop: bool
var _music_tween: Tween


func _ready() -> void:
	for index: int in ui_voice_limit:
		_ui_voices.append(_create_voice(ui_pool, "UiVoice%d" % index))
	for index: int in unit_voice_limit:
		_unit_voices.append(_create_voice(unit_pool, "UnitVoice%d" % index))


func _exit_tree() -> void:
	_cancel_music_tween()
	music_player.stop()
	music_player.stream = null
	for voice: AudioStreamPlayer in _ui_voices + _unit_voices:
		voice.stop()
		voice.stream = null


## 播放一个已编目的曲目，并带有短暂的淡入效果
## 如果 [param track_id] 未知，则返回 [code]false[/code]
func play_music(track_id: StringName, fade_seconds: float = 0.4) -> bool:
	var stream: AudioStream = RwAudioCatalog.music_track(track_id)
	if stream == null:
		return false
	return play_music_stream(stream, track_id, true, fade_seconds)


## 播放任何音乐流，Ogg 流会被复制以保持它们的循环标志本地化
## 当 [param stream] 为 null 时返回 [code]false[/code]
func play_music_stream(stream: AudioStream, track_id: StringName = &"", loop: bool = true, fade_seconds: float = 0.4) -> bool:
	if stream == null:
		return false
	if not track_id.is_empty() and _music_track_id == track_id and music_player.playing:
		_cancel_music_tween()
		music_player.volume_db = music_volume_db
		return true
	_cancel_music_tween()
	music_player.stop()
	var playback_stream: AudioStream = stream.duplicate() as AudioStream
	if playback_stream is AudioStreamOggVorbis:
		(playback_stream as AudioStreamOggVorbis).loop = loop
	music_player.stream = playback_stream
	_music_track_id = track_id
	_music_loop = loop
	if fade_seconds > 0.0:
		music_player.volume_db = -60.0
		_music_tween = create_tween()
		_music_tween.tween_property(music_player, "volume_db", music_volume_db, fade_seconds)
	else:
		music_player.volume_db = music_volume_db
	music_player.play()
	music_started.emit(track_id)
	return true


## 立即停止音乐或在 [param fade_seconds] 秒内淡出
func stop_music(fade_seconds: float = 0.4) -> void:
	_cancel_music_tween()
	if not music_player.playing:
		_finish_music_stop()
		return
	if fade_seconds <= 0.0:
		_finish_music_stop()
		return
	_music_tween = create_tween()
	_music_tween.tween_property(music_player, "volume_db", -60.0, fade_seconds)
	_music_tween.finished.connect(_finish_music_stop)


## 播放已归档的玩家反馈声音，例如移动指令提示音
## 如果 [param sound_id] 未知，则返回 [code]false[/code]
func play_ui(sound_id: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_ui_stream(RwAudioCatalog.ui_sound(sound_id), volume_offset_db, pitch_scale)


## 通过界面语音池播放任意音流
func play_ui_stream(stream: AudioStream, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return _play_sound(_ui_voices, stream, ui_volume_db + volume_offset_db, pitch_scale)


## 播放已编目的非定位战场音效
func play_unit(sound_id: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_unit_stream(RwAudioCatalog.unit_sound(sound_id), volume_offset_db, pitch_scale)


## 通过设备的声音池播放任意音频流
func play_unit_stream(stream: AudioStream, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return _play_sound(_unit_voices, stream, unit_volume_db + volume_offset_db, pitch_scale)


## 播放经过听者距离衰减的已归档战场声音
## 当在[param hearing_radius]之外时返回[code]false[/code]
func play_unit_at(sound_id: StringName, world_position: Vector2, listener_position: Vector2, hearing_radius: float = 900.0, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_unit_stream_at(RwAudioCatalog.unit_sound(sound_id), world_position, listener_position, hearing_radius, volume_offset_db, pitch_scale)


## 播放一个根据听者距离衰减的任意战场流
## 如果流为空或无法听到，则返回 [code]false[/code]
func play_unit_stream_at(stream: AudioStream, world_position: Vector2, listener_position: Vector2, hearing_radius: float = 900.0, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	if stream == null or hearing_radius <= 0.0:
		return false
	var distance: float = world_position.distance_to(listener_position)
	if distance >= hearing_radius:
		return false
	var gain: float = maxf(1.0 - distance / hearing_radius, 0.001)
	return play_unit_stream(stream, volume_offset_db + linear_to_db(gain), pitch_scale)


## 设置当前和未来的音乐音量（分贝）
func set_music_volume_db(value: float) -> void:
	music_volume_db = value
	if music_player.playing:
		_cancel_music_tween()
		music_player.volume_db = value


## 设置未来 UI 声音的基础音量（分贝）
func set_ui_volume_db(value: float) -> void:
	ui_volume_db = value


## 为未来单位的声音设置基础音量（分贝）
func set_unit_volume_db(value: float) -> void:
	unit_volume_db = value


## 返回音乐播放器是否处于活动状态
func is_music_playing() -> bool:
	return music_player.playing


## 返回当前曲目的目录 ID，如果有提供的话
func get_music_track_id() -> StringName:
	return _music_track_id


## 返回当前正在播放的 UI 语音数量
func get_active_ui_voice_count() -> int:
	return _count_active_voices(_ui_voices)


## 返回当前正在播放的单位声音数量
func get_active_unit_voice_count() -> int:
	return _count_active_voices(_unit_voices)


func _on_music_player_finished() -> void:
	if _music_loop and music_player.stream != null:
		music_player.play()
	else:
		_finish_music_stop()


func _create_voice(parent: Node, voice_name: String) -> AudioStreamPlayer:
	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.name = voice_name
	parent.add_child(voice)
	return voice


func _play_sound(voices: Array[AudioStreamPlayer], stream: AudioStream, volume_db: float, pitch_scale: float) -> bool:
	if stream == null or voices.is_empty():
		return false
	var voice: AudioStreamPlayer = _choose_voice(voices)
	voice.stop()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = maxf(pitch_scale, 0.01)
	voice.play()
	_voice_serial += 1
	_voice_started_at[voice.get_instance_id()] = _voice_serial
	return true


func _choose_voice(voices: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	var oldest_voice: AudioStreamPlayer = voices[0]
	var oldest_serial: int = _voice_serial + 1
	for voice: AudioStreamPlayer in voices:
		if not voice.playing:
			return voice
		var serial: int = int(_voice_started_at.get(voice.get_instance_id(), 0))
		if serial < oldest_serial:
			oldest_serial = serial
			oldest_voice = voice
	return oldest_voice


func _count_active_voices(voices: Array[AudioStreamPlayer]) -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in voices:
		if voice.playing:
			count += 1
	return count


func _cancel_music_tween() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	_music_tween = null


func _finish_music_stop() -> void:
	var was_active: bool = music_player.playing or not _music_track_id.is_empty()
	music_player.stop()
	music_player.stream = null
	_music_track_id = &""
	_music_loop = false
	_music_tween = null
	if was_active:
		music_stopped.emit()
