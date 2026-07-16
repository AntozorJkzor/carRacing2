class_name CarController
extends RigidBody3D

const _VehicleDiff = preload("res://vehicles/vehicle_diff.gd")
const _TireModel = preload("res://vehicles/tire_model.gd")
const _WheelSmokeScript = preload("res://vehicles/wheel_smoke.gd")
const _PlayerDriverScript = preload("res://vehicles/player_driver.gd")
const _CarLightsScript = preload("res://vehicles/car_lights.gd")
const _ExhaustFlameScript = preload("res://vehicles/exhaust_flame.gd")

## Tuning resource assigned on the car pack scene (.tres). Scene is source of truth.
@export var setup: CarSetup
## Pack id used for catalog / per-car debug overrides (user://tuning_<id>.cfg).
@export var car_id: StringName = &"golf"
## Pack-local wheel mesh scene (shared by VisualWheels + WheelLayout if they leave theirs empty).
@export var wheel_scene: PackedScene
## Pack-local engine loops (consumed by EngineAudio if its streams are empty).
@export var audio_profile: CarAudioProfile
## Additive ride height for Model + CollisionShape3D (relative to scene bases).
@export var clearance: float = 0.0
## When false, reverse gear is disabled (endless-road / arcade modes).
@export var allow_reverse: bool = true

signal gear_shifted(from_gear: int, to_gear: int)

## Driver inputs. Set these from gameplay code each frame.
## throttle / brake / handbrake: 0..1, steering: -1..1 (negative = left).
var throttle: float = 0.0
var brake: float = 0.0
var handbrake: float = 0.0
var steering: float = 0.0
## Automatic only: true while driver holds reverse intent (mapped brake near stop / in R).
var want_reverse: bool = false

var current_gear: int = 1
var engine_rpm: float = 800.0
## true = automatic gearbox, false = manual (toggle with P).
var automatic: bool = true
## 1 = fully engaged, 0 = open.
var clutch: float = 1.0

## Debug / telemetry (updated each steering step).
var debug_steer_rad: float = 0.0
var debug_steer_lock: float = 1.0
var debug_steer_target: float = 0.0

## Drivetrain debug (engine / clutch / gearbox / TC).
var debug_eng_combustion: float = 0.0
var debug_clutch_torque: float = 0.0
var debug_trans_rpm: float = 0.0
var debug_clutch_slip_w: float = 0.0
var debug_driveline: float = 0.0
var debug_gear_ratio: float = 0.0
var debug_shift_timer: float = 0.0
var debug_auto_cd: float = 0.0
var debug_est_rpm_cur: float = 0.0
var debug_est_rpm_up: float = 0.0
var debug_want_up: int = 0
var debug_want_down: int = 0
var debug_tc_scale: float = 1.0
var debug_eff_throttle: float = 0.0
var debug_rev_limiter_cut: bool = false
var rev_limiter_active: bool = false
var debug_rear_spin: int = 0
var debug_body_slip_deg: float = 0.0
var debug_yaw_assist_nm: float = 0.0

var _wheels: Array[Wheel] = []
var _current_steer: float = 0.0
## Filtered throttle used by engine/clutch (pedal input stays in `throttle`).
var _throttle_cmd: float = 0.0
var _shift_timer: float = 0.0
var _prev_lengths: Array[float] = []
var _body_applied: bool = false
var _base_angular_damp: float = 1.2
var _auto_shift_cooldown: float = 0.0
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _clutch_engage_timer: float = 0.0
var _rev_limiter_cut: bool = false
var occupied: bool = false
var occupant: Node = null
var _model_base_y: float = 0.0
var _collision_base_y: float = 0.0
var _visual_bases_cached: bool = false


func _ready() -> void:
	add_to_group("player_cars")
	_spawn_transform = global_transform
	if setup != null:
		setup = setup.duplicate(true) as CarSetup
	else:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	setup.ensure_steer_angle_curve()
	setup.migrate_legacy_fields()
	TuningStore.apply_overrides_to_car(self)
	_apply_pack_assets()
	_apply_body_setup()
	_rebuild_wheels()
	_apply_visual_tuning()
	can_sleep = false
	continuous_cd = true
	_base_angular_damp = angular_damp
	angular_damp = _base_angular_damp
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.0
	TuningStore.bind_car_id(car_id)


func _apply_pack_assets() -> void:
	## Push pack wheel / audio into child nodes when they have no local override.
	if wheel_scene != null:
		var visual := get_node_or_null("VisualWheels")
		if visual != null and visual.get("wheel_scene") == null:
			visual.set("wheel_scene", wheel_scene)
		var layout := get_node_or_null("WheelLayout")
		if layout != null and layout.get("wheel_scene") == null:
			layout.set("wheel_scene", wheel_scene)
	if audio_profile != null:
		var engine_audio := get_node_or_null("EngineAudio")
		if engine_audio != null and engine_audio.has_method("apply_profile"):
			engine_audio.call("apply_profile", audio_profile, true)
			if engine_audio.has_method("is_live") and bool(engine_audio.call("is_live")):
				if engine_audio.has_method("apply_setup"):
					engine_audio.call("apply_setup", setup)
			else:
				var user_banks := EngineBankBaker.load_user(car_id)
				if user_banks.is_empty() and audio_profile != null:
					var bank_dir := str(audio_profile.get("engine_bank_dir"))
					if not bank_dir.is_empty():
						user_banks = EngineBankBaker.load_dir(bank_dir)
				if not user_banks.is_empty() and engine_audio.has_method("apply_banks"):
					engine_audio.call("apply_banks", user_banks)
	_ensure_wheel_smoke()
	_ensure_player_driver()
	_ensure_car_lights()
	_ensure_exhaust_flame()


