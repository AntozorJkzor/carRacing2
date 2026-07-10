extends Camera3D

@export var target_path: NodePath
@export var follow_distance: float = 8.0
@export var follow_height: float = 3.2
@export var look_ahead: float = 6.0
@export var position_lerp: float = 6.0
@export var rotation_lerp: float = 8.0

var _target: Node3D
var _active: bool = false


func _ready() -> void:
	add_to_group("car_follow_cameras")
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	set_active(false)


func set_active(value: bool) -> void:
	_active = value
	current = value


func _physics_process(delta: float) -> void:
	if not _active or _target == null:
		return

	var back := _target.global_transform.basis.z.normalized()
	var up := Vector3.UP
	var desired_pos := _target.global_position + back * follow_distance + up * follow_height
	global_position = global_position.lerp(desired_pos, clampf(position_lerp * delta, 0.0, 1.0))

	var look_at_pos := _target.global_position - back * look_ahead + up * 0.8
	var desired_basis := Basis.looking_at(look_at_pos - global_position, up)
	global_transform.basis = global_transform.basis.slerp(desired_basis, clampf(rotation_lerp * delta, 0.0, 1.0)).orthonormalized()
