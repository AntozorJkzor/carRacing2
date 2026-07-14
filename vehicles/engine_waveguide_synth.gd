class_name EngineWaveguideSynth
extends RefCounted

## Baldan-style waveguide engine (offline bake only).
## Tuned away from harsh intake hiss / “fart pops” — darker, softer combustion.

const SAMPLE_RATE := 22050.0
const SR_SCALE := SAMPLE_RATE / 44100.0

var rpm: float = 800.0
var throttle: float = 0.5
var _revolution: float = 0.0
var _noise_seed: int = 2463534242
var _intake_lp: float = 0.0
var _crank_lp: float = 0.0
var _block_lp: float = 0.0
var _outlet_lp: float = 0.0
var _dc_lp: float = 0.0

var _cylinders: Array = []
var _straight: _Wg
var _outlet: _Wg
var _muffler: Array = []
var _cyl_inv: float = 0.25
var _mix_block: float = 0.35
var _mix_intake: float = 0.08
var _mix_outlet: float = 0.55
var _gain: float = 0.35
var _has_muffler: bool = true
var _intake_noise_cut: float = 1800.0
var _outlet_cut: float = 2200.0
var _block_cut: float = 110.0
var _pulse_mul: float = 1.0
var _ign_mul: float = 1.0
var _dc_kill: float = 0.65 # lower = more sub thump left (big displacement)
var _rasp_cut: float = 2600.0 # final de-rasp shelf
var _rasp_lp: float = 0.0
var _intake_noise_amt: float = 0.75
var _idle_rpm: float = 800.0
var _max_rpm: float = 7000.0
var _has_turbo: bool = false
var _has_supercharger: bool = false
var _turbo_whistle: float = 0.0
var _sc_whine: float = 0.0
var _power_mul: float = 1.0
var _size_t: float = 0.4
var _res_t: float = 0.0
var _boost_lp: float = 0.0
var _whistle_hp: float = 0.0
var _buzz_lp: float = 0.0


class _Delay extends RefCounted:
	var data: PackedFloat32Array = PackedFloat32Array()
	var index: int = 0

	func _init(length: int = 1) -> void:
		data.resize(maxi(length, 1))
		data.fill(0.0)

	func update_left(v: float) -> void:
		data[index] = v
		index += 1
		if index >= data.size():
			index = 0

	func update_right(v: float) -> void:
		data[index] = v
		index -= 1
		if index < 0:
			index = data.size() - 1

	func get0() -> float:
		return data[index]


class _Wg extends RefCounted:
	var upper: _Delay
	var lower: _Delay
	var refl_l: float = 0.0
	var refl_r: float = 0.0
	var out_l: float = 0.0
	var out_r: float = 0.0

	func _init(length: int = 1, rl: float = 0.0, rr: float = 0.0) -> void:
		upper = _Delay.new(length)
		lower = _Delay.new(length)
		refl_l = rl
		refl_r = rr

	func add(v_l: float, v_r: float) -> void:
		var ll := lower.get0()
		var uu := upper.get0()
		out_l = ll * (1.0 - refl_l)
		out_r = uu * (1.0 - refl_r)
		upper.update_right(v_l + ll * refl_l)
		lower.update_left(v_r + uu * refl_r)


