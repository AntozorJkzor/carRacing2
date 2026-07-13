extends Node

## Global car tuning. Loaded at startup, edited in Settings, applied to cars.
const SAVE_PATH := "user://car_tuning.cfg"
const BASE_SETUP_PATH := "res://assets/scenes/cars/car_setup.tres"

var setup: CarSetup
var model_y_offset: float = 0.28
var collision_y: float = 0.48
var suspension_mount_y: float = 0.42


func _ready() -> void:
	_reset_from_base()
	load_from_disk()


func _reset_from_base() -> void:
	var base := load(BASE_SETUP_PATH) as CarSetup
	if base:
		setup = base.duplicate(true) as CarSetup
	else:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	setup.ensure_steer_angle_curve()
	setup.migrate_legacy_fields()
	model_y_offset = 0.28
	collision_y = 0.48
	suspension_mount_y = 0.42
	if setup.wheel_positions.size() > 0:
		suspension_mount_y = setup.wheel_positions[0].y


func reset_to_defaults() -> void:
	_reset_from_base()
	save_to_disk()


func apply_mount_height() -> void:
	if setup == null:
		return
	for i in setup.wheel_positions.size():
		var p := setup.wheel_positions[i]
		p.y = suspension_mount_y
		setup.wheel_positions[i] = p


