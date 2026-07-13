class_name CarSetup
extends Resource

## Drive layout for distributing engine torque to wheels.
enum DriveType { FWD, RWD, AWD }
## Rear axle only. Front axle is always open.
## Values: 0=open, 1=LSD, 2=welded (same as vehicle_diff.gd).
enum RearDiffType { OPEN, LSD, WELDED }

@export_group("Body")
@export var mass: float = 1200.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.32, 0.06)

@export_group("Engine")
## Peak engine power in kilowatts (at ~80% of max_rpm on the torque curve).
@export var max_power_kw: float = 180.0
@export var idle_rpm: float = 800.0
@export var max_rpm: float = 7000.0
## Multiplier on top of the physical torque model.
@export var torque_boost: float = 1.25
## Crankshaft inertia (kg·m²) for clutch / free-rev integration.
@export var engine_inertia: float = 0.25
## X = RPM (0..1 normalized against max_rpm), Y = torque multiplier (0..1+).
@export var torque_curve: Curve

@export_group("Drivetrain")
## Forward gear ratios, index 0 = 1st gear.
@export var gear_ratios: Array[float] = [3.67, 2.10, 1.36, 1.00, 0.82]
@export var reverse_ratio: float = 3.53
@export var final_drive: float = 3.9
@export var drive_type: DriveType = DriveType.RWD
@export var shift_time: float = 0.15
## Max clutch friction torque (N·m) at the crank when fully engaged.
@export var clutch_max_torque: float = 1000.0
@export var clutch_engage_time: float = 0.28
## AWD only: fraction of driveline torque to the front axle.
@export_range(0.0, 1.0) var awd_front_bias: float = 0.4
## Rear differential: open / LSD / welded lock. Front is always open.
@export var rear_diff_type: RearDiffType = RearDiffType.LSD
## LSD only: constant locking bias (N·m).
@export var diff_preload: float = 80.0
## LSD only: lock fraction under power / coast.
@export_range(0.0, 1.0) var diff_power_lock: float = 0.35
@export_range(0.0, 1.0) var diff_coast_lock: float = 0.15
## WELDED (заварка): equalizing stiffness (N·m per rad/s of wheel-speed diff).
@export var locked_diff_stiffness: float = 800.0

@export_group("Wheels")
@export var wheel_radius: float = 0.22
@export var wheel_width: float = 0.22
@export var wheel_inertia: float = 1.2
## Local attachment points relative to the car body origin.
## Convention: [FL, FR, RL, RR] — first two steer, drive depends on drive_type.
@export var wheel_positions: Array[Vector3] = [
	Vector3(-0.75, 0.0, 1.25),
	Vector3(0.75, 0.0, 1.25),
	Vector3(-0.75, 0.0, -1.25),
	Vector3(0.75, 0.0, -1.25),
]

@export_group("Suspension Front")
@export var front_rest_length: float = 0.4
@export var front_travel: float = 0.2
@export var front_stiffness: float = 35000.0
@export var front_damping_compression: float = 3500.0
@export var front_damping_rebound: float = 4200.0
@export var front_anti_roll: float = 5600.0

@export_group("Suspension Rear")
@export var rear_rest_length: float = 0.4
@export var rear_travel: float = 0.2
@export var rear_stiffness: float = 35000.0
@export var rear_damping_compression: float = 3500.0
@export var rear_damping_rebound: float = 4200.0
@export var rear_anti_roll: float = 2600.0

@export_group("Suspension Legacy")
## Kept for old .tres / cfg migration. Prefer front_/rear_ fields.
@export var rest_length: float = 0.4
@export var travel: float = 0.2
@export var stiffness: float = 35000.0
@export var damping: float = 3500.0
@export var anti_roll: float = 5000.0

@export_group("Tires")
@export var tire_mu_front: float = 1.7
@export var tire_mu_rear: float = 1.95
@export var tire_v_low: float = 0.5
@export var pacejka_b_long: float = 10.0
@export var pacejka_c_long: float = 1.55
@export var pacejka_e_long: float = 0.2
@export var pacejka_b_lat: float = 5.5
@export var pacejka_c_lat: float = 1.2
@export var pacejka_e_lat: float = 0.25
@export var rolling_resistance: float = 0.015
## Soft minimum normal load as fraction of static weight per wheel.
@export_range(0.0, 0.25) var min_load_fraction: float = 0.06

@export_group("Tires Legacy")
@export var grip_longitudinal: float = 1.2
@export var grip_lateral: float = 1.1
@export var grip_lateral_rear: float = 3.5

@export_group("Brakes")
@export var brake_force: float = 12000.0
@export var handbrake_force: float = 22000.0
## Rear lateral grip while handbrake is fully held (0 = ice, 1 = no cut).
## Scales with handbrake input: lat *= lerp(1, this, hb).
@export_range(0.0, 1.0) var handbrake_lat_grip: float = 0.15
## Fraction of service brake torque on the front axle.
@export_range(0.0, 1.0) var brake_bias_front: float = 0.65

@export_group("Aero")
@export var drag_coefficient: float = 0.32
@export var downforce_coefficient: float = 0.45
@export var frontal_area: float = 2.1
@export var air_density: float = 1.225

@export_group("Steering")
## Absolute max road-wheel steer angle at standstill (degrees).
@export var max_steer_angle: float = 32.0
## How fast the wheels follow the input target (rad/s at low speed).
@export var steer_speed: float = 2.8
## Speed (km/h) where steer_angle_curve X = 1.
@export var steer_curve_max_kmh: float = 140.0
## X = speed / steer_curve_max_kmh (0..1), Y = fraction of max_steer_angle (0..1).
@export var steer_angle_curve: Curve
## Legacy fallbacks if curve is missing (migrated into default curve).
@export var steer_speed_ref: float = 14.0
@export_range(0.2, 1.0) var steer_high_speed_factor: float = 0.55