func _ensure_wheel_smoke() -> void:
	## Tire smoke is pack FX — create if missing so tracks never wire particles.
	if get_node_or_null("WheelSmoke") != null:
		return
	var smoke := Node3D.new()
	smoke.name = "WheelSmoke"
	smoke.set_script(_WheelSmokeScript)
	add_child(smoke)


func _ensure_player_driver() -> void:
	## Driver input lives on the car pack — drop the scene on a track and go.
	if get_node_or_null("PlayerDriver") != null:
		return
	var driver := Node.new()
	driver.name = "PlayerDriver"
	driver.set_script(_PlayerDriverScript)
	add_child(driver)


func _ensure_car_lights() -> void:
	if get_node_or_null("CarLights") != null:
		return
	var lights := Node3D.new()
	lights.name = "CarLights"
	lights.set_script(_CarLightsScript)
	add_child(lights)


func _ensure_exhaust_flame() -> void:
	if get_node_or_null("ExhaustFlame") != null:
		return
	var fx := Node3D.new()
	fx.name = "ExhaustFlame"
	fx.set_script(_ExhaustFlameScript)
	add_child(fx)


func set_occupied(value: bool, who: Node = null) -> void:
	occupied = value
	occupant = who if value else null
	var driver := get_node_or_null("PlayerDriver")
	if driver != null and "active" in driver:
		driver.active = value
	if not is_inside_tree():
		return
	for cam in get_tree().get_nodes_in_group("car_follow_cameras"):
		if value and cam.has_method("set_target"):
			cam.call("set_target", self)
		if cam.has_method("set_active"):
			cam.call("set_active", value)
		elif cam is Camera3D:
			(cam as Camera3D).current = value
	if value:
		for hud in get_tree().get_nodes_in_group("car_huds"):
			if hud.has_method("bind_car"):
				hud.call("bind_car", self)
		TuningStore.bind_car_id(car_id)


func reset_to_spawn() -> void:
	throttle = 0.0
	brake = 0.0
	handbrake = 0.0
	steering = 0.0
	_current_steer = 0.0
	_throttle_cmd = 0.0
	current_gear = 1
	engine_rpm = setup.idle_rpm if setup else 800.0
	clutch = 1.0
	_clutch_engage_timer = 0.0
	_shift_timer = 0.0
	_auto_shift_cooldown = 0.0
	want_reverse = false
	angular_damp = _base_angular_damp
	sleeping = false
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


func _cache_visual_bases() -> void:
	if _visual_bases_cached:
		return
	var model := get_node_or_null("Model") as Node3D
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if model:
		_model_base_y = model.position.y
	if col:
		_collision_base_y = col.position.y
	_visual_bases_cached = true


func refresh_visual_tuning() -> void:
	_apply_visual_tuning()


func _apply_visual_tuning() -> void:
	_cache_visual_bases()
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.position.y = _model_base_y + clearance
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.position.y = _collision_base_y + clearance


