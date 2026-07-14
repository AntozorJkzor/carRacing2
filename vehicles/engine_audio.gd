extends Node3D

## Baked waveguide engine banks (idle/low/mid/max) with RPM crossfade + pitch.
## Banks come from EngineSoundBaker (Baldan waveguide offline).

@export var master_volume_db: float = -9.1
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0
@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
## Reference RPMs for each baked bank (pitch_scale = rpm / ref).
@export var idle_rpm_ref: float = 800.0
@export var low_rpm_ref: float = 2200.0
@export var mid_rpm_ref: float = 4200.0
@export var max_rpm_ref: float = 6300.0
## How far pitch may track RPM relative to each bank's bake RPM.
@export var pitch_min: float = 0.65
@export var pitch_max: float = 1.4
## 1 = linear rpm/ref; >1 exaggerates how much pitch moves with RPM.
@export var pitch_exaggeration: float = 1.2
## <1 pulls crossfade toward higher banks earlier (more change through the rev range).
@export var band_bias_exp: float = 0.7

var _car: CarController
var _players: Array[AudioStreamPlayer3D] = []
var _smooth_rpm: float = 800.0
var _smooth_load: float = 0.0
var _profile_applied: bool = false
var _vols: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	_car = get_parent() as CarController
	_resolve_profile_from_pack()
	_setup_players()
	if _car and _car.setup:
		_smooth_rpm = _car.setup.idle_rpm
		_apply_default_rpm_refs_from_setup(_car.setup)


func apply_profile(profile: CarAudioProfile, only_fill_empty: bool = true) -> void:
	if profile == null:
		return
	if not only_fill_empty or not _profile_applied:
		master_volume_db = profile.master_volume_db
		max_distance = profile.max_distance
		unit_size = profile.unit_size
		if profile.idle_stream:
			idle_stream = profile.idle_stream
		if profile.low_stream:
			low_stream = profile.low_stream
		if profile.mid_stream:
			mid_stream = profile.mid_stream
		if profile.max_stream:
			max_stream = profile.max_stream
		_profile_applied = true
		_apply_streams_to_players()
		_apply_spatial()


## Swap idle/low/mid/max banks (from EngineSoundBaker bake_user / bake_streams).
func apply_banks(banks: Dictionary) -> void:
	if banks.is_empty():
		return
	if banks.has("idle"):
		idle_stream = banks["idle"] as AudioStream
	if banks.has("low"):
		low_stream = banks["low"] as AudioStream
	if banks.has("mid"):
		mid_stream = banks["mid"] as AudioStream
	if banks.has("max"):
		max_stream = banks["max"] as AudioStream
	if banks.has("rpms"):
		var rpms: PackedFloat32Array = banks["rpms"]
		if rpms.size() >= 4:
			idle_rpm_ref = rpms[0]
			low_rpm_ref = rpms[1]
			mid_rpm_ref = rpms[2]
			max_rpm_ref = rpms[3]
	_profile_applied = true
	_apply_streams_to_players()
	# Restart players so new PCM is heard immediately.
	for p in _players:
		if p.stream != null:
			p.stop()
			p.play()


func _resolve_profile_from_pack() -> void:
	if _car != null and _car.audio_profile != null:
		apply_profile(_car.audio_profile, true)
	if _car != null:
		var user_banks := EngineSoundBaker.load_user(_car.car_id)
		if not user_banks.is_empty():
			apply_banks(user_banks)


func _apply_default_rpm_refs_from_setup(setup: Resource) -> void:
	var rpms := EngineSoundBaker.band_rpms(setup)
	idle_rpm_ref = rpms[0]
	low_rpm_ref = rpms[1]
	mid_rpm_ref = rpms[2]
	max_rpm_ref = rpms[3]


func _setup_players() -> void:
	var streams: Array[AudioStream] = [idle_stream, low_stream, mid_stream, max_stream]
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.name = "Band%d" % i
		p.bus = "Master"
		p.volume_db = -80.0
		p.max_distance = max_distance
		p.unit_size = unit_size
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		if streams[i]:
			p.stream = streams[i]
			p.play()
		add_child(p)
		_players.append(p)


