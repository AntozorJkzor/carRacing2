class_name EngineBankBaker
extends RefCounted

## Offline bake orchestration → seamless loop banks for EngineAudio.
## Prefers EngineSimBaker (addons/engine_sim_audio); falls back to legacy paths.

const SAMPLE_RATE := 44100
const RPM_STEP := 250.0
## Capture / slice length per RPM band (EngineSimBaker.capture_seconds).
## Sweep mode needs ≥1.0 s — shorter slices + low hf_gain → near-silent loops (clicks only).
const DEFAULT_DURATION_SEC := 1.0
const DEFAULT_SETTLE_SEC := 0.5
const SWEEP_MIN_CAPTURE_SEC := 1.0
const SWEEP_MIN_SETTLE_SEC := 0.5


static func band_name_for_rpm(rpm: float) -> String:
	return "rpm_%04d" % int(round(rpm))


static func band_rpms(setup: Resource) -> PackedFloat32Array:
	var idle := maxf(float(setup.get("idle_rpm")), 100.0)
	var mx := maxf(float(setup.get("max_rpm")), idle + RPM_STEP)
	var out: Array[float] = []
	out.append(idle)
	var first_step := ceilf(idle / RPM_STEP) * RPM_STEP
	if first_step <= idle + 1.0:
		first_step += RPM_STEP
	var r := first_step
	while r < mx - 1.0:
		out.append(r)
		r += RPM_STEP
	if mx - out[out.size() - 1] > 1.0:
		out.append(mx)
	var packed := PackedFloat32Array()
	packed.resize(out.size())
	for i in out.size():
		packed[i] = out[i]
	return packed


static func band_names(rpms: PackedFloat32Array) -> PackedStringArray:
	var names := PackedStringArray()
	names.resize(rpms.size())
	for i in rpms.size():
		names[i] = band_name_for_rpm(rpms[i])
	return names


static func band_loads_for(rpms: PackedFloat32Array) -> PackedFloat32Array:
	var n := rpms.size()
	var loads := PackedFloat32Array()
	loads.resize(n)
	if n == 0:
		return loads
	if n == 1:
		loads[0] = 0.5
		return loads
	var idle := rpms[0]
	var mx := rpms[n - 1]
	for i in n:
		var t := clampf(inverse_lerp(idle, mx, rpms[i]), 0.0, 1.0)
		loads[i] = lerpf(0.08, 1.0, pow(t, 0.85))
	return loads


static func frames_for_loop(rpm: float, duration_sec: float = 2.5) -> int:
	var cycle_sec := 120.0 / maxf(rpm, 100.0)
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
	ResourceSaver.save(samples_to_stream(samples), path.get_basename() + ".tres")
	return OK


static func write_audit_concat(
	out_dir: String,
	banks: Dictionary,
	seconds_per_band: float = 0.45,
	gap_sec: float = 0.12
) -> String:
	if out_dir.is_empty() or banks.is_empty():
		return ""
	if not banks.has("names") or not banks.has("rpms"):
		return ""
	var names: PackedStringArray = banks["names"]
	var rpms: PackedFloat32Array = banks["rpms"]
	if names.is_empty() or names.size() != rpms.size():
		return ""
	var sample_rate := SAMPLE_RATE
	var gap_frames := maxi(int(gap_sec * float(sample_rate)), 0)
	var out := PackedFloat32Array()
	var audit_names: Array[String] = []
	for i in names.size():
		audit_names.append(names[i])
	if banks.has("limiter"):
		audit_names.append("limiter")
	for i in audit_names.size():
		var stream := banks.get(audit_names[i], null) as AudioStreamWAV
		if stream == null:
			continue
		if stream.mix_rate > 0:
			sample_rate = stream.mix_rate
			gap_frames = maxi(int(gap_sec * float(sample_rate)), 0)
		var mono := wav_stream_to_mono_f32(stream)
		if mono.is_empty():
			continue
		if seconds_per_band > 0.0:
			var keep := mini(mono.size(), int(seconds_per_band * float(sample_rate)))
			mono = mono.slice(0, keep)
		fade_edges(mono, mini(128, mono.size() / 8))
		out.append_array(mono)
		if gap_frames > 0 and i < audit_names.size() - 1:
			var silence := PackedFloat32Array()
			silence.resize(gap_frames)
			out.append_array(silence)
	if out.is_empty():
		return ""
	var path := out_dir.path_join("audit_concat.wav")
	return path if save_wav_mono(path, out) == OK else ""


