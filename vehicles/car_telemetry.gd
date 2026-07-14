class_name CarTelemetry
extends Node

## Physics telemetry CSV for handling + drivetrain analysis.
## F4 start/stop on the occupied car only. Writes car_telemetry_latest.csv + stamped copy.

const LOG_DIR := "res://logs"
const LATEST_NAME := "car_telemetry_latest.csv"

@export var sample_every_n_frames: int = 1
@export var auto_start: bool = false

@onready var _car: CarController = get_parent() as CarController

var recording: bool = false
var _file: FileAccess
var _path_latest: String = ""
var _path_stamp: String = ""
var _t: float = 0.0
var _frame: int = 0
var _rows: int = 0
var _hud: Label
var _prev_vel: Vector3 = Vector3.ZERO
var _has_prev_vel: bool = false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 160)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	_hud.visible = false
	layer.add_child(_hud)
	if auto_start and _is_car_occupied():
		start_recording()


func _exit_tree() -> void:
	stop_recording()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			if recording:
				stop_recording()
				get_viewport().set_input_as_handled()
			elif _is_car_occupied():
				start_recording()
				get_viewport().set_input_as_handled()
			# Unoccupied cars ignore F4 so the occupied car's Telemetry can catch it.


func _physics_process(delta: float) -> void:
	if not recording or _car == null:
		return
	# Drop the session if the player left this car mid-record.
	if not _car.occupied:
		stop_recording()
		return
	_t += delta
	_frame += 1
	if (_frame % maxi(sample_every_n_frames, 1)) != 0:
		return
	_write_row(delta)
	if _hud:
		_hud.text = "REC telemetry %d rows\n%s" % [_rows, _path_latest]


func _is_car_occupied() -> bool:
	if _car == null:
		_car = get_parent() as CarController
	return _car != null and _car.occupied


func start_recording() -> void:
	if recording:
		return
	if _car == null:
		_car = get_parent() as CarController
	if _car == null:
		push_warning("CarTelemetry: parent is not CarController")
		return
	if not _car.occupied:
		push_warning("CarTelemetry: start ignored — car is not occupied")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_path_latest = ProjectSettings.globalize_path("%s/%s" % [LOG_DIR, LATEST_NAME])
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var car_tag := String(_car.car_id)
	if car_tag.is_empty():
		car_tag = "car"
	_path_stamp = ProjectSettings.globalize_path(
		"%s/car_telemetry_%s_%s.csv" % [LOG_DIR, car_tag, stamp]
	)

	_file = FileAccess.open(_path_latest, FileAccess.WRITE)
	if _file == null:
		push_error("CarTelemetry: cannot open %s (%s)" % [_path_latest, FileAccess.get_open_error()])
		return

	_t = 0.0
	_frame = 0
	_rows = 0
	_has_prev_vel = false
	_file.store_line(_header())
	recording = true
	if _hud:
		_hud.visible = true
		_hud.text = "REC telemetry (%s)\n%s" % [car_tag, _path_latest]
	print("CarTelemetry START car=", car_tag, " -> ", _path_latest)


func stop_recording() -> void:
	if not recording:
		return
	recording = false
	if _file:
		_file.flush()
		_file.close()
		_file = null
	if not _path_latest.is_empty() and not _path_stamp.is_empty():
		var src := FileAccess.open(_path_latest, FileAccess.READ)
		if src:
			var dst := FileAccess.open(_path_stamp, FileAccess.WRITE)
			if dst:
				dst.store_string(src.get_as_text())
				dst.close()
			src.close()
	if _hud:
		_hud.text = "Telemetry saved (%d rows)\n%s" % [_rows, _path_latest]
	print("CarTelemetry STOP rows=", _rows, " path=", _path_latest)
	print("CarTelemetry COPY -> ", _path_stamp)


func _header() -> String:
	var cols: PackedStringArray = [
		"t",
		"kmh",
		"vx_body",
		"vy_body",
		"vz_body",
		"ax_body",
		"ay_body",
		"az_body",
		"yaw_rate",
		"steer_in",
		"steer_deg",
		"steer_target_deg",
		"steer_lock",
		"thr",
		"brk",
		"hb",
		# Drivetrain
		"auto",
		"gear",
		"gear_ratio",
		"rpm",
		"eff_thr",
		"eng_tq",
		"clutch",
		"clutch_tq",
		"clutch_slip_w",
		"trans_rpm",
		"driveline",
		"shift_t",
		"auto_cd",
		"est_rpm",
		"est_rpm_up",
		"want_up",
		"want_down",
		"tc_scale",
		"rear_spin",
		"rear_diff",
		"body_slip_deg",
		"yaw_assist_nm",
	]
	for i in 4:
		cols.append_array(
			PackedStringArray(
				[
					"w%d_gnd" % i,
					"w%d_comp" % i,
					"w%d_k" % i,
					"w%d_a_deg" % i,
					"w%d_fx" % i,
					"w%d_fy" % i,
					"w%d_fz" % i,
					"w%d_w" % i,
					"w%d_drive" % i,
					"w%d_brake" % i,
				]
			)
		)
	cols.append_array(
		PackedStringArray(
			[
				"front_fy_sum",
				"rear_fy_sum",
				"rear_k_avg",
				"rear_a_avg_deg",
				"yaw",
			]
		)
	)
	return ",".join(cols)