func _physics_process(delta: float) -> void:
	if setup == null:
		return
	if not _body_applied:
		_apply_body_setup()

	throttle = clampf(throttle, 0.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	handbrake = clampf(handbrake, 0.0, 1.0)
	steering = clampf(steering, -1.0, 1.0)

	_update_throttle_response(delta)

	if _shift_timer > 0.0:
		_shift_timer = maxf(_shift_timer - delta, 0.0)
	if _auto_shift_cooldown > 0.0:
		_auto_shift_cooldown = maxf(_auto_shift_cooldown - delta, 0.0)

	if automatic:
		_update_automatic_transmission()
	else:
		debug_want_up = 0
		debug_want_down = 0
		debug_shift_timer = _shift_timer
		debug_auto_cd = 0.0
		debug_est_rpm_cur = _estimate_transmission_rpm(current_gear)
		if setup != null and current_gear > 0 and current_gear < setup.get_forward_gear_count():
			debug_est_rpm_up = _estimate_transmission_rpm(current_gear + 1)
		else:
			debug_est_rpm_up = 0.0

	_update_steering(delta)

	var steps := clampi(setup.physics_substeps, 1, 8)
	var dt := delta / float(steps)
	var force_scale := 1.0 / float(steps)
	for _i in steps:
		_physics_substep(dt, force_scale)


func _physics_substep(dt: float, force_scale: float) -> void:
	_update_clutch(dt)
	_update_suspension(dt, force_scale)
	_update_anti_roll(force_scale)
	_update_engine_clutch_diff(dt)
	_apply_tire_and_wheel(dt, force_scale)
	_apply_yaw_stability(force_scale)
	_apply_aero(force_scale)


func set_setup(new_setup: CarSetup) -> void:
	setup = new_setup
	if setup == null:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	setup.ensure_steer_angle_curve()
	setup.migrate_legacy_fields()
	_body_applied = false
	_rebuild_wheels()
	if is_inside_tree():
		_apply_body_setup()


func shift_up() -> void:
	if setup == null or _shift_timer > 0.0:
		return
	var max_gear := setup.get_forward_gear_count()
	if current_gear < max_gear:
		var from_gear := current_gear
		current_gear += 1
		_begin_shift(from_gear, current_gear)
		if automatic:
			_auto_shift_cooldown = 0.7


func shift_down() -> void:
	if setup == null or _shift_timer > 0.0:
		return
	var min_gear := -1 if allow_reverse else 1
	if current_gear > min_gear:
		var from_gear := current_gear
		current_gear -= 1
		_begin_shift(from_gear, current_gear)
		if automatic:
			_auto_shift_cooldown = 0.55


func _begin_shift(from_gear: int, to_gear: int) -> void:
	_shift_timer = setup.shift_time
	clutch = 0.0
	_clutch_engage_timer = setup.clutch_engage_time
	gear_shifted.emit(from_gear, to_gear)


func toggle_transmission() -> void:
	automatic = not automatic
	want_reverse = false
	_auto_shift_cooldown = 0.0
	if automatic and current_gear <= 0:
		current_gear = 1


func get_transmission_label() -> String:
	return "АВТО" if automatic else "МЕХ"


func _estimate_transmission_rpm(gear: int) -> float:
	if setup == null:
		return 0.0
	var gear_ratio := setup.get_gear_ratio(gear)
	if absf(gear_ratio) < 0.001:
		return 0.0
	var wheel_omega := _average_driven_omega()
	var wheel_rpm := absf(wheel_omega) * 60.0 / TAU
	return wheel_rpm * absf(gear_ratio) * setup.final_drive


func _estimate_ground_transmission_rpm(gear: int) -> float:
	## RPM as if driven wheels matched body longitudinal speed (ignores wheelspin).
	if setup == null:
		return 0.0
	var gear_ratio := setup.get_gear_ratio(gear)
	if absf(gear_ratio) < 0.001:
		return 0.0
	var radius := 0.32
	if _wheels.size() >= 4:
		radius = maxf(setup.get_wheel_radius(2), 0.05)
	elif _wheels.size() > 0:
		radius = maxf(setup.get_wheel_radius(0), 0.05)
	var ground_speed := absf(linear_velocity.dot(-global_transform.basis.z))
	var wheel_rpm := (ground_speed / radius) * 60.0 / TAU
	return wheel_rpm * absf(gear_ratio) * setup.final_drive


func _max_driven_slip_ratio() -> float:
	var peak := 0.0
	for wheel in _wheels:
		if wheel.is_driven and wheel.on_ground:
			peak = maxf(peak, absf(wheel.slip_ratio))
	return peak


func _average_driven_omega() -> float:
	var sum := 0.0
	var count := 0
	for wheel in _wheels:
		if wheel.is_driven:
			sum += wheel.angular_velocity
			count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


func _update_automatic_transmission() -> void:
	debug_want_up = 0
	debug_want_down = 0
	debug_shift_timer = _shift_timer
	debug_auto_cd = _auto_shift_cooldown
	if setup == null:
		return
	debug_est_rpm_cur = _estimate_transmission_rpm(current_gear)
	if current_gear > 0 and current_gear < setup.get_forward_gear_count():
		debug_est_rpm_up = _estimate_transmission_rpm(current_gear + 1)
	else:
		debug_est_rpm_up = 0.0

	if _shift_timer > 0.0 or _auto_shift_cooldown > 0.0:
		return

	var max_gear := setup.get_forward_gear_count()
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)

	# --- Reverse / Drive selection (arcade hold-to-reverse) ---
	if not allow_reverse:
		if current_gear < 1:
			_auto_set_gear(1)
		want_reverse = false
	else:
		if want_reverse and absf(forward_speed) < 1.5:
			if current_gear != -1:
				_auto_set_gear(-1)
				_auto_shift_cooldown = 0.4
			return
		if current_gear < 0:
			# Stay in R while reversing with intent; exit near stop when intent ends.
			if not want_reverse and absf(forward_speed) < 1.0:
				_auto_set_gear(1)
				_auto_shift_cooldown = 0.4
			return
		if current_gear == 0:
			_auto_set_gear(1)
			return

	# --- Forward gears only from here ---
	if current_gear < 1:
		return

	# Upshifts use BODY speed RPM only — spinning wheels must not fake redline.
	# Do NOT hard-block on slip: with RWD burnout κ stays high and we'd sit on
	# the limiter in 1st forever. Ground RPM already refuses early burnout shifts.
	var ground_rpm := _estimate_ground_transmission_rpm(current_gear)
	var next_ground := 0.0
	if current_gear < max_gear:
		next_ground = _estimate_ground_transmission_rpm(current_gear + 1)
	var driven_slip := _max_driven_slip_ratio()
	var spinning := driven_slip > 0.35

	# Downshifts still use engine / wheel est (clutch-open coast).
	var shift_rpm := engine_rpm
	if clutch < 0.9 or absf(debug_clutch_slip_w) > 40.0:
		shift_rpm = debug_est_rpm_cur

	var up_frac := 0.72 if throttle > 0.5 else 0.62
	var want_up := false
	if current_gear < max_gear and throttle > 0.08:
		var road_ready := ground_rpm >= setup.max_rpm * up_frac
		# Escape: engine on the limiter but car already has meaningful road speed.
		var limiter_escape := (
			engine_rpm >= setup.max_rpm * 0.94
			and ground_rpm >= setup.max_rpm * 0.42
		)
		if road_ready or limiter_escape:
			if next_ground >= setup.idle_rpm * 1.15:
				want_up = true

	var want_down := false
	if current_gear > 1:
		if shift_rpm <= setup.max_rpm * 0.38 and throttle < 0.7:
			want_down = true
		elif throttle > 0.9 and shift_rpm < setup.max_rpm * 0.55:
			var rpm_if_down := _estimate_transmission_rpm(current_gear - 1)
			if rpm_if_down > 0.0 and rpm_if_down < setup.max_rpm * 0.9:
				want_down = true
		# No kickdown deeper into a lit axle.
		if spinning and throttle > 0.5:
			want_down = false

	debug_want_up = 1 if want_up else 0
	debug_want_down = 1 if want_down else 0

	if want_up and not want_down:
		_auto_set_gear(current_gear + 1)
		_auto_shift_cooldown = 0.55
	elif want_down and not want_up:
		_auto_set_gear(current_gear - 1)
		_auto_shift_cooldown = 0.5


