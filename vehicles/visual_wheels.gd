@tool
extends Node3D

## Spawns 4 visual wheel meshes and syncs them to raycast Wheel physics.
## Typical game setup: body mesh without wheels + separate tire meshes
## that follow contact points, steer yaw, and spin from ω.
## In the editor, WheelLayout owns the previews — this node stays idle.

## Optional override. If empty, uses CarController.wheel_scene from the car pack.
@export var wheel_scene: PackedScene
@export var mirror_right: bool = true
## Extra mesh rotation if the GLB axle is not along +X (degrees).
@export var mesh_euler_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale: float = 2.875
@export var front_mesh_scale: float = 2.875
@export var rear_mesh_scale: float = 2.875

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


func resolve_wheel_scene() -> PackedScene:
	if wheel_scene != null:
		return wheel_scene
	if _car != null and _car.wheel_scene != null:
		return _car.wheel_scene
	return null


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _car == null or _car.setup == null:
		return
	var wheels := _car.get_wheels()
	if wheels.size() != _hubs.size():
		_rebuild()
		wheels = _car.get_wheels()
	if wheels.is_empty():
		return

	var radius := maxf(_car.setup.get_wheel_radius(0), 0.05)
	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var hub := _hubs[i]
		var spinner := _spinners[i]
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
			var steer_basis := _car.global_transform.basis.rotated(up, wheel.steer_angle)
			forward = (-steer_basis.z).normalized()
			right = up.cross(forward).normalized()
			forward = right.cross(up).normalized()
			var rest := _car.setup.get_rest_length(i)
			var travel := _car.setup.get_travel(i)
			center_world = _car.to_global(wheel.local_origin) - up * (rest + travel - radius)

		# Hub faces the wheel plane (steer + camber from contact).
		var basis := Basis(right, up, -forward).orthonormalized()
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

	var scene := resolve_wheel_scene()
	if _car == null or _car.setup == null or scene == null:
		if scene == null and _car != null:
			push_warning("VisualWheels: no wheel_scene on pack '%s' or override" % String(_car.car_id))
		return

	var count := _car.setup.wheel_positions.size()
	for i in count:
		var hub := Node3D.new()
		hub.name = "Hub_%d" % i
		add_child(hub)

		var spinner := Node3D.new()
		spinner.name = "Spinner"
		hub.add_child(spinner)

		var mesh_root := scene.instantiate() as Node3D
		mesh_root.name = "Mesh"
		var local_x := _car.setup.wheel_positions[i].x
		# Flip outward face with 180° yaw (not scale.x — negative scale reverses spin).
		var yaw_flip := 0.0
		if mirror_right and local_x < 0.0:
			yaw_flip = 180.0
		mesh_root.rotation_degrees = mesh_euler_degrees + Vector3(0.0, yaw_flip, 0.0)
		var scale_v := _car.setup.get_mesh_scale(i)
		if scale_v <= 0.01:
			scale_v = front_mesh_scale if i < 2 else rear_mesh_scale
		if scale_v <= 0.01:
			scale_v = mesh_scale
		mesh_root.scale = Vector3(scale_v, scale_v, scale_v)
		spinner.add_child(mesh_root)

		_hubs.append(hub)
		_spinners.append(spinner)
		_spin_angle.append(0.0)
		_spin_sign.append(1.0)
