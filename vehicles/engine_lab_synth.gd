class_name EngineLabSynth
extends RefCounted

## Port of engine-sound-lab (pulse @ 10 kHz → synth chain + FI + IR) for offline bake.
## API mirrors EngineWaveguideSynth: configure_from_setup + render_mono.

const SPEED_OF_SOUND := 343.0
const SIM_RATE := 10000.0

var sample_rate: float = 22050.0
var rpm: float = 800.0
var throttle: float = 0.5

# Mapped knobs
var _cyl_n: int = 4
var _angles: PackedFloat32Array = PackedFloat32Array()
var _bank_side: PackedFloat32Array = PackedFloat32Array()
var _disp_l: float = 2.0
var _power_hp: float = 150.0
var _pipe_m: float = 1.2
var _bank_deg: float = 0.0
var _ex_mm: float = 55.0
var _evo_deg: float = 110.0
var _open_deg: float = 230.0
var _size_t: float = 0.4
var _flow_gain: float = 1.0
var _runner_tau: float = 0.01
var _chamber_bleed: float = 0.5
var _residual_tau: float = 0.01
var _liters_per_cyl: float = 0.5

var _hf_gain: float = 0.01
var _air_noise: float = 0.5
var _jitter: float = 0.3
var _conv_mix: float = 1.0
var _noise_cut: float = 1500.0
var _low_shelf_g: float = 1.0
var _low_shelf_hz: float = 180.0
var _mid_punch: float = 1.0
var _vol_db: float = 0.0

var _has_turbo: bool = false
var _has_sc: bool = false
var _turbo_lvl: float = 0.2
var _sc_lvl: float = 0.14
var _spool_lag: float = 0.5

# Pulse state
var _crank_deg: float = 0.0
var _p_chamber: PackedFloat32Array = PackedFloat32Array()
var _p_runner: PackedFloat32Array = PackedFloat32Array()
var _burning: PackedFloat32Array = PackedFloat32Array()
var _delay_bufs: Array = []
var _delay_idx: PackedInt32Array = PackedInt32Array()
var _sim_phase: float = 0.0
var _last_sim: float = 0.0
var _aa_y: float = 0.0
var _aa_y2: float = 0.0

# Chain state
var _prev_in: float = 0.0
var _dc_y: float = 0.0
var _n_y: float = 0.0
var _n_y2: float = 0.0
var _aa_out_y: float = 0.0
var _aa_out_y2: float = 0.0
var _lo_y: float = 0.0
var _mid_lp: float = 0.0
var _mid_hp: float = 0.0
var _level: float = 1.0
var _noise_seed: int = 2463534242
var _ir: PackedFloat32Array = PackedFloat32Array()
var _conv_hist: PackedFloat32Array = PackedFloat32Array()
var _conv_pos: int = 0

# FI state
var _spool: float = 0.0
var _phase_t: float = 0.0
var _phase_sc: float = 0.0
var _prev_thr: float = 0.0
var _wg_env: float = 0.0


static func displacement_size_t(disp_l: float) -> float:
	var d := clampf(disp_l, 0.5, 10.0)
	if d <= 1.0:
		return (d - 0.5) / 0.5 * 0.05
	if d <= 3.0:
		return 0.05 + (d - 1.0) / 2.0 * 0.65
	if d <= 6.0:
		return 0.70 + (d - 3.0) / 3.0 * 0.14
	return 0.84 + minf((d - 6.0) / 2.0, 1.0) * 0.16


