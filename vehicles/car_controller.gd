class_name CarController
extends RigidBody3D

## Tuning resource. Assign in the inspector or via set_setup().
@export var setup: CarSetup
## When false, reverse gear is disabled (endless-road / arcade modes).
@export var allow_reverse: bool = true

## Driver inputs. Set these from gameplay code each frame.
## throttle / brake / handbrake: 0..1, steering: -1..1 (negative = left).
var throttle: float = 0.0
var brake: float = 0.0
var handbrake: float = 0.0
var steering: float = 0.0

var current_gear: int = 1
var engine_rpm: float = 800.0
## true = automatic gearbox, false = manual (toggle with P).
var automatic: bool = true

var _wheels: Array[Wheel] = []
var _current_steer: float = 0.0
var _shift_timer: float = 0.0
var _prev_lengths: Array[float] = []
var _body_applied: bool = false
## 0 = rear gripped, 1 = full drift. Builds on handbrake, decays slowly.
var _rear_drift: float = 0.0
var _base_angular_damp: float = 1.2
var _auto_reverse_armed: bool = false
var _auto_shift_cooldown: float = 0.0
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var occupied: bool = false
var occupant: Node = null


func _ready() -> void:
	add_to_group("player_cars")
	_spawn_transform = global_transform
	# Prefer persisted tuning from Settings menu.
	if TuningStore.setup != null:
		setup = TuningStore.make_runtime_setup()
	elif setup == null:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	_apply_body_setup()
	_rebuild_wheels()
	_apply_visual_tuning()
	can_sleep = false
	continuous_cd = true
	_base_angular_damp = angular_damp
	# Keep chassis from fighting the raycast suspension.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.0


func set_occupied(value: bool, who: Node = null) -> void:
	occupied = value
	occupant = who if value else null
	var driver := get_node_or_null("PlayerDriver")
	if driver != null and "active" in driver:
		driver.active = value
	if not is_inside_tree():
		return
	for cam in get_tree().get_nodes_in_group("car_follow_cameras"):
		if cam.has_method("set_active"):
			cam.call("set_active", value)
		elif cam is Camera3D:
			(cam as Camera3D).current = value


func reset_to_spawn() -> void:
	throttle = 0.0
	brake = 0.0
	handbrake = 0.0
	steering = 0.0
	_current_steer = 0.0
	current_gear = 1
	engine_rpm = setup.idle_rpm if setup else 800.0
	_shift_timer = 0.0
	_auto_shift_cooldown = 0.0
	_auto_reverse_armed = false
	_rear_drift = 0.0
	angular_damp = _base_angular_damp
	sleeping = false
	# Direct physics state write — assigning transform alone is flaky on RigidBody3D.
	PhysicsServer3D.body_set_state(
		get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM,
		_spawn_transform
	)
	PhysicsServer3D.body_set_state(
		get_rid(),
		PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		Vector3.ZERO
	)
	PhysicsServer3D.body_set_state(
		get_rid(),
		PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3.ZERO
	)
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if setup:
		_rebuild_wheels()


func _apply_visual_tuning() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.position.y = TuningStore.model_y_offset
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.position.y = TuningStore.collision_y

