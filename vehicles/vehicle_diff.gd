extends RefCounted

## Axle torque split helpers. Front axle is always open.
## rear_diff_type: 0=open, 1=LSD, 2=welded
## drive_type: 0=FWD, 1=RWD, 2=AWD


static func split_open(total_torque: float) -> Vector2:
	var half: float = total_torque * 0.5
	return Vector2(half, half)


static func split_lsd(
	total_torque: float,
	omega_left: float,
	omega_right: float,
	preload_torque: float,
	power_lock: float,
	coast_lock: float
) -> Vector2:
	var half: float = total_torque * 0.5
	var avg_omega: float = (omega_left + omega_right) * 0.5
	var is_power: bool = total_torque * avg_omega >= 0.0
	var lock_ratio: float = power_lock
	if not is_power:
		lock_ratio = coast_lock
	var delta_w: float = omega_left - omega_right
	var t_lock: float = (preload_torque + absf(total_torque) * lock_ratio) * signf(delta_w)
	var max_transfer: float = absf(half) + preload_torque
	t_lock = clampf(t_lock, -max_transfer, max_transfer)
	return Vector2(half - t_lock * 0.5, half + t_lock * 0.5)


static func split_welded(
	total_torque: float,
	omega_left: float,
	omega_right: float,
	stiffness: float
) -> Vector2:
	var half: float = total_torque * 0.5
	var delta_w: float = omega_left - omega_right
	var k: float = maxf(stiffness, 50.0)
	var max_eq: float = absf(total_torque) + k * 40.0
	var t_eq: float = clampf(delta_w * k, -max_eq, max_eq)
	return Vector2(half - t_eq * 0.5, half + t_eq * 0.5)


static func split_rear(
	total_torque: float,
	omega_left: float,
	omega_right: float,
	diff_type: int,
	preload_torque: float,
	power_lock: float,
	coast_lock: float,
	locked_stiffness: float
) -> Vector2:
	if diff_type == 0:
		return split_open(total_torque)
	if diff_type == 2:
		return split_welded(total_torque, omega_left, omega_right, locked_stiffness)
	return split_lsd(
		total_torque,
		omega_left,
		omega_right,
		preload_torque,
		power_lock,
		coast_lock
	)


static func split_driveline(
	driveline_torque: float,
	drive_type: int,
	front_bias: float,
	fl: float,
	fr: float,
	rl: float,
	rr: float,
	rear_diff_type: int,
	preload_torque: float,
	power_lock: float,
	coast_lock: float,
	locked_stiffness: float
) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(4)
	out[0] = 0.0
	out[1] = 0.0
	out[2] = 0.0
	out[3] = 0.0

	if drive_type == 0:
		var front: Vector2 = split_open(driveline_torque)
		out[0] = front.x
		out[1] = front.y
	elif drive_type == 1:
		var rear: Vector2 = split_rear(
			driveline_torque,
			rl,
			rr,
			rear_diff_type,
			preload_torque,
			power_lock,
			coast_lock,
			locked_stiffness
		)
		out[2] = rear.x
		out[3] = rear.y
	elif drive_type == 2:
		var bias: float = clampf(front_bias, 0.0, 1.0)
		var front_awd: Vector2 = split_open(driveline_torque * bias)
		var rear_awd: Vector2 = split_rear(
			driveline_torque * (1.0 - bias),
			rl,
			rr,
			rear_diff_type,
			preload_torque,
			power_lock,
			coast_lock,
			locked_stiffness
		)
		out[0] = front_awd.x
		out[1] = front_awd.y
		out[2] = rear_awd.x
		out[3] = rear_awd.y

	return out