func _auto_set_gear(gear: int) -> void:
	## Automatic path only: clamps to [-1..max] or [1..max], never lands on N.
	if setup == null:
		return
	var max_gear := setup.get_forward_gear_count()
	var min_gear := -1 if allow_reverse else 1
	var target := clampi(gear, min_gear, max_gear)
	if target == 0:
		target = 1
	if target == current_gear:
		return
	var from_gear := current_gear
	current_gear = target
	_begin_shift(from_gear, current_gear)


func set_gear(gear: int) -> void:
	if setup == null:
		return
	var max_gear := setup.get_forward_gear_count()
	var min_gear := -1 if allow_reverse else 1
	var target := clampi(gear, min_gear, max_gear)
	if target == current_gear:
		return
	var from_gear := current_gear
	current_gear = target
	_begin_shift(from_gear, current_gear)


func get_speed_ms() -> float:
	return linear_velocity.length()


func get_speed_kmh() -> float:
	return get_speed_ms() * 3.6


func get_power_hp() -> float:
	if setup == null:
		return 0.0
	return setup.max_power_hp


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
	# Scene packs used angular_damp ~2.4 which kills yaw — drifts never build.
	# REPLACE so project default linear_damp 0.1 does not combine in —
	# that alone ate ~m*0.1*|v| ≈ 3.5 kN at 90 km/h and capped 5th.
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.08
	linear_damp = 0.0
	_base_angular_damp = angular_damp
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
		_prev_lengths.append(setup.get_rest_length(i))


func _is_driven_index(index: int) -> bool:
	match setup.drive_type:
		CarSetup.DriveType.FWD:
			return index < 2
		CarSetup.DriveType.RWD:
			return index >= 2
		CarSetup.DriveType.AWD:
			return true
	return index >= 2


func _update_throttle_response(delta: float) -> void:
	## Soften gas onset without capping steer angle (full opposite lock stays available).
	var target := throttle
	var rise := maxf(setup.throttle_rise_rate, 0.1)
	var fall := maxf(setup.throttle_fall_rate, 0.1)
	var rate := rise if target > _throttle_cmd else fall
	_throttle_cmd = move_toward(_throttle_cmd, target, rate * delta)


func _update_steering(delta: float) -> void:
	## Full lock at any speed — needed to catch a slide with opposite lock.
	var target := steering * deg_to_rad(setup.max_steer_angle)
	_current_steer = move_toward(_current_steer, target, setup.steer_speed * delta)
	debug_steer_rad = _current_steer
	debug_steer_lock = 1.0
	debug_steer_target = target
	for wheel in _wheels:
		wheel.steer_angle = _current_steer if wheel.is_steering else 0.0


func _update_clutch(dt: float) -> void:
	if setup == null:
		return
	if current_gear == 0 or _shift_timer > 0.0:
		clutch = 0.0
		_clutch_engage_timer = setup.clutch_engage_time
		return
	if _clutch_engage_timer > 0.0:
		_clutch_engage_timer = maxf(_clutch_engage_timer - dt, 0.0)
		var engage := setup.clutch_engage_time
		if engage <= 0.001:
			clutch = 1.0
		else:
			clutch = 1.0 - (_clutch_engage_timer / engage)
	else:
		clutch = 1.0


