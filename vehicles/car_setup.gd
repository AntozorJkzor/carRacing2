class_name CarSetup
extends Resource

## Mechanical HP → kW (same factor as legacy get_power_hp).
const KW_PER_HP := 0.7457

## Drive layout for distributing engine torque to wheels.
enum DriveType { FWD, RWD, AWD }
## Rear axle only. Front axle is always open.
## Values: 0=open, 1=LSD, 2=welded (same as vehicle_diff.gd).
enum RearDiffType { OPEN, LSD, WELDED }
## EngineSimBaker layout (matches GDExtension Layout enum).
enum EngineLayout { INLINE, V, BOXER }

@export_group("Body")
@export var mass: float = 1200.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.32, 0.06)

@export_group("Engine")
## Peak engine power in horsepower (at ~80% of max_rpm on the torque curve).
@export var max_power_hp: float = 241.0
## Legacy kW — kept for old .tres / cfg. Synced from max_power_hp in migrate.
@export var max_power_kw: float = 180.0
@export var idle_rpm: float = 800.0
@export var max_rpm: float = 7000.0
## Legacy unused — kept so old .tres / tuning cfg still load. Do not multiply power.
@export var torque_boost: float = 1.0
## Crankshaft inertia (kg·m²) for clutch / free-rev integration.
@export var engine_inertia: float = 0.25
## Spark cut above this × max_rpm (open throttle). Re-enable below rev_limiter_cut_low_frac.
@export_range(0.94, 1.0, 0.005) var rev_limiter_cut_high_frac: float = 0.98
@export_range(0.84, 0.97, 0.005) var rev_limiter_cut_low_frac: float = 0.91
## Extra RPM-dependent friction when throttle released (neutral / coast).
@export_range(0.5, 3.0, 0.05) var engine_coast_friction_scale: float = 1.65
## X = RPM (0..1 normalized against max_rpm), Y = torque multiplier (0..1+).
@export var torque_curve: Curve

@export_group("Engine Sound")
## Maps 1:1 to EngineSimBaker.apply_params (idle/max RPM taken from Engine group).
@export_range(2, 12, 1) var cylinders: int = 4
@export_range(500.0, 10000.0, 50.0) var displacement_cc: float = 2000.0
## 0 = auto from displacement + stroke.
@export_range(0.0, 120.0, 1.0) var bore_mm: float = 0.0
@export_range(50.0, 120.0, 1.0) var stroke_mm: float = 86.0
@export var engine_layout: EngineLayout = EngineLayout.INLINE
@export_range(0.0, 180.0, 1.0) var bank_angle_deg: float = 90.0
@export_range(2, 4, 2) var valves_per_cylinder: int = 2
@export_range(300.0, 900.0, 10.0) var exhaust_length_mm: float = 500.0
@export_range(180.0, 280.0, 1.0) var cam_duration_deg: float = 220.0
@export_range(6.0, 14.0, 0.1) var cam_lift_mm: float = 9.5
@export_range(0.0, 1.0, 0.01) var hf_gain: float = 0.01
@export_range(0.0, 2.0, 0.01) var noise: float = 1.0
@export_range(0.0, 1.0, 0.01) var jitter: float = 0.5
## Playback trim only (EngineAudio) — not sent to bake API.
@export_range(-24.0, 12.0, 0.1) var engine_sound_volume_db: float = 0.0

@export_group("Drivetrain")
## Forward gear ratios, index 0 = 1st gear.
@export var gear_ratios: Array[float] = [3.67, 2.10, 1.36, 1.00, 0.82]
@export var reverse_ratio: float = 3.53
@export var final_drive: float = 3.9
@export var drive_type: DriveType = DriveType.RWD
@export var shift_time: float = 0.15
## Max clutch friction torque (N·m) at the crank when fully engaged.
@export var clutch_max_torque: float = 1000.0
@export var clutch_engage_time: float = 0.12
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

@export_group("Wheels / Axles")
## Legacy single radius — synced from front when axles migrate; prefer per-axle radii.
@export var wheel_radius: float = 0.22
## Legacy single width — prefer front_/rear_wheel_width.
@export var wheel_width: float = 0.22
@export var wheel_inertia: float = 0.85
## Local mounts [FL, FR, RL, RR] — rebuilt from axle fields (keep for physics / old data).
@export var wheel_positions: Array[Vector3] = [
	Vector3(-0.75, 0.4, -1.25),
	Vector3(0.75, 0.4, -1.25),
	Vector3(-0.75, 0.4, 1.25),
	Vector3(0.75, 0.4, 1.25),
]

