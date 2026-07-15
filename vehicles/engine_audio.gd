extends Node3D

## Engine audio: baked RPM banks with classic middleware Autopitch.
## pitch_scale = rpm / bank_ref  (playback-rate, not FFT) + equal-power crossfade.
## Refs: Wwise Blend Container / FMOD Autopitch / BOOM Library loop engines.

@export var use_live_synth: bool = false
@export var master_volume_db: float = -9.1
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0
## Legacy 4-slot pack profile (used when user bake missing).
@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
## Soft safety only — Autopitch must track rpm/ref through the whole crossfade.
## Neighbors at 250 rpm need ~0.80…1.25; clamping to ~1.14 causes “stuck note” electric steps.
@export var pitch_min: float = 0.72
@export var pitch_max: float = 1.40
@export var vol_smooth_rate: float = 22.0
@export var pitch_smooth_rate: float = 40.0
## Blend in log-RPM (matches log-spaced bake banks).
@export var use_log_blend: bool = true

var _car: CarController
var _players: Array[AudioStreamPlayer3D] = []
var _band_streams: Array[AudioStream] = []
var _band_rpms: PackedFloat32Array = PackedFloat32Array()
var _smooth_rpm: float = 800.0
var _smooth_load: float = 0.0
var _profile_applied: bool = false
var _vols: PackedFloat32Array = PackedFloat32Array()
var _vols_smooth: PackedFloat32Array = PackedFloat32Array()
var _pitch_smooth: PackedFloat32Array = PackedFloat32Array()

var _live: bool = false
var _live_player: AudioStreamPlayer3D
var _live_stream: AudioStream
var _perf_accum: float = 0.0
var _perf_frames: int = 0


func _ready() -> void:
	_car = get_parent() as CarController
	_live = use_live_synth and ClassDB.class_exists("EngineSoundStream")
	if _live:
		_setup_live()
	else:
		if use_live_synth:
			push_warning("EngineAudio: EngineSoundStream missing — falling back to baked banks")
		_resolve_profile_from_pack()
		_ensure_players()
	if _car and _car.setup:
		_smooth_rpm = _car.setup.idle_rpm
		if _live:
			apply_setup(_car.setup)
		elif _band_rpms.is_empty():
			_apply_default_rpm_refs_from_setup(_car.setup)


func is_live() -> bool:
	return _live


func apply_setup(setup: Resource) -> void:
	if setup == null:
		return
	if _live:
		_configure_live_from_setup(setup)
		return
	if _band_rpms.is_empty():
		_apply_default_rpm_refs_from_setup(setup)


func apply_profile(profile: CarAudioProfile, only_fill_empty: bool = true) -> void:
	if profile == null:
		return
	if not only_fill_empty or not _profile_applied:
		master_volume_db = profile.master_volume_db
		max_distance = profile.max_distance
		unit_size = profile.unit_size
		if _live:
			_profile_applied = true
			_apply_spatial_live()
			if _car and _car.setup:
				_configure_live_from_setup(_car.setup)
			return
		if profile.idle_stream:
			idle_stream = profile.idle_stream
		if profile.low_stream:
			low_stream = profile.low_stream
		if profile.mid_stream:
			mid_stream = profile.mid_stream
		if profile.max_stream:
			max_stream = profile.max_stream
		_band_streams = [idle_stream, low_stream, mid_stream, max_stream]
		_profile_applied = true
		_ensure_players()
		_apply_spatial()


func apply_banks(banks: Dictionary) -> void:
	if _live:
		if _car and _car.setup:
			_configure_live_from_setup(_car.setup)
		return
	if banks.is_empty():
		return
	_band_streams.clear()
	var names: PackedStringArray = PackedStringArray()
	if banks.has("names"):
		names = banks["names"] as PackedStringArray
	elif banks.has("rpms"):
		names = EngineBankBaker.band_names(banks["rpms"] as PackedFloat32Array)
	for name: String in names:
		if banks.has(name) and banks[name] is AudioStream:
			_band_streams.append(banks[name] as AudioStream)
	if banks.has("rpms"):
		_band_rpms = banks["rpms"] as PackedFloat32Array
	if _band_streams.size() >= 1:
		var last := _band_streams.size() - 1
		idle_stream = _band_streams[0]
		low_stream = _band_streams[clampi(last / 3, 0, last)]
		mid_stream = _band_streams[clampi((last * 2) / 3, 0, last)]
		max_stream = _band_streams[last]
	_profile_applied = true
	_ensure_players()
	for p in _players:
		if p.stream != null:
			p.stop()
			p.play()


