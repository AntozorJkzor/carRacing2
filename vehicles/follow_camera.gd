extends Camera3D

## Orbit camera: fixed distance around car center, mouse yaw/pitch. No speed zoom / chase lag.

@export var target_path: NodePath
@export var follow_distance: float = 7.0
@export var follow_height: float = 2.2
@export var look_height: float = 0.9
## How quickly the look-pivot follows the car (1/s). Keep modest to avoid shake, not speed-scaled.
@export var pivot_lerp: float = 12.0
@export var mouse_sensitivity: float = 0.004
@export var pitch_min_deg: float = -10.0
@export var pitch_max_deg: float = 65.0

var _target: Node3D
var _active: bool = false
## Yaw offset from behind the car (radians). Mouse X.
var _orbit_yaw: float = 0.0
## Pitch from horizontal (radians). Mouse Y. 0 = level with look point + height offset.
var _orbit_pitch: float = 0.25
var _pivot: Vector3 = Vector3.ZERO
var _pivot_ready: bool = false


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
		_orbit_pitch = 0.25
		_pivot_ready = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_target(target: Node3D) -> void:
	_target = target
	_pivot_ready = false
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
	var desired_pivot := _target.global_position + up * look_height
	if not _pivot_ready:
		_pivot = desired_pivot
		_pivot_ready = true
	else:
		var w := clampf(pivot_lerp * delta, 0.0, 1.0)
		_pivot = _pivot.lerp(desired_pivot, w)

	# Behind the car in local space, then mouse orbit around the pivot.
	var car_back := _flat_back_from_target(_target)
	var offset := car_back * follow_distance
	offset = offset.rotated(up, _orbit_yaw)

	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.0001:
		var right := up.cross(flat.normalized()).normalized()
		offset = offset.rotated(right, _orbit_pitch)

	offset.y += follow_height
	global_position = _pivot + offset
	look_at(_pivot, up)


func _flat_back_from_target(target: Node3D) -> Vector3:
	var back := target.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return Vector3.FORWARD
	return back.normalized()
