class_name EngineSynth
extends RefCounted

## Lightweight pulse→pipe engine synth (Baldan-inspired, GDScript-friendly).
## Per-cylinder waveguides were too heavy on the main thread — shared delay pipes only.

const SAMPLE_RATE := 22050.0
const PIPE_SIZE := 512 # power of 2 — room for long-stroke muffler delays
const MUFF_SIZE := 128
const PIPE_MASK := PIPE_SIZE - 1
const MUFF_MASK := MUFF_SIZE - 1

# F5 overload / band meter (EngineAudio).
const METER_BAND_HZ := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0]
var meter_enabled: bool = false
var _m_peak_out: float = 0.0
var _m_peak_pre: float = 0.0
var _m_sum_sq: float = 0.0
var _m_n: int = 0
var _m_near_clip: int = 0
var _m_hard_drive: int = 0
var _m_band_e: PackedFloat32Array = PackedFloat32Array()
var _m_band_lp: PackedFloat32Array = PackedFloat32Array()
var _m_band_coef: PackedFloat32Array = PackedFloat32Array()

var _revolution: float = 0.0
var _bu_phase: float = 0.0
var _bu2_phase: float = 0.0
var _noise_seed: int = 2463534242
var _intake_lp: float = 0.0
var _block_lp: float = 0.0
var _pipe_lp: float = 0.0
var _sub_lp: float = 0.0
var _chest_lp: float = 0.0
var _turbo_phase: float = 0.0
var _sc_phase: float = 0.0
var _turbo_spool: float = 0.0

var _pipe: PackedFloat32Array = PackedFloat32Array()
var _pipe_i: int = 0
var _muff: PackedFloat32Array = PackedFloat32Array()
var _muff_i: int = 0
var _muff2: PackedFloat32Array = PackedFloat32Array()
var _muff2_i: int = 0


func _init() -> void:
	_pipe.resize(PIPE_SIZE)
	_pipe.fill(0.0)
	_muff.resize(MUFF_SIZE)
	_muff.fill(0.0)
	_muff2.resize(MUFF_SIZE)
	_muff2.fill(0.0)
	var bc := METER_BAND_HZ.size()
	_m_band_e.resize(bc + 1)
	_m_band_lp.resize(bc)
	_m_band_coef.resize(bc)
	_m_band_e.fill(0.0)
	_m_band_lp.fill(0.0)
	for i in bc:
		_m_band_coef[i] = 1.0 - exp(-TAU * float(METER_BAND_HZ[i]) / SAMPLE_RATE)


func reset() -> void:
	_revolution = 0.0
	_bu_phase = 0.0
	_bu2_phase = 0.0
	_intake_lp = 0.0
	_block_lp = 0.0
	_pipe_lp = 0.0
	_sub_lp = 0.0
	_chest_lp = 0.0
	_turbo_phase = 0.0
	_sc_phase = 0.0
	_turbo_spool = 0.0
	_pipe_i = 0
	_muff_i = 0
	_muff2_i = 0
	_pipe.fill(0.0)
	_muff.fill(0.0)
	_muff2.fill(0.0)
	reset_meters()


func reset_meters() -> void:
	_m_peak_out = 0.0
	_m_peak_pre = 0.0
	_m_sum_sq = 0.0
	_m_n = 0
	_m_near_clip = 0
	_m_hard_drive = 0
	_m_band_e.fill(0.0)
	_m_band_lp.fill(0.0)