func _setup_live() -> void:
	_live_stream = ClassDB.instantiate("EngineSoundStream") as AudioStream
	_live_player = AudioStreamPlayer3D.new()
	_live_player.name = "LiveEngine"
	_live_player.bus = "Master"
	_live_player.stream = _live_stream
	_live_player.max_distance = max_distance
	_live_player.unit_size = unit_size
	_live_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_live_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_live_player.volume_db = master_volume_db
	add_child(_live_player)
	_live_player.play()
	if _car and _car.audio_profile != null:
		apply_profile(_car.audio_profile, false)
	print("EngineAudio: live EngineSoundStream active")


func _configure_live_from_setup(setup: Resource) -> void:
	if _live_stream == null:
		return
	EngineBankBaker.apply_setup_to_native(_live_stream, setup)
	var vol_db := float(setup.get("engine_sound_volume_db"))
	if _live_player:
		_live_player.volume_db = master_volume_db + vol_db


func _apply_spatial_live() -> void:
	if _live_player == null:
		return
	_live_player.max_distance = max_distance
	_live_player.unit_size = unit_size


func _resolve_profile_from_pack() -> void:
	if _car != null and _car.audio_profile != null:
		apply_profile(_car.audio_profile, true)
	if _car != null:
		var user_banks := EngineBankBaker.load_user(_car.car_id)
		if not user_banks.is_empty():
			apply_banks(user_banks)
			return
	if _band_streams.is_empty():
		_band_streams = [idle_stream, low_stream, mid_stream, max_stream]


func _apply_default_rpm_refs_from_setup(setup: Resource) -> void:
	_band_rpms = EngineBankBaker.band_rpms(setup)


func _ensure_players() -> void:
	var n := maxi(_band_streams.size(), 1)
	while _players.size() < n:
		var p := AudioStreamPlayer3D.new()
		p.name = "Band%d" % _players.size()
		p.bus = "Master"
		p.volume_db = -80.0
		p.max_distance = max_distance
		p.unit_size = unit_size
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.pitch_scale = 1.0
		add_child(p)
		_players.append(p)
	_vols.resize(n)
	_vols_smooth.resize(n)
	_pitch_smooth.resize(n)
	for i in n:
		_vols[i] = 0.0
		if i >= _vols_smooth.size():
			_vols_smooth.append(0.0)
		if i >= _pitch_smooth.size():
			_pitch_smooth.append(1.0)
		var p: AudioStreamPlayer3D = _players[i]
		var stream: AudioStream = _band_streams[i] if i < _band_streams.size() else null
		if p.stream != stream:
			var was := p.playing
			p.stream = stream
			if stream != null and was:
				p.play()
		elif stream != null and not p.playing:
			p.play()
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED


func _apply_spatial() -> void:
	for p in _players:
		p.max_distance = max_distance
		p.unit_size = unit_size


func _process(delta: float) -> void:
	if _car == null or _car.setup == null:
		return
	if _live:
		_process_live(delta)
	else:
		if _players.is_empty():
			return
		_process_baked(delta)