static func wav_stream_to_mono_f32(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	if data.is_empty():
		return PackedFloat32Array()
	match stream.format:
		AudioStreamWAV.FORMAT_16_BITS:
			var channels := 2 if stream.stereo else 1
			var frames := (data.size() / 2) / channels
			var out := PackedFloat32Array()
			out.resize(frames)
			for f in frames:
				if channels == 1:
					out[f] = float(data.decode_s16(f * 2)) / 32768.0
				else:
					var l := float(data.decode_s16(f * 4)) / 32768.0
					var r := float(data.decode_s16(f * 4 + 2)) / 32768.0
					out[f] = (l + r) * 0.5
			return out
		AudioStreamWAV.FORMAT_8_BITS:
			var frames8 := data.size() / (2 if stream.stereo else 1)
			var out8 := PackedFloat32Array()
			out8.resize(frames8)
			for f in frames8:
				if stream.stereo:
					var l8 := (float(data[f * 2]) - 128.0) / 128.0
					var r8 := (float(data[f * 2 + 1]) - 128.0) / 128.0
					out8[f] = (l8 + r8) * 0.5
				else:
					out8[f] = (float(data[f]) - 128.0) / 128.0
			return out8
		_:
			return PackedFloat32Array()


static func user_bake_dir(car_id: StringName) -> String:
	return "user://engine_bake/%s" % String(car_id).to_lower()


static func has_engine_sim() -> bool:
	return ClassDB.class_exists("EngineSimBaker")


static func has_native_baker() -> bool:
	return has_engine_sim() or ClassDB.class_exists("EngineSoundBaker")


## Map CarSetup → EngineSimBaker.apply_params (1:1 API keys).
static func params_from_setup(
	setup: Resource,
	car_id: StringName = &"",
	capture_seconds: float = DEFAULT_DURATION_SEC,
	settle_seconds: float = DEFAULT_SETTLE_SEC
) -> Dictionary:
	var cyl := clampi(int(setup.get("cylinders")), 2, 12)
	var disp_cc := clampf(float(setup.get("displacement_cc")), 500.0, 10000.0)
	var idle := maxf(float(setup.get("idle_rpm")), 100.0)
	var mx := maxf(float(setup.get("max_rpm")), idle + RPM_STEP)
	var stroke := clampf(float(setup.get("stroke_mm")), 50.0, 120.0)
	var bore := clampf(float(setup.get("bore_mm")), 0.0, 120.0)
	var layout := clampi(int(setup.get("engine_layout")), 0, 2)
	var bank := clampf(float(setup.get("bank_angle_deg")), 0.0, 180.0)
	var valves := 4 if int(setup.get("valves_per_cylinder")) >= 4 else 2

	var capture := maxf(capture_seconds, 0.25)
	var settle := maxf(settle_seconds, 0.05)
	capture = maxf(capture, SWEEP_MIN_CAPTURE_SEC)
	settle = maxf(settle, SWEEP_MIN_SETTLE_SEC)

	var params := {
		"name": String(car_id) if not String(car_id).is_empty() else "engine",
		"cylinders": cyl,
		"displacement_cc": disp_cc,
		"stroke_mm": stroke,
		"valves_per_cylinder": valves,
		"layout": layout,
		"bank_angle_deg": bank if layout != 0 else 0.0,
		"idle_rpm": idle,
		"redline_rpm": mx,
		"min_rpm": idle,
		"max_rpm": mx,
		"rpm_step": RPM_STEP,
		"throttle": 1.0,
		"settle_seconds": settle,
		"capture_seconds": capture,
		"use_rpm_sweep": true,
		"sweep_seconds": 0.0, # auto from band count
		"bake_limiter": true,
		"limiter_seconds": 0.0, # auto ≥ capture
		"limiter_cut_seconds": 0.10,
		"exhaust_length_mm": clampf(float(setup.get("exhaust_length_mm")), 300.0, 900.0),
		"cam_duration_deg": clampf(float(setup.get("cam_duration_deg")), 180.0, 280.0),
		"cam_lift_mm": clampf(float(setup.get("cam_lift_mm")), 6.0, 14.0),
		"hf_gain": clampf(float(setup.get("hf_gain")), 0.0, 1.0),
		"noise": clampf(float(setup.get("noise")), 0.0, 2.0),
		"jitter": clampf(float(setup.get("jitter")), 0.0, 1.0),
	}
	if bore > 1.0:
		params["bore_mm"] = bore
	return params


static func clear_dir(out_dir: String) -> void:
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


static func clear_user(car_id: StringName) -> void:
	clear_dir(user_bake_dir(car_id))


static func _append_fingerprint(out_dir: String, fingerprint: String) -> void:
	if fingerprint.is_empty():
		return
	var meta := ConfigFile.new()
	var path := out_dir.path_join("meta.cfg")
	meta.load(path)
	meta.set_value("bake", "fingerprint", fingerprint)
	meta.save(path)


static func _banks_from_sim_result(result: Dictionary, out_dir: String) -> Dictionary:
	var banks := {}
	var rpms := PackedFloat32Array()
	var rpms_v: Variant = result.get("rpms", [])
	if rpms_v is PackedFloat32Array:
		rpms = rpms_v
	elif rpms_v is Array:
		for v in rpms_v:
			rpms.append(float(v))
	var names := band_names(rpms)
	banks["rpms"] = rpms
	banks["names"] = names
	for i in names.size():
		var name: String = names[i]
		var path := out_dir.path_join("%s.tres" % name)
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			push_error("EngineBankBaker: missing baked band %s" % path)
			continue
		var stream := _load_stream_fresh(path)
		if stream == null:
			push_error("EngineBankBaker: failed load %s" % path)
			continue
		banks[name] = stream
	_load_limiter_into_banks(banks, out_dir, result)
	return banks


static func _load_limiter_into_banks(banks: Dictionary, out_dir: String, result: Dictionary = {}) -> void:
	var lim_name := "rpm_limiter"
	if result.has("limiter_band") and not str(result.get("limiter_band")).is_empty():
		lim_name = str(result.get("limiter_band"))
	var path := out_dir.path_join("%s.tres" % lim_name)
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return
	var stream := _load_stream_fresh(path)
	if stream == null:
		return
	banks[lim_name] = stream
	banks["limiter"] = stream
	banks["has_limiter"] = true
	banks["limiter_band"] = lim_name


static func _load_stream_fresh(path: String) -> AudioStream:
	## Bake overwrites .tres on disk; ignore/replace Godot cache or we keep silent zeros.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as AudioStream


static func bake_streams(setup: Resource, duration_sec: float = DEFAULT_DURATION_SEC) -> Dictionary:
	if has_engine_sim():
		var tmp := "user://engine_bake/_tmp_streams"
		clear_dir(tmp)
		var baker: RefCounted = ClassDB.instantiate("EngineSimBaker")
		baker.call("apply_params", params_from_setup(setup, &"tmp", duration_sec, DEFAULT_SETTLE_SEC))
		var result: Dictionary = baker.call("bake_and_save", tmp)
		if not bool(result.get("ok", false)):
			push_error("EngineBankBaker: EngineSim bake failed: %s" % str(result.get("error", "")))
			return {}
		return _banks_from_sim_result(result, tmp)

	var rpms := band_rpms(setup)
	var names := band_names(rpms)
	var loads := band_loads_for(rpms)
	var result := {}
	result["rpms"] = rpms
	result["names"] = names
	for b in rpms.size():
		var name: String = names[b]
		result[name] = samples_to_stream(render_band(setup, rpms[b], loads[b], duration_sec))
	return result


static func bake_user(
	setup: Resource,
	car_id: StringName,
	duration_sec: float = DEFAULT_DURATION_SEC,
	fingerprint: String = ""
) -> Dictionary:
	var out_dir := user_bake_dir(car_id)
	## Bake into a temp folder first so a failed/aborted run never leaves silent banks.
	var tmp_dir := "user://engine_bake/_tmp_%s" % String(car_id).to_lower()
	clear_dir(tmp_dir)

	if has_engine_sim():
		var baker: RefCounted = ClassDB.instantiate("EngineSimBaker")
		baker.call("apply_params", params_from_setup(setup, car_id, duration_sec, DEFAULT_SETTLE_SEC))
		var t0 := Time.get_ticks_msec()
		var result: Dictionary = baker.call("bake_and_save", tmp_dir)
		var dt := Time.get_ticks_msec() - t0
		if not bool(result.get("ok", false)):
			push_error("EngineBankBaker: EngineSimBake failed for %s: %s" % [
				String(car_id), str(result.get("error", "")),
			])
			clear_dir(tmp_dir)
			return {}
		_append_fingerprint(tmp_dir, fingerprint)
		var banks := _banks_from_sim_result(result, tmp_dir)
		var audit_path := write_audit_concat(tmp_dir, banks)
		if not _promote_bake_dir(tmp_dir, out_dir):
			push_error("EngineBankBaker: failed to promote bake for %s" % String(car_id))
			clear_dir(tmp_dir)
			return {}
		## Belt-and-suspenders: fingerprint must land in the final folder.
		_append_fingerprint(out_dir, fingerprint)
		print("EngineBankBaker: EngineSim bake %s → %d bands in %d ms @ %s" % [
			String(car_id),
			int(result.get("band_count", 0)),
			dt,
			out_dir,
		])
		if not audit_path.is_empty():
			print("EngineBankBaker: audit concat → %s" % out_dir.path_join("audit_concat.wav"))
		return banks

	push_warning("EngineBankBaker: EngineSimBaker missing — legacy bake")
	var banks_legacy := bake_streams(setup, duration_sec)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp_dir))
	var rpms: PackedFloat32Array = banks_legacy["rpms"]
	var names: PackedStringArray = banks_legacy["names"]
	for b in rpms.size():
		var name: String = names[b]
		var err := ResourceSaver.save(banks_legacy[name], tmp_dir.path_join("%s.tres" % name))
		if err != OK:
			push_error("EngineBankBaker: failed user save %s (%s)" % [name, error_string(err)])
	var meta := ConfigFile.new()
	meta.set_value("bake", "band_count", rpms.size())
	meta.set_value("bake", "rpm_step", RPM_STEP)
	for b in rpms.size():
		meta.set_value("bake", "rpm_%d" % b, rpms[b])
		meta.set_value("bake", "band_%d" % b, names[b])
	if not fingerprint.is_empty():
		meta.set_value("bake", "fingerprint", fingerprint)
	meta.save(tmp_dir.path_join("meta.cfg"))
	write_audit_concat(tmp_dir, banks_legacy)
	if not _promote_bake_dir(tmp_dir, out_dir):
		clear_dir(tmp_dir)
		return {}
	return banks_legacy


