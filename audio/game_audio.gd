extends Node

## Global music + one-shot SFX (hit jingle).

@export var music_volume_db: float = -12.0
@export var sfx_volume_db: float = 8.0

var _music: AudioStreamPlayer
var _hit_stream: AudioStream


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	_music.bus = "Master"
	_music.volume_db = music_volume_db
	add_child(_music)

	_hit_stream = load("res://assets/audio/music/win.mp3") as AudioStream

	var music_stream := load("res://assets/audio/music/music.mp3") as AudioStream
	if music_stream:
		if music_stream is AudioStreamMP3:
			(music_stream as AudioStreamMP3).loop = true
		_music.stream = music_stream


## Start (or restart from the beginning) the background track.
func restart_music() -> void:
	if _music == null or _music.stream == null:
		return
	_music.stop()
	_music.play(0.0)


func play_npc_hit() -> void:
	if _hit_stream == null:
		return
	# New player each hit so overlapping knocks stack instead of cutting off.
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = sfx_volume_db
	player.stream = _hit_stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
