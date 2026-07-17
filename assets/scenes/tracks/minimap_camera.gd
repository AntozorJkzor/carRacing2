extends Camera3D

@export var target_path: NodePath
@export var follow_height: float = 80.0
@export var ortho_size: float = 165.0
@export var size_min: float = 40.0
@export var size_max: float = 6400.0
@export var zoom_step: float = 400.0
@export var zoom_smooth: float = 10.0

var _target: Node3D
var _size_target: float = 165.0


func _ready() -> void:
	top_level = true
	projection = PROJECTION_ORTHOGONAL
	_size_target = ortho_size
	size = ortho_size
	near = 0.5
	far = follow_height * 2.5
	current = true
	_resolve_target()
	if _target != null:
		_sync_transform()


func set_target(target: Node3D) -> void:
	_target = target
	if target != null and is_inside_tree():
		target_path = get_path_to(target)
		_sync_transform()


func nudge_zoom(delta_size: float) -> void:
	_size_target = clampf(_size_target + delta_size, size_min, size_max)


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		_resolve_target()
	size = lerpf(size, _size_target, clampf(zoom_smooth * delta, 0.0, 1.0))
	ortho_size = size
	if _target == null:
		return
	_sync_transform()


func _sync_transform() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		return
	var p := _target.global_position
	global_position = Vector3(p.x, p.y + follow_height, p.z)
	# Keep a locked top-down view regardless of UI / parent transforms.
	global_basis = Basis(Vector3.RIGHT, -PI * 0.5)


func _resolve_target() -> void:
	if target_path == NodePath():
		return
	_target = get_node_or_null(target_path) as Node3D