@export_subgroup("Front axle")
## Longitudinal mount (local Z). Negative = toward front (−Z forward).
@export var front_axle_z: float = -1.25
## Mount height (local Y).
@export var front_mount_y: float = 0.4
## Track width (full left↔right, meters).
@export var front_track: float = 1.5
@export var front_wheel_radius: float = 0.22
@export var front_wheel_width: float = 0.22
## Visual mesh scale for front tires.
@export var front_mesh_scale: float = 2.875

@export_subgroup("Rear axle")
@export var rear_axle_z: float = 1.25
@export var rear_mount_y: float = 0.4
@export var rear_track: float = 1.5
@export var rear_wheel_radius: float = 0.22
@export var rear_wheel_width: float = 0.22
@export var rear_mesh_scale: float = 2.875

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
## Rear grip — keep below front for RWD so launches can spin when TC is soft/off.
@export var tire_mu_rear: float = 1.55
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
## Cl-style plant force (world-down). Higher = less float at speed.
@export var downforce_coefficient: float = 0.95
@export var frontal_area: float = 2.1
@export var air_density: float = 1.225

@export_group("Steering")
## Absolute max road-wheel steer angle (degrees) — full lock at any speed (needed for counter-steer).
@export var max_steer_angle: float = 32.0
## How fast the road wheels follow the input target (rad/s).
@export var steer_speed: float = 2.4
## Legacy unused — kept so old .tres / tuning cfg still load.
@export var steer_curve_max_kmh: float = 140.0
@export var steer_angle_curve: Curve
@export var steer_speed_ref: float = 14.0
@export_range(0.2, 1.0) var steer_high_speed_factor: float = 1.0

@export_group("Throttle response")
## How fast throttle command rises toward pedal (1/s). Lower = softer throttle onset.
@export var throttle_rise_rate: float = 2.0
## How fast throttle command falls when lifting (1/s).
@export var throttle_fall_rate: float = 6.0

@export_group("Assist")
## Помощь дрифта: 0 = выкл (симулятор), 1 = норма, до 2 = сильнее держит угол / гасит спин.
@export_range(0.0, 2.0, 0.05) var drift_assist: float = 1.0

@export_group("Simulation")
@export_range(1, 8) var physics_substeps: int = 4
## When on, softens torque after high slip — leave off for stronger launch wheelspin.
@export var traction_control: bool = false
## Target |κ| under power. Higher = more launch wheelspin allowed.
@export_range(0.05, 0.55) var tc_slip_ratio: float = 0.35
## How hard TC cuts torque per unit of excess slip.
@export_range(0.5, 12.0) var tc_gain: float = 1.4
## Never cut driven-wheel torque below this fraction (0 = can kill all drive).
@export_range(0.0, 1.0) var tc_min_scale: float = 0.55


## Litres helper for legacy synth paths / UI display.
func get_displacement_liters() -> float:
	return displacement_cc * 0.001


func set_displacement_liters(liters: float) -> void:
	displacement_cc = clampf(liters, 0.5, 12.0) * 1000.0


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

	ensure_axle_layout()
	ensure_power_units()
	ensure_clutch_capacity()


func ensure_power_units() -> void:
	## Prefer horsepower as source of truth. Migrate old kW-only setups.
	if max_power_hp <= 1.0 and max_power_kw > 1.0:
		max_power_hp = max_power_kw / KW_PER_HP
	elif absf(max_power_hp * KW_PER_HP - max_power_kw) > 1.0:
		# Old .tres had only max_power_kw written; HP still at class default.
		# Prefer the kW value that physics used before.
		if max_power_kw > 1.0:
			max_power_hp = max_power_kw / KW_PER_HP
	max_power_kw = max_power_hp * KW_PER_HP


func get_max_power_kw() -> float:
	return max_power_hp * KW_PER_HP