class _Cyl extends RefCounted:
	var cyl: _Wg
	var intake: _Wg
	var exhaust: _Wg
	var extractor: _Wg
	var in_open: float
	var in_closed: float
	var ex_open: float
	var ex_closed: float
	var ign_t: float
	var intake_v: float = 0.0
	var exhaust_v: float = 0.0

	func _init(
		intake_len: int = 50,
		exhaust_len: int = 50,
		extractor_len: int = 50,
		cyl_len: int = 5,
		in_o: float = 0.01,
		in_c: float = 0.95,
		ex_o: float = 0.01,
		ex_c: float = 0.95,
		ign: float = 0.022
	) -> void:
		cyl = _Wg.new(maxi(cyl_len, 2), 0.7, 0.7)
		intake = _Wg.new(intake_len, 0.01, in_o)
		exhaust = _Wg.new(exhaust_len, ex_c, 0.01)
		extractor = _Wg.new(extractor_len, 0.01, 0.01)
		in_open = in_o
		in_closed = in_c
		ex_open = ex_o
		ex_closed = ex_c
		ign_t = ign

	func _set_refl() -> void:
		var iv := intake_v
		var ev := exhaust_v
		intake.refl_r = in_open * iv + in_closed * (1.0 - iv)
		cyl.refl_l = in_open * iv + in_closed * (1.0 - iv)
		exhaust.refl_l = ex_open * ev + ex_closed * (1.0 - ev)
		cyl.refl_r = ex_open * ev + ex_closed * (1.0 - ev)

	## Soft raised-cosine valve windows (less lisp / click).
	func _soft_window(x: float, a: float, b: float) -> float:
		if x <= a or x >= b:
			return 0.0
		var t := (x - a) / maxf(b - a, 1e-4)
		return 0.5 - 0.5 * cos(t * TAU * 0.5) # 0→1→0 smooth half-cos

	func tick(intake_noise: float, straight_l: float, x: float, pulse_s: float, ign_s: float) -> void:
		exhaust_v = _soft_window(x, 0.72, 0.98)
		intake_v = _soft_window(x, 0.02, 0.24)
		var piston := cos(4.0 * PI * x)
		# Softer combustion bloom (was sharp sin puff → “пердёж”).
		var ign := 0.0
		var ign_span := maxf(ign_t, 0.02)
		if x > 0.0 and x < ign_span:
			var u := x / ign_span
			ign = sin(PI * u) # half-sine pulse, no hard edges
			ign *= ign # rounder attack
		_set_refl()
		var gated := intake_noise * intake_v * 0.18
		# Rounder body, less saw-edge (chainsaw harmonics).
		var amp := piston * 0.7 * pulse_s + ign * 1.35 * ign_s
		amp = tanh(amp * 0.65)
		var ex_l := extractor.out_l
		var c_l := cyl.out_l
		var c_r := cyl.out_r
		var i_r := intake.out_r
		extractor.add(exhaust.out_r, straight_l)
		exhaust.add(c_r, ex_l)
		cyl.add(amp + i_r * (1.0 - intake.refl_r), ex_l * (1.0 - exhaust.refl_l))
		intake.add(gated, c_l * (1.0 - intake.refl_r))


