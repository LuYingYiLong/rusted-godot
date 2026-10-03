class_name RwAudioCatalog
extends RefCounted
## 将稳定的原版音频 ID 映射到导入的流

## 玩家反馈声音，包括移动顺序确认
const UI_SOUNDS: Dictionary = {
	&"click": preload("uid://chiuni33ydda6"),
	&"add": preload("uid://cah3cmaf2bbgv"),
	&"remove": preload("uid://cou361qawe8uj"),
	&"attack": preload("uid://cxy2iu2r3uewv"),
	&"error": preload("uid://016h4ylopbi7"),
	&"message": preload("uid://rnkxu8m8bs7u"),
	&"warning": preload("uid://bt8cunm7n6fpe"),
	&"move": preload("uid://bf50j5lngiuj6"),
}

## 单位或战场发出的声音
const UNIT_SOUNDS: Dictionary = {
	&"explode": preload("uid://qiosplwo0uoy"),
}

## 菜单和战斗场景使用的循环背景音乐
const MUSIC_TRACKS: Dictionary = {
	&"menu": preload("uid://bq4a2vrs343ht"),
	&"battle": preload("uid://c82rpe2csas0e"),
}


## 返回 [param sound_id] 的 UI 流，如果未知则返回 [code]null[/code]
static func ui_sound(sound_id: StringName) -> AudioStream:
	return UI_SOUNDS.get(sound_id) as AudioStream


## 返回 [param sound_id] 的音单元流，如果未知则返回 [code]null[/code]
static func unit_sound(sound_id: StringName) -> AudioStream:
	return UNIT_SOUNDS.get(sound_id) as AudioStream


## 返回 [param track_id] 的音乐流，如果未知则返回 [code]null[/code]
static func music_track(track_id: StringName) -> AudioStream:
	return MUSIC_TRACKS.get(track_id) as AudioStream