func configure_from_setup(setup: Resource) -> void:
	sample_rate = 22050.0
	_cyl_n = clampi(int(setup.get("cylinder_count")), 2, 12)
	_disp_l = clampf(float(setup.get("displacement_liters")), 0.5, 12.0)
	_power_hp = clampf(float(setup.get("max_power_hp")), 40.0, 900.0)
	_ex_mm = clampf(float(setup.get("exhaust_diameter_mm")), 30.0, 120.0)
	_has_turbo = bool(setup.get("has_turbo"))
	_has_sc = bool(setup.get("has_supercharger"))
	var muffler := bool(setup.get("has_muffler"))
	var resonators := clampi(int(setup.get("resonator_count")), 0, 3)
	_vol_db = float(setup.get("engine_sound_volume_db"))

	# Layout heuristic (CarSetup has no layout yet).
	var layout := "inline"
	if _cyl_n >= 8:
		layout = "v"
	elif _cyl_n == 6 and _disp_l >= 3.0:
		layout = "v"
	_set_firing(layout, _cyl_n)

	var style := "muffler"
	if not muffler:
		style = "straight"
	elif resonators >= 2:
		style = "resonator"

	_size_t = displacement_size_t(_disp_l)
	_map_knobs(style, resonators, layout)
	_build_delays()
	_build_ir(style, resonators)
	reset()


func _set_firing(layout: String, cyl: int) -> void:
	# Even-fire tables (720° cycle).
	_angles = PackedFloat32Array()
	_bank_side = PackedFloat32Array()
	var step := 720.0 / float(cyl)
	for i in cyl:
		_angles.append(float(i) * step)
		if layout == "v" or layout == "boxer":
			_bank_side.append(-1.0 if (i % 2) == 0 else 1.0)
		else:
			_bank_side.append(0.0)
	_cyl_n = cyl


func _map_knobs(style: String, resonators: int, layout: String) -> void:
	var pipe := 1.4
	var conv := 1.0
	var noise := 0.85
	var noise_cut := 1500.0
	var evo := 115.0
	var open_w := 230.0
	if style == "straight":
		pipe = 0.9
		conv = 0.88
		noise = 0.55
		noise_cut = 1600.0
		evo = 105.0
		open_w = 200.0
	elif style == "resonator":
		pipe = 1.2
		conv = 1.0
		noise = 0.75
		noise_cut = 1700.0
		evo = 110.0
		open_w = 220.0

	var d_norm := (_ex_mm - 40.0) / 50.0
	noise_cut = clampf(noise_cut + 400.0 * d_norm, 900.0, 2400.0)
	var hf := clampf(0.012 + 0.015 * maxf(d_norm, 0.0), 0.008, 0.05)
	var density := float(_cyl_n) / 4.0
	var jitter := 0.4
	if layout == "v":
		noise *= clampf(1.15 / density, 0.35, 0.85)
		noise_cut *= 0.85
		hf = clampf(hf + 0.015, 0.01, 0.06)
		open_w = clampf(open_w - 25.0 * (density - 1.0), 140.0, open_w)
		jitter = 0.28
		_bank_deg = 90.0
	else:
		_bank_deg = 0.0

	var t := _size_t
	_low_shelf_g = lerpf(0.08, 5.4, t)
	_mid_punch = lerpf(0.12, 3.5, t)
	_low_shelf_hz = lerpf(420.0, 85.0, t)
	noise_cut = lerpf(9800.0, 680.0, t) * (noise_cut / 1500.0)
	noise_cut = clampf(noise_cut, 550.0, 12000.0)
	noise = clampf(lerpf(1.0, 0.08, t) * noise, 0.06, 1.0)
	hf = clampf(lerpf(0.42, 0.002, t), 0.002, 0.55)
	open_w = lerpf(72.0, 295.0, t)
	evo = lerpf(78.0, 132.0, t)
	pipe = lerpf(0.28, 2.15, t) * (pipe / 1.2)
	jitter = clampf(lerpf(0.95, 0.12, t) * (jitter / 0.4), 0.10, 1.0)
	var ir_stretch := lerpf(0.18, 2.60, t)
	conv = clampf(lerpf(0.42, 1.0, t) * conv, 0.35, 1.0)

	var res_mix := clampf(float(resonators) / 2.0, 0.0, 1.0)
	if resonators > 0:
		pipe += 0.08 * res_mix
		noise_cut *= 1.0 - 0.1 * res_mix

	_pipe_m = clampf(pipe, 0.4, 2.4)
	_evo_deg = evo
	_open_deg = open_w
	_hf_gain = hf
	_air_noise = noise
	_jitter = jitter
	_conv_mix = conv
	_noise_cut = noise_cut
	_ir_stretch = ir_stretch

	var d_flow := clampf(_ex_mm / 70.0, 0.4, 1.8)
	_flow_gain = 0.65 + 0.55 * d_flow
	_liters_per_cyl = maxf(_disp_l, 0.2) / float(_cyl_n)
	_runner_tau = (0.0006 + 0.022 * t) / d_flow
	_chamber_bleed = 0.78 - 0.55 * t
	_residual_tau = 0.0009 + 0.036 * t

	_turbo_lvl = (0.18 + 0.04 * (_power_hp / 300.0)) * lerpf(1.55, 0.28, t)
	_sc_lvl = 0.14 * lerpf(1.25, 0.45, t)
	_spool_lag = 0.5 if _has_turbo else 0.2


