@tool
extends Node3D

## Spawns 4 visual wheel meshes and syncs them to raycast Wheel physics.
## Typical game setup: body mesh without wheels + separate tire meshes
## that follow contact points, steer yaw, and spin from ω.
## Brake discs / rotors (names: brake, rotor, disc, disk, caliper) stay on the hub:
## same scale + steer as the wheel, but they do not spin.
## In the editor, WheelLayout owns the previews — this node stays idle.

## Optional override. If empty, uses CarController.wheel_scene from the car pack.
@export var wheel_scene: PackedScene
@export var mirror_right: bool = true
## Extra mesh rotation if the GLB axle is not along +X (degrees).
@export var mesh_euler_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale: float = 2.875:
	set(value):
		mesh_scale = value
		_on_scale_export_changed()
@export var front_mesh_scale: float = 2.875:
	set(value):
		front_mesh_scale = value
		_on_scale_export_changed()
@export var rear_mesh_scale: float = 2.875:
	set(value):
		rear_mesh_scale = value
		_on_scale_export_changed()

const _STATIC_PART_KEYS: PackedStringArray = [
	"brake", "rotor", "disc", "disk", "caliper", "pads",
]

@onready var _car: CarController = get_parent() as CarController

var _hubs: Array[Node3D] = []
var _spinners: Array[Node3D] = []
var _spin_angle: Array[float] = []
## +1 normally; kept for compatibility if a side needs spin flip.
var _spin_sign: Array[float] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rebuild()


func _on_scale_export_changed() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or _hubs.is_empty():
		return
	_rebuild()


func resolve_wheel_scene() -> PackedScene:
	if wheel_scene != null:
		return wheel_scene
	if _car != null and _car.wheel_scene != null:
		return _car.wheel_scene
	return null


func _physics_process(delta: float) -> void:
	FrameClock.measure("phys:visual_wheels", _profiled_physics_process, delta)


func _profiled_physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _car == null or _car.setup == null:
		return
	var wheels = _car.get_wheels()
	if wheels.size() != _hubs.size():
		_rebuild()
		wheels = _car.get_wheels()
	if wheels.is_empty():
		return

	var radius = maxf(_car.setup.get_wheel_radius(0), 0.05)
	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var hub = _hubs[i]
		var spinner = _spinners[i]
		radius = maxf(_car.setup.get_wheel_radius(i), 0.05)

		var center_world: Vector3
		var up: Vector3
		var forward: Vector3
		var right: Vector3
		if wheel.on_ground:
			up = wheel.up
			forward = wheel.forward
			right = wheel.right
			center_world = wheel.hit_point + up * radius
		else:
			up = _car.global_transform.basis.y.normalized()
			var steer_basis = _car.global_transform.basis.rotated(up, wheel.steer_angle)
			forward = (-steer_basis.z).normalized()
			right = up.cross(forward).normalized()
			forward = right.cross(up).normalized()
			var rest = _car.setup.get_rest_length(i)
			var travel = _car.setup.get_travel(i)
			center_world = _car.to_global(wheel.local_origin) - up * (rest + travel - radius)

		# Hub faces the wheel plane (steer + camber from contact).
		var basis = Basis(right, up, -forward).orthonormalized()
		hub.global_transform = Transform3D(basis, center_world)

		_spin_angle[i] = wrapf(
			_spin_angle[i] + wheel.angular_velocity * delta,
			-TAU,
			TAU
		)
		spinner.rotation = Vector3(-_spin_sign[i] * _spin_angle[i], 0.0, 0.0)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_hubs.clear()
	_spinners.clear()
	_spin_angle.clear()
	_spin_sign.clear()

	var scene = resolve_wheel_scene()
	if _car == null or _car.setup == null or scene == null:
		if scene == null and _car != null:
			push_warning("VisualWheels: no wheel_scene on pack '%s' or override" % String(_car.car_id))
		return

	var count = _car.setup.wheel_positions.size()
	for i in count:
		var hub = Node3D.new()
		hub.name = "Hub_%d" % i
		add_child(hub)

		var local_x = _car.setup.wheel_positions[i].x
		# Flip outward face with 180° yaw (not scale.x — negative scale reverses spin).
		var yaw_flip = 0.0
		if mirror_right and local_x < 0.0:
			yaw_flip = 180.0
		## Prefer live exports (WheelLayout syncs these); fall back to CarSetup.
		var scale_v: float = front_mesh_scale if i < 2 else rear_mesh_scale
		if scale_v <= 0.01:
			scale_v = float(_car.setup.get_mesh_scale(i))
		if scale_v <= 0.01:
			scale_v = mesh_scale

		## Shared scale / mirror for tire + brake disc.
		var visual := Node3D.new()
		visual.name = "Visual"
		visual.rotation_degrees = mesh_euler_degrees + Vector3(0.0, yaw_flip, 0.0)
		visual.scale = Vector3(scale_v, scale_v, scale_v)
		hub.add_child(visual)

		var spinner = Node3D.new()
		spinner.name = "Spinner"
		visual.add_child(spinner)

		var mesh_root = scene.instantiate() as Node3D
		mesh_root.name = "Mesh"
		## Attach under visual first so static parts can keep world pose when peeled off.
		visual.add_child(mesh_root)
		var static_parts := _collect_static_parts(mesh_root)
		if static_parts.is_empty():
			visual.remove_child(mesh_root)
			spinner.add_child(mesh_root)
		else:
			for part in static_parts:
				var xf := part.transform
				var parent := part.get_parent()
				if parent != null:
					## Bake parent chain under Mesh into the part local xform.
					xf = _xform_to_ancestor(part, mesh_root)
					parent.remove_child(part)
				visual.add_child(part)
				part.transform = xf
			visual.remove_child(mesh_root)
			spinner.add_child(mesh_root)

		_hubs.append(hub)
		_spinners.append(spinner)
		_spin_angle.append(0.0)
		_spin_sign.append(1.0)


func _is_static_wheel_part(node_name: String) -> bool:
	var key := node_name.to_lower().replace(" ", "").replace("-", "_")
	for token: String in _STATIC_PART_KEYS:
		if key == token or key.begins_with(token) or ("_%s" % token) in key or ("%s_" % token) in key:
			return true
	return false


func _collect_static_parts(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_static_parts_recursive(root, out)
	return out


func _collect_static_parts_recursive(node: Node, out: Array[Node3D]) -> void:
	if node is Node3D and _is_static_wheel_part(String(node.name)):
		out.append(node as Node3D)
		return
	for child in node.get_children():
		_collect_static_parts_recursive(child, out)


func _xform_to_ancestor(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != ancestor:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
