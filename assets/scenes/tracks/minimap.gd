extends PanelContainer

## Fallback when no target is bound yet (usually the on-foot player).
@export var player_path: NodePath = NodePath("../../Player")

@onready var _sub_viewport: SubViewport = $MapFrame/SubViewportContainer/SubViewport
@onready var _camera: Camera3D = $MapFrame/SubViewportContainer/SubViewport/MinimapCamera
@onready var _marker: Control = $MapFrame/MarkerOverlay

var _target: Node3D


func _ready() -> void:
	call_deferred("_bind_world")
	call_deferred("_bind_initial_target")


func bind_target(node: Node3D) -> void:
	_target = node
	if _camera != null and _camera.has_method("set_target"):
		_camera.set_target(node)


func bind_car(car: Node3D) -> void:
	bind_target(car)


func _bind_world() -> void:
	var main_vp := get_viewport()
	if main_vp != null and _sub_viewport != null:
		_sub_viewport.world_3d = main_vp.world_3d


func _bind_initial_target() -> void:
	if _target != null:
		return
	var player := _find_on_foot_player()
	if player != null:
		bind_target(player)
		return
	if player_path != NodePath():
		var node := get_node_or_null(player_path) as Node3D
		if node != null:
			bind_target(node)


func _find_on_foot_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player_character"):
		if node.has_method("is_on_foot") and node.call("is_on_foot"):
			return node as Node3D
	return null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		_bind_initial_target()
	if _target == null:
		return
	if _marker != null and _marker.has_method("set_heading"):
		_marker.set_heading(_flat_yaw(_target))


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or not _camera.has_method("nudge_zoom"):
		return
	var step := float(_camera.get("zoom_step")) if "zoom_step" in _camera else 20.0
	if event.is_action_pressed("camera_zoom_in"):
		# Smaller ortho size = closer.
		_camera.nudge_zoom(-step)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		_camera.nudge_zoom(step)
		get_viewport().set_input_as_handled()


func _flat_yaw(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	var forward := -node.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = node.global_transform.basis.x
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	# Local marker tip points up (-Y); world forward -Z maps to yaw 0.
	return atan2(forward.x, -forward.z)