func _update_suspension(dt: float, force_scale: float) -> void:
	var space := get_world_3d().direct_space_state
	var exclude := [get_rid()]
	var max_force := setup.mass * 9.81 * 4.5
	var safe_dt := maxf(dt, 0.0001)

	for i in _wheels.size():
		var wheel := _wheels[i]
		wheel.reset_forces()

		var rest := setup.get_rest_length(i)
		var travel := setup.get_travel(i)
		var ray_length := rest + travel
		var stiffness := setup.get_stiffness(i)

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
			wheel.normal_load = 0.0
			_prev_lengths[i] = ray_length
			continue

		wheel.on_ground = true
		wheel.hit_point = hit.position
		wheel.hit_normal = hit.normal.normalized()
		var spring_length := origin_world.distance_to(hit.position)
		wheel.suspension_length = spring_length

		var compression_distance := rest - spring_length
		var compression := clampf(
			compression_distance / maxf(travel, 0.001),
			0.0,
			1.0
		)
		wheel.compression = compression

		# Damper MUST track spring length rate. Using mount_velocity.dot(up)
		# pumped the body upward under hard handbrake (pitch / scrub looked
		# like extension to the damper) and only settled after stop.
		var length_rate := (spring_length - _prev_lengths[i]) / safe_dt
		length_rate = clampf(length_rate, -12.0, 12.0)
		var spring_travel := clampf(compression_distance, 0.0, travel)
		var spring_force := stiffness * spring_travel
		# length_rate > 0 → spring extending → rebound.
		var damp_coeff := setup.get_damping(i, length_rate)
		var damper_force := -damp_coeff * length_rate
		# Rebound must not erase support while still compressed (anti jack-up).
		if damper_force < 0.0 and spring_force > 0.0:
			damper_force = maxf(damper_force, -spring_force * 0.75)

		var bump := 0.0
		if compression_distance > travel:
			var overrun := compression_distance - travel
			bump = stiffness * overrun * 3.0 + setup.mass * 9.81 * overrun * 8.0
		elif compression > 0.75:
			var t := (compression - 0.75) / 0.25
			bump = t * t * setup.mass * 9.81

		wheel.suspension_force = clampf(spring_force + damper_force + bump, 0.0, max_force)
		wheel.normal_load = wheel.suspension_force
		_prev_lengths[i] = spring_length

		var force_vec := wheel.hit_normal * wheel.suspension_force * force_scale
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


func _update_anti_roll(force_scale: float) -> void:
	if _wheels.size() < 4:
		return
	_apply_anti_roll_pair(0, 1, true, force_scale)
	_apply_anti_roll_pair(2, 3, false, force_scale)


func _apply_anti_roll_pair(left_i: int, right_i: int, axle_front: bool, force_scale: float) -> void:
	var bar := setup.get_anti_roll(axle_front)
	if bar <= 0.0:
		return
	var left := _wheels[left_i]
	var right := _wheels[right_i]
	if not left.on_ground and not right.on_ground:
		return
	var diff := left.compression - right.compression
	var force := diff * bar * force_scale
	if left.on_ground:
		var left_origin := to_global(left.local_origin)
		apply_force(left.hit_normal * force, left_origin - global_position)
	if right.on_ground:
		var right_origin := to_global(right.local_origin)
		apply_force(right.hit_normal * -force, right_origin - global_position)