@export_group("Simulation")
@export_range(1, 8) var physics_substeps: int = 4
## Limit drive torque when slip ratio exceeds target (stops past-peak wheelspin).
@export var traction_control: bool = true
## Target |κ| under power. Higher = more launch wheelspin allowed.
@export_range(0.05, 0.45) var tc_slip_ratio: float = 0.2
## How hard TC cuts torque per unit of excess slip.
@export_range(0.5, 12.0) var tc_gain: float = 2.5
## Never cut driven-wheel torque below this fraction (0 = can kill all drive).
@export_range(0.0, 1.0) var tc_min_scale: float = 0.35


func migrate_legacy_fields() -> void:
	## Copy legacy single-axle suspension / grip into sim fields when they look unused.
	var legacy_suspension := (
		is_equal_approx(front_stiffness, 35000.0)
		and is_equal_approx(rear_stiffness, 35000.0)
		and not is_equal_approx(stiffness, 35000.0)
	)
	if legacy_suspension or (
		is_equal_approx(front_rest_length, 0.4)
		and not is_equal_approx(rest_length, 0.4)
	):
		front_rest_length = rest_length
		rear_rest_length = rest_length
		front_travel = travel
		rear_travel = travel
		front_stiffness = stiffness
		rear_stiffness = stiffness
		front_damping_compression = damping
		rear_damping_compression = damping
		front_damping_rebound = damping * 1.2
		rear_damping_rebound = damping * 1.2
		front_anti_roll = anti_roll
		rear_anti_roll = anti_roll

	# Old arcade grip numbers were ~1.1–3.5; map into mu if still at defaults.
	if is_equal_approx(tire_mu_front, 1.55) and grip_longitudinal > 1.3:
		tire_mu_front = clampf(grip_lateral * 0.72, 0.8, 2.4)
		tire_mu_rear = clampf(grip_lateral_rear * 0.45, 0.8, 2.4)

	ensure_clutch_capacity()


func ensure_clutch_capacity() -> void:
	## Clutch must exceed peak engine torque or it never locks and RPM sits on the limiter.
	var peak := get_peak_torque_nm()
	var need := peak * 1.35
	if clutch_max_torque < need:
		clutch_max_torque = need


func is_front_wheel(index: int) -> bool:
	return index < 2


func get_rest_length(index: int) -> float:
	return front_rest_length if is_front_wheel(index) else rear_rest_length


func get_travel(index: int) -> float:
	return front_travel if is_front_wheel(index) else rear_travel


func get_stiffness(index: int) -> float:
	return front_stiffness if is_front_wheel(index) else rear_stiffness


func get_damping(index: int, compression_speed: float) -> float:
	## compression_speed > 0 means mounting point moving up (spring extending / rebound).
	if is_front_wheel(index):
		return front_damping_rebound if compression_speed > 0.0 else front_damping_compression
	return rear_damping_rebound if compression_speed > 0.0 else rear_damping_compression


func get_anti_roll(axle_front: bool) -> float:
	return front_anti_roll if axle_front else rear_anti_roll


func get_tire_mu(index: int) -> float:
	return tire_mu_front if is_front_wheel(index) else tire_mu_rear


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
	torque_curve.add_point(Vector2(0.0, 0.62))
	torque_curve.add_point(Vector2(0.2, 0.88))
	torque_curve.add_point(Vector2(0.45, 1.0))
	torque_curve.add_point(Vector2(0.7, 0.98))
	torque_curve.add_point(Vector2(0.88, 0.9))
	torque_curve.add_point(Vector2(1.0, 0.78))


func ensure_steer_angle_curve() -> void:
	if steer_angle_curve != null and steer_angle_curve.get_point_count() > 0:
		return
	steer_angle_curve = Curve.new()
	# Stronger high-speed cut: ~40% at 50 km/h, ~25% at 70 if max=140.
	steer_angle_curve.add_point(Vector2(0.0, 1.0))
	steer_angle_curve.add_point(Vector2(0.2, 0.68))
	steer_angle_curve.add_point(Vector2(0.36, 0.40))
	steer_angle_curve.add_point(Vector2(0.5, 0.28))
	steer_angle_curve.add_point(Vector2(0.75, 0.18))
	steer_angle_curve.add_point(Vector2(1.0, 0.14))


func sample_steer_lock_factor(speed_ms: float) -> float:
	ensure_steer_angle_curve()
	var max_ms := maxf(steer_curve_max_kmh, 1.0) / 3.6
	var t := clampf(speed_ms / max_ms, 0.0, 1.0)
	return clampf(steer_angle_curve.sample(t), 0.15, 1.0)


func sample_torque_multiplier(rpm: float) -> float:
	ensure_torque_curve()
	var t := 0.0
	if max_rpm > 0.0:
		t = clampf(rpm / max_rpm, 0.0, 1.0)
	return maxf(torque_curve.sample(t), 0.0)


func get_peak_torque_nm() -> float:
	var power_rpm := max_rpm * 0.8
	var omega := power_rpm * TAU / 60.0
	var curve_at_power := sample_torque_multiplier(power_rpm)
	var torque_at_rated_power := (max_power_kw * 1000.0 * torque_boost) / maxf(omega, 1.0)
	return torque_at_rated_power / maxf(curve_at_power, 0.25)


func get_engine_torque(rpm: float) -> float:
	return get_peak_torque_nm() * sample_torque_multiplier(maxf(rpm, idle_rpm * 0.5))


func get_engine_power_kw(rpm: float) -> float:
	var torque := get_engine_torque(rpm)
	var omega := maxf(rpm, idle_rpm) * TAU / 60.0
	return torque * omega / 1000.0
