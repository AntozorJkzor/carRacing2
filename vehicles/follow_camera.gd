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

var _target: Node3D
var _active: bool = false
## Yaw offset from behind the car (radians). Mouse X.
var _orbit_yaw: float = 0.0
## Extra pitch on top of the default chase angle (radians). Mouse Y.
var _orbit_pitch: float = 0.0


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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_target(target: Node3D) -> void:
	_target = target
	if target != null:
		target_path = get_path_to(target) if is_inside_tree() else target_path


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _target == null and target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		return

	if event is InputEventMouseMotion:
		# Captured look, or drag with RMB if cursor is free.
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
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _target == null and target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		return

	var up := Vector3.UP
	var back := _target.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		back = Vector3.FORWARD
	else:
		back = back.normalized()

	var offset := back * follow_distance + up * follow_height
	offset = offset.rotated(up, _orbit_yaw)

	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.0001:
		var right := up.cross(flat.normalized()).normalized()
		offset = offset.rotated(right, _orbit_pitch)

	var desired_pos := _target.global_position + offset
	global_position = global_position.lerp(desired_pos, clampf(position_lerp * delta, 0.0, 1.0))

	var look_at_pos := _target.global_position - back * look_ahead + up * look_height
	var side_blend := clampf(absf(_orbit_yaw) / (PI * 0.5), 0.0, 1.0)
	var car_focus := _target.global_position + up * look_height
	look_at_pos = look_at_pos.lerp(car_focus, side_blend)

	var to_look := look_at_pos - global_position
	if to_look.length_squared() < 0.0001:
		return
	var desired_basis := Basis.looking_at(to_look, up)
	global_transform.basis = global_transform.basis.slerp(
		desired_basis, clampf(rotation_lerp * delta, 0.0, 1.0)
	).orthonormalized()