var _ir_stretch: float = 1.0


func _build_delays() -> void:
	_delay_bufs.clear()
	_delay_idx = PackedInt32Array()
	_delay_idx.resize(_cyl_n)
	var base_delay := _pipe_m / SPEED_OF_SOUND
	for c in _cyl_n:
		var side := _bank_side[c] if c < _bank_side.size() else 0.0
		var scale := 1.0 + 0.12 * side * (_bank_deg / 90.0)
		var d_s := maxf(0.0005, base_delay * scale)
		var n := maxi(2, int(d_s * SIM_RATE))
		var buf := PackedFloat32Array()
		buf.resize(n)
		buf.fill(0.0)
		_delay_bufs.append(buf)
		_delay_idx[c] = 0


func _build_ir(style: String, resonators: int) -> void:
	# Synthetic IRs (same idea as ir_bank.synthesize_ir), scaled to sample_rate.
	var sr := sample_rate
	var rng := 1337
	var n: int
	var ir := PackedFloat32Array()
	if style == "straight":
		n = mini(5000, int(0.12 * sr))
		ir.resize(n)
		for i in n:
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var noise := (float(rng) / 1073741823.5) - 1.0
			var t := float(i) / sr
			var env := exp(-6.91 * t / 0.11)
			var early := 2.2 if i < int(0.002 * sr) else 1.0
			ir[i] = (noise * env * early + 0.25 * sin(TAU * 110.0 * t) * exp(-14.0 * t)) * 0.35
	elif style == "resonator":
		n = mini(5000, int(0.18 * sr))
		ir.resize(n)
		var soft := 0.0
		var a := 1.0 - exp(-TAU * 3500.0 / sr)
		for i in n:
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var noise := (float(rng) / 1073741823.5) - 1.0
			soft += a * (noise - soft)
			var t := float(i) / sr
			var ring := (
				sin(TAU * 145.0 * t) * exp(-6.0 * t)
				+ 0.7 * sin(TAU * 290.0 * t) * exp(-11.0 * t)
				+ 0.4 * sin(TAU * 435.0 * t) * exp(-16.0 * t)
			)
			ir[i] = (0.4 * soft + 0.75 * ring) * exp(-6.91 * t / 0.16)
	else:
		n = mini(5000, int(0.22 * sr))
		ir.resize(n)
		var soft := 0.0
		var a := 1.0 - exp(-TAU * 2800.0 / sr)
		for i in n:
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var noise := (float(rng) / 1073741823.5) - 1.0
			soft += a * (noise - soft)
			var t := float(i) / sr
			var body := (
				0.55 * sin(TAU * 95.0 * t) * exp(-8.0 * t)
				+ 0.35 * sin(TAU * 160.0 * t) * exp(-10.0 * t)
				+ 0.25 * sin(TAU * 240.0 * t) * exp(-14.0 * t)
			)
			ir[i] = (0.65 * soft + 0.35 * body) * exp(-6.91 * t / 0.20)

	# Resonate blend for muffler + resonators
	if style == "muffler" and resonators > 0:
		var m := clampf(float(resonators) / 2.0, 0.0, 1.0) * 0.5
		for i in ir.size():
			var t := float(i) / sr
			var ring := sin(TAU * 145.0 * t) * exp(-6.0 * t)
			ir[i] = (1.0 - m) * ir[i] + m * ring

	# Displacement stretch
	var stretch := _ir_stretch
	if absf(stretch - 1.0) > 0.05 and ir.size() > 16:
		var new_len := clampi(int(round(float(ir.size()) * stretch)), 64, 5000)
		var stretched := PackedFloat32Array()
		stretched.resize(new_len)
		for i in new_len:
			var u := float(i) / float(maxi(new_len - 1, 1))
			var src := u * float(ir.size() - 1)
			var i0 := int(src)
			var i1 := mini(i0 + 1, ir.size() - 1)
			var f := src - float(i0)
			stretched[i] = lerpf(ir[i0], ir[i1], f)
		ir = stretched

	var peak := 0.0
	for i in ir.size():
		peak = maxf(peak, absf(ir[i]))
	if peak > 1e-12:
		for i in ir.size():
			ir[i] /= peak
	_ir = ir
	_conv_hist.resize(maxi(_ir.size(), 1))
	_conv_hist.fill(0.0)
	_conv_pos = 0