func take_meter_snapshot() -> Dictionary:
	var n := maxi(_m_n, 1)
	var rms := sqrt(_m_sum_sq / float(n))
	var near_pct := 100.0 * float(_m_near_clip) / float(n)
	var hard_pct := 100.0 * float(_m_hard_drive) / float(n)
	var total_e := 0.0
	for i in _m_band_e.size():
		total_e += _m_band_e[i]
	total_e = maxf(total_e, 1e-12)
	var bands: Array = []
	var top_i := 0
	var top_e := -1.0
	for i in _m_band_e.size():
		var e: float = _m_band_e[i]
		var label: String
		if i == 0:
			label = "<%dHz" % int(METER_BAND_HZ[0])
		elif i >= METER_BAND_HZ.size():
			label = ">%dHz" % int(METER_BAND_HZ[METER_BAND_HZ.size() - 1])
		else:
			label = "%d-%dHz" % [int(METER_BAND_HZ[i - 1]), int(METER_BAND_HZ[i])]
		var pct := 100.0 * e / total_e
		bands.append({"label": label, "energy": e, "pct": pct})
		if e > top_e:
			top_e = e
			top_i = i
	var snap := {
		"frames": _m_n,
		"peak_out": _m_peak_out,
		"peak_pre": _m_peak_pre,
		"rms": rms,
		"crest": _m_peak_out / maxf(rms, 1e-6),
		"near_clip_pct": near_pct,
		"hard_drive_pct": hard_pct,
		"bands": bands,
		"top_band": bands[top_i]["label"] if bands.size() > 0 else "?",
		"overload": _m_peak_pre > 1.2 or hard_pct > 5.0 or near_pct > 15.0,
	}
	reset_meters()
	return snap


func format_meter_snapshot(snap: Dictionary, rpm: float = 0.0, engine_load: float = 0.0) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"[EngineSynth] RPM=%.0f load=%.2f peak_out=%.3f peak_pre=%.3f rms=%.3f crest=%.1f near_clip=%.1f%% hard_drive=%.1f%% OVERLOAD=%s top=%s"
		% [
			rpm,
			engine_load,
			float(snap.get("peak_out", 0.0)),
			float(snap.get("peak_pre", 0.0)),
			float(snap.get("rms", 0.0)),
			float(snap.get("crest", 0.0)),
			float(snap.get("near_clip_pct", 0.0)),
			float(snap.get("hard_drive_pct", 0.0)),
			str(snap.get("overload", false)),
			str(snap.get("top_band", "?")),
		]
	)
	var bands: Array = snap.get("bands", []) as Array
	var bar := ""
	for b in bands:
		var pct: float = float(b.get("pct", 0.0))
		var marks := mini(20, int(round(pct / 5.0)))
		bar += "%s %5.1f%% %s\n" % [str(b.get("label", "?")), pct, "#".repeat(marks)]
	lines.append(bar.strip_edges())
	return "\n".join(lines)


func _meter_tick(out_s: float, pre_s: float) -> void:
	if not meter_enabled:
		return
	var ao := absf(out_s)
	var ap := absf(pre_s)
	if ao > _m_peak_out:
		_m_peak_out = ao
	if ap > _m_peak_pre:
		_m_peak_pre = ap
	_m_sum_sq += out_s * out_s
	_m_n += 1
	if ap >= 0.95:
		_m_near_clip += 1
	if ap >= 1.5:
		_m_hard_drive += 1
	var x := out_s
	var prev_y := 0.0
	for i in _m_band_lp.size():
		_m_band_lp[i] += _m_band_coef[i] * (x - _m_band_lp[i])
		var y: float = _m_band_lp[i]
		var band := y - prev_y
		_m_band_e[i] += band * band
		prev_y = y
	var hi := x - prev_y
	_m_band_e[_m_band_lp.size()] += hi * hi