func ensure_axle_layout() -> void:
	## Prefer explicit axle fields; if .tres only has corner mounts, derive axles once.
	if wheel_positions.size() >= 4:
		var from_axle := compute_wheel_positions_from_axles()
		var diverge := false
		for i in 4:
			if wheel_positions[i].distance_to(from_axle[i]) > 0.025:
				diverge = true
				break
		if diverge:
			derive_axles_from_wheel_positions()
	rebuild_wheel_positions()
	wheel_radius = front_wheel_radius
	wheel_width = front_wheel_width


func derive_axles_from_wheel_positions() -> void:
	if wheel_positions.size() < 4:
		return
	var fl: Vector3 = wheel_positions[0]
	var fr: Vector3 = wheel_positions[1]
	var rl: Vector3 = wheel_positions[2]
	var rr: Vector3 = wheel_positions[3]
	front_axle_z = (fl.z + fr.z) * 0.5
	front_mount_y = (fl.y + fr.y) * 0.5
	front_track = absf(fr.x - fl.x)
	rear_axle_z = (rl.z + rr.z) * 0.5
	rear_mount_y = (rl.y + rr.y) * 0.5
	rear_track = absf(rr.x - rl.x)
	if front_wheel_radius <= 0.01:
		front_wheel_radius = wheel_radius
	if rear_wheel_radius <= 0.01:
		rear_wheel_radius = wheel_radius
	if front_wheel_width <= 0.01:
		front_wheel_width = wheel_width
	if rear_wheel_width <= 0.01:
		rear_wheel_width = wheel_width


func compute_wheel_positions_from_axles() -> Array[Vector3]:
	var ft := maxf(front_track, 0.2) * 0.5
	var rt := maxf(rear_track, 0.2) * 0.5
	return [
		Vector3(-ft, front_mount_y, front_axle_z),
		Vector3(ft, front_mount_y, front_axle_z),
		Vector3(-rt, rear_mount_y, rear_axle_z),
		Vector3(rt, rear_mount_y, rear_axle_z),
	]


func rebuild_wheel_positions() -> void:
	wheel_positions = compute_wheel_positions_from_axles()


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
	## compression_speed > 0 means spring length increasing (extending / rebound).
	if is_front_wheel(index):
		return front_damping_rebound if compression_speed > 0.0 else front_damping_compression
	return rear_damping_rebound if compression_speed > 0.0 else rear_damping_compression


func get_anti_roll(axle_front: bool) -> float:
	return front_anti_roll if axle_front else rear_anti_roll


func get_tire_mu(index: int) -> float:
	return tire_mu_front if is_front_wheel(index) else tire_mu_rear


func get_wheel_radius(index: int) -> float:
	return front_wheel_radius if is_front_wheel(index) else rear_wheel_radius


func get_wheel_width(index: int) -> float:
	return front_wheel_width if is_front_wheel(index) else rear_wheel_width


func get_mesh_scale(index: int) -> float:
	return front_mesh_scale if is_front_wheel(index) else rear_mesh_scale


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


func sample_steer_lock_factor(_speed_ms: float) -> float:
	## Always full lock — limiting by speed blocks counter-steer in a slide.
	## Soft throttle response is used instead (see throttle_rise_rate).
	return 1.0


func sample_torque_multiplier(rpm: float) -> float:
	ensure_torque_curve()
	var t := 0.0
	if max_rpm > 0.0:
		t = clampf(rpm / max_rpm, 0.0, 1.0)
	return maxf(torque_curve.sample(t), 0.0)


func get_peak_torque_nm() -> float:
	## Peak torque from max_power_hp only (no hidden boosts).
	var power_rpm := max_rpm * 0.8
	var omega := power_rpm * TAU / 60.0
	var curve_at_power := sample_torque_multiplier(power_rpm)
	var power_w := max_power_hp * KW_PER_HP * 1000.0
	var torque_at_rated_power := power_w / maxf(omega, 1.0)
	return torque_at_rated_power / maxf(curve_at_power, 0.25)


func get_engine_torque(rpm: float) -> float:
	return get_peak_torque_nm() * sample_torque_multiplier(maxf(rpm, idle_rpm * 0.5))


func get_engine_power_kw(rpm: float) -> float:
	var torque := get_engine_torque(rpm)
	var omega := maxf(rpm, idle_rpm) * TAU / 60.0
	return torque * omega / 1000.0