func _update_engine_clutch_diff(dt: float) -> void:
	var gear_ratio := setup.get_gear_ratio(current_gear)
	var engine_omega := engine_rpm * TAU / 60.0
	var idle_omega := setup.idle_rpm * TAU / 60.0
	var max_omega := setup.max_rpm * TAU / 60.0

	var effective_throttle := _throttle_cmd
	_rev_limiter_cut = _update_rev_limiter_cut(engine_rpm)
	rev_limiter_active = _rev_limiter_cut
	debug_rev_limiter_cut = _rev_limiter_cut
	if _rev_limiter_cut:
		effective_throttle = 0.0
	elif throttle < 0.05:
		# Cut fuel immediately on pedal release — don't wait for _throttle_cmd bleed.
		effective_throttle = 0.0
	debug_eff_throttle = effective_throttle

	var combustion := setup.get_engine_torque(engine_rpm) * effective_throttle
	var engine_friction := 12.0 + 0.004 * engine_rpm
	if throttle < 0.05:
		var coast := setup.engine_coast_friction_scale
		engine_friction += coast * (14.0 + 0.018 * engine_rpm)
		combustion = -engine_friction
	elif _rev_limiter_cut:
		engine_friction += 0.35 * (10.0 + 0.012 * engine_rpm)
		combustion = -engine_friction

	var in_gear := absf(gear_ratio) > 0.001
	var trans_omega := 0.0
	if in_gear:
		trans_omega = _average_driven_omega() * gear_ratio * setup.final_drive

	var clutch_torque := 0.0
	var slip_w := 0.0
	if in_gear and clutch > 0.001:
		slip_w = engine_omega - trans_omega
		var max_t := clutch * setup.clutch_max_torque
		# Locked enough: pass combustion + soft slip sync.
		# Old slip*180 slammed ±max at |slip|≳5 and still pumped engine-brake.
		var lock_band := 40.0
		if clutch >= 0.95 and absf(slip_w) < lock_band:
			var sync := clampf(slip_w * 28.0, -max_t * 0.25, max_t * 0.25)
			clutch_torque = clampf(combustion + sync, -max_t, max_t)
			if throttle > 0.1:
				clutch_torque = maxf(clutch_torque, -max_t * 0.08)
			engine_omega = lerpf(engine_omega, trans_omega, clampf(10.0 * dt, 0.0, 1.0))
			slip_w = engine_omega - trans_omega
		elif throttle < 0.05:
			# Idle / coast slip: soft viscous coupling only.
			clutch_torque = clampf(slip_w * 12.0, -60.0, 60.0)
		else:
			# Kinetic: viscous slip toward combustion — NEVER full ±max slam.
			# Old dir*max_t flipped driveline ±8kNm every substep and erased accel.
			var slip_limit := max_t * clampf(maxf(_throttle_cmd, throttle), 0.15, 1.0)
			var target := combustion + slip_w * 45.0
			# Under power, cap engine-brake so the clutch can't haul the car down.
			if throttle > 0.1:
				target = maxf(target, -slip_limit * 0.08)
			clutch_torque = clampf(target, -slip_limit, slip_limit)

	var net_engine := combustion - clutch_torque
	var i_e := maxf(setup.engine_inertia, 0.05)
	engine_omega += (net_engine / i_e) * dt
	engine_omega = clampf(engine_omega, idle_omega * 0.5, max_omega)
	# Hold idle when clutch open / neutral.
	if not in_gear or clutch < 0.05:
		if throttle < 0.05 and engine_omega < idle_omega:
			engine_omega = move_toward(engine_omega, idle_omega, 40.0 * dt)
	elif engine_omega < idle_omega and throttle < 0.02:
		engine_omega = idle_omega
	engine_rpm = engine_omega * 60.0 / TAU

	# Brake torques per wheel (service bias + handbrake rear).
	for i in _wheels.size():
		var wheel := _wheels[i]
		var bias := setup.brake_bias_front if wheel.is_steering else (1.0 - setup.brake_bias_front)
		# Two wheels per axle share the axle bias.
		var service := setup.brake_force * brake * bias * 0.5
		var hb := 0.0
		if not wheel.is_steering:
			hb = setup.handbrake_force * handbrake * 0.5
		wheel.brake_torque = service + hb

	# Driveline torque at wheels from clutch * ratios.
	var driveline := 0.0
	if in_gear:
		driveline = clutch_torque * gear_ratio * setup.final_drive

	# Parked / idle: no creep. Softly settle body instead of locking tires
	# (hard brake was causing κ-smoke on all four while the car eased backward).
	# Only when planted — never damp freefall after spawn.
	var horiz_speed := Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	var parked := (
		throttle < 0.05
		and brake < 0.05
		and handbrake < 0.05
		and horiz_speed < 1.25
		and absf(linear_velocity.y) < 0.6
		and _is_planted()
	)
	if parked:
		driveline = 0.0
		clutch_torque = 0.0

	debug_eng_combustion = combustion
	debug_clutch_torque = clutch_torque
	debug_trans_rpm = trans_omega * 60.0 / TAU
	debug_clutch_slip_w = slip_w
	debug_driveline = driveline
	debug_gear_ratio = gear_ratio
	debug_shift_timer = _shift_timer

	_assign_drive_torques(driveline)
	_apply_traction_control()
	_update_spin_debug()
	if parked:
		# Must run AFTER torque assign — old order re-applied welded ±24kNm
		# and fought settle every substep.
		_settle_parked(dt)


func _update_rev_limiter_cut(rpm: float) -> bool:
	if setup == null or throttle < 0.3:
		return false
	var cut_high := setup.max_rpm * setup.rev_limiter_cut_high_frac
	var cut_low := minf(setup.max_rpm * setup.rev_limiter_cut_low_frac, cut_high - 50.0)
	if rpm >= cut_high:
		return true
	if rpm <= cut_low:
		return false
	return _rev_limiter_cut


func _is_planted() -> bool:
	var grounded := 0
	for wheel in _wheels:
		if wheel.on_ground:
			grounded += 1
	return grounded >= 2


func _settle_parked(dt: float) -> void:
	## Bleed residual ground crawl without killing freefall or tire-lock smoke.
	var damp := clampf(12.0 * dt, 0.0, 1.0)
	var v := linear_velocity
	v.x = lerpf(v.x, 0.0, damp)
	v.z = lerpf(v.z, 0.0, damp)
	if absf(v.y) < 0.35:
		v.y = lerpf(v.y, 0.0, damp)
	linear_velocity = v
	angular_velocity = angular_velocity.lerp(Vector3.ZERO, damp)
	if Vector3(v.x, 0.0, v.z).length() < 0.08 and absf(v.y) < 0.08:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	for wheel in _wheels:
		wheel.angular_velocity = move_toward(wheel.angular_velocity, 0.0, 40.0 * dt)
		wheel.drive_torque = 0.0
		wheel.brake_torque = 0.0


