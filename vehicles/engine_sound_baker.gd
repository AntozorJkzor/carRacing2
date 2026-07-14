class_name EngineSoundBaker
extends RefCounted

## Offline bake: waveguide engine → seamless WAV banks for EngineAudio.

const SAMPLE_RATE := 22050
const BAND_NAMES := ["idle", "low", "mid", "max"]


static func band_rpms(setup: Resource) -> PackedFloat32Array:
	var idle := float(setup.get("idle_rpm"))
	var mx := maxf(float(setup.get("max_rpm")), idle + 500.0)
	# Low sits clearly above idle so banks differ in pitch + work character.
	return PackedFloat32Array([
		idle,
		lerpf(idle, mx, 0.34),
		lerpf(idle, mx, 0.62),
		lerpf(idle, mx, 0.92),
	])


static func band_loads() -> PackedFloat32Array:
	# Idle = soft coast; low already “pulling” so timbre leaves idle faster.
	return PackedFloat32Array([0.08, 0.58, 0.82, 1.0])


## Duration snapped to exact engine-cycle count for seamless looping.
static func frames_for_loop(rpm: float, duration_sec: float = 2.5) -> int:
	var cycle_sec := 120.0 / maxf(rpm, 100.0) # one 720° cycle
	var cycles := maxi(int(ceil(duration_sec / cycle_sec)), 4)
	return int(round(float(cycles) * cycle_sec * float(SAMPLE_RATE)))


static func normalize_peak(samples: PackedFloat32Array, target: float = 0.72) -> void:
	var peak := 0.0
	for i in samples.size():
		var a := absf(samples[i])
		if a > peak:
			peak = a
	if peak < 1e-6:
		return
	var g := target / peak
	for i in samples.size():
		samples[i] *= g


static func fade_edges(samples: PackedFloat32Array, fade_samples: int = 512) -> void:
	var n := samples.size()
	var f := mini(fade_samples, n / 8)
	if f <= 1:
		return
	for i in f:
		var w := float(i) / float(f)
		samples[i] *= w
		samples[n - 1 - i] *= w


static func to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes


static func samples_to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	stream.data = to_pcm16(samples)
	return stream


