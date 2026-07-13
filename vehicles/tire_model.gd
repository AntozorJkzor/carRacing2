extends RefCounted

## Simplified Pacejka Magic Formula + soft combined-slip scaling.


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

	# Slightly higher lateral peak helps turn-in without early snap oversteer.
	var d_long: float = mu * load
	var d_lat: float = mu * load * 1.08

	var fx_pure: float = magic_formula(kappa, b_long, c_long, d_long, e_long)
	var fy_pure: float = -magic_formula(alpha, b_lat, c_lat, d_lat, e_lat)

	# Soft friction ellipse. Prefer cutting longitudinal first under combined
	# load so a spinning drive axle keeps more cornering grip.
	var gx: float = absf(fx_pure) / maxf(d_long, 1.0)
	var gy: float = absf(fy_pure) / maxf(d_lat, 1.0)
	var g: float = sqrt(gx * gx + gy * gy)
	if g > 1.0:
		var inv: float = 1.0 / g
		fx_pure *= inv * inv
		fy_pure *= sqrt(inv)

	return Vector2(fx_pure, fy_pure)