func reset() -> void:
	_crank_deg = 0.0
	_p_chamber = PackedFloat32Array()
	_p_runner = PackedFloat32Array()
	_burning = PackedFloat32Array()
	_p_chamber.resize(_cyl_n)
	_p_runner.resize(_cyl_n)
	_burning.resize(_cyl_n)
	_p_chamber.fill(0.0)
	_p_runner.fill(0.0)
	_burning.fill(0.0)
	for c in _delay_bufs.size():
		(_delay_bufs[c] as PackedFloat32Array).fill(0.0)
		if c < _delay_idx.size():
			_delay_idx[c] = 0
	_sim_phase = 0.0
	_last_sim = 0.0
	_aa_y = 0.0
	_aa_y2 = 0.0
	_prev_in = 0.0
	_dc_y = 0.0
	_n_y = 0.0
	_n_y2 = 0.0
	_aa_out_y = 0.0
	_aa_out_y2 = 0.0
	_lo_y = 0.0
	_mid_lp = 0.0
	_mid_hp = 0.0
	_level = 1.0
	_conv_hist.fill(0.0)
	_conv_pos = 0
	_spool = 0.0
	_phase_t = 0.0
	_phase_sc = 0.0
	_prev_thr = 0.0
	_wg_env = 0.0


func _noise() -> float:
	_noise_seed = (_noise_seed * 48271) % 2147483647
	if _noise_seed <= 0:
		_noise_seed += 2147483646
	return (float(_noise_seed) / 1073741823.5) - 1.0


func _lp1(state: float, x: float, hz: float) -> float:
	var a := 1.0 - exp(-TAU * hz / sample_rate)
	return state + a * (x - state)