func _physics_process(delta: float) -> void:
	if setup == null:
		return
	if not _body_applied:
		_apply_body_setup()

	throttle = clampf(throttle, 0.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	handbrake = clampf(handbrake, 0.0, 1.0)
	steering = clampf(steering, -1.0, 1.0)

	if _shift_timer > 0.0:
		_shift_timer = maxf(_shift_timer - delta, 0.0)
	if _auto_shift_cooldown > 0.0:
		_auto_shift_cooldown = maxf(_auto_shift_cooldown - delta, 0.0)

	if automatic:
		_update_automatic_transmission()

	_update_drift_state(delta)
	_update_steering(delta)
	_update_suspension(delta)
	_update_anti_roll()
	_update_engine_and_drivetrain(delta)
	_apply_tire_forces(delta)
	_apply_aero_drag()


func _update_drift_state(delta: float) -> void:
	# Estimate rear sideslip from body velocity vs facing.
	var right := global_transform.basis.x
	var speed := linear_velocity.length()
	var lat_vel := absf(linear_velocity.dot(right))
	var slip_ratio := 0.0
	if speed > 2.0:
		slip_ratio = clampf(lat_vel / speed, 0.0, 1.0)

	if handbrake > 0.15 and speed > 4.0:
		# Quick breakaway into drift.
		var initiate := handbrake * (0.55 + 0.45 * absf(steering))
		_rear_drift = move_toward(_rear_drift, maxf(_rear_drift, initiate), delta * 6.0)
		_rear_drift = maxf(_rear_drift, slip_ratio)
	elif slip_ratio > 0.25 and speed > 5.0:
		# Hold drift while still sliding sideways.
		_rear_drift = move_toward(_rear_drift, maxf(slip_ratio, 0.45), delta * 1.2)
	else:
		# Slow grip recovery so the car doesn't snap straight instantly.
		_rear_drift = move_toward(_rear_drift, 0.0, delta * 0.85)

	_rear_drift = clampf(_rear_drift, 0.0, 1.0)
	angular_damp = lerpf(_base_angular_damp, 0.12, _rear_drift)

func set_setup(new_setup: CarSetup) -> void:
	setup = new_setup
	if setup == null:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	_body_applied = false
	_rebuild_wheels()
	if is_inside_tree():
		_apply_body_setup()


func shift_up() -> void:
	if setup == null or _shift_timer > 0.0:
		return
	var max_gear := setup.get_forward_gear_count()
	if current_gear < max_gear:
		current_gear += 1
		_shift_timer = setup.shift_time
		_sync_rpm_to_transmission()
		if automatic:
			_auto_shift_cooldown = 0.7


func shift_down() -> void:
	if setup == null or _shift_timer > 0.0:
		return
	var min_gear := -1 if allow_reverse else 1
	if current_gear > min_gear:
		current_gear -= 1
		_shift_timer = setup.shift_time
		_sync_rpm_to_transmission()
		if automatic:
			_auto_shift_cooldown = 0.55


func toggle_transmission() -> void:
	automatic = not automatic
	_auto_reverse_armed = false
	_auto_shift_cooldown = 0.0
	if automatic and current_gear == 0:
		current_gear = 1


func get_transmission_label() -> String:
	return "АВТО" if automatic else "МЕХ"


func _sync_rpm_to_transmission() -> void:
	var rpm := _estimate_transmission_rpm(current_gear)
	if rpm > 0.0:
		engine_rpm = clampf(rpm, setup.idle_rpm * 0.5, setup.max_rpm)


func _estimate_transmission_rpm(gear: int) -> float:
	if setup == null:
		return 0.0
	var gear_ratio := setup.get_gear_ratio(gear)
	if absf(gear_ratio) < 0.001:
		return 0.0
	var speed := absf(linear_velocity.dot(-global_transform.basis.z))
	var wheel_omega := speed / maxf(setup.wheel_radius, 0.05)
	var wheel_rpm := wheel_omega * 60.0 / TAU
	return wheel_rpm * absf(gear_ratio) * setup.final_drive


func _update_automatic_transmission() -> void:
	if setup == null or _shift_timer > 0.0 or _auto_shift_cooldown > 0.0:
		return

	var max_gear := setup.get_forward_gear_count()
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)
	var speed_kmh := absf(forward_speed) * 3.6

	if allow_reverse:
		# Arm reverse when nearly stopped and holding brake.
		if absf(forward_speed) < 1.2 and brake > 0.35 and throttle < 0.05:
			_auto_reverse_armed = true
		if forward_speed > 2.5:
			_auto_reverse_armed = false

		if _auto_reverse_armed and throttle > 0.1 and forward_speed < 1.5:
			if current_gear != -1:
				current_gear = -1
				_shift_timer = setup.shift_time
				_auto_shift_cooldown = 0.4
				_sync_rpm_to_transmission()
			return

		if current_gear < 0:
			if throttle < 0.05 and absf(forward_speed) < 0.6:
				current_gear = 1
				_auto_reverse_armed = false
				_shift_timer = setup.shift_time
				_auto_shift_cooldown = 0.4
				_sync_rpm_to_transmission()
			elif throttle > 0.1 and forward_speed > 0.4:
				current_gear = 1
				_auto_reverse_armed = false
				_shift_timer = setup.shift_time
				_auto_shift_cooldown = 0.4
				_sync_rpm_to_transmission()
			return
	else:
		_auto_reverse_armed = false
		if current_gear < 1:
			current_gear = 1

	if current_gear <= 0:
		current_gear = 1

	# Downshift: small gearboxes use speed floors; big (endless) boxes use RPM.
	var down_at: Dictionary = {2: 12.0, 3: 28.0, 4: 48.0, 5: 75.0}
	var down_speed := float(down_at.get(current_gear, -1.0))
	var wide_box := max_gear > 8

	var want_up := false
	var skip_to_gear := -1
	if current_gear < max_gear and throttle > 0.08:
		if wide_box:
			# 100 closely-spaced ratios: jump forward until RPM actually drops.
			if engine_rpm >= setup.max_rpm * 0.92:
				var best := current_gear
				for g in range(current_gear + 1, max_gear + 1):
					var rpm_g := _estimate_transmission_rpm(g)
					if rpm_g <= 0.0:
						break
					best = g
					if rpm_g <= setup.max_rpm * 0.72:
						break
				if best > current_gear:
					skip_to_gear = best
					want_up = true
		else:
			var redline_up2 := setup.max_rpm * 0.85
			if engine_rpm >= redline_up2:
				var next_rpm2 := _estimate_transmission_rpm(current_gear + 1)
				if next_rpm2 >= setup.idle_rpm * 1.2 or speed_kmh > 15.0:
					want_up = true

	var want_down := false
	if current_gear > 1:
		if wide_box:
			# Wide hysteresis vs upshift band so it can't bounce.
			if engine_rpm <= setup.max_rpm * 0.42 and throttle < 0.65:
				want_down = true
			elif throttle > 0.9 and engine_rpm < setup.max_rpm * 0.48:
				var rpm_if_down := _estimate_transmission_rpm(current_gear - 1)
				if rpm_if_down > 0.0 and rpm_if_down < setup.max_rpm * 0.9:
					want_down = true
		else:
			if speed_kmh <= down_speed and throttle < 0.7:
				want_down = true
			elif engine_rpm <= setup.idle_rpm * 1.2 and throttle < 0.3 and speed_kmh <= down_speed + 10.0:
				want_down = true
			elif throttle > 0.9 and engine_rpm < setup.max_rpm * 0.55:
				var rpm_if_down2 := _estimate_transmission_rpm(current_gear - 1)
				if rpm_if_down2 < setup.max_rpm * 0.9:
					want_down = true

	if want_up and not want_down:
		if skip_to_gear > current_gear:
			current_gear = skip_to_gear
			_shift_timer = setup.shift_time
			_auto_shift_cooldown = 0.5
			_sync_rpm_to_transmission()
		else:
			shift_up()
	elif want_down and not want_up:
		shift_down()
		if wide_box:
			_auto_shift_cooldown = maxf(_auto_shift_cooldown, 0.45)


