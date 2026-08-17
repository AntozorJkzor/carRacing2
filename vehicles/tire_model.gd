extends RefCounted

## Simplified Pacejka Magic Formula + combined-slip friction ellipse.


static func magic_formula(x: float, b: float, c: float, d: float, e: float) -> float:
	var bx: float = b * x
	return d * sin(c * atan(bx - e * (bx - atan(bx))))


static func compute_slip(
	long_speed: float,
	lat_speed: float,
	wheel_omega: float,
	radius: float,
	v_low: float
) -> Vector2:
	var v_ref: float = maxf(absf(long_speed), v_low)
	var kappa: float = (wheel_omega * radius - long_speed) / v_ref
	# Clamp extreme kappa at near-zero speed so combined grip does not collapse.
	kappa = clampf(kappa, -3.0, 3.0)
	var alpha: float = atan2(lat_speed, v_ref)
	return Vector2(kappa, alpha)


static func evaluate(
	kappa: float,
	alpha: float,
	fz: float,
	mu: float,
	b_long: float,
	c_long: float,
	e_long: float,
	b_lat: float,
	c_lat: float,
	e_lat: float
) -> Vector2:
	var load: float = maxf(fz, 0.0)
	if load < 1.0:
		return Vector2.ZERO

	## Mild load sensitivity: peak force grows sub-linearly with Fz so weight
	## transfer under throttle doesn't give an unrealistically sticky axle.
	const FZ_REF := 3200.0
	const LOAD_SENS := 0.18
	var load_scale: float = 1.0 - LOAD_SENS * (load / FZ_REF - 1.0)
	load_scale = clampf(load_scale, 0.72, 1.12)
	var d_long: float = mu * load * load_scale
	var d_lat: float = mu * load * load_scale

	var fx_pure: float = magic_formula(kappa, b_long, c_long, d_long, e_long)
	var fy_pure: float = -magic_formula(alpha, b_lat, c_lat, d_lat, e_lat)

	# Isotropic friction ellipse — both axes share the mu budget.
	var gx: float = absf(fx_pure) / maxf(d_long, 1.0)
	var gy: float = absf(fy_pure) / maxf(d_lat, 1.0)
	var g: float = sqrt(gx * gx + gy * gy)
	if g > 1.0:
		var inv: float = 1.0 / g
		fx_pure *= inv
		fy_pure *= inv

	# Excess longitudinal slip softens cornering, but keep enough Fy to steer
	# out of a slide. Old 0.65*κ→floor 0.12 made any RWD spin an instant donut.
	var excess_kappa: float = maxf(absf(kappa) - 0.2, 0.0)
	var kappa_lat_scale: float = clampf(1.0 - excess_kappa * 0.35, 0.4, 1.0)
	fy_pure *= kappa_lat_scale

	return Vector2(fx_pure, fy_pure)