func _sim_step(load: float) -> float:
	if rpm <= 1.0:
		return 0.0
	var dt := 1.0 / SIM_RATE
	var omega := rpm * (TAU / 60.0)
	var att := minf(absf(omega), 40.0) / 40.0
	var att3 := att * att * att
	var dens := sqrt(maxf(_disp_l, 0.1) / 2.0)
	var pow_s := sqrt(maxf(_power_hp, 1.0) / 150.0)
	var size_t := _size_t
	var vol_amp := 0.45 + 2.4 * size_t
	var peak_p := (0.25 + 1.5 * load) * dens * vol_amp * pow_s
	var dump_gain := 1.0 + 2.2 * size_t
	var deg_per := (rpm / 60.0) * 360.0 * dt
	_crank_deg = fmod(_crank_deg + deg_per, 720.0)
	if _crank_deg < 0.0:
		_crank_deg += 720.0
	var runner_a := 1.0 - exp(-dt / maxf(_runner_tau, 1e-4))
	var burn_decay := exp(-dt / 0.0035)
	var staging := 0.0
	var evo := _evo_deg
	var open_w := _open_deg

	for c in _cyl_n:
		var fire := _angles[c]
		var a := fmod(_crank_deg - fire, 720.0)
		if a < 0.0:
			a += 720.0
		if a < deg_per:
			_burning[c] = 1.0
			_p_chamber[c] = peak_p
		if _burning[c] > 0.01 and a < evo:
			_p_chamber[c] = (
				peak_p
				* (0.55 + 0.45 * sin(minf(a, 40.0) / 40.0 * PI * 0.5))
				* (0.75 + 0.25 * _burning[c])
			)
			_burning[c] *= burn_decay
		elif a >= evo:
			_burning[c] *= burn_decay

		var lift := 0.0
		if a >= evo and a < evo + open_w:
			var x := (a - evo) / open_w
			var s := sin(PI * x)
			lift = s * s

		if lift > 1e-4:
			var flow := lift * _p_chamber[c] * _flow_gain
			_p_runner[c] += runner_a * (flow * dump_gain - _p_runner[c])
			_p_chamber[c] *= 1.0 - _chamber_bleed * lift * runner_a
		else:
			_p_runner[c] *= exp(-dt / _residual_tau)
			_p_chamber[c] *= exp(-dt / (0.04 + 0.03 * _liters_per_cyl))

		var runner_env := _p_runner[c]
		var pedestal := 0.02 + 0.22 * size_t
		var shaped := runner_env * runner_env / (absf(runner_env) + pedestal)
		var dyn := shaped * omega * (0.02 - 0.012 * size_t)
		var pulse := att3 * 1600.0 * (shaped + 0.08 * dyn)

		var buf: PackedFloat32Array = _delay_bufs[c]
		var idx := _delay_idx[c]
		var delayed := buf[idx]
		buf[idx] = pulse
		_delay_bufs[c] = buf
		_delay_idx[c] = (idx + 1) % buf.size()
		var side := _bank_side[c] if c < _bank_side.size() else 0.0
		var bank_scale := 1.0 + 0.03 * side * (_bank_deg / 90.0)
		staging += delayed * bank_scale

	var inv_l2 := 1.0 / maxf(_pipe_m * _pipe_m, 0.25)
	return staging * inv_l2 / float(maxi(_cyl_n, 1))


