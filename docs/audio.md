# AudioManager

`AudioManager` is a project Autoload. It owns one looping music player and two fixed-size sound pools: eight UI voices and sixteen unit voices. When a pool is full, the oldest voice is reused.

```gdscript
AudioManager.play_music(&"menu")
AudioManager.play_music(&"battle")
AudioManager.stop_music()

AudioManager.play_ui(&"click")
AudioManager.play_ui(&"move")
AudioManager.play_unit_at(&"explode", unit_position, camera_position)
```

The vanilla IDs are listed in `RwAudioCatalog`. Custom content can pass an `AudioStream` directly through `play_music_stream`, `play_ui_stream`, `play_unit_stream`, or `play_unit_stream_at`. The `*_at` methods attenuate volume by distance and return `false` when the sound is outside the hearing radius.

`set_music_volume_db`, `set_ui_volume_db`, and `set_unit_volume_db` control the three categories independently. UI and unit volume changes affect subsequent sounds.

The two initial music tracks and the move and explosion sounds were copied from the local RWX `assets` directory. `move.wav` is a UI command cue; `unit_explode.ogg` is a battlefield sound. Their original filenames are retained in this project.
