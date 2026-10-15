@tool
extends EditorScript

## File → Run: glue all user-bake RPM banks into ONE .wav (no game pitch / crossfade).
## Listen to hear generator quality alone. If this already sounds “electric”, problem is bake;
## if this is fine but in-game is bad — problem is Autopitch / blend.
##
## Output: user://engine_bake/<car>/audit_concat.wav
## Absolute path printed in Output panel.

const CAR_NAME := "volga"
## How much of each bank to keep (seconds). 0 = full loop.
const SECONDS_PER_BAND := 0.45
## Silence between banks so you hear the handoff as discrete steps.
const GAP_SEC := 0.12


func _run() -> void:
	var car := CAR_NAME.strip_edges().to_lower()
	var banks: Dictionary = EngineBankBaker.load_user(StringName(car))
	if banks.is_empty() or not banks.has("names") or not banks.has("rpms"):
		push_error("Concat: no user bake for '%s' at %s" % [
			car, EngineBankBaker.user_bake_dir(StringName(car)),
		])
		return

	var names: PackedStringArray = banks["names"]
	var rpms: PackedFloat32Array = banks["rpms"]
	if names.size() == 0 or names.size() != rpms.size():
		push_error("Concat: meta names/rpms mismatch")
		return

	var sample_rate := EngineBankBaker.SAMPLE_RATE
	var gap_frames := maxi(int(GAP_SEC * float(sample_rate)), 0)
	var out := PackedFloat32Array()

	for i in names.size():
		var stream: AudioStreamWAV = banks[names[i]] as AudioStreamWAV
		if stream == null:
			push_warning("Concat: skip missing stream %s" % names[i])
			continue
		if stream.mix_rate > 0:
			sample_rate = stream.mix_rate
		var mono := _wav_stream_to_mono_f32(stream)
		if mono.is_empty():
			push_warning("Concat: empty PCM %s" % names[i])
			continue
		if SECONDS_PER_BAND > 0.0:
			var keep := mini(mono.size(), int(SECONDS_PER_BAND * float(sample_rate)))
			mono = mono.slice(0, keep)
		# Tiny edge fade so splice clicks don’t fake “electric”.
		_fade_edges_local(mono, mini(128, mono.size() / 8))
		out.append_array(mono)
		if gap_frames > 0 and i < names.size() - 1:
			var silence := PackedFloat32Array()
			silence.resize(gap_frames)
			out.append_array(silence)
		print("Concat: + %s (%.0f rpm, %d frames)" % [names[i], rpms[i], mono.size()])

	if out.is_empty():
		push_error("Concat: nothing to write")
		return

	var out_path := EngineBankBaker.user_bake_dir(StringName(car)).path_join("audit_concat.wav")
	var err := _write_wav_mono(out_path, out, sample_rate)
	if err != OK:
		push_error("Concat: write failed %s (%s)" % [out_path, error_string(err)])
		return
	var abs_path := ProjectSettings.globalize_path(out_path)
	print("Concat OK: %d bands → %s (%.1f s)" % [
		names.size(), abs_path, float(out.size()) / float(sample_rate),
	])


func _wav_stream_to_mono_f32(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	if data.is_empty():
		return PackedFloat32Array()
	match stream.format:
		AudioStreamWAV.FORMAT_16_BITS:
			var n := data.size() / 2
			var channels := 2 if stream.stereo else 1
			var frames := n / channels
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
			push_warning("Concat: unsupported WAV format %s" % stream.format)
			return PackedFloat32Array()


func _fade_edges_local(samples: PackedFloat32Array, fade: int) -> void:
	var n := samples.size()
	var f := mini(fade, n / 8)
	if f <= 1:
		return
	for i in f:
		var w := float(i) / float(f)
		samples[i] *= w
		samples[n - 1 - i] *= w


func _write_wav_mono(path: String, samples: PackedFloat32Array, sample_rate: int) -> Error:
	var dir_abs := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, v)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data_size := pcm.size()
	f.store_buffer("RIFF".to_utf8_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_utf8_buffer())
	f.store_buffer("fmt ".to_utf8_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(sample_rate)
	f.store_32(sample_rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_utf8_buffer())
	f.store_32(data_size)
	f.store_buffer(pcm)
	return OK
