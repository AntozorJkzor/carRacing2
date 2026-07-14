extends Camera3D

@export var target_path: NodePath
@export var follow_distance: float = 2.0
@export var follow_height: float = 0.85
@export var look_ahead: float = 1.5
@export var look_height: float = 0.7
@export var position_lerp: float = 6.0
@export var rotation_lerp: float = 8.0
@export var mouse_sensitivity: float = 0.005
@export var pitch_min_deg: float = -15.0
@export var pitch_max_deg: float = 60.0
## How fast chase "behind" follows car heading / velocity (1/s).
@export var chase_heading_lerp: float = 4.0
## Above this horizontal speed (m/s), prefer velocity as chase direction.
@export var velocity_chase_speed: float = 6.0

var _target: Node3D
var _active: bool = false
## Yaw offset from behind the chase frame (radians). Mouse X.
var _orbit_yaw: float = 0.0
## Extra pitch on top of the default chase angle (radians). Mouse Y.
var _orbit_pitch: float = 0.0
## Flattened, smoothed "behind car" direction (world XZ).
var _chase_back: Vector3 = Vector3.FORWARD
## Brief boost after mouse orbit so lag at speed does not eat the turn.
var _orbit_boost: float = 0.0


func _ready() -> void:
	add_to_group("car_follow_cameras")
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	set_process_input(true)
	set_active(false)


func set_active(value: bool) -> void:
	_active = value
	current = value
	if value:
		_orbit_yaw = 0.0
		_orbit_pitch = 0.0
		_orbit_boost = 0.0
		_chase_back = Vector3.FORWARD
		if _target != null:
			_chase_back = _flat_back_from_target(_target)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_target(target: Node3D) -> void:
	_target = target
	if target != null:
		target_path = get_path_to(target) if is_inside_tree() else target_path
		_chase_back = _flat_back_from_target(target)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _target == null and target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var looking := (
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			or (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0
		)
		if not looking:
			return
		_orbit_yaw -= motion.relative.x * mouse_sensitivity
		_orbit_pitch -= motion.relative.y * mouse_sensitivity
		_orbit_pitch = clampf(
			_orbit_pitch,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg)
		)
		# Keep orbit responsive even when the car is flying down the road.
		_orbit_boost = 1.0
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _target == null and target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		return

	_orbit_boost = move_toward(_orbit_boost, 0.0, delta * 2.2)

	var up := Vector3.UP
	var desired_back := _desired_chase_back(_target)
	var heading_w := clampf(chase_heading_lerp * delta, 0.0, 1.0)
	# While orbiting, freeze chase heading more so mouse yaw is not cancelled by car spin.
	if absf(_orbit_yaw) > 0.35 or _orbit_boost > 0.05:
		heading_w *= 0.25
	_chase_back = _chase_back.slerp(desired_back, heading_w).normalized()

	var offset := _chase_back * follow_distance + up * follow_height
	offset = offset.rotated(up, _orbit_yaw)

	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.0001:
		var right := up.cross(flat.normalized()).normalized()
		offset = offset.rotated(right, _orbit_pitch)

	var desired_pos := _target.global_position + offset

	# At high speed camera lag makes orbit feel stuck — scale follow + orbit boost.
	var speed := _horiz_speed(_target)
	var speed_boost := lerpf(1.0, 3.2, clampf(speed / 35.0, 0.0, 1.0))
	var orbit_boost := lerpf(1.0, 2.8, _orbit_boost)
	var pos_w := clampf(position_lerp * speed_boost * orbit_boost * delta, 0.0, 1.0)
	# Hard snap horizontal chase when actively dragging orbit at speed.
	if _orbit_boost > 0.35 and speed > velocity_chase_speed:
		var snapped := desired_pos
		snapped.y = lerpf(global_position.y, desired_pos.y, pos_w)
		global_position = global_position.lerp(snapped, clampf(pos_w * 1.5, 0.0, 1.0))
	else:
		global_position = global_position.lerp(desired_pos, pos_w)

	var look_forward := -_chase_back
	var look_at_pos := _target.global_position + look_forward * look_ahead + up * look_height
	var side_blend := clampf(absf(_orbit_yaw) / (PI * 0.45), 0.0, 1.0)
	var car_focus := _target.global_position + up * look_height
	look_at_pos = look_at_pos.lerp(car_focus, side_blend)

	var to_look := look_at_pos - global_position
	if to_look.length_squared() < 0.0001:
		return
	var desired_basis := Basis.looking_at(to_look, up)
	var rot_w := clampf(rotation_lerp * speed_boost * lerpf(1.0, 1.8, _orbit_boost) * delta, 0.0, 1.0)
	global_transform.basis = global_transform.basis.slerp(desired_basis, rot_w).orthonormalized()


func _desired_chase_back(target: Node3D) -> Vector3:
	## Prefer velocity direction when moving — stable at speed vs noisy body yaw.
	var body_back := _flat_back_from_target(target)
	var vel := _horiz_velocity(target)
	var speed := vel.length()
	if speed < velocity_chase_speed:
		return body_back
	# Camera sits behind motion: opposite of travel direction.
	var vel_back := (-vel / speed)
	# Blend so low speed still respects car facing (parking / reverse).
	var t := clampf((speed - velocity_chase_speed) / 12.0, 0.0, 1.0)
	return body_back.slerp(vel_back, t).normalized()


func _flat_back_from_target(target: Node3D) -> Vector3:
	var back := target.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return Vector3.FORWARD
	return back.normalized()


func _horiz_velocity(target: Node3D) -> Vector3:
	if target is RigidBody3D:
		var v: Vector3 = (target as RigidBody3D).linear_velocity
		return Vector3(v.x, 0.0, v.z)
	if target is CharacterBody3D:
		var v2: Vector3 = (target as CharacterBody3D).velocity
		return Vector3(v2.x, 0.0, v2.z)
	return Vector3.ZERO


func _horiz_speed(target: Node3D) -> float:
	return _horiz_velocity(target).length()