func configure_from_setup(setup: Resource) -> void:
	var cyl_n := clampi(int(setup.get("cylinder_count")), 2, 12)
	var stroke := clampf(float(setup.get("piston_stroke_mm")), 50.0, 120.0)
	var exhaust_mm := clampf(float(setup.get("exhaust_diameter_mm")), 30.0, 120.0)
	var disp := clampf(float(setup.get("displacement_liters")), 0.5, 12.0)
	var stroke_t := clampf(inverse_lerp(65.0, 100.0, stroke), 0.0, 1.0)
	var dia_t := clampf((exhaust_mm - 30.0) / 90.0, 0.0, 1.0)
	var size_t := clampf((disp - 0.5) / 5.5, 0.0, 1.0)
	var per_cyl := disp / float(cyl_n)
	var per_t := clampf((per_cyl - 0.2) / 0.9, 0.0, 1.0)
	var muffler := bool(setup.get("has_muffler"))
	var resonator_count := clampi(int(setup.get("resonator_count")), 0, 3)
	var res_t := float(resonator_count) / 3.0
	var vol_db := float(setup.get("engine_sound_volume_db"))
	var hp := clampf(float(setup.get("max_power_hp")), 40.0, 900.0)
	var hp_t := clampf((hp - 70.0) / 330.0, 0.0, 1.0) # ~70→400 hp
	var specific := hp / maxf(disp, 0.5) # hp per litre
	var sp_t := clampf((specific - 35.0) / 130.0, 0.0, 1.0) # stock→hot
	_has_muffler = muffler
	_has_turbo = bool(setup.get("has_turbo"))
	_has_supercharger = bool(setup.get("has_supercharger"))
	_size_t = size_t
	_res_t = res_t
	# From CarSetup / Settings — not hardwired bake defaults.
	_idle_rpm = maxf(float(setup.get("idle_rpm")), 400.0)
	_max_rpm = maxf(float(setup.get("max_rpm")), _idle_rpm + 500.0)

	var dia_len := lerpf(1.45, 0.55, dia_t)
	var stroke_len := lerpf(0.88, 1.18, stroke_t)
	var size_len := lerpf(0.9, 1.2, size_t)
	var len_scale := dia_len * stroke_len * size_len

	var intake_len := _len(lerpf(70.0, 130.0, size_t), len_scale)
	if _has_turbo or _has_supercharger:
		intake_len = maxi(int(round(float(intake_len) * lerpf(1.12, 1.22, float(_has_turbo)))), 2)
	var exhaust_len := _len(lerpf(160.0, 65.0, dia_t), size_len)
	var extractor_len := _len(lerpf(130.0, 70.0, dia_t), size_len)
	var pipe_len := _len(lerpf(220.0, 85.0, dia_t), size_len)
	# Resonators lengthen a little — not enough to turn redline into a drone pipe.
	pipe_len = maxi(int(round(float(pipe_len) * lerpf(1.0, 1.12, res_t))), 2)
	var outlet_len := _len(lerpf(18.0, 3.0, dia_t), 1.0)
	var cyl_chamber := maxi(int(round(lerpf(3.0, 11.0, per_t))), 2)

	var ex_open := lerpf(0.003, 0.032, dia_t)
	var pipe_refl := lerpf(0.05, 0.008, dia_t)
	var outlet_refl := lerpf(0.06, 0.01, dia_t)
	if muffler:
		ex_open *= 0.28
		pipe_refl = lerpf(pipe_refl, 0.014, 0.55)
		outlet_refl = lerpf(outlet_refl, 0.012, 0.55)
	ex_open *= lerpf(1.0, 0.7, res_t)
	pipe_refl = lerpf(pipe_refl, 0.022, res_t)
	var action := lerpf(0.07, 0.035, dia_t) if muffler else lerpf(0.035, 0.015, dia_t)
	action = lerpf(action, action * 0.55, res_t)
	var ign_t := lerpf(0.024, 0.05, lerpf(stroke_t, per_t, 0.55))
	ign_t *= lerpf(1.08, 0.82, sp_t)

	_cylinders.clear()
	for _i in cyl_n:
		_cylinders.append(_Cyl.new(
			intake_len, exhaust_len, extractor_len, cyl_chamber,
			0.01, 0.92, ex_open, 0.92, ign_t
		))
	_cyl_inv = 1.0 / float(cyl_n)
	_straight = _Wg.new(pipe_len, pipe_refl, pipe_refl)
	_outlet = _Wg.new(outlet_len, outlet_refl, outlet_refl)

	var bases: Array[float] = [10.0, 14.0, 19.0, 26.0, 34.0]
	var n_el := 1
	if muffler:
		n_el = clampi(resonator_count + 1, 1, 4)
	elif resonator_count > 0:
		n_el = clampi(resonator_count, 1, 3)
	_muffler.clear()
	for e in n_el:
		var base_i := mini(e, bases.size() - 1)
		_muffler.append(_Wg.new(
			_len(bases[base_i] * lerpf(1.25, 0.75, dia_t) * lerpf(1.0, 1.1, res_t), size_len),
			0.0,
			action
		))

	_pulse_mul = lerpf(0.5, 1.55, per_t) * lerpf(0.85, 1.15, size_t)
	_ign_mul = lerpf(0.65, 1.35, per_t)
	_pulse_mul *= lerpf(0.88, 1.18, hp_t) * lerpf(0.95, 1.12, sp_t)
	_ign_mul *= lerpf(0.9, 1.22, hp_t) * lerpf(0.92, 1.18, sp_t)
	_power_mul = lerpf(0.9, 1.05, hp_t)

	_block_cut = lerpf(210.0, 60.0, size_t)
	_block_cut = lerpf(_block_cut, maxf(_block_cut, 150.0), 1.0 - size_t)
	_block_cut = lerpf(_block_cut, _block_cut * 1.2, sp_t)
	_dc_kill = lerpf(0.78, 0.4, size_t)
	# Small muffled fours: lean on pulsed exhaust, not block boom.
	_mix_block = lerpf(0.12, 0.48, size_t) * lerpf(1.0, 0.85, hp_t)
	_mix_intake = (0.015 if muffler else lerpf(0.03, 0.08, size_t)) * lerpf(1.05, 0.7, dia_t)
	_mix_outlet = lerpf(0.48, 0.78, size_t) * lerpf(0.85, 1.12, dia_t)
	_mix_outlet *= lerpf(1.05, 0.9, res_t)
	_mix_outlet *= lerpf(0.95, 1.1, hp_t)

	_intake_noise_amt = 0.32 if muffler else 0.65
	_intake_noise_cut = lerpf(800.0, 1400.0, dia_t) if muffler else lerpf(1300.0, 2600.0, dia_t)
	_outlet_cut = lerpf(900.0, 2800.0, pow(dia_t, 0.75))
	_outlet_cut *= lerpf(1.15, 0.95, size_t)
	if muffler:
		_outlet_cut *= lerpf(0.7, 0.88, dia_t)
	_outlet_cut *= lerpf(1.0, 0.88, res_t)
	_outlet_cut *= lerpf(0.95, 1.08, sp_t)
	_rasp_cut = lerpf(2100.0, 2800.0, dia_t)
	if muffler:
		_rasp_cut *= 0.88
	_rasp_cut *= lerpf(1.0, 0.9, res_t)
	# Small NA: a bit clearer, but not chainsaw-bright.
	if muffler and size_t < 0.4 and not _has_turbo and not _has_supercharger:
		_ign_mul *= 1.06
		_pulse_mul *= 1.04
		_outlet_cut *= 1.06
		_mix_block *= 0.9
		_mix_outlet *= 1.05

	_turbo_whistle = 0.0
	_sc_whine = 0.0
	if _has_turbo:
		_turbo_whistle = 0.1
		_mix_intake *= 1.05
		_intake_noise_cut = maxf(_intake_noise_cut, 1500.0)
		_outlet_cut *= lerpf(0.95, 1.05, sp_t)
		_pulse_mul *= 1.04
		_ign_mul *= 1.06
	if _has_supercharger:
		_sc_whine = 0.16
		_mix_intake *= 1.18
		_intake_noise_amt *= 1.1
		_intake_noise_cut = maxf(_intake_noise_cut, 1700.0)
		_ign_mul *= 1.04

	_gain = db_to_linear(vol_db) * lerpf(0.24, 0.38, size_t) * lerpf(0.85, 1.05, dia_t)
	_gain *= lerpf(0.95, 1.04, hp_t)
	if not muffler:
		_gain *= 1.1
	_gain *= lerpf(1.0, 0.92, res_t)

	reset()


