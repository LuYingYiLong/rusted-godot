## Maps stable vanilla audio IDs to imported streams.
class_name RwAudioCatalog
extends RefCounted

## Player feedback sounds, including the move order acknowledgement.
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

## Sounds emitted by units or the battlefield.
const UNIT_SOUNDS: Dictionary = {
	&"explode": preload("uid://qiosplwo0uoy"),
}

## Looping background tracks used by the menu and battle scenes.
const MUSIC_TRACKS: Dictionary = {
	&"menu": preload("uid://bq4a2vrs343ht"),
	&"battle": preload("uid://c82rpe2csas0e"),
}


## Returns a UI stream for [param sound_id], or [code]null[/code] if unknown.
static func ui_sound(sound_id: StringName) -> AudioStream:
	return UI_SOUNDS.get(sound_id) as AudioStream


## Returns a unit stream for [param sound_id], or [code]null[/code] if unknown.
static func unit_sound(sound_id: StringName) -> AudioStream:
	return UNIT_SOUNDS.get(sound_id) as AudioStream


## Returns a music stream for [param track_id], or [code]null[/code] if unknown.
static func music_track(track_id: StringName) -> AudioStream:
	return MUSIC_TRACKS.get(track_id) as AudioStream