func _assign_drive_torques(driveline_torque: float) -> void:
	for wheel in _wheels:
		wheel.drive_torque = 0.0

	if _wheels.size() < 4:
		return

	var torques: PackedFloat32Array = _VehicleDiff.split_driveline(
		driveline_torque,
		int(setup.drive_type),
		setup.awd_front_bias,
		_wheels[0].angular_velocity,
		_wheels[1].angular_velocity,
		_wheels[2].angular_velocity,
		_wheels[3].angular_velocity,
		int(setup.rear_diff_type),
		setup.diff_preload,
		setup.diff_power_lock,
		setup.diff_coast_lock,
		setup.locked_diff_stiffness
	)
	for i in 4:
		_wheels[i].drive_torque = torques[i]


func _update_spin_debug() -> void:
	debug_rear_spin = 0
	if _wheels.size() < 4:
		return
	if absf(_wheels[2].slip_ratio) > 0.2 or absf(_wheels[3].slip_ratio) > 0.2:
		debug_rear_spin = 1


func _apply_traction_control() -> void:
	## Past Pacejka peak, more spin means less Fx — slow accel and no lateral grip.
	## Cut drive torque when |κ| exceeds the target so tires stay near peak.
	debug_tc_scale = 1.0
	if setup == null or not setup.traction_control:
		return
	var target := setup.tc_slip_ratio
	var gain := setup.tc_gain
	var scale_sum := 0.0
	var scale_n := 0
	var floor_cut := setup.tc_min_scale
	for wheel in _wheels:
		if absf(wheel.drive_torque) < 0.01:
			continue
		# Power spin only (same sign). Coast/brake slip is left alone.
		if wheel.drive_torque * wheel.slip_ratio <= 0.0:
			scale_sum += 1.0
			scale_n += 1
			continue
		var over := absf(wheel.slip_ratio) - target
		var cut := 1.0
		if over > 0.0:
			cut = clampf(1.0 - over * gain, floor_cut, 1.0)
			wheel.drive_torque *= cut
		scale_sum += cut
		scale_n += 1
	if scale_n > 0:
		debug_tc_scale = scale_sum / float(scale_n)


func _apply_tire_and_wheel(dt: float, force_scale: float) -> void:
	var wheel_i := maxf(setup.wheel_inertia, 0.15)
	var static_wheel_load := setup.mass * 9.81 * 0.25
	var min_load := static_wheel_load * setup.min_load_fraction

	for i in _wheels.size():
		var wheel := _wheels[i]
		var radius := maxf(setup.get_wheel_radius(i), 0.05)
		if not wheel.on_ground:
			_integrate_wheel_omega(wheel, 0.0, radius, wheel_i, dt)
			wheel.slip_ratio = 0.0
			wheel.slip_angle = 0.0
			continue

		var point_velocity := _velocity_at_point(wheel.hit_point)
		var long_speed := point_velocity.dot(wheel.forward)
		var lat_speed := point_velocity.dot(wheel.right)

		var fz := maxf(wheel.suspension_force, min_load)
		wheel.normal_load = fz

		var slip: Vector2 = _TireModel.compute_slip(
			long_speed,
			lat_speed,
			wheel.angular_velocity,
			radius,
			setup.tire_v_low
		)
		wheel.slip_ratio = slip.x
		wheel.slip_angle = slip.y

		var forces: Vector2 = _TireModel.evaluate(
			slip.x,
			slip.y,
			fz,
			setup.get_tire_mu(i),
			setup.pacejka_b_long,
			setup.pacejka_c_long,
			setup.pacejka_e_long,
			setup.pacejka_b_lat,
			setup.pacejka_c_lat,
			setup.pacejka_e_lat
		)

		var rr := -signf(long_speed) * setup.rolling_resistance * fz
		if absf(long_speed) < 0.05:
			rr = 0.0

		wheel.long_force = forces.x + rr
		wheel.lat_force = forces.y
		# Handbrake: dump rear cornering + soften residual lock Fx so pitch
		# doesn't jack the body up on the springs while yaw builds.
		if handbrake > 0.001 and not wheel.is_steering:
			var hb_lat := lerpf(1.0, setup.handbrake_lat_grip, handbrake)
			wheel.lat_force *= hb_lat
			wheel.long_force *= lerpf(1.0, 0.5, handbrake)

		var tire_force := wheel.forward * wheel.long_force + wheel.right * wheel.lat_force
		tire_force = tire_force - wheel.hit_normal * tire_force.dot(wheel.hit_normal)
		apply_force(tire_force * force_scale, wheel.hit_point - global_position)

		_integrate_wheel_omega(wheel, wheel.long_force, radius, wheel_i, dt)

	_sync_welded_rear_axle(dt)