func reset() -> void:
	_revolution = 0.0
	_intake_lp = 0.0
	_crank_lp = 0.0
	_block_lp = 0.0
	_outlet_lp = 0.0
	_dc_lp = 0.0
	_rasp_lp = 0.0
	_boost_lp = 0.0
	_whistle_hp = 0.0
	_buzz_lp = 0.0


func _len(base_44k: float, scale: float) -> int:
	return maxi(int(round(base_44k * SR_SCALE * scale)), 2)


func _noise() -> float:
	_noise_seed = (_noise_seed * 48271) % 2147483647
	if _noise_seed <= 0:
		_noise_seed += 2147483646
	return (float(_noise_seed) / 1073741823.5) - 1.0


func _lp(state: float, x: float, hz: float) -> float:
	var a := 1.0 - exp(-TAU * hz / SAMPLE_RATE)
	return state + a * (x - state)


func _muff_sum_l() -> float:
	var s := 0.0
	for m in _muffler:
		s += (m as _Wg).out_l
	return s


func _muff_sum_r() -> float:
	var s := 0.0
	for m in _muffler:
		s += (m as _Wg).out_r
	return s


func render_mono(frame_count: int, pulse_scale: float = 1.0, ign_scale: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frame_count)
	var inv_sr := 1.0 / SAMPLE_RATE
	var muff_inv := 1.0 / float(maxi(_muffler.size(), 1))
	var load_a := clampf(throttle, 0.0, 1.0)
	var rpm_t := clampf(inverse_lerp(_idle_rpm, _max_rpm, rpm), 0.0, 1.0)
	var work_t := pow(rpm_t, 0.5)
	var top_t := pow(rpm_t, 1.05)
	var small := 1.0 - _size_t
	# Mild climb — hard pulse×top was reading as chainsaw / drone.
	pulse_scale *= lerpf(0.58, 1.05, load_a) * _pulse_mul * lerpf(0.85, 1.08, work_t)
	ign_scale *= lerpf(0.45, 1.0, load_a) * _ign_mul * lerpf(0.7, 1.1, work_t)
	# Keep some mid body on top (not pure buzz outlet).
	var mix_block_s := lerpf(1.15, lerpf(0.55, 0.7, _size_t), top_t)
	var mix_intake_s := lerpf(0.75, lerpf(0.4, 0.55, _size_t), top_t)
	var mix_outlet_s := lerpf(0.6, lerpf(1.2, 1.1, _size_t), top_t)
	# Cap brightness — 1.6+ was piercer / UAV buzz.
	var outlet_cut_s := lerpf(0.82, lerpf(1.12, 1.05, _size_t), top_t)
	# Stronger de-buzz shelf near redline.
	var rasp_blend := lerpf(0.62, lerpf(0.58, 0.52, _size_t), top_t)
	var intake_amt := _intake_noise_amt * lerpf(0.7, 0.45, top_t) * lerpf(0.7, 1.0, load_a)
	intake_amt *= lerpf(1.0, 0.8, _res_t)
	var crank_jit := lerpf(0.12, 0.025, work_t)

	var turbo_t := 0.0
	if _has_turbo:
		turbo_t = pow(work_t, 1.4) * load_a
		mix_outlet_s *= lerpf(1.0, 1.05, turbo_t)
		pulse_scale *= lerpf(1.0, 1.05, turbo_t)
	var sc_t := 0.0
	if _has_supercharger:
		sc_t = lerpf(0.3, 0.85, work_t) * load_a
		mix_intake_s *= lerpf(1.0, 1.15, sc_t)
		ign_scale *= lerpf(1.0, 1.04, sc_t)

	for i in frame_count:
		var n := _noise()
		_intake_lp = _lp(_intake_lp, n, _intake_noise_cut)
		var intake_noise := _intake_lp * intake_amt
		if _has_turbo and turbo_t > 0.01:
			_boost_lp = _lp(_boost_lp, n, 1500.0)
			_whistle_hp = _lp(_whistle_hp, n - _boost_lp, 2600.0)
			intake_noise += _whistle_hp * _turbo_whistle * turbo_t
		if _has_supercharger and sc_t > 0.01:
			intake_noise += _intake_lp * _sc_whine * sc_t
		if rpm < 25.0:
			intake_noise = 0.0
		_crank_lp = _lp(_crank_lp, crank_jit * n, 40.0)

		var block := 0.0
		var intake_sum := 0.0
		var straight_in := 0.0
		var muff_l := _muff_sum_l()

		for ci in _cylinders.size():
			var c: _Cyl = _cylinders[ci]
			var x := _revolution + float(ci) * (_cyl_inv + _crank_lp)
			x -= floorf(x)
			c.tick(intake_noise, _straight.out_l, x, pulse_scale, ign_scale)
			block += c.cyl.out_l
			intake_sum += c.intake.out_l
			straight_in += c.extractor.out_r

		_revolution += inv_sr * rpm / 120.0
		if _revolution >= 1.0:
			_revolution -= floorf(_revolution)

		_straight.add(straight_in, muff_l)
		_outlet.add(_muff_sum_r(), 0.0)
		var min_in := _straight.out_r * muff_inv
		var mout := _outlet.out_l * muff_inv
		for m2 in _muffler:
			(m2 as _Wg).add(min_in, mout)

		_block_lp = _lp(_block_lp, block, _block_cut)
		_outlet_lp = _lp(_outlet_lp, _outlet.out_r, _outlet_cut * outlet_cut_s)
		var sample := (
			_block_lp * _mix_block * mix_block_s
			+ intake_sum * _mix_intake * mix_intake_s
			+ _outlet_lp * _mix_outlet * mix_outlet_s
		)
		_dc_lp = _lp(_dc_lp, sample, 30.0)
		sample -= _dc_lp * lerpf(_dc_kill, minf(_dc_kill + 0.1, 0.85), top_t)
		_rasp_lp = _lp(_rasp_lp, sample, _rasp_cut)
		sample = lerpf(sample, _rasp_lp, rasp_blend)
		# Extra anti-buzz one-pole near top (kills UAV / chainsaw hiss).
		_buzz_lp = _lp(_buzz_lp, sample, lerpf(4200.0, 2600.0, top_t))
		sample = lerpf(sample, _buzz_lp, lerpf(0.15, 0.45, top_t))
		var drive := lerpf(0.58, 0.72, load_a) * lerpf(0.95, 0.88, small * top_t)
		sample *= _gain * _power_mul * lerpf(0.72, 1.0, load_a) * lerpf(0.94, 1.02, work_t)
		sample = tanh(sample * drive)
		out[i] = sample

	return out
