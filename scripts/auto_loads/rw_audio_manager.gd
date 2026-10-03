## Plays looping music, player feedback, and pooled battlefield sounds.
## Add its scene as the AudioManager autoload to share voice pools across scenes.
class_name RwAudioManager
extends Node

## Emitted after a music track starts playing.
signal music_started(track_id: StringName)
## Emitted when the active music track finishes or is stopped.
signal music_stopped()

## Maximum simultaneous UI sounds; the oldest voice is reused when full.
@export_range(1, 32, 1) var ui_voice_limit: int
## Maximum simultaneous unit sounds; the oldest voice is reused when full.
@export_range(1, 64, 1) var unit_voice_limit: int
## Base volume for music, in decibels.
@export var music_volume_db: float
## Base volume for UI feedback, in decibels.
@export var ui_volume_db: float
## Base volume for battlefield sounds, in decibels.
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


## Plays a catalogued track with a short fade-in.
## Returns [code]false[/code] if [param track_id] is unknown.
func play_music(track_id: StringName, fade_seconds: float = 0.4) -> bool:
	var stream: AudioStream = RwAudioCatalog.music_track(track_id)
	if stream == null:
		return false
	return play_music_stream(stream, track_id, true, fade_seconds)


## Plays any music stream. Ogg streams are duplicated to keep their loop flag local.
## Returns [code]false[/code] when [param stream] is null.
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


## Stops music immediately or fades it out over [param fade_seconds].
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


## Plays a catalogued player feedback sound, such as a move order cue.
## Returns [code]false[/code] if [param sound_id] is unknown.
func play_ui(sound_id: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_ui_stream(RwAudioCatalog.ui_sound(sound_id), volume_offset_db, pitch_scale)


## Plays an arbitrary stream through the UI voice pool.
func play_ui_stream(stream: AudioStream, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return _play_sound(_ui_voices, stream, ui_volume_db + volume_offset_db, pitch_scale)


## Plays a catalogued non-positional battlefield sound.
func play_unit(sound_id: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_unit_stream(RwAudioCatalog.unit_sound(sound_id), volume_offset_db, pitch_scale)


## Plays an arbitrary stream through the unit voice pool.
func play_unit_stream(stream: AudioStream, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return _play_sound(_unit_voices, stream, unit_volume_db + volume_offset_db, pitch_scale)


## Plays a catalogued battlefield sound attenuated by listener distance.
## Returns [code]false[/code] when outside [param hearing_radius].
func play_unit_at(sound_id: StringName, world_position: Vector2, listener_position: Vector2, hearing_radius: float = 900.0, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return play_unit_stream_at(RwAudioCatalog.unit_sound(sound_id), world_position, listener_position, hearing_radius, volume_offset_db, pitch_scale)


## Plays an arbitrary battlefield stream attenuated by listener distance.
## Returns [code]false[/code] if the stream is null or inaudible.
func play_unit_stream_at(stream: AudioStream, world_position: Vector2, listener_position: Vector2, hearing_radius: float = 900.0, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	if stream == null or hearing_radius <= 0.0:
		return false
	var distance: float = world_position.distance_to(listener_position)
	if distance >= hearing_radius:
		return false
	var gain: float = maxf(1.0 - distance / hearing_radius, 0.001)
	return play_unit_stream(stream, volume_offset_db + linear_to_db(gain), pitch_scale)


## Sets the current and future music volume in decibels.
func set_music_volume_db(value: float) -> void:
	music_volume_db = value
	if music_player.playing:
		_cancel_music_tween()
		music_player.volume_db = value


## Sets the base volume for future UI sounds in decibels.
func set_ui_volume_db(value: float) -> void:
	ui_volume_db = value


## Sets the base volume for future unit sounds in decibels.
func set_unit_volume_db(value: float) -> void:
	unit_volume_db = value


## Returns whether the music player is active.
func is_music_playing() -> bool:
	return music_player.playing


## Returns the catalog ID of the current track, if one was supplied.
func get_music_track_id() -> StringName:
	return _music_track_id


## Returns the number of UI voices currently playing.
func get_active_ui_voice_count() -> int:
	return _count_active_voices(_ui_voices)


## Returns the number of unit voices currently playing.
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
	var count: int
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