func set_gear(gear: int) -> void:
	if setup == null:
		return
	var max_gear := setup.get_forward_gear_count()
	var min_gear := -1 if allow_reverse else 1
	current_gear = clampi(gear, min_gear, max_gear)
	_shift_timer = setup.shift_time


func get_speed_ms() -> float:
	return linear_velocity.length()


func get_speed_kmh() -> float:
	return get_speed_ms() * 3.6


func get_power_hp() -> float:
	if setup == null:
		return 0.0
	return setup.max_power_kw / 0.7457


func get_gear_label() -> String:
	if current_gear < 0:
		return "R"
	if current_gear == 0:
		return "N"
	return str(current_gear)


func get_wheels() -> Array[Wheel]:
	return _wheels


func _apply_body_setup() -> void:
	mass = maxf(setup.mass, 1.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = setup.center_of_mass_offset
	_body_applied = true


func _rebuild_wheels() -> void:
	_wheels.clear()
	_prev_lengths.clear()
	var positions := setup.wheel_positions
	for i in positions.size():
		var wheel := Wheel.new()
		wheel.local_origin = positions[i]
		wheel.is_steering = i < 2
		wheel.is_driven = _is_driven_index(i)
		_wheels.append(wheel)
		_prev_lengths.append(setup.rest_length)


func _is_driven_index(index: int) -> bool:
	match setup.drive_type:
		CarSetup.DriveType.FWD:
			return index < 2
		CarSetup.DriveType.RWD:
			return index >= 2
		CarSetup.DriveType.AWD:
			return true
	return index >= 2


func _update_steering(delta: float) -> void:
	var target := steering * deg_to_rad(setup.max_steer_angle)
	_current_steer = move_toward(_current_steer, target, setup.steer_speed * delta)
	for wheel in _wheels:
		wheel.steer_angle = _current_steer if wheel.is_steering else 0.0


func _update_suspension(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var exclude := [get_rid()]
	# rest_length = target ray distance to ground; travel = extra compression allowed.
	var ray_length := setup.rest_length + setup.travel
	# Cap force high enough to support weight transfer without launching.
	var max_force := setup.mass * 9.81 * 4.5

	for i in _wheels.size():
		var wheel := _wheels[i]
		wheel.reset_forces()

		var origin_world := to_global(wheel.local_origin)
		var up := global_transform.basis.y.normalized()
		var down := -up
		var query := PhysicsRayQueryParameters3D.create(
			origin_world,
			origin_world + down * ray_length
		)
		query.exclude = exclude
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var hit := space.intersect_ray(query)
		if hit.is_empty():
			wheel.on_ground = false
			wheel.compression = 0.0
			wheel.suspension_length = ray_length
			_prev_lengths[i] = ray_length
			continue

		wheel.on_ground = true
		wheel.hit_point = hit.position
		wheel.hit_normal = hit.normal.normalized()
		# Spring length is the raw ray hit distance (do NOT subtract wheel radius).
		var spring_length := origin_world.distance_to(hit.position)
		wheel.suspension_length = spring_length

		# Positive when shorter than rest (compressed).
		var compression_distance := setup.rest_length - spring_length
		var compression := clampf(
			compression_distance / maxf(setup.travel, 0.001),
			0.0,
			1.0
		)
		wheel.compression = compression

		# Damper from rigid-body velocity along the suspension axis (stable vs finite-diff).
		var mount_velocity := _velocity_at_point(origin_world)
		var suspension_speed := mount_velocity.dot(up)
		# Spring engages as soon as length < rest_length (not only after full travel).
		var spring_travel := clampf(compression_distance, 0.0, setup.travel)
		var spring_force := setup.stiffness * spring_travel
		var damper_force := -setup.damping * suspension_speed

		# Progressive bump stop so the car cannot sit through the road under load.
		var bump := 0.0
		if compression_distance > setup.travel:
			var overrun := compression_distance - setup.travel
			bump = setup.stiffness * overrun * 3.0 + setup.mass * 9.81 * overrun * 8.0
		elif compression > 0.75:
			var t := (compression - 0.75) / 0.25
			bump = t * t * setup.mass * 9.81

		wheel.suspension_force = clampf(spring_force + damper_force + bump, 0.0, max_force)
		_prev_lengths[i] = spring_length

		var force_vec := wheel.hit_normal * wheel.suspension_force
		apply_force(force_vec, origin_world - global_position)

		_update_wheel_basis(wheel)


func _update_wheel_basis(wheel: Wheel) -> void:
	var steer_basis := global_transform.basis.rotated(global_transform.basis.y, wheel.steer_angle)
	var forward := -steer_basis.z
	var up := wheel.hit_normal
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.0001:
		forward = -global_transform.basis.z
	var right := up.cross(forward).normalized()
	if right.length_squared() < 0.0001:
		right = global_transform.basis.x
	else:
		right = right.normalized()
	forward = right.cross(up).normalized()
	wheel.forward = forward
	wheel.right = right
	wheel.up = up


func _update_anti_roll() -> void:
	if setup.anti_roll <= 0.0 or _wheels.size() < 4:
		return
	_apply_anti_roll_pair(0, 1)
	_apply_anti_roll_pair(2, 3)


func _apply_anti_roll_pair(left_i: int, right_i: int) -> void:
	var left := _wheels[left_i]
	var right := _wheels[right_i]
	if not left.on_ground and not right.on_ground:
		return
	# Resist compression difference: more-compressed side gets extra UP force.
	var diff := left.compression - right.compression
	var force := diff * setup.anti_roll
	if left.on_ground:
		var left_origin := to_global(left.local_origin)
		apply_force(left.hit_normal * force, left_origin - global_position)
	if right.on_ground:
		var right_origin := to_global(right.local_origin)
		apply_force(right.hit_normal * -force, right_origin - global_position)


func _update_engine_and_drivetrain(delta: float) -> void:
	var gear_ratio := setup.get_gear_ratio(current_gear)
	var driven := _driven_wheels()
	var driven_grounded := 0

	# Use body forward speed for gearbox RPM so a bit of slip/steer doesn't cap revs.
	var forward := -global_transform.basis.z
	var long_speed_body := linear_velocity.dot(forward)
	var wheel_omega := absf(long_speed_body) / maxf(setup.wheel_radius, 0.05)

	for wheel in driven:
		if wheel.on_ground:
			wheel.angular_velocity = long_speed_body / maxf(setup.wheel_radius, 0.05)
			driven_grounded += 1
		else:
			wheel.angular_velocity = lerpf(wheel.angular_velocity, 0.0, clampf(2.0 * delta, 0.0, 1.0))

	var transmission_rpm := engine_rpm
	if absf(gear_ratio) > 0.001:
		var wheel_rpm := wheel_omega * 60.0 / TAU
		transmission_rpm = wheel_rpm * absf(gear_ratio) * setup.final_drive

	var in_gear := absf(gear_ratio) > 0.001 and _shift_timer <= 0.0
	if in_gear and driven_grounded > 0:
		engine_rpm = lerpf(engine_rpm, transmission_rpm, clampf(14.0 * delta, 0.0, 1.0))
	elif _shift_timer > 0.0:
		var hold_rpm := transmission_rpm
		if hold_rpm <= 1.0:
			hold_rpm = _estimate_transmission_rpm(current_gear)
		if hold_rpm > 1.0:
			engine_rpm = lerpf(engine_rpm, hold_rpm, clampf(18.0 * delta, 0.0, 1.0))
		else:
			engine_rpm = move_toward(engine_rpm, setup.idle_rpm, 2000.0 * delta)
	else:
		var target_rpm := setup.idle_rpm + throttle * (setup.max_rpm - setup.idle_rpm)
		engine_rpm = move_toward(engine_rpm, target_rpm, 4000.0 * delta)

	engine_rpm = clampf(engine_rpm, setup.idle_rpm * 0.5, setup.max_rpm)

	var effective_throttle := throttle
	if engine_rpm >= setup.max_rpm * 0.98:
		effective_throttle = 0.0

	if not in_gear:
		return

	var engine_torque := setup.get_engine_torque(engine_rpm) * effective_throttle
	var drive_torque := engine_torque * gear_ratio * setup.final_drive
	var split_count := maxi(driven_grounded, 1)
	var torque_per_wheel := drive_torque / float(split_count)

	for wheel in driven:
		if not wheel.on_ground:
			continue
		var drive_force := torque_per_wheel / maxf(setup.wheel_radius, 0.05)
		wheel.long_force += drive_force


func _driven_wheels() -> Array[Wheel]:
	var result: Array[Wheel] = []
	for wheel in _wheels:
		if wheel.is_driven:
			result.append(wheel)
	return result


func _apply_tire_forces(delta: float) -> void:
	for wheel in _wheels:
		if not wheel.on_ground:
			continue

		var point_velocity := _velocity_at_point(wheel.hit_point)
		var long_speed := point_velocity.dot(wheel.forward)
		var lat_speed := point_velocity.dot(wheel.right)

		# Floor the load a bit so grip doesn't collapse when a wheel unloads in a turn.
		var normal_load := maxf(wheel.suspension_force, setup.mass * 9.81 * 0.08)
		var max_long := setup.grip_longitudinal * normal_load
		var grip_lat := setup.grip_lateral_rear if not wheel.is_steering else setup.grip_lateral
		if not wheel.is_steering:
			# Blend toward very low rear grip while drifting / handbraking.
			var drift_grip := setup.handbrake_lat_grip
			grip_lat *= lerpf(1.0, drift_grip, maxf(_rear_drift, handbrake))
		var max_lat := grip_lat * normal_load

		# Engine braking only on driven wheels — otherwise the front feels like it drags.
		var brake_input := brake
		if (
			wheel.is_driven
			and throttle < 0.05
			and handbrake < 0.05
			and absf(setup.get_gear_ratio(current_gear)) > 0.001
		):
			brake_input = maxf(brake_input, 0.05)

		if brake_input > 0.0:
			var brake_dir := -signf(long_speed)
			if absf(long_speed) < 0.15:
				brake_dir = 0.0
			wheel.long_force += brake_dir * setup.brake_force * brake_input

		# Handbrake locks the rear axle; keep a bit of throttle freedom for sustained drift.
		if not wheel.is_steering and handbrake > 0.0:
			var hb_dir := -signf(long_speed)
			if absf(long_speed) < 0.2:
				hb_dir = 0.0
			else:
				wheel.long_force += hb_dir * setup.handbrake_force * handbrake
			# Scale down drive instead of killing it completely.
			if wheel.is_driven and wheel.long_force > 0.0:
				wheel.long_force *= lerpf(1.0, 0.25, handbrake)

		wheel.long_force += -signf(long_speed) * setup.rolling_resistance * normal_load

		# Balance: enough drive to pull higher gears, enough circle left for steering.
		var drive_budget_ratio := 0.72 if wheel.is_driven else 0.7
		if not wheel.is_steering and _rear_drift > 0.2:
			drive_budget_ratio = lerpf(drive_budget_ratio, 0.88, _rear_drift)
		var drive_budget := max_long * drive_budget_ratio
		wheel.long_force = clampf(wheel.long_force, -max_long, drive_budget)

		var long_ratio := absf(wheel.long_force) / maxf(max_long, 1.0)
		var lat_budget := max_lat * sqrt(maxf(0.0, 1.0 - long_ratio * long_ratio))

		var lat_response := 2400.0 + 75.0 * absf(long_speed)
		if not wheel.is_steering:
			lat_response *= lerpf(1.55, 0.2, _rear_drift)
		elif _rear_drift > 0.3:
			lat_response *= 1.2
		var desired_lat := -lat_speed * lat_response
		wheel.lat_force = clampf(desired_lat, -lat_budget, lat_budget)

		var tire_force := wheel.forward * wheel.long_force + wheel.right * wheel.lat_force
		tire_force = tire_force - wheel.hit_normal * tire_force.dot(wheel.hit_normal)
		apply_force(tire_force, wheel.hit_point - global_position)

		var accel := (wheel.long_force * setup.wheel_radius) / maxf(setup.mass * 0.05, 1.0)
		wheel.angular_velocity += accel * delta


func _velocity_at_point(world_point: Vector3) -> Vector3:
	var local := world_point - global_position
	return linear_velocity + angular_velocity.cross(local)


func _apply_aero_drag() -> void:
	var speed := linear_velocity.length()
	if speed < 0.01:
		return
	# Mild quadratic drag — old 0.35*v^2 killed pull in 3rd+ gears.
	var drag_coeff := 0.1
	var drag := -linear_velocity.normalized() * drag_coeff * speed * speed
	apply_central_force(drag)