func _pulse_audio(n: int, load: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	if rpm <= 1.0:
		out.fill(0.0)
		return out
	var ratio := SIM_RATE / sample_rate
	var phase := _sim_phase
	var a := _last_sim
	var b := _last_sim
	if phase <= 1e-12:
		b = _sim_step(load)
		phase = 0.0
	# AA ~1.9 kHz (2× one-pole)
	var aa_hz := minf(1900.0, sample_rate * 0.4)
	for i in n:
		phase += ratio
		while phase >= 1.0:
			a = b
			b = _sim_step(load)
			phase -= 1.0
		var s := a * (1.0 - phase) + b * phase
		_aa_y = _lp1(_aa_y, s, aa_hz)
		_aa_y2 = _lp1(_aa_y2, _aa_y, aa_hz)
		out[i] = _aa_y2
	_sim_phase = phase
	_last_sim = b
	return out


func _convolve_tap(x: float) -> float:
	if _ir.is_empty() or _conv_mix < 1e-6:
		return x
	_conv_hist[_conv_pos] = x
	var acc := 0.0
	var m := _ir.size()
	var pos := _conv_pos
	# Decimate IR taps for bake speed.
	var step := 1
	if m > 600:
		step = 3
	elif m > 300:
		step = 2
	for k in range(0, m, step):
		acc += _ir[k] * _conv_hist[(pos - k + m) % m]
	_conv_pos = (_conv_pos + 1) % m
	return lerpf(x, acc * float(step) * 0.85, _conv_mix)


func _chain_sample(dry: float) -> float:
	# Light AM jitter (stand-in for delay jitter).
	var jit_n := _noise()
	var f_in := dry * (1.0 + _jitter * 0.08 * jit_n)
	_dc_y = _lp1(_dc_y, f_in, 10.0)
	var f := f_in - _dc_y
	var f_p := (f_in - _prev_in) * sample_rate
	_prev_in = f_in
	var nw := _noise()
	_n_y = _lp1(_n_y, nw, _noise_cut)
	_n_y2 = _lp1(_n_y2, _n_y, _noise_cut)
	var r_mixed := _air_noise * _n_y2 + (1.0 - _air_noise)
	var dmix := _hf_gain
	var v_in := f_p * dmix + f * r_mixed * (1.0 - dmix)
	var v := _convolve_tap(v_in)
	_aa_out_y = _lp1(_aa_out_y, v, sample_rate * 0.45)
	_aa_out_y2 = _lp1(_aa_out_y2, _aa_out_y, sample_rate * 0.45)
	v = _aa_out_y2
	_lo_y = _lp1(_lo_y, v, _low_shelf_hz)
	_mid_lp = _lp1(_mid_lp, v, 420.0)
	_mid_hp = _lp1(_mid_hp, v, 80.0)
	var mid := _mid_lp - _mid_hp
	v = v + (_low_shelf_g - 1.0) * _lo_y + (_mid_punch - 1.0) * mid
	return v


func _fi_sample(load: float) -> float:
	if not _has_turbo and not _has_sc:
		_prev_thr = throttle
		return 0.0
	var dt := 1.0 / sample_rate
	var target := 0.0
	if _has_turbo:
		target = clampf((rpm - 1500.0) / 4500.0, 0.0, 1.0) * clampf(load, 0.0, 1.0)
		target *= clampf(throttle, 0.0, 1.0)
	if _has_turbo and throttle < _prev_thr - 0.08 and _spool > 0.45:
		_wg_env = 1.0
	_prev_thr = throttle
	var alpha := 1.0 - exp(-dt / maxf(_spool_lag, 0.05))
	_spool += (target - _spool) * alpha
	var s := 0.0
	if _has_turbo and _spool > 0.01:
		var freq := 2800.0 + 8200.0 * _spool
		_phase_t += TAU * freq * dt
		if _phase_t > 1e6:
			_phase_t = fmod(_phase_t, TAU)
		s += _turbo_lvl * _spool * (0.75 * sin(_phase_t) + 0.25 * _noise())
	if _wg_env > 1e-4:
		_wg_env *= exp(-dt * 8.0)
		s += _wg_env * 0.55 * absf(_noise()) * sin(TAU * (900.0 + 4000.0 * _wg_env) * dt)
	if _has_sc:
		var sc_amt := clampf(rpm / 6500.0, 0.0, 1.0) * clampf(throttle, 0.15, 1.0)
		var freq_sc := 900.0 + rpm * 0.55
		_phase_sc += TAU * freq_sc * dt
		if _phase_sc > 1e6:
			_phase_sc = fmod(_phase_sc, TAU)
		var gear := sin(_phase_sc) + 0.35 * sin(2.0 * _phase_sc)
		s += _sc_lvl * sc_amt * gear * 0.5
	return s


func render_mono(frame_count: int, _pulse_scale: float = 1.0, _ign_scale: float = 1.0) -> PackedFloat32Array:
	var load := clampf(throttle, 0.0, 1.0)
	var dry := _pulse_audio(frame_count, load)
	var out := PackedFloat32Array()
	out.resize(frame_count)
	var vol := db_to_linear(_vol_db)
	# Running RMS for soft leveling (engine-sim style).
	var acc := 0.0
	for i in frame_count:
		var colored := _chain_sample(dry[i])
		var fi := _fi_sample(load)
		var mix := colored + 0.55 * fi
		acc += mix * mix
		var rms := sqrt(acc / float(i + 1) + 1e-12)
		var desired := clampf(0.20 / maxf(rms, 1e-6), 0.08, 10.0)
		_level = 0.992 * _level + 0.008 * desired
		mix = tanh(mix * _level * 0.65) * vol
		out[i] = tanh(mix)
	return out