static func write_bake_meta(
	out_dir: String,
	rpms: PackedFloat32Array,
	names: PackedStringArray,
	fingerprint: String
) -> void:
	var meta := ConfigFile.new()
	meta.set_value("bake", "band_count", rpms.size())
	meta.set_value("bake", "rpm_step", RPM_STEP)
	for b in rpms.size():
		meta.set_value("bake", "rpm_%d" % b, rpms[b])
		meta.set_value("bake", "band_%d" % b, names[b])
	if not fingerprint.is_empty():
		meta.set_value("bake", "fingerprint", fingerprint)
	meta.save(out_dir.path_join("meta.cfg"))


static func promote_bake_dir(tmp_dir: String, out_dir: String) -> bool:
	return _promote_bake_dir(tmp_dir, out_dir)


static func _promote_bake_dir(tmp_dir: String, out_dir: String) -> bool:
	if tmp_dir.is_empty() or out_dir.is_empty():
		return false
	clear_dir(out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var dir := DirAccess.open(tmp_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var ok := true
	while file_name != "":
		if not dir.current_is_dir():
			var from_path := tmp_dir.path_join(file_name)
			var to_path := out_dir.path_join(file_name)
			var err := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(from_path),
				ProjectSettings.globalize_path(to_path)
			)
			if err != OK:
				push_error("EngineBankBaker: copy %s → %s failed (%s)" % [
					from_path, to_path, error_string(err),
				])
				ok = false
				break
		file_name = dir.get_next()
	dir.list_dir_end()
	clear_dir(tmp_dir)
	return ok


static func user_fingerprint(car_id: StringName) -> String:
	var meta := ConfigFile.new()
	if meta.load(user_bake_dir(car_id).path_join("meta.cfg")) != OK:
		return ""
	return str(meta.get_value("bake", "fingerprint", ""))


## Load a folder of per-RPM chunks: meta.cfg + rpm_XXXX.tres (250 rpm ladder).
static func load_dir(out_dir: String) -> Dictionary:
	if out_dir.is_empty():
		return {}
	var meta := ConfigFile.new()
	var meta_path := out_dir.path_join("meta.cfg")
	if meta.load(meta_path) != OK:
		return {}
	var count := int(meta.get_value("bake", "band_count", 0))
	if count <= 0:
		return {}
	var result := {}
	var rpms := PackedFloat32Array()
	var names := PackedStringArray()
	rpms.resize(count)
	names.resize(count)
	for b in count:
		var rpm_v := float(meta.get_value("bake", "rpm_%d" % b, 800.0))
		var name := str(meta.get_value("bake", "band_%d" % b, band_name_for_rpm(rpm_v)))
		var path := out_dir.path_join("%s.tres" % name)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			push_warning("EngineBankBaker.load_dir: missing %s" % path)
			return {}
		var stream := _load_stream_fresh(path)
		if stream == null:
			push_warning("EngineBankBaker.load_dir: failed load %s" % path)
			return {}
		names[b] = name
		rpms[b] = rpm_v
		result[name] = stream
	result["rpms"] = rpms
	result["names"] = names
	if bool(meta.get_value("bake", "has_limiter", false)):
		_load_limiter_into_banks(result, out_dir, {
			"limiter_band": str(meta.get_value("bake", "limiter_band", "rpm_limiter")),
		})
	return result


static func load_user(car_id: StringName) -> Dictionary:
	return load_dir(user_bake_dir(car_id))


static func has_user_bake(car_id: StringName) -> bool:
	return not load_user(car_id).is_empty()


## Legacy live EngineSoundStream mapping (optional debug path).
static func apply_setup_to_native(native: Object, setup: Resource) -> void:
	if native == null or setup == null:
		return
	var liters := clampf(float(setup.get("displacement_cc")) * 0.001, 0.5, 8.0)
	native.set("displacement_l", liters)
	native.set("power_hp", clampf(float(setup.get("max_power_hp")), 50.0, 1000.0))
	var cyl := clampi(int(setup.get("cylinders")), 3, 12)
	native.set("cylinders", cyl)
	var layout := clampi(int(setup.get("engine_layout")), 0, 2)
	native.set("layout", layout)
	# Approximate tip diameter from exhaust length for legacy baker.
	var ex_len := clampf(float(setup.get("exhaust_length_mm")), 300.0, 900.0)
	var tip := lerpf(100.0, 35.0, clampf(inverse_lerp(360.0, 640.0, ex_len), 0.0, 1.0))
	native.set("exhaust_diameter_mm", tip)
	native.set("has_turbo", float(setup.get("noise")) < 0.6)
	native.set("has_supercharger", false)
	var muffler := ex_len > 520.0
	var style := 1 if muffler else 0
	native.set("exhaust_style", style)
	native.set("resonators", 1 if muffler else 0)
	native.set("bank_angle_deg", float(setup.get("bank_angle_deg")) if layout != 0 else 0.0)
	if native.has_method("configure"):
		native.call("configure")


static func _make_legacy_baker(setup: Resource) -> Object:
	if not ClassDB.class_exists("EngineSoundBaker"):
		return null
	var baker: Object = ClassDB.instantiate("EngineSoundBaker")
	apply_setup_to_native(baker, setup)
	return baker


static func render_band(setup: Resource, rpm: float, load: float, duration_sec: float = 2.5) -> PackedFloat32Array:
	var baker := _make_legacy_baker(setup)
	if baker != null and baker.has_method("render"):
		var frames: int = int(baker.call("frames_for_loop", rpm, duration_sec)) if baker.has_method("frames_for_loop") else frames_for_loop(rpm, duration_sec)
		if frames < 256:
			frames = frames_for_loop(rpm, duration_sec)
		baker.call("reset")
		var warm: int = maxi(int(float(SAMPLE_RATE) * 0.12), 512)
		baker.call("render", rpm, load, load, warm)
		var samples: PackedFloat32Array = baker.call("render", rpm, load, load, frames)
		fade_edges(samples, 256)
		normalize_peak(samples, 0.68)
		return samples

	push_warning("EngineBankBaker: legacy render — EngineLabSynth")
	var synth := EngineLabSynth.new()
	synth.configure_from_setup(setup)
	synth.rpm = rpm
	synth.throttle = load
	synth.render_mono(int(SAMPLE_RATE * 0.25))
	var samples_fb := synth.render_mono(frames_for_loop(rpm, duration_sec))
	fade_edges(samples_fb, 256)
	normalize_peak(samples_fb, 0.62)
	return samples_fb


## Editor/pack bake into out_dir via EngineSimBaker.bake_and_save.
static func bake_setup(setup: Resource, out_dir: String, duration_sec: float = DEFAULT_DURATION_SEC) -> Dictionary:
	if has_engine_sim():
		clear_dir(out_dir)
		var baker: RefCounted = ClassDB.instantiate("EngineSimBaker")
		var car_name := out_dir.get_file()
		baker.call("apply_params", params_from_setup(setup, StringName(car_name), duration_sec, DEFAULT_SETTLE_SEC))
		var result: Dictionary = baker.call("bake_and_save", out_dir)
		if not bool(result.get("ok", false)):
			push_error("EngineBankBaker: bake_setup failed: %s" % str(result.get("error", "")))
			return {}
		var banks := _banks_from_sim_result(result, out_dir)
		write_audit_concat(out_dir, banks)
		# Paths for editor tool convenience.
		var names: PackedStringArray = banks["names"]
		for name: String in names:
			banks[name] = out_dir.path_join("%s.tres" % name)
		return banks

	var rpms := band_rpms(setup)
	var names_fb := band_names(rpms)
	var loads := band_loads_for(rpms)
	var result_fb := {"rpms": rpms, "names": names_fb}
	for b in rpms.size():
		var name: String = names_fb[b]
		var path := out_dir.path_join("%s.wav" % name)
		save_wav_mono(path, render_band(setup, rpms[b], loads[b], duration_sec))
		var tres := out_dir.path_join("%s.tres" % name)
		result_fb[name] = tres if ResourceLoader.exists(tres) else path
	return result_fb