func save_to_disk() -> void:
	apply_mount_height()
	var cfg := ConfigFile.new()
	cfg.set_value("visual", "model_y_offset", model_y_offset)
	cfg.set_value("visual", "collision_y", collision_y)
	cfg.set_value("visual", "suspension_mount_y", suspension_mount_y)

	cfg.set_value("body", "mass", setup.mass)
	cfg.set_value("body", "com_x", setup.center_of_mass_offset.x)
	cfg.set_value("body", "com_y", setup.center_of_mass_offset.y)
	cfg.set_value("body", "com_z", setup.center_of_mass_offset.z)

	cfg.set_value("engine", "max_power_kw", setup.max_power_kw)
	cfg.set_value("engine", "idle_rpm", setup.idle_rpm)
	cfg.set_value("engine", "max_rpm", setup.max_rpm)
	cfg.set_value("engine", "torque_boost", setup.torque_boost)
	cfg.set_value("engine", "engine_inertia", setup.engine_inertia)

	cfg.set_value("drivetrain", "reverse_ratio", setup.reverse_ratio)
	cfg.set_value("drivetrain", "final_drive", setup.final_drive)
	cfg.set_value("drivetrain", "drive_type", int(setup.drive_type))
	cfg.set_value("drivetrain", "shift_time", setup.shift_time)
	cfg.set_value("drivetrain", "clutch_max_torque", setup.clutch_max_torque)
	cfg.set_value("drivetrain", "clutch_engage_time", setup.clutch_engage_time)
	cfg.set_value("drivetrain", "awd_front_bias", setup.awd_front_bias)
	cfg.set_value("drivetrain", "rear_diff_type", int(setup.rear_diff_type))
	cfg.set_value("drivetrain", "diff_preload", setup.diff_preload)
	cfg.set_value("drivetrain", "diff_power_lock", setup.diff_power_lock)
	cfg.set_value("drivetrain", "diff_coast_lock", setup.diff_coast_lock)
	cfg.set_value("drivetrain", "locked_diff_stiffness", setup.locked_diff_stiffness)
	for i in setup.gear_ratios.size():
		cfg.set_value("drivetrain", "gear_%d" % (i + 1), setup.gear_ratios[i])

	cfg.set_value("wheels", "wheel_radius", setup.wheel_radius)
	cfg.set_value("wheels", "wheel_width", setup.wheel_width)
	cfg.set_value("wheels", "wheel_inertia", setup.wheel_inertia)
	if setup.wheel_positions.size() >= 4:
		cfg.set_value("wheels", "track", absf(setup.wheel_positions[0].x))
		cfg.set_value("wheels", "front_z", setup.wheel_positions[0].z)
		cfg.set_value("wheels", "rear_z", setup.wheel_positions[2].z)

	cfg.set_value("suspension", "front_rest_length", setup.front_rest_length)
	cfg.set_value("suspension", "rear_rest_length", setup.rear_rest_length)
	cfg.set_value("suspension", "front_travel", setup.front_travel)
	cfg.set_value("suspension", "rear_travel", setup.rear_travel)
	cfg.set_value("suspension", "front_stiffness", setup.front_stiffness)
	cfg.set_value("suspension", "rear_stiffness", setup.rear_stiffness)
	cfg.set_value("suspension", "front_damping_compression", setup.front_damping_compression)
	cfg.set_value("suspension", "front_damping_rebound", setup.front_damping_rebound)
	cfg.set_value("suspension", "rear_damping_compression", setup.rear_damping_compression)
	cfg.set_value("suspension", "rear_damping_rebound", setup.rear_damping_rebound)
	cfg.set_value("suspension", "front_anti_roll", setup.front_anti_roll)
	cfg.set_value("suspension", "rear_anti_roll", setup.rear_anti_roll)
	# Legacy mirrors for older builds.
	cfg.set_value("suspension", "rest_length", setup.front_rest_length)
	cfg.set_value("suspension", "travel", setup.front_travel)
	cfg.set_value("suspension", "stiffness", setup.front_stiffness)
	cfg.set_value("suspension", "damping", setup.front_damping_compression)
	cfg.set_value("suspension", "anti_roll", setup.front_anti_roll)

	cfg.set_value("tires", "tire_mu_front", setup.tire_mu_front)
	cfg.set_value("tires", "tire_mu_rear", setup.tire_mu_rear)
	cfg.set_value("tires", "tire_v_low", setup.tire_v_low)
	cfg.set_value("tires", "pacejka_b_long", setup.pacejka_b_long)
	cfg.set_value("tires", "pacejka_c_long", setup.pacejka_c_long)
	cfg.set_value("tires", "pacejka_e_long", setup.pacejka_e_long)
	cfg.set_value("tires", "pacejka_b_lat", setup.pacejka_b_lat)
	cfg.set_value("tires", "pacejka_c_lat", setup.pacejka_c_lat)
	cfg.set_value("tires", "pacejka_e_lat", setup.pacejka_e_lat)
	cfg.set_value("tires", "rolling_resistance", setup.rolling_resistance)
	cfg.set_value("tires", "brake_force", setup.brake_force)
	cfg.set_value("tires", "handbrake_force", setup.handbrake_force)
	cfg.set_value("tires", "handbrake_lat_grip", setup.handbrake_lat_grip)
	cfg.set_value("tires", "brake_bias_front", setup.brake_bias_front)

	cfg.set_value("aero", "drag_coefficient", setup.drag_coefficient)
	cfg.set_value("aero", "downforce_coefficient", setup.downforce_coefficient)
	cfg.set_value("aero", "frontal_area", setup.frontal_area)

	cfg.set_value("steering", "max_steer_angle", setup.max_steer_angle)
	cfg.set_value("steering", "steer_speed", setup.steer_speed)
	cfg.set_value("steering", "steer_curve_max_kmh", setup.steer_curve_max_kmh)
	cfg.set_value("steering", "steer_speed_ref", setup.steer_speed_ref)
	cfg.set_value("steering", "steer_high_speed_factor", setup.steer_high_speed_factor)
	cfg.set_value("simulation", "physics_substeps", setup.physics_substeps)
	cfg.set_value("simulation", "traction_control", setup.traction_control)
	cfg.set_value("simulation", "tc_slip_ratio", setup.tc_slip_ratio)
	cfg.set_value("simulation", "tc_gain", setup.tc_gain)
	cfg.set_value("simulation", "tc_min_scale", setup.tc_min_scale)

	cfg.save(SAVE_PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	model_y_offset = float(cfg.get_value("visual", "model_y_offset", model_y_offset))
	collision_y = float(cfg.get_value("visual", "collision_y", collision_y))
	suspension_mount_y = float(cfg.get_value("visual", "suspension_mount_y", suspension_mount_y))

	setup.mass = float(cfg.get_value("body", "mass", setup.mass))
	setup.center_of_mass_offset = Vector3(
		float(cfg.get_value("body", "com_x", setup.center_of_mass_offset.x)),
		float(cfg.get_value("body", "com_y", setup.center_of_mass_offset.y)),
		float(cfg.get_value("body", "com_z", setup.center_of_mass_offset.z))
	)

	setup.max_power_kw = float(cfg.get_value("engine", "max_power_kw", setup.max_power_kw))
	setup.idle_rpm = float(cfg.get_value("engine", "idle_rpm", setup.idle_rpm))
	setup.max_rpm = float(cfg.get_value("engine", "max_rpm", setup.max_rpm))
	setup.torque_boost = float(cfg.get_value("engine", "torque_boost", setup.torque_boost))
	setup.engine_inertia = float(cfg.get_value("engine", "engine_inertia", setup.engine_inertia))

	setup.reverse_ratio = float(cfg.get_value("drivetrain", "reverse_ratio", setup.reverse_ratio))
	setup.final_drive = float(cfg.get_value("drivetrain", "final_drive", setup.final_drive))
	setup.drive_type = int(cfg.get_value("drivetrain", "drive_type", int(setup.drive_type))) as CarSetup.DriveType
	setup.shift_time = float(cfg.get_value("drivetrain", "shift_time", setup.shift_time))
	setup.clutch_max_torque = float(cfg.get_value("drivetrain", "clutch_max_torque", setup.clutch_max_torque))
	setup.clutch_engage_time = float(cfg.get_value("drivetrain", "clutch_engage_time", setup.clutch_engage_time))
	setup.awd_front_bias = float(cfg.get_value("drivetrain", "awd_front_bias", setup.awd_front_bias))
	setup.rear_diff_type = int(cfg.get_value("drivetrain", "rear_diff_type", int(setup.rear_diff_type))) as CarSetup.RearDiffType
	setup.diff_preload = float(cfg.get_value("drivetrain", "diff_preload", setup.diff_preload))
	setup.diff_power_lock = float(cfg.get_value("drivetrain", "diff_power_lock", setup.diff_power_lock))
	setup.diff_coast_lock = float(cfg.get_value("drivetrain", "diff_coast_lock", setup.diff_coast_lock))
	setup.locked_diff_stiffness = float(cfg.get_value("drivetrain", "locked_diff_stiffness", setup.locked_diff_stiffness))
	var gears: Array[float] = []
	for i in maxi(setup.gear_ratios.size(), 5):
		var default_g := setup.gear_ratios[i] if i < setup.gear_ratios.size() else 1.0
		gears.append(float(cfg.get_value("drivetrain", "gear_%d" % (i + 1), default_g)))
	setup.gear_ratios = gears

	setup.wheel_radius = float(cfg.get_value("wheels", "wheel_radius", setup.wheel_radius))
	setup.wheel_width = float(cfg.get_value("wheels", "wheel_width", setup.wheel_width))
	setup.wheel_inertia = float(cfg.get_value("wheels", "wheel_inertia", setup.wheel_inertia))
	var track := 0.52
	var front_z := -0.81
	var rear_z := 0.7
	if setup.wheel_positions.size() >= 4:
		track = absf(setup.wheel_positions[0].x)
		front_z = setup.wheel_positions[0].z
		rear_z = setup.wheel_positions[2].z
	track = float(cfg.get_value("wheels", "track", track))
	front_z = float(cfg.get_value("wheels", "front_z", front_z))
	rear_z = float(cfg.get_value("wheels", "rear_z", rear_z))
	setup.wheel_positions = [
		Vector3(-track, suspension_mount_y, front_z),
		Vector3(track, suspension_mount_y, front_z),
		Vector3(-track, suspension_mount_y, rear_z),
		Vector3(track, suspension_mount_y, rear_z),
	]

	var legacy_rest := float(cfg.get_value("suspension", "rest_length", setup.rest_length))
	var legacy_travel := float(cfg.get_value("suspension", "travel", setup.travel))
	var legacy_stiff := float(cfg.get_value("suspension", "stiffness", setup.stiffness))
	var legacy_damp := float(cfg.get_value("suspension", "damping", setup.damping))
	var legacy_ar := float(cfg.get_value("suspension", "anti_roll", setup.anti_roll))

	setup.front_rest_length = float(cfg.get_value("suspension", "front_rest_length", legacy_rest))
	setup.rear_rest_length = float(cfg.get_value("suspension", "rear_rest_length", legacy_rest))
	setup.front_travel = float(cfg.get_value("suspension", "front_travel", legacy_travel))
	setup.rear_travel = float(cfg.get_value("suspension", "rear_travel", legacy_travel))
	setup.front_stiffness = float(cfg.get_value("suspension", "front_stiffness", legacy_stiff))
	setup.rear_stiffness = float(cfg.get_value("suspension", "rear_stiffness", legacy_stiff))
	setup.front_damping_compression = float(cfg.get_value("suspension", "front_damping_compression", legacy_damp))
	setup.rear_damping_compression = float(cfg.get_value("suspension", "rear_damping_compression", legacy_damp))
	setup.front_damping_rebound = float(cfg.get_value("suspension", "front_damping_rebound", legacy_damp * 1.2))
	setup.rear_damping_rebound = float(cfg.get_value("suspension", "rear_damping_rebound", legacy_damp * 1.2))
	setup.front_anti_roll = float(cfg.get_value("suspension", "front_anti_roll", legacy_ar))
	setup.rear_anti_roll = float(cfg.get_value("suspension", "rear_anti_roll", legacy_ar))
	setup.rest_length = setup.front_rest_length
	setup.travel = setup.front_travel
	setup.stiffness = setup.front_stiffness
	setup.damping = setup.front_damping_compression
	setup.anti_roll = setup.front_anti_roll

	var legacy_grip_lat := float(cfg.get_value("tires", "grip_lateral", setup.grip_lateral))
	var legacy_grip_rear := float(cfg.get_value("tires", "grip_lateral_rear", setup.grip_lateral_rear))
	setup.tire_mu_front = float(cfg.get_value("tires", "tire_mu_front", clampf(legacy_grip_lat * 0.72, 0.8, 2.4)))
	setup.tire_mu_rear = float(cfg.get_value("tires", "tire_mu_rear", clampf(legacy_grip_rear * 0.45, 0.8, 2.4)))
	setup.tire_v_low = float(cfg.get_value("tires", "tire_v_low", setup.tire_v_low))
	setup.pacejka_b_long = float(cfg.get_value("tires", "pacejka_b_long", setup.pacejka_b_long))
	setup.pacejka_c_long = float(cfg.get_value("tires", "pacejka_c_long", setup.pacejka_c_long))
	setup.pacejka_e_long = float(cfg.get_value("tires", "pacejka_e_long", setup.pacejka_e_long))
	setup.pacejka_b_lat = float(cfg.get_value("tires", "pacejka_b_lat", setup.pacejka_b_lat))
	setup.pacejka_c_lat = float(cfg.get_value("tires", "pacejka_c_lat", setup.pacejka_c_lat))
	setup.pacejka_e_lat = float(cfg.get_value("tires", "pacejka_e_lat", setup.pacejka_e_lat))
	setup.rolling_resistance = float(cfg.get_value("tires", "rolling_resistance", setup.rolling_resistance))
	setup.brake_force = float(cfg.get_value("tires", "brake_force", setup.brake_force))
	setup.handbrake_force = float(cfg.get_value("tires", "handbrake_force", setup.handbrake_force))
	setup.handbrake_lat_grip = float(cfg.get_value("tires", "handbrake_lat_grip", setup.handbrake_lat_grip))
	setup.brake_bias_front = float(cfg.get_value("tires", "brake_bias_front", setup.brake_bias_front))

	setup.drag_coefficient = float(cfg.get_value("aero", "drag_coefficient", setup.drag_coefficient))
	setup.downforce_coefficient = float(cfg.get_value("aero", "downforce_coefficient", setup.downforce_coefficient))
	setup.frontal_area = float(cfg.get_value("aero", "frontal_area", setup.frontal_area))

	setup.max_steer_angle = float(cfg.get_value("steering", "max_steer_angle", setup.max_steer_angle))
	setup.steer_speed = float(cfg.get_value("steering", "steer_speed", setup.steer_speed))
	setup.steer_curve_max_kmh = float(cfg.get_value("steering", "steer_curve_max_kmh", setup.steer_curve_max_kmh))
	setup.steer_speed_ref = float(cfg.get_value("steering", "steer_speed_ref", setup.steer_speed_ref))
	setup.steer_high_speed_factor = float(cfg.get_value("steering", "steer_high_speed_factor", setup.steer_high_speed_factor))
	setup.physics_substeps = int(cfg.get_value("simulation", "physics_substeps", setup.physics_substeps))
	setup.traction_control = bool(cfg.get_value("simulation", "traction_control", setup.traction_control))
	setup.tc_slip_ratio = float(cfg.get_value("simulation", "tc_slip_ratio", setup.tc_slip_ratio))
	setup.tc_gain = float(cfg.get_value("simulation", "tc_gain", setup.tc_gain))
	setup.tc_min_scale = float(cfg.get_value("simulation", "tc_min_scale", setup.tc_min_scale))
	# Old saves kept a clutch weaker than the engine — force a sane floor.
	if setup.clutch_max_torque < 600.0:
		setup.clutch_max_torque = 1000.0
	setup.ensure_torque_curve()
	setup.ensure_steer_angle_curve()
	setup.migrate_legacy_fields()


func make_runtime_setup() -> CarSetup:
	apply_mount_height()
	var copy := setup.duplicate(true) as CarSetup
	copy.ensure_torque_curve()
	copy.ensure_steer_angle_curve()
	copy.migrate_legacy_fields()
	return copy
