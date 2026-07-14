extends Node

## Global music + one-shot SFX (hit jingle). No looping game bed track.

@export var music_volume_db: float = -12.0
@export var sfx_volume_db: float = 8.0
## Terror overlay vs music bed volume reference.
@export var terror_volume_mult: float = 6.0

var _music: AudioStreamPlayer
var _terror: AudioStreamPlayer
var _npc1_hit_streams: Array[AudioStream] = []
var _npc2_hit_streams: Array[AudioStream] = []
var _intro_music_stream: AudioStream
var _lose_music_stream: AudioStream
var _terror_music_stream: AudioStream
var _terror_active: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	_music.bus = "Master"
	_music.volume_db = music_volume_db
	add_child(_music)

	_terror = AudioStreamPlayer.new()
	_terror.name = "TerrorPlayer"
	_terror.bus = "Master"
	_terror.volume_db = _terror_volume_db()
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
	_intro_music_stream = load("res://assets/audio/music/intro.mp3") as AudioStream
	_lose_music_stream = load("res://assets/audio/music/lose.mp3") as AudioStream
	_terror_music_stream = load("res://assets/audio/music/terror.mp3") as AudioStream

	if _intro_music_stream is AudioStreamMP3:
		(_intro_music_stream as AudioStreamMP3).loop = false
	if _lose_music_stream is AudioStreamMP3:
		(_lose_music_stream as AudioStreamMP3).loop = false
	if _terror_music_stream is AudioStreamMP3:
		(_terror_music_stream as AudioStreamMP3).loop = true

	if _terror_music_stream:
		_terror.stream = _terror_music_stream


func _terror_volume_db() -> float:
	return music_volume_db + linear_to_db(maxf(terror_volume_mult, 0.01))


func _stop_terror_player() -> void:
	if _terror != null and _terror.playing:
		_terror.stop()
	_terror_active = false


## Stop any looping bed / one-shot music (no game bed track).
func restart_music() -> void:
	_stop_terror_player()
	if _music != null and _music.playing:
		_music.stop()
	_music.stream = null


func play_intro_music() -> void:
	_stop_terror_player()
	if _music == null or _intro_music_stream == null:
		return
	_music.volume_db = music_volume_db
	_music.stop()
	_music.stream = _intro_music_stream
	_music.play(0.0)


func play_lose_music() -> void:
	_stop_terror_player()
	if _music == null or _lose_music_stream == null:
		return
	_music.volume_db = music_volume_db
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