func render_to_playback(
	playback: AudioStreamGeneratorPlayback,
	setup: CarSetup,
	rpm: float,
	engine_load: float,
	frame_count: int
) -> void:
	if playback == null or setup == null or frame_count <= 0:
		return

	var cyl_n := clampi(setup.cylinders, 2, 12)
	var stroke := clampf(setup.stroke_mm, 50.0, 120.0)
	var disp := clampf(setup.get_displacement_liters(), 0.5, 12.0)
	var exhaust_mm := lerpf(100.0, 35.0, clampf(inverse_lerp(360.0, 640.0, setup.exhaust_length_mm), 0.0, 1.0))
	var muffler := setup.exhaust_length_mm > 520.0
	var has_forced := setup.noise < 0.6
	var cyl_inv := 1.0 / float(cyl_n)
	var load_a := clampf(engine_load, 0.0, 1.0)
	var rpm_c := maxf(rpm, setup.idle_rpm * 0.5)
	var rpm_t := clampf(
		inverse_lerp(setup.idle_rpm, maxf(setup.max_rpm, setup.idle_rpm + 1.0), rpm_c),
		0.0,
		1.0
	)
	var size_t := clampf((disp - 0.8) / 3.2, 0.0, 1.0)
	var stroke_t := clampf(inverse_lerp(65.0, 100.0, stroke), 0.0, 1.0)
	var hp := clampf(setup.max_power_hp, 40.0, 600.0)
	var hp_t := clampf(inverse_lerp(80.0, 380.0, hp), 0.0, 1.0)
	var straight := not muffler
	var dia_t := clampf((exhaust_mm - 30.0) / 90.0, 0.0, 1.0)

	# Liters/cylinder — Volga 2.5 I4 (~0.62) vs 1.0 I4 (0.25).
	var lit_cyl := disp / float(cyl_n)
	var thump_t := clampf(inverse_lerp(0.28, 0.7, lit_cyl), 0.0, 1.0)
	var street_t := stroke_t * lerpf(1.15, 0.45, clampf((float(cyl_n) - 4.0) / 8.0, 0.0, 1.0))
	street_t = clampf(street_t * lerpf(0.9, 1.2, thump_t), 0.0, 1.0)
	var density_t := clampf(inverse_lerp(45.0, 130.0, hp / maxf(disp, 0.5)), 0.0, 1.0)
	# How "busy" pulses feel — street lug compresses rate so 4k rpm ≠ sportbike zip.
	var feel_fast := lerpf(0.42, 1.0, (1.0 - street_t) * (1.0 - thump_t * 0.55))
	feel_fast = clampf(feel_fast, 0.4, 1.0)

	var ign_time := lerpf(0.03, 0.09, street_t) * lerpf(1.05, 0.8, density_t)
	var pulse_amp := (0.08 + thump_t * 0.16) * lerpf(0.9, 1.05, hp_t) * lerpf(0.55, 1.0, load_a)
	pulse_amp *= lerpf(0.75, 0.35, street_t)
	var ign_amp := (0.35 + thump_t * 0.4 + street_t * 0.2) * lerpf(0.95, 1.1, hp_t) * (0.4 + load_a * 0.6)
	ign_amp *= lerpf(1.0, 1.1, rpm_t * rpm_t)
	if straight:
		pulse_amp *= 1.05
		ign_amp *= 1.12

	# Slow compressed "бу" (old muffler path) — pitch climbs gently, not 1:1 with RPM.
	var f_fire := rpm_c / 60.0 * (float(cyl_n) * 0.5)
	var pair := 0.65 if cyl_n == 4 else (0.35 if cyl_n == 6 else 0.15)
	pair = lerpf(pair, pair * 0.5, 1.0 - street_t)
	var f_merge := lerpf(f_fire, f_fire * 0.5, pair)
	var f_bu := 14.0 + pow(clampf(f_merge / 18.0, 0.12, 10.0), 0.68) * lerpf(20.0, 30.0, thump_t)
	# Cap boom speed hard on street — was the "sportbike on revs" feeling.
	var bu_cap := lerpf(48.0, 110.0, 1.0 - street_t * 0.85)
	f_bu = clampf(f_bu, 12.0, bu_cap)
	var f_bu2 := clampf(f_bu * 2.0, 24.0, bu_cap * 1.8)
	var bu_amp := (0.38 + thump_t * 0.35 + street_t * 0.22) * lerpf(0.9, 1.1, hp_t) * lerpf(0.55, 1.0, load_a)
	if muffler:
		bu_amp *= 0.62
	var am_depth := lerpf(0.62, 0.32, rpm_t) * lerpf(0.85, 1.05, street_t)
	am_depth = clampf(am_depth, 0.22, 0.7)

	var pipe_delay := int(lerpf(110.0, 200.0, thump_t) * lerpf(1.05, 0.88, dia_t))
	pipe_delay = clampi(pipe_delay, 72, PIPE_SIZE - 2)
	var muff_delay := clampi(int(lerpf(32.0, 62.0, thump_t)), 18, MUFF_SIZE - 2)
	var muff2_delay := clampi(muff_delay + 10 + (6 if muffler else 0), 18, MUFF_SIZE - 2)
	var pipe_fb := (0.28 if muffler else 0.16) * lerpf(0.95, 1.05, street_t)
	pipe_fb *= lerpf(1.0, 0.65, rpm_t)
	var muff_fb := (0.18 if muffler else 0.07) * lerpf(0.95, 1.1, street_t)
	muff_fb *= lerpf(1.0, 0.55, rpm_t)

	var intake_amp := lerpf(0.02, 0.055, load_a) * lerpf(0.45, 0.7, rpm_t) * lerpf(1.0, 0.4, street_t)
	if rpm_c < 40.0:
		intake_amp = 0.0

	var inv_sr := 1.0 / SAMPLE_RATE
	var intake_a := 1.0 - exp(-TAU * lerpf(1800.0, 3500.0, 1.0 - street_t) * inv_sr)
	var block_cut := lerpf(100.0, 170.0, rpm_t) * lerpf(0.85, 1.15, thump_t)
	var block_a := 1.0 - exp(-TAU * block_cut * inv_sr)
	var pipe_cut := lerpf(650.0, 1600.0, rpm_t) * lerpf(0.8, 1.2, thump_t)
	if muffler:
		pipe_cut *= lerpf(0.65, 0.85, thump_t)
	else:
		pipe_cut *= 1.1
	var pipe_a := 1.0 - exp(-TAU * pipe_cut * inv_sr)
	# Mild sub trim — keep some slow bass, but hush it (esp. with muffler).
	var sub_cut_hz := 38.0 if muffler else 28.0
	var sub_a := 1.0 - exp(-TAU * sub_cut_hz * inv_sr)
	var sub_trim := 0.55 if muffler else 0.32
	var chest_a := 1.0 - exp(-TAU * lerpf(140.0, 210.0, thump_t) * inv_sr)

	if has_forced:
		_turbo_spool = lerpf(_turbo_spool, load_a * lerpf(0.35, 1.0, rpm_t), 0.012)
	else:
		_turbo_spool = lerpf(_turbo_spool, 0.0, 0.02)

	# Mix: street = slow бу dominant; race = more pipe tick.
	var bu_mix := lerpf(0.38, 0.58, street_t) * lerpf(0.85, 1.1, thump_t)
	if muffler:
		bu_mix *= 0.7
	var block_mix := lerpf(0.18, 0.1, rpm_t) * lerpf(0.8, 1.1, thump_t)
	var pipe_mix := lerpf(0.22, 0.45, 1.0 - street_t) * lerpf(0.85, 1.1, thump_t)
	pipe_mix = lerpf(0.28, pipe_mix, feel_fast)
	var intake_mix := lerpf(0.025, 0.05, rpm_t) * (1.0 - street_t * 0.6)
	if straight:
		pipe_mix *= 1.15
		bu_mix *= 1.05

	var gain := db_to_linear(setup.engine_sound_volume_db) * 3.6 * lerpf(0.9, 1.15, hp_t)
	gain *= lerpf(1.0, 1.2, thump_t)
	if straight:
		gain *= 1.12

	var pair_amt := 0.0
	if cyl_n == 4:
		pair_amt = lerpf(0.7, 0.45, rpm_t) * street_t
	elif cyl_n == 6:
		pair_amt = 0.25 * street_t
	elif cyl_n >= 8:
		pair_amt = 0.08

	# Unrolled cylinder phases stay cheap: float math only, shared pipes.
	for _i in frame_count:
		var noise := _next_noise()
		_intake_lp += intake_a * (noise - _intake_lp)

		var block := 0.0
		var exhaust_excite := 0.0
		var intake_sum := 0.0

		for c in cyl_n:
			var x := _revolution + float(c) * cyl_inv
			x -= floorf(x)
			var four_pi_x := x * (PI * 4.0)
			var piston := cos(four_pi_x)
			var ign := 0.0
			if x > 0.0 and x < 0.5 * ign_time:
				ign = sin(PI * 2.0 * (x / ign_time))

			block += piston * pulse_amp * 0.55 + ign * ign_amp

			# Intake valve 0..0.25
			if x < 0.25:
				var iv := sin(four_pi_x)
				intake_sum += _intake_lp * iv

			# Exhaust valve 0.75..1 — ignition pops into pipe (not continuous whir).
			if x > 0.75:
				var ev := absf(-sin(four_pi_x))
				exhaust_excite += (ign * ign_amp + piston * pulse_amp * 0.15) * ev

		_revolution += inv_sr * rpm_c / 120.0 * feel_fast
		if _revolution >= 1.0:
			_revolution -= floorf(_revolution)

		_bu_phase += f_bu * inv_sr
		if _bu_phase >= 1.0:
			_bu_phase -= floorf(_bu_phase)
		_bu2_phase += f_bu2 * inv_sr
		if _bu2_phase >= 1.0:
			_bu2_phase -= floorf(_bu2_phase)

		var bu_wave := sin(_bu_phase * TAU)
		var am := 1.0 - am_depth + am_depth * (0.5 + 0.5 * bu_wave)

		# I4: lean toward half-order.
		if pair_amt > 0.001:
			var half := sin(_revolution * PI * 2.0)
			exhaust_excite *= lerpf(1.0, 0.45 + 0.55 * absf(half), pair_amt)
			block *= lerpf(1.0, 0.7 + 0.3 * absf(half), pair_amt * 0.65)

		# Shared exhaust pipe delay (circ buffer).
		var pr := _pipe[(_pipe_i - pipe_delay) & PIPE_MASK]
		var pipe_v := exhaust_excite + pr * pipe_fb
		_pipe[_pipe_i] = pipe_v
		_pipe_i = (_pipe_i + 1) & PIPE_MASK

		# Parallel muffler chambers (short).
		var mr := _muff[(_muff_i - muff_delay) & MUFF_MASK]
		var muff_v := pipe_v * 0.55 + mr * muff_fb
		_muff[_muff_i] = muff_v
		_muff_i = (_muff_i + 1) & MUFF_MASK

		var mr2 := _muff2[(_muff2_i - muff2_delay) & MUFF_MASK]
		var muff2_v := pipe_v * 0.45 + mr2 * (muff_fb * 0.85)
		_muff2[_muff2_i] = muff2_v
		_muff2_i = (_muff2_i + 1) & MUFF_MASK

		var outlet := (muff_v + muff2_v) * 0.5
		if straight:
			outlet = lerpf(outlet, pipe_v, 0.55)

		_block_lp += block_a * (block - _block_lp)
		_pipe_lp += pipe_a * (outlet - _pipe_lp)

		var raw := bu_wave * bu_amp * bu_mix
		raw += sin(_bu2_phase * TAU) * bu_amp * 0.18 * bu_mix
		raw += _block_lp * block_mix + _pipe_lp * pipe_mix + intake_sum * intake_mix * intake_amp
		raw += _pipe_lp * rpm_t * rpm_t * load_a * lerpf(0.02, 0.06, 1.0 - street_t)
		raw *= am
		_sub_lp += sub_a * (raw - _sub_lp)
		var timed := raw - _sub_lp * sub_trim
		_chest_lp += chest_a * (timed - _chest_lp)
		var sample := timed + _chest_lp * (0.18 + thump_t * 0.28) * (0.75 if muffler else 1.0)

		if has_forced and _turbo_spool > 0.01:
			var tw := lerpf(2200.0, 5200.0, _turbo_spool)
			_turbo_phase += tw * inv_sr
			if _turbo_phase >= 1.0:
				_turbo_phase -= floorf(_turbo_phase)
			sample += sin(_turbo_phase * TAU) * 0.028 * _turbo_spool

		sample *= lerpf(0.75, 1.0, load_a * 0.55 + 0.45)
		sample *= gain
		var pre_tanh := sample
		sample = tanh(sample * 0.9)
		_meter_tick(sample, pre_tanh)
		playback.push_frame(Vector2(sample, sample))


func _next_noise() -> float:
	_noise_seed = (_noise_seed * 48271) % 2147483647
	if _noise_seed <= 0:
		_noise_seed += 2147483646
	return (float(_noise_seed) / 1073741823.5) - 1.0