func _write_row(delta: float) -> void:
	if _file == null or _car.setup == null:
		return

	var basis := _car.global_transform.basis
	var vel_world := _car.linear_velocity
	var vel_body := basis.inverse() * vel_world
	var accel_body := Vector3.ZERO
	if _has_prev_vel and delta > 0.0001:
		var accel_world := (vel_world - _prev_vel) / delta
		accel_body = basis.inverse() * accel_world
	_prev_vel = vel_world
	_has_prev_vel = true

	var wheels := _car.get_wheels()
	var front_fy := 0.0
	var rear_fy := 0.0
	var rear_k := 0.0
	var rear_a := 0.0
	var rear_n := 0

	var parts: PackedStringArray = [
		"%.4f" % _t,
		"%.2f" % _car.get_speed_kmh(),
		"%.3f" % vel_body.x,
		"%.3f" % vel_body.y,
		"%.3f" % vel_body.z,
		"%.3f" % accel_body.x,
		"%.3f" % accel_body.y,
		"%.3f" % accel_body.z,
		"%.4f" % _car.angular_velocity.y,
		"%.3f" % _car.steering,
		"%.2f" % rad_to_deg(_car.debug_steer_rad),
		"%.2f" % rad_to_deg(_car.debug_steer_target),
		"%.3f" % _car.debug_steer_lock,
		"%.3f" % _car.throttle,
		"%.3f" % _car.brake,
		"%.3f" % _car.handbrake,
		"%d" % (1 if _car.automatic else 0),
		"%d" % _car.current_gear,
		"%.3f" % _car.debug_gear_ratio,
		"%.0f" % _car.engine_rpm,
		"%.3f" % _car.debug_eff_throttle,
		"%.1f" % _car.debug_eng_combustion,
		"%.3f" % _car.clutch,
		"%.1f" % _car.debug_clutch_torque,
		"%.2f" % _car.debug_clutch_slip_w,
		"%.0f" % _car.debug_trans_rpm,
		"%.1f" % _car.debug_driveline,
		"%.3f" % _car.debug_shift_timer,
		"%.3f" % _car.debug_auto_cd,
		"%.0f" % _car.debug_est_rpm_cur,
		"%.0f" % _car.debug_est_rpm_up,
		"%d" % _car.debug_want_up,
		"%d" % _car.debug_want_down,
		"%.3f" % _car.debug_tc_scale,
		"%d" % _car.debug_rear_spin,
		"%d" % int(_car.setup.rear_diff_type),
		"%.2f" % _car.debug_body_slip_deg,
		"%.1f" % _car.debug_yaw_assist_nm,
	]

	for i in 4:
		var gnd := 0
		var comp := 0.0
		var k := 0.0
		var a := 0.0
		var fx := 0.0
		var fy := 0.0
		var fz := 0.0
		var w := 0.0
		var drive := 0.0
		var brk := 0.0
		if i < wheels.size():
			var wheel: Wheel = wheels[i]
			gnd = 1 if wheel.on_ground else 0
			comp = wheel.compression
			k = wheel.slip_ratio
			a = rad_to_deg(wheel.slip_angle)
			fx = wheel.long_force
			fy = wheel.lat_force
			fz = wheel.normal_load
			w = wheel.angular_velocity
			drive = wheel.drive_torque
			brk = wheel.brake_torque
			if i < 2:
				front_fy += fy
			else:
				rear_fy += fy
				rear_k += absf(k)
				rear_a += absf(a)
				rear_n += 1
		parts.append_array(
			PackedStringArray(
				[
					"%d" % gnd,
					"%.3f" % comp,
					"%.4f" % k,
					"%.2f" % a,
					"%.1f" % fx,
					"%.1f" % fy,
					"%.1f" % fz,
					"%.2f" % w,
					"%.1f" % drive,
					"%.1f" % brk,
				]
			)
		)

	var rear_k_avg := rear_k / float(maxi(rear_n, 1))
	var rear_a_avg := rear_a / float(maxi(rear_n, 1))
	parts.append_array(
		PackedStringArray(
			[
				"%.1f" % front_fy,
				"%.1f" % rear_fy,
				"%.4f" % rear_k_avg,
				"%.2f" % rear_a_avg,
				"%.2f" % rad_to_deg(_car.rotation.y),
			]
		)
	)

	_file.store_line(",".join(parts))
	_rows += 1
	if (_rows % 30) == 0:
		_file.flush()
