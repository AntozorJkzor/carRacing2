extends RefCounted

## Shared spin / slide / lockup intensity for smoke and skid marks.


static func intensity(
	car: Node,
	wheel: Wheel,
	spin_kappa: float,
	slide_angle_deg: float
) -> float:
	var amounts := slip_parts(car, wheel, spin_kappa, slide_angle_deg)
	var value := maxf(amounts.x, maxf(amounts.y, amounts.z))
	if value < 0.12:
		var throttle := float(car.get("throttle")) if car != null else 0.0
		var brake := float(car.get("brake")) if car != null else 0.0
		var handbrake := float(car.get("handbrake")) if car != null else 0.0
		var speed := _speed(car)
		if throttle < 0.08 and brake < 0.2 and handbrake < 0.15 and speed < 2.5:
			return 0.0
	return value


## x = spin (κ), y = slide (α), z = lockup (brake / handbrake).
static func slip_parts(
	car: Node,
	wheel: Wheel,
	spin_kappa: float,
	slide_angle_deg: float
) -> Vector3:
	if car == null or wheel == null or not wheel.on_ground:
		return Vector3.ZERO
	var k := absf(wheel.slip_ratio)
	var spin_i := 0.0
	var k0 := maxf(spin_kappa, 0.04)
	if k >= k0:
		spin_i = clampf((k - k0) / 0.45, 0.0, 1.0)
	var slide_i := 0.0
	var a_deg := absf(rad_to_deg(wheel.slip_angle))
	var a0 := maxf(slide_angle_deg, 4.0)
	if a_deg >= a0:
		slide_i = clampf((a_deg - a0) / 26.0, 0.0, 1.0)
	var speed := _speed(car)
	var brake := float(car.get("brake"))
	var handbrake := float(car.get("handbrake"))
	var lock_i := 0.0
	if speed > 3.0:
		if handbrake > 0.2 and not wheel.is_steering:
			lock_i = maxf(lock_i, clampf(handbrake, 0.0, 1.0))
		if brake > 0.5:
			var pedal := clampf((brake - 0.5) / 0.5, 0.0, 1.0)
			var slip_boost := clampf(k / 0.14, 0.4, 1.0)
			lock_i = maxf(lock_i, pedal * slip_boost)
	return Vector3(spin_i, slide_i, lock_i)


static func _speed(car: Node) -> float:
	if car == null:
		return 0.0
	if car.has_method("get_speed_ms"):
		return float(car.call("get_speed_ms"))
	var vel: Variant = car.get("linear_velocity")
	if vel is Vector3:
		return (vel as Vector3).length()
	return 0.0
