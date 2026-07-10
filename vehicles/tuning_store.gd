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

	cfg.set_value("drivetrain", "reverse_ratio", setup.reverse_ratio)
	cfg.set_value("drivetrain", "final_drive", setup.final_drive)
	cfg.set_value("drivetrain", "drive_type", int(setup.drive_type))
	cfg.set_value("drivetrain", "shift_time", setup.shift_time)
	for i in setup.gear_ratios.size():
		cfg.set_value("drivetrain", "gear_%d" % (i + 1), setup.gear_ratios[i])

	cfg.set_value("wheels", "wheel_radius", setup.wheel_radius)
	cfg.set_value("wheels", "wheel_width", setup.wheel_width)
	if setup.wheel_positions.size() >= 4:
		cfg.set_value("wheels", "track", absf(setup.wheel_positions[0].x))
		cfg.set_value("wheels", "front_z", setup.wheel_positions[0].z)
		cfg.set_value("wheels", "rear_z", setup.wheel_positions[2].z)

	cfg.set_value("suspension", "rest_length", setup.rest_length)
	cfg.set_value("suspension", "travel", setup.travel)
	cfg.set_value("suspension", "stiffness", setup.stiffness)
	cfg.set_value("suspension", "damping", setup.damping)
	cfg.set_value("suspension", "anti_roll", setup.anti_roll)

	cfg.set_value("tires", "grip_longitudinal", setup.grip_longitudinal)
	cfg.set_value("tires", "grip_lateral", setup.grip_lateral)
	cfg.set_value("tires", "grip_lateral_rear", setup.grip_lateral_rear)
	cfg.set_value("tires", "rolling_resistance", setup.rolling_resistance)
	cfg.set_value("tires", "brake_force", setup.brake_force)
	cfg.set_value("tires", "handbrake_force", setup.handbrake_force)
	cfg.set_value("tires", "handbrake_lat_grip", setup.handbrake_lat_grip)

	cfg.set_value("steering", "max_steer_angle", setup.max_steer_angle)
	cfg.set_value("steering", "steer_speed", setup.steer_speed)

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

	setup.reverse_ratio = float(cfg.get_value("drivetrain", "reverse_ratio", setup.reverse_ratio))
	setup.final_drive = float(cfg.get_value("drivetrain", "final_drive", setup.final_drive))
	setup.drive_type = int(cfg.get_value("drivetrain", "drive_type", int(setup.drive_type))) as CarSetup.DriveType
	setup.shift_time = float(cfg.get_value("drivetrain", "shift_time", setup.shift_time))
	var gears: Array[float] = []
	for i in maxi(setup.gear_ratios.size(), 5):
		var default_g := setup.gear_ratios[i] if i < setup.gear_ratios.size() else 1.0
		gears.append(float(cfg.get_value("drivetrain", "gear_%d" % (i + 1), default_g)))
	setup.gear_ratios = gears

	setup.wheel_radius = float(cfg.get_value("wheels", "wheel_radius", setup.wheel_radius))
	setup.wheel_width = float(cfg.get_value("wheels", "wheel_width", setup.wheel_width))
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

	setup.rest_length = float(cfg.get_value("suspension", "rest_length", setup.rest_length))
	setup.travel = float(cfg.get_value("suspension", "travel", setup.travel))
	setup.stiffness = float(cfg.get_value("suspension", "stiffness", setup.stiffness))
	setup.damping = float(cfg.get_value("suspension", "damping", setup.damping))
	setup.anti_roll = float(cfg.get_value("suspension", "anti_roll", setup.anti_roll))

	setup.grip_longitudinal = float(cfg.get_value("tires", "grip_longitudinal", setup.grip_longitudinal))
	setup.grip_lateral = float(cfg.get_value("tires", "grip_lateral", setup.grip_lateral))
	setup.grip_lateral_rear = float(cfg.get_value("tires", "grip_lateral_rear", setup.grip_lateral_rear))
	setup.rolling_resistance = float(cfg.get_value("tires", "rolling_resistance", setup.rolling_resistance))
	setup.brake_force = float(cfg.get_value("tires", "brake_force", setup.brake_force))
	setup.handbrake_force = float(cfg.get_value("tires", "handbrake_force", setup.handbrake_force))
	setup.handbrake_lat_grip = float(cfg.get_value("tires", "handbrake_lat_grip", setup.handbrake_lat_grip))

	setup.max_steer_angle = float(cfg.get_value("steering", "max_steer_angle", setup.max_steer_angle))
	setup.steer_speed = float(cfg.get_value("steering", "steer_speed", setup.steer_speed))
	setup.ensure_torque_curve()


func make_runtime_setup() -> CarSetup:
	apply_mount_height()
	var copy := setup.duplicate(true) as CarSetup
	copy.ensure_torque_curve()
	return copy
