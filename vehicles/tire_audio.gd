extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")

## Tire squeal for spin / slide / lockup.
## Attach to TireAudio under CarController (car pack: golf.tscn, volga.tscn, car_base.tscn).

@export var loop_stream: AudioStream
@export var spin_chirp_stream: AudioStream
@export var brake_chirp_stream: AudioStream

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0
@export_range(0.05, 0.5, 0.01) var loop_start: float = 0.14
@export_range(0.15, 0.6, 0.01) var spin_chirp_at: float = 0.38
@export_range(0.15, 0.6, 0.01) var brake_chirp_at: float = 0.28

@export_group("Mix")
@export_range(-24.0, 6.0, 0.5) var master_volume_db: float = -4.0
@export_range(8.0, 120.0, 1.0) var max_distance: float = 55.0
@export_range(4.0, 40.0, 0.5) var unit_size: float = 10.0
@export_range(4.0, 40.0, 0.5) var vol_smooth_rate: float = 14.0
@export_range(0.2, 1.5, 0.05) var chirp_cooldown: float = 0.45

var _car: CarController
var _loop: AudioStreamPlayer3D
var _chirp: AudioStreamPlayer3D
var _intensity_smooth: float = 0.0
var _spin_smooth: float = 0.0
var _lock_smooth: float = 0.0
var _spin_was: bool = false
var _lock_was: bool = false
var _chirp_cd: float = 0.0


func _ready() -> void:
	_car = get_parent() as CarController
	_ensure_streams()
	_loop = _make_player("Loop")
	_loop.stream = _as_loop(loop_stream)
	_chirp = _make_player("Chirp")
	_chirp.max_polyphony = 2


func _physics_process(delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _loop == null:
		return
	_chirp_cd = maxf(_chirp_cd - delta, 0.0)
	var spin_i := 0.0
	var slide_i := 0.0
	var lock_i := 0.0
	for wheel: Wheel in _car.get_wheels():
		var amounts := _TireFx.slip_parts(_car, wheel, spin_kappa, slide_angle_deg)
		spin_i = maxf(spin_i, amounts.x)
		slide_i = maxf(slide_i, amounts.y)
		lock_i = maxf(lock_i, amounts.z)
	var total := maxf(spin_i, maxf(slide_i, lock_i))
	var k := clampf(vol_smooth_rate * delta, 0.0, 1.0)
	_intensity_smooth = lerpf(_intensity_smooth, total, k)
	_spin_smooth = lerpf(_spin_smooth, spin_i, k)
	_lock_smooth = lerpf(_lock_smooth, lock_i, k)
	var mute := (
		GameAudio != null
		and GameAudio.has_method("is_terror_playing")
		and GameAudio.is_terror_playing()
	)
	var car_user := 0.0
	if GameAudio != null and GameAudio.has_method("get_car_volume_offset_db"):
		car_user = float(GameAudio.get_car_volume_offset_db())
	var occupied_db := 0.0 if _car.occupied else -9.0
	var hear := (not mute) and _intensity_smooth >= loop_start * 0.55
	var vol := -80.0
	if hear:
		var gain := clampf((_intensity_smooth - loop_start * 0.4) / 0.7, 0.0, 1.0)
		gain = pow(gain, 0.62)
		vol = master_volume_db + occupied_db + car_user + linear_to_db(maxf(gain, 0.0008))
	_loop.volume_db = vol
	var speed_kmh := 0.0
	if _car.has_method("get_speed_kmh"):
		speed_kmh = float(_car.get_speed_kmh())
	_loop.pitch_scale = clampf(0.90 + speed_kmh * 0.0018 + _intensity_smooth * 0.08, 0.86, 1.18)
	if hear:
		if not _loop.playing and _loop.stream != null:
			_loop.play()
	elif _loop.playing and _intensity_smooth < loop_start * 0.35:
		_loop.stop()
	var spin_now := _spin_smooth >= spin_chirp_at and _car.throttle > 0.22 and _car.brake < 0.35
	var lock_now := _lock_smooth >= brake_chirp_at
	if _chirp_cd <= 0.0:
		if lock_now and not _lock_was:
			_play_chirp(brake_chirp_stream if brake_chirp_stream != null else spin_chirp_stream)
		elif spin_now and not _spin_was:
			_play_chirp(spin_chirp_stream if spin_chirp_stream != null else brake_chirp_stream)
	_spin_was = spin_now
	_lock_was = lock_now


func _play_chirp(stream: AudioStream) -> void:
	if stream == null or _chirp == null:
		return
	_chirp.stream = stream
	var car_user := 0.0
	if GameAudio != null and GameAudio.has_method("get_car_volume_offset_db"):
		car_user = float(GameAudio.get_car_volume_offset_db())
	var occupied_db := 0.0 if _car != null and _car.occupied else -9.0
	_chirp.volume_db = master_volume_db + 1.5 + occupied_db + car_user
	_chirp.pitch_scale = randf_range(0.94, 1.08)
	_chirp.play()
	_chirp_cd = chirp_cooldown


func _ensure_streams() -> void:
	if loop_stream == null:
		loop_stream = load("res://assets/audio/tires/skid-loop.wav") as AudioStream
	if spin_chirp_stream == null:
		spin_chirp_stream = load("res://assets/audio/tires/skid-piece.wav") as AudioStream
	if brake_chirp_stream == null:
		brake_chirp_stream = load("res://assets/audio/tires/skid-piece-fadeinout.wav") as AudioStream


func _as_loop(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _make_player(player_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.bus = "Master"
	p.volume_db = -80.0
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p
