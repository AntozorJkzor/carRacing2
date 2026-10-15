extends Node

## Global music + one-shot SFX (hit jingle). No looping game bed track.

const AUDIO_SAVE_PATH := "user://audio_settings.cfg"

@export var music_volume_db: float = -12.0
@export var sfx_volume_db: float = 8.0
## Terror overlay vs music bed volume reference.
@export var terror_volume_mult: float = 6.0

## User volume scales 0..1 (settings menu).
var master_linear: float = 1.0
var music_linear: float = 1.0
var car_linear: float = 1.0

var _music: AudioStreamPlayer
var _terror: AudioStreamPlayer
var _npc1_hit_streams: Array[AudioStream] = []
var _npc2_hit_streams: Array[AudioStream] = []
var _main_music_stream: AudioStream
var _intro_music_stream: AudioStream
var _lose_music_stream: AudioStream
var _terror_music_stream: AudioStream
var _terror_active: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	_music.bus = "Master"
	add_child(_music)

	_terror = AudioStreamPlayer.new()
	_terror.name = "TerrorPlayer"
	_terror.bus = "Master"
	add_child(_terror)

	for path: String in [
		"res://assets/audio/music/win.mp3",
		"res://assets/audio/music/win2.mp3",
		"res://assets/audio/music/win3.mp3",
		"res://assets/audio/music/win4.mp3",
	]:
		var stream := load(path) as AudioStream
		if stream != null:
			_npc1_hit_streams.append(stream)
	for path: String in [
		"res://assets/audio/music/apple.mp3",
		"res://assets/audio/music/apple2.mp3",
		"res://assets/audio/music/apple3.mp3",
	]:
		var stream := load(path) as AudioStream
		if stream != null:
			_npc2_hit_streams.append(stream)
	_main_music_stream = load("res://assets/audio/music/main_sound.mp3") as AudioStream
	_intro_music_stream = load("res://assets/audio/music/intro.mp3") as AudioStream
	_lose_music_stream = load("res://assets/audio/music/lose.mp3") as AudioStream
	_terror_music_stream = load("res://assets/audio/music/terror.mp3") as AudioStream

	if _main_music_stream is AudioStreamMP3:
		(_main_music_stream as AudioStreamMP3).loop = true
	if _intro_music_stream is AudioStreamMP3:
		(_intro_music_stream as AudioStreamMP3).loop = false
	if _lose_music_stream is AudioStreamMP3:
		(_lose_music_stream as AudioStreamMP3).loop = false
	if _terror_music_stream is AudioStreamMP3:
		(_terror_music_stream as AudioStreamMP3).loop = true

	if _terror_music_stream:
		_terror.stream = _terror_music_stream

	load_audio_settings()
	apply_volumes()


func load_audio_settings() -> void:
	if not FileAccess.file_exists(AUDIO_SAVE_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(AUDIO_SAVE_PATH) != OK:
		return
	master_linear = clampf(float(cfg.get_value("volume", "master", master_linear)), 0.0, 1.0)
	music_linear = clampf(float(cfg.get_value("volume", "music", music_linear)), 0.0, 1.0)
	car_linear = clampf(float(cfg.get_value("volume", "car", car_linear)), 0.0, 1.0)


func save_audio_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("volume", "master", master_linear)
	cfg.set_value("volume", "music", music_linear)
	cfg.set_value("volume", "car", car_linear)
	cfg.save(AUDIO_SAVE_PATH)


func set_master_linear(value: float) -> void:
	master_linear = clampf(value, 0.0, 1.0)
	apply_volumes()


func set_music_linear(value: float) -> void:
	music_linear = clampf(value, 0.0, 1.0)
	_refresh_music_volumes()


func set_car_linear(value: float) -> void:
	car_linear = clampf(value, 0.0, 1.0)


func apply_volumes() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		if master_linear <= 0.001:
			AudioServer.set_bus_volume_db(master_idx, -80.0)
		else:
			AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_linear))
	_refresh_music_volumes()


func get_effective_music_db() -> float:
	return music_volume_db + _scale_to_db(music_linear)


func get_car_volume_offset_db() -> float:
	return _scale_to_db(car_linear)


func _scale_to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func _refresh_music_volumes() -> void:
	var music_db := get_effective_music_db()
	if _music != null:
		_music.volume_db = music_db
	if _terror != null:
		_terror.volume_db = _terror_volume_db()


func _terror_volume_db() -> float:
	return get_effective_music_db() + linear_to_db(maxf(terror_volume_mult, 0.01))


func _stop_terror_player() -> void:
	if _terror != null and _terror.playing:
		_terror.stop()
	_terror_active = false


## Stop any looping bed / one-shot music (no game bed track).
func restart_music() -> void:
	_stop_terror_player()
	if _music == null or _main_music_stream == null:
		return
	_music.volume_db = get_effective_music_db()
	if _music.stream != _main_music_stream:
		_music.stop()
		_music.stream = _main_music_stream
	if not _music.playing:
		_music.play(0.0)


func play_intro_music() -> void:
	_stop_terror_player()
	if _music == null or _intro_music_stream == null:
		return
	_music.volume_db = get_effective_music_db()
	_music.stop()
	_music.stream = _intro_music_stream
	_music.play(0.0)


func play_lose_music() -> void:
	_stop_terror_player()
	if _music == null or _lose_music_stream == null:
		return
	_music.volume_db = get_effective_music_db()
	_music.stop()
	_music.stream = _lose_music_stream
	_music.play(0.0)


func play_terror_music() -> void:
	if _terror == null or _terror_music_stream == null:
		return
	_terror_active = true
	# No game bed — terror alone.
	if _music != null and _music.playing:
		_music.stop()
	_terror.volume_db = _terror_volume_db()
	_terror.stream = _terror_music_stream
	if not _terror.playing:
		_terror.play(0.0)


func stop_terror_music() -> void:
	if not _terror_active and (_terror == null or not _terror.playing):
		return
	_stop_terror_player()


func is_terror_playing() -> bool:
	return _terror_active


func restore_game_music() -> void:
	restart_music()


func play_npc_hit(kind: String = "npc1") -> void:
	# During terror: mute all one-shots; only terror remains.
	if _terror_active:
		return
	var stream: AudioStream = null
	if kind.to_lower() == "npc2":
		if not _npc2_hit_streams.is_empty():
			stream = _npc2_hit_streams[_rng.randi_range(0, _npc2_hit_streams.size() - 1)]
	elif not _npc1_hit_streams.is_empty():
		stream = _npc1_hit_streams[_rng.randi_range(0, _npc1_hit_streams.size() - 1)]
	if stream == null:
		return
	# New player each hit so overlapping knocks stack instead of cutting off.
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = sfx_volume_db
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
