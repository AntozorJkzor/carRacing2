class_name CarSetup
extends Resource

## Drive layout for distributing engine torque to wheels.
enum DriveType { FWD, RWD, AWD }

@export_group("Body")
@export var mass: float = 1200.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.3, 0.0)

@export_group("Engine")
## Peak engine power in kilowatts (at ~80% of max_rpm on the torque curve).
@export var max_power_kw: float = 180.0
@export var idle_rpm: float = 800.0
@export var max_rpm: float = 7000.0
## Arcade multiplier on top of the physical torque model (drivetrain losses inverted).
@export var torque_boost: float = 1.65
## X = RPM (0..1 normalized against max_rpm), Y = torque multiplier (0..1+).
@export var torque_curve: Curve

@export_group("Drivetrain")
## Forward gear ratios, index 0 = 1st gear.
@export var gear_ratios: Array[float] = [3.67, 2.10, 1.36, 1.00, 0.82]
@export var reverse_ratio: float = 3.53
@export var final_drive: float = 3.9
@export var drive_type: DriveType = DriveType.RWD
@export var shift_time: float = 0.15

@export_group("Wheels")
@export var wheel_radius: float = 0.33
@export var wheel_width: float = 0.22
## Local attachment points relative to the car body origin.
## Convention: [FL, FR, RL, RR] — first two steer, drive depends on drive_type.
@export var wheel_positions: Array[Vector3] = [
	Vector3(-0.75, 0.0, 1.25),
	Vector3(0.75, 0.0, 1.25),
	Vector3(-0.75, 0.0, -1.25),
	Vector3(0.75, 0.0, -1.25),
]

@export_group("Suspension")
@export var rest_length: float = 0.4
@export var travel: float = 0.2
@export var stiffness: float = 35000.0
@export var damping: float = 3500.0
@export var anti_roll: float = 5000.0

@export_group("Tires")
@export var grip_longitudinal: float = 1.2
@export var grip_lateral: float = 1.1
## Extra lateral grip for the rear axle (non-steering wheels).
@export var grip_lateral_rear: float = 3.5
@export var rolling_resistance: float = 0.015
@export var brake_force: float = 12000.0
@export var handbrake_force: float = 22000.0
## How much rear lateral grip remains while handbrake/drift is active (0..1).
@export_range(0.0, 1.0) var handbrake_lat_grip: float = 0.12

@export_group("Steering")
@export var max_steer_angle: float = 32.0
@export var steer_speed: float = 5.0


func get_forward_gear_count() -> int:
	return gear_ratios.size()


func get_gear_ratio(gear: int) -> float:
	if gear == 0:
		return 0.0
	if gear < 0:
		return -reverse_ratio
	var index := gear - 1
	if index < 0 or index >= gear_ratios.size():
		return 0.0
	return gear_ratios[index]


func ensure_torque_curve() -> void:
	if torque_curve != null and torque_curve.get_point_count() > 0:
		return
	torque_curve = Curve.new()
	# Fat mid/high band so higher gears still pull hard toward redline.
	torque_curve.add_point(Vector2(0.0, 0.62))
	torque_curve.add_point(Vector2(0.2, 0.88))
	torque_curve.add_point(Vector2(0.45, 1.0))
	torque_curve.add_point(Vector2(0.7, 0.98))
	torque_curve.add_point(Vector2(0.88, 0.9))
	torque_curve.add_point(Vector2(1.0, 0.78))


func sample_torque_multiplier(rpm: float) -> float:
	ensure_torque_curve()
	var t := 0.0
	if max_rpm > 0.0:
		t = clampf(rpm / max_rpm, 0.0, 1.0)
	return maxf(torque_curve.sample(t), 0.0)


## Peak torque (N·m) corresponding to max_power_kw on the curve.
func get_peak_torque_nm() -> float:
	var power_rpm := max_rpm * 0.8
	var omega := power_rpm * TAU / 60.0
	var curve_at_power := sample_torque_multiplier(power_rpm)
	var torque_at_rated_power := (max_power_kw * 1000.0 * torque_boost) / maxf(omega, 1.0)
	return torque_at_rated_power / maxf(curve_at_power, 0.25)


## Engine crankshaft torque at RPM.
func get_engine_torque(rpm: float) -> float:
	# Correct model: T(rpm) = T_peak * curve — NOT (P_max / omega) * curve.
	# The old formula double-cut torque on the top end (1/omega and curve together),
	# so 3rd+ gears felt gutless before redline.
	return get_peak_torque_nm() * sample_torque_multiplier(maxf(rpm, idle_rpm * 0.5))


func get_engine_power_kw(rpm: float) -> float:
	var torque := get_engine_torque(rpm)
	var omega := maxf(rpm, idle_rpm) * TAU / 60.0
	return torque * omega / 1000.0
