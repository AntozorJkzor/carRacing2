extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")

## Per-wheel tire squeal for spin / slide / lockup.
@export var clip_streams: Array[AudioStream] = []

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0
@export_range(0.05, 0.5, 0.01) var loop_start: float = 0.14

@export_group("Mix")
@export_range(-24.0, 18.0, 0.5) var master_volume_db: float = -4.0
@export_range(8.0, 120.0, 1.0) var max_distance: float = 55.0
@export_range(4.0, 40.0, 0.5) var unit_size: float = 10.0
@export_range(4.0, 40.0, 0.5) var vol_smooth_rate: float = 14.0

@export_group("Load response")
@export var load_volume_min: float = 0.72
@export var load_volume_max: float = 1.28
@export var load_pitch_max: float = 1.06
@export var load_pitch_min: float = 0.92

var _car: CarController
var _players: Array[AudioStreamPlayer3D] = []
var _intensity: Array[float] = []
var _pitch: Array[float] = []
var _variation: Array[float] = []


func _ready() -> void:
	_car = get_parent() as CarController
	_ensure_streams()


func _physics_process(delta: float) -> void:
	FrameClock.measure("phys:tire_audio", _profiled_physics_process, delta)


func _profiled_physics_process(delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _car.setup == null:
		return
	var wheels := _car.get_wheels()
	_ensure_wheel_players(wheels.size())
	var k := clampf(vol_smooth_rate * delta, 0.0, 1.0)
	var static_load := maxf(_car.setup.mass * 9.81 * 0.25, 1.0)
	var speed_norm := clampf(_car.get_speed_ms() / 55.0, 0.0, 1.0)
	var mute := GameAudio != null and GameAudio.is_terror_playing()
	var car_user := float(GameAudio.get_car_volume_offset_db()) if GameAudio != null else 0.0
	var occupied_db := 0.0 if _car.occupied else -9.0

	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var amounts := _TireFx.slip_parts(_car, wheel, spin_kappa, slide_angle_deg)
		var total := maxf(amounts.x, maxf(amounts.y, amounts.z))
		_intensity[i] = lerpf(_intensity[i], total, k)
		var load_ratio := clampf(wheel.normal_load / static_load, 0.0, 1.5)
		var load_volume := lerpf(load_volume_min, load_volume_max, load_ratio / 1.5)
		var load_pitch := lerpf(load_pitch_max, load_pitch_min, load_ratio / 1.5)
		var target_pitch := (0.88 + _intensity[i] * 0.22 + speed_norm * 0.12) * load_pitch * _variation[i]
		_pitch[i] = lerpf(_pitch[i], target_pitch, k)

		var player := _players[i]
		player.global_position = wheel.hit_point + wheel.up * 0.08
		var hear: bool = not mute and wheel.on_ground and _intensity[i] >= loop_start * 0.55
		if hear:
			var gain := clampf((_intensity[i] - loop_start * 0.4) / 0.7, 0.0, 1.0)
			gain = pow(gain, 0.62) * load_volume
			player.volume_db = master_volume_db + occupied_db + car_user + linear_to_db(maxf(gain, 0.0008))
			player.pitch_scale = clampf(_pitch[i], 0.72, 1.35)
			if not player.playing:
				_choose_clip(i)
				player.play()
		else:
			player.volume_db = -80.0
			if player.playing and _intensity[i] < loop_start * 0.35:
				player.stop()


func _ensure_wheel_players(count: int) -> void:
	while _players.size() < count:
		var index := _players.size()
		_players.append(_make_player("Wheel_%d" % index))
		_intensity.append(0.0)
		_pitch.append(1.0)
		_variation.append(randf_range(0.965, 1.035))
		_choose_clip(index)
	while _players.size() > count:
		_players.pop_back().queue_free()
		_intensity.pop_back()
		_pitch.pop_back()
		_variation.pop_back()


func _choose_clip(index: int) -> void:
	if clip_streams.is_empty() or index < 0 or index >= _players.size():
		return
	var clip_index := (randi() + index) % clip_streams.size()
	_players[index].stream = _as_loop(clip_streams[clip_index])


func _ensure_streams() -> void:
	if clip_streams.is_empty():
		for i in range(1, 7):
			var stream := load("res://assets/audio/tires/tires_%02d.wav" % i) as AudioStream
			if stream != null:
				clip_streams.append(stream)


func _as_loop(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
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