func _process_live(delta: float) -> void:
	if _live_stream == null or _live_player == null:
		return
	var t0 := Time.get_ticks_usec()
	_smooth_rpm = lerpf(_smooth_rpm, _car.engine_rpm, clampf(10.0 * delta, 0.0, 1.0))
	var load_target := clampf(_car.throttle, 0.0, 1.0)
	if not _car.occupied:
		load_target = 0.15
	_smooth_load = lerpf(_smooth_load, load_target, clampf(6.0 * delta, 0.0, 1.0))

	var mute := (
		GameAudio != null
		and GameAudio.has_method("is_terror_playing")
		and GameAudio.is_terror_playing()
	)
	if mute:
		_live_player.volume_db = -80.0
		if _live_player.playing:
			_live_player.stop()
	else:
		var occupied_db := 0.0 if _car.occupied else -8.0
		var vol_trim := float(_car.setup.get("engine_sound_volume_db"))
		_live_player.volume_db = master_volume_db + vol_trim + occupied_db
		if not _live_player.playing:
			_live_player.play()
		_live_stream.call("set_driving", _smooth_rpm, _smooth_load, _smooth_load)

	var dt_us := Time.get_ticks_usec() - t0
	_perf_accum += float(dt_us)
	_perf_frames += 1
	if _perf_frames >= 120:
		var avg_us := _perf_accum / float(_perf_frames)
		print("EngineAudio live: avg set_driving+mix %.1f µs/frame (%.2f%% of 16.6ms)" % [
			avg_us,
			avg_us / 166.0,
		])
		_perf_accum = 0.0
		_perf_frames = 0


func _process_baked(delta: float) -> void:
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
	var vol_trim := float(_car.setup.get("engine_sound_volume_db"))
	var master := -80.0 if mute else (master_volume_db + vol_trim + load_db + occupied_db + rpm_db)

	if _band_rpms.is_empty() and _car.setup:
		_apply_default_rpm_refs_from_setup(_car.setup)
	_compute_band_weights(_smooth_rpm)

	var vol_k := clampf(vol_smooth_rate * delta, 0.0, 1.0)
	var pitch_k := clampf(pitch_smooth_rate * delta, 0.0, 1.0)
	var n := mini(_players.size(), mini(_band_streams.size(), _band_rpms.size()))
	for i in n:
		var p: AudioStreamPlayer3D = _players[i]
		if p.stream == null:
			p.volume_db = -80.0
			continue
		# Exact Autopitch (FMOD/Wwise): pitch = rpm / recorded_rpm — never flatten mid-blend.
		var ref_rpm := maxf(_band_rpms[i], 100.0)
		var target_pitch := _smooth_rpm / ref_rpm
		target_pitch = clampf(target_pitch, pitch_min, pitch_max)
		_pitch_smooth[i] = lerpf(_pitch_smooth[i], target_pitch, pitch_k)
		p.pitch_scale = _pitch_smooth[i]

		_vols_smooth[i] = lerpf(_vols_smooth[i], _vols[i], vol_k)
		var w: float = _vols_smooth[i]
		if w < 0.004:
			p.volume_db = -80.0
			continue
		p.volume_db = master + linear_to_db(clampf(w, 0.0, 1.0))
		if not p.playing and not mute:
			p.play()


## Full-span equal-power crossfade between adjacent banks (Blend Container style).
func _compute_band_weights(rpm: float) -> void:
	var n := _band_rpms.size()
	if n <= 0:
		return
	if _vols.size() != n:
		_vols.resize(n)
	if _vols_smooth.size() != n:
		_vols_smooth.resize(n)
	if _pitch_smooth.size() != n:
		var old_n := _pitch_smooth.size()
		_pitch_smooth.resize(n)
		for i in range(old_n, n):
			_pitch_smooth[i] = 1.0
	for i in n:
		_vols[i] = 0.0

	var rpm_c := maxf(rpm, 100.0)
	if n == 1 or rpm_c <= _band_rpms[0]:
		_vols[0] = 1.0
		return
	if rpm_c >= _band_rpms[n - 1]:
		_vols[n - 1] = 1.0
		return

	for i in n - 1:
		var a := maxf(_band_rpms[i], 100.0)
		var b := maxf(_band_rpms[i + 1], 100.0)
		if rpm_c < a or rpm_c > b:
			continue
		var t: float
		if use_log_blend:
			t = inverse_lerp(log(a), log(b), log(rpm_c))
		else:
			t = inverse_lerp(a, b, rpm_c)
		t = clampf(t, 0.0, 1.0)
		# Sine / constant-power — loudness stays flat across the handoff.
		var ang := t * PI * 0.5
		_vols[i] = cos(ang)
		_vols[i + 1] = sin(ang)
		return