func _apply_yaw_stability(force_scale: float) -> void:
	## Soft chassis assist scaled by setup.drift_assist.
	## 0 = pure sim (tires only), 1 = default hold, >1 = stronger.
	if setup == null or setup.drift_assist <= 0.001:
		debug_yaw_assist_nm = 0.0
		debug_body_slip_deg = 0.0
		return

	const MIN_SPEED_MS := 6.0
	const ENTER_DEG := 8.0
	const HOLD_DEG := 28.0
	const SPIN_DEG := 48.0
	const BASE_DAMP_DRIFT := 2200.0
	const BASE_DAMP_SPIN := 5200.0
	const BASE_BETA_RESTORE := 4500.0
	const BASE_MAX_TORQUE := 9000.0

	var assist := clampf(setup.drift_assist, 0.0, 2.0)
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	var v_long := linear_velocity.dot(forward)
	var v_lat := linear_velocity.dot(right)
	var speed_h := Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	var beta := atan2(v_lat, maxf(absf(v_long), 0.8))
	debug_body_slip_deg = rad_to_deg(beta)

	if speed_h < MIN_SPEED_MS:
		debug_yaw_assist_nm = 0.0
		return

	var abs_beta := absf(beta)
	var enter := deg_to_rad(ENTER_DEG)
	var hold := deg_to_rad(HOLD_DEG)
	var spin := deg_to_rad(SPIN_DEG)

	# Grip zone: no assist — high-speed corner entry stays on tires alone.
	if abs_beta < enter:
		debug_yaw_assist_nm = 0.0
		return

	var yaw_rate := angular_velocity.dot(up)
	var thr := clampf(_throttle_cmd, 0.0, 1.0)

	var t_drift := clampf((abs_beta - enter) / maxf(hold - enter, 0.001), 0.0, 1.0)
	var damp := BASE_DAMP_DRIFT * assist * t_drift * lerpf(0.4, 1.0, thr)

	var opening := yaw_rate * beta > 0.0
	if opening:
		damp *= 1.35
	else:
		damp *= 0.55

	var steer_into := _current_steer * beta > 0.0 and absf(steering) > 0.25
	if steer_into and thr > 0.15:
		damp *= 0.65

	var restore := 0.0
	if abs_beta > hold:
		var t_spin := clampf((abs_beta - hold) / maxf(spin - hold, 0.001), 0.0, 1.0)
		damp += BASE_DAMP_SPIN * assist * t_spin
		restore = BASE_BETA_RESTORE * assist * t_spin

	var max_tq := BASE_MAX_TORQUE * assist
	var torque_nm := -damp * yaw_rate - restore * beta
	torque_nm = clampf(torque_nm, -max_tq, max_tq)
	debug_yaw_assist_nm = torque_nm
	if absf(torque_nm) < 1.0:
		return
	apply_torque(up * (torque_nm * force_scale))


func _sync_welded_rear_axle(dt: float) -> void:
	## Soft spool: pull both rear wheels toward a common shaft speed.
	## Hard overwrite made every throttle+steer input a permanent spin-out.
	if setup == null or setup.rear_diff_type != CarSetup.RearDiffType.WELDED:
		return
	if _wheels.size() < 4:
		return
	var left := _wheels[2]
	var right := _wheels[3]
	if not left.is_driven and not right.is_driven:
		return
	var avg := (left.angular_velocity + right.angular_velocity) * 0.5
	var rate := clampf(setup.locked_diff_stiffness * 0.02, 12.0, 60.0)
	var blend := clampf(rate * dt, 0.0, 1.0)
	left.angular_velocity = lerpf(left.angular_velocity, avg, blend)
	right.angular_velocity = lerpf(right.angular_velocity, avg, blend)


func _integrate_wheel_omega(
	wheel: Wheel,
	fx: float,
	radius: float,
	wheel_inertia: float,
	dt: float
) -> void:
	var tau_tire := -fx * radius
	var tau_drive := wheel.drive_torque
	var tau_brake := 0.0
	if wheel.brake_torque > 0.0:
		# Brake opposes spin; clamps toward zero.
		var opposing := -signf(wheel.angular_velocity)
		if absf(wheel.angular_velocity) < 0.05:
			# Holding torque at rest - cancel drive if smaller than brake.
			if absf(tau_drive + tau_tire) <= wheel.brake_torque:
				wheel.angular_velocity = 0.0
				return
			opposing = -signf(tau_drive + tau_tire)
		tau_brake = opposing * wheel.brake_torque

	var alpha := (tau_drive + tau_brake + tau_tire) / wheel_inertia
	var new_omega := wheel.angular_velocity + alpha * dt

	# Prevent brake from reversing wheel through zero in one step.
	if wheel.brake_torque > 0.0 and wheel.angular_velocity * new_omega < 0.0:
		new_omega = 0.0

	wheel.angular_velocity = new_omega


func _velocity_at_point(world_point: Vector3) -> Vector3:
	var local := world_point - global_position
	return linear_velocity + angular_velocity.cross(local)


func _apply_aero(force_scale: float) -> void:
	## Drag only in the horizontal plane so pitch/bounce can't turn aero into lift.
	## Downforce always pulls toward world floor (plants the car at speed).
	var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var speed_h := horiz.length()
	if speed_h < 0.05:
		return
	var q := 0.5 * setup.air_density * speed_h * speed_h
	var drag := -horiz.normalized() * (setup.drag_coefficient * setup.frontal_area * q)
	var down := Vector3.DOWN * (setup.downforce_coefficient * setup.frontal_area * q)
	apply_central_force((drag + down) * force_scale)
