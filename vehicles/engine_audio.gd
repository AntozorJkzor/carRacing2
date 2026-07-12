extends Node3D

## Crossfades idling / low / mid / max engine loops from car RPM.

@export var master_volume_db: float = -9.1 ## ~0.35 linear (~50% quieter than previous -3.1)
@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0

var _car: CarController
var _players: Array[AudioStreamPlayer3D] = []
var _smooth_rpm: float = 800.0
var _smooth_load: float = 0.0


func _ready() -> void:
	_car = get_parent() as CarController
	_ensure_defaults()
	_players = [
		_make_player("Idle", idle_stream),
		_make_player("Low", low_stream),
		_make_player("Mid", mid_stream),
		_make_player("Max", max_stream),
	]
	for p in _players:
		p.play()
	if _car and _car.setup:
		_smooth_rpm = _car.setup.idle_rpm


func _process(delta: float) -> void:
	if _car == null or _car.setup == null:
		return

	var idle := _car.setup.idle_rpm
	var redline := _car.setup.max_rpm
	_smooth_rpm = lerpf(_smooth_rpm, _car.engine_rpm, clampf(12.0 * delta, 0.0, 1.0))
	var load_target := clampf(_car.throttle, 0.0, 1.0)
	if not _car.occupied:
		load_target = 0.0
	_smooth_load = lerpf(_smooth_load, load_target, clampf(6.0 * delta, 0.0, 1.0))

	var t := clampf(inverse_lerp(idle, redline, _smooth_rpm), 0.0, 1.0)
	var weights := _rpm_weights(t)
	# Normalize so overlapping bands don't clip too hard.
	var sum := weights[0] + weights[1] + weights[2] + weights[3]
	if sum > 0.001:
		for i in 4:
			weights[i] /= sum

	var pitch := lerpf(0.92, 1.22, t) + _smooth_load * 0.04
	var load_db := lerpf(-2.5, 2.0, _smooth_load)
	# Quieter when nobody is driving, but keep a soft idle presence.
	var occupied_db := 0.0 if _car.occupied else -8.0
	var mute_engine := GameAudio != null and GameAudio.has_method("is_terror_playing") and GameAudio.is_terror_playing()

	for i in _players.size():
		var player := _players[i]
		var w: float = weights[i]
		player.pitch_scale = pitch
		if mute_engine or w <= 0.001:
			player.volume_db = -80.0
		else:
			# linear weight -> dB
			player.volume_db = master_volume_db + load_db + occupied_db + linear_to_db(w)


func _rpm_weights(t: float) -> Array[float]:
	# Soft triangular / trapezoid envelopes across the rev range.
	return [
		_band(t, -0.05, 0.0, 0.08, 0.28),   # idle
		_band(t, 0.08, 0.28, 0.38, 0.58),  # low
		_band(t, 0.38, 0.55, 0.68, 0.88),  # mid
		_band(t, 0.65, 0.82, 1.05, 1.2),   # max / high
	]


func _band(t: float, in_start: float, in_full: float, out_start: float, out_end: float) -> float:
	if t <= in_start or t >= out_end:
		return 0.0
	if t < in_full:
		return inverse_lerp(in_start, in_full, t)
	if t <= out_start:
		return 1.0
	return 1.0 - inverse_lerp(out_start, out_end, t)


func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.stream = _looped(stream)
	player.bus = "Master"
	player.volume_db = -80.0
	player.max_distance = max_distance
	player.unit_size = unit_size
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(player)
	return player


func _looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	# Duplicate so we don't mutate the shared imported resource permanently in odd ways.
	var copy := stream.duplicate()
	if copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	return copy


func _ensure_defaults() -> void:
	if idle_stream == null:
		idle_stream = load("res://assets/audio/cars/idling.mp3")
	if low_stream == null:
		low_stream = load("res://assets/audio/cars/low.mp3")
	if mid_stream == null:
		mid_stream = load("res://assets/audio/cars/mid.mp3")
	if max_stream == null:
		max_stream = load("res://assets/audio/cars/max.mp3")