static func save_wav_mono(path: String, samples: PackedFloat32Array) -> Error:
	var dir_abs := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var pcm := to_pcm16(samples)
	var data_size := pcm.size()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	# RIFF WAV header (PCM 16-bit mono).
	f.store_buffer("RIFF".to_utf8_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_utf8_buffer())
	f.store_buffer("fmt ".to_utf8_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(SAMPLE_RATE)
	f.store_32(SAMPLE_RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_utf8_buffer())
	f.store_32(data_size)
	f.store_buffer(pcm)
	var stream := samples_to_stream(samples)
	var res_path := path.get_basename() + ".tres"
	ResourceSaver.save(stream, res_path)
	return OK


static func user_bake_dir(car_id: StringName) -> String:
	return "user://engine_bake/%s" % String(car_id).to_lower()


## In-memory banks for immediate EngineAudio swap.
## Returns {idle/low/mid/max: AudioStreamWAV, rpms: PackedFloat32Array}.
static func bake_streams(setup: Resource, duration_sec: float = 1.5) -> Dictionary:
	var rpms := band_rpms(setup)
	var loads := band_loads()
	var result := {}
	result["rpms"] = rpms
	for b in BAND_NAMES.size():
		var name: String = BAND_NAMES[b]
		var samples := render_band(setup, rpms[b], loads[b], duration_sec)
		result[name] = samples_to_stream(samples)
	return result


## Bake + persist under user:// so next race loads tuned banks.
static func bake_user(
	setup: Resource,
	car_id: StringName,
	duration_sec: float = 1.5,
	fingerprint: String = ""
) -> Dictionary:
	var banks := bake_streams(setup, duration_sec)
	var out_dir := user_bake_dir(car_id)
	var dir_abs := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var rpms: PackedFloat32Array = banks["rpms"]
	for b in BAND_NAMES.size():
		var name: String = BAND_NAMES[b]
		var stream: AudioStreamWAV = banks[name]
		var tres_path := out_dir.path_join("%s.tres" % name)
		var err := ResourceSaver.save(stream, tres_path)
		if err != OK:
			push_error("EngineSoundBaker: failed user save %s (%s)" % [tres_path, error_string(err)])
	var meta := ConfigFile.new()
	meta.set_value("bake", "idle_rpm", rpms[0])
	meta.set_value("bake", "low_rpm", rpms[1])
	meta.set_value("bake", "mid_rpm", rpms[2])
	meta.set_value("bake", "max_rpm", rpms[3])
	if not fingerprint.is_empty():
		meta.set_value("bake", "fingerprint", fingerprint)
	meta.save(out_dir.path_join("meta.cfg"))
	print("EngineSoundBaker: user bake %s @ %s" % [String(car_id), out_dir])
	return banks


static func user_fingerprint(car_id: StringName) -> String:
	var meta := ConfigFile.new()
	if meta.load(user_bake_dir(car_id).path_join("meta.cfg")) != OK:
		return ""
	return str(meta.get_value("bake", "fingerprint", ""))


static func load_user(car_id: StringName) -> Dictionary:
	var out_dir := user_bake_dir(car_id)
	var result := {}
	for name: String in BAND_NAMES:
		var path := out_dir.path_join("%s.tres" % name)
		if not FileAccess.file_exists(path):
			return {}
		var stream := load(path) as AudioStream
		if stream == null:
			return {}
		result[name] = stream
	var meta := ConfigFile.new()
	if meta.load(out_dir.path_join("meta.cfg")) == OK:
		result["rpms"] = PackedFloat32Array([
			float(meta.get_value("bake", "idle_rpm", 800.0)),
			float(meta.get_value("bake", "low_rpm", 2200.0)),
			float(meta.get_value("bake", "mid_rpm", 4200.0)),
			float(meta.get_value("bake", "max_rpm", 6300.0)),
		])
	return result


static func clear_user(car_id: StringName) -> void:
	var out_dir := user_bake_dir(car_id)
	var abs_dir := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var dir := DirAccess.open(out_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_dir)


static func render_band(setup: Resource, rpm: float, load: float, duration_sec: float = 2.5) -> PackedFloat32Array:
	var synth := EngineWaveguideSynth.new()
	synth.configure_from_setup(setup)
	synth.rpm = rpm
	synth.throttle = load
	# Warm-up so delay lines settle before capture.
	var warm := int(SAMPLE_RATE * 0.35)
	synth.render_mono(warm)
	var frames := frames_for_loop(rpm, duration_sec)
	var samples := synth.render_mono(frames)
	fade_edges(samples, 256)
	_post_warm(samples)
	normalize_peak(samples, 0.56)
	return samples


## Mild dual LP to kill leftover rasp / lisp — keep some top for redline clarity.
static func _post_warm(samples: PackedFloat32Array) -> void:
	var lp1 := 0.0
	var lp2 := 0.0
	var a1 := 1.0 - exp(-TAU * 3400.0 / float(SAMPLE_RATE))
	var a2 := 1.0 - exp(-TAU * 2400.0 / float(SAMPLE_RATE))
	for i in samples.size():
		lp1 += a1 * (samples[i] - lp1)
		lp2 += a2 * (lp1 - lp2)
		samples[i] = lerpf(samples[i], lp2, 0.5)


## Bakes idle/low/mid/max into out_dir. Returns {"idle": path, ... , "rpms": PackedFloat32Array}.
static func bake_setup(setup: Resource, out_dir: String, duration_sec: float = 2.5) -> Dictionary:
	var rpms := band_rpms(setup)
	var loads := band_loads()
	var result := {}
	result["rpms"] = rpms
	for b in BAND_NAMES.size():
		var name: String = BAND_NAMES[b]
		var path := out_dir.path_join("%s.wav" % name)
		var samples := render_band(setup, rpms[b], loads[b], duration_sec)
		var err := save_wav_mono(path, samples)
		if err != OK:
			push_error("EngineSoundBaker: failed to save %s (%s)" % [path, error_string(err)])
		else:
			print("EngineSoundBaker: wrote %s (rpm=%.0f, frames=%d)" % [path, rpms[b], samples.size()])
		# Prefer looped .tres twin if present.
		var tres := out_dir.path_join("%s.tres" % name)
		result[name] = tres if ResourceLoader.exists(tres) else path
	return result