func _apply_streams_to_players() -> void:
	if _players.size() < 4:
		return
	var streams: Array[AudioStream] = [idle_stream, low_stream, mid_stream, max_stream]
	for i in 4:
		var p: AudioStreamPlayer3D = _players[i]
		if p.stream != streams[i]:
			var was_playing := p.playing
			p.stream = streams[i]
			if streams[i] != null and was_playing:
				p.play()
		elif streams[i] != null and not p.playing:
			p.play()


func _apply_spatial() -> void:
	for p in _players:
		p.max_distance = max_distance
		p.unit_size = unit_size


func _process(delta: float) -> void:
	if _car == null or _car.setup == null or _players.is_empty():
		return

	_smooth_rpm = lerpf(_smooth_rpm, _car.engine_rpm, clampf(10.0 * delta, 0.0, 1.0))
	var load_target := clampf(_car.throttle, 0.0, 1.0)
	if not _car.occupied:
		load_target = 0.0
	_smooth_load = lerpf(_smooth_load, load_target, clampf(6.0 * delta, 0.0, 1.0))

	var mute := (
		GameAudio != null
		and GameAudio.has_method("is_terror_playing")
		and GameAudio.is_terror_playing()
	)
	var occupied_db := 0.0 if _car.occupied else -10.0
	var load_db := lerpf(-3.0, 1.5, _smooth_load)
	var idle_r := float(_car.setup.get("idle_rpm"))
	var max_r := maxf(float(_car.setup.get("max_rpm")), idle_r + 1.0)
	var rpm_t := clampf(inverse_lerp(idle_r, max_r, _smooth_rpm), 0.0, 1.0)
	var rpm_db := lerpf(-1.0, 1.8, pow(rpm_t, 1.15))
	var master := -80.0 if mute else (master_volume_db + load_db + occupied_db + rpm_db)

	var refs := PackedFloat32Array([idle_rpm_ref, low_rpm_ref, mid_rpm_ref, max_rpm_ref])
	# Bias blend RPM upward so mid/max dominate sooner — clearer climb.
	var blend_rpm := lerpf(refs[0], refs[3], pow(rpm_t, band_bias_exp))
	_compute_band_weights(blend_rpm, refs)

	for i in _players.size():
		var p: AudioStreamPlayer3D = _players[i]
		if p.stream == null:
			p.volume_db = -80.0
			continue
		var w: float = _vols[i]
		# Idle drops faster; low peakes early so leaving idle is obvious.
		if i == 0:
			w *= lerpf(1.25, 0.22, pow(rpm_t, 0.65))
		elif i == 1:
			var into_low := clampf(rpm_t / 0.32, 0.0, 1.0)
			var past_low := clampf((rpm_t - 0.38) / 0.45, 0.0, 1.0)
			w *= lerpf(0.88, 1.28, into_low) * lerpf(1.0, 0.48, past_low)
		else:
			w *= lerpf(0.85, 1.25, rpm_t)
		if w < 0.002:
			p.volume_db = -80.0
		else:
			p.volume_db = master + linear_to_db(clampf(w, 0.0, 1.15))
			var ref_rpm := maxf(refs[i], 100.0)
			var ratio := _smooth_rpm / ref_rpm
			# Stretch deviation from 1 so idle↔redline is more obvious.
			var pitched := 1.0 + (ratio - 1.0) * pitch_exaggeration
			# Mild climb — hard stretch turned banks into chainsaw/UAV buzz.
			pitched *= lerpf(0.96, 1.06, rpm_t)
			p.pitch_scale = clampf(pitched, pitch_min, pitch_max)
		if not p.playing and p.stream != null and not mute:
			p.play()


func _compute_band_weights(rpm: float, refs: PackedFloat32Array) -> void:
	# Piecewise triangular blend across 4 reference RPMs.
	for i in 4:
		_vols[i] = 0.0
	if rpm <= refs[0]:
		_vols[0] = 1.0
		return
	if rpm >= refs[3]:
		_vols[3] = 1.0
		return
	for i in 3:
		var a: float = refs[i]
		var b: float = refs[i + 1]
		if rpm >= a and rpm <= b:
			var t := inverse_lerp(a, b, rpm)
			# Idle→low: pull low bank sooner; later segments ease a bit.
			if i == 0:
				t = pow(t, 0.7)
			else:
				t = pow(t, 0.85)
			_vols[i] = 1.0 - t
			_vols[i + 1] = t
			return
