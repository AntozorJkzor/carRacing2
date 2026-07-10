extends Node3D

## Bright debug overlays for chassis collision and raycast wheels.
## Toggle with F3. Off by default — start with the normal car model.

@export var enabled: bool = false
@export var hide_visual_model: bool = true

@onready var _car: CarController = get_parent() as CarController

var _body_mesh: MeshInstance3D
var _wheel_mounts: Array[MeshInstance3D] = []
var _wheel_rays: Array[MeshInstance3D] = []
var _wheel_contacts: Array[MeshInstance3D] = []
var _wheel_discs: Array[MeshInstance3D] = []
var _mat_body: StandardMaterial3D
var _mat_wheel: StandardMaterial3D
var _mat_ray: StandardMaterial3D
var _mat_contact_ok: StandardMaterial3D
var _mat_contact_air: StandardMaterial3D
var _built: bool = false


func _ready() -> void:
	_make_materials()
	_apply_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			enabled = not enabled
			_apply_visibility()
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not enabled or _car == null or _car.setup == null:
		return
	if not _built:
		_build_meshes()
	_update_meshes()


func _make_materials() -> void:
	_mat_body = _emissive(Color(1.0, 0.05, 0.05, 0.55))
	_mat_wheel = _emissive(Color(1.0, 0.2, 0.0, 0.95))
	_mat_ray = _emissive(Color(1.0, 0.45, 0.0, 0.85))
	_mat_contact_ok = _emissive(Color(0.1, 1.0, 0.25, 1.0))
	_mat_contact_air = _emissive(Color(1.0, 1.0, 0.15, 1.0))


func _emissive(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat


func _build_meshes() -> void:
	_clear_meshes()

	var col := _car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "DebugBody"
	var box := BoxMesh.new()
	if col and col.shape is BoxShape3D:
		box.size = (col.shape as BoxShape3D).size
		_body_mesh.transform = col.transform
	else:
		box.size = Vector3(1.0, 0.35, 1.7)
		_body_mesh.position = Vector3(0.0, 0.55, 0.0)
	_body_mesh.mesh = box
	_body_mesh.material_override = _mat_body
	add_child(_body_mesh)

	var wheel_count := _car.get_wheels().size()
	if wheel_count == 0:
		wheel_count = _car.setup.wheel_positions.size()

	for _i in wheel_count:
		var mount := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.08
		sphere.height = 0.16
		mount.mesh = sphere
		mount.material_override = _mat_wheel
		add_child(mount)
		_wheel_mounts.append(mount)

		var ray := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.025
		cyl.height = 1.0
		ray.mesh = cyl
		ray.material_override = _mat_ray
		add_child(ray)
		_wheel_rays.append(ray)

		var contact := MeshInstance3D.new()
		var c_sphere := SphereMesh.new()
		c_sphere.radius = 0.1
		c_sphere.height = 0.2
		contact.mesh = c_sphere
		contact.material_override = _mat_contact_air
		add_child(contact)
		_wheel_contacts.append(contact)

		var disc := MeshInstance3D.new()
		var d_mesh := CylinderMesh.new()
		d_mesh.top_radius = _car.setup.wheel_radius
		d_mesh.bottom_radius = _car.setup.wheel_radius
		d_mesh.height = 0.08
		disc.mesh = d_mesh
		disc.material_override = _mat_wheel
		add_child(disc)
		_wheel_discs.append(disc)

	_built = true
	_apply_visibility()


func _clear_meshes() -> void:
	for child in get_children():
		child.queue_free()
	_body_mesh = null
	_wheel_mounts.clear()
	_wheel_rays.clear()
	_wheel_contacts.clear()
	_wheel_discs.clear()
	_built = false


func _update_meshes() -> void:
	var wheels := _car.get_wheels()
	if wheels.is_empty():
		return
	if wheels.size() != _wheel_mounts.size():
		_build_meshes()
		return

	var ray_length := _car.setup.rest_length + _car.setup.travel

	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var mount_local: Vector3 = wheel.local_origin
		_wheel_mounts[i].position = mount_local

		var end_local := mount_local + Vector3(0.0, -ray_length, 0.0)
		if wheel.on_ground:
			end_local = _car.to_local(wheel.hit_point)

		var mid := (mount_local + end_local) * 0.5
		var length := mount_local.distance_to(end_local)
		_wheel_rays[i].position = mid
		_wheel_rays[i].rotation = Vector3.ZERO
		_wheel_rays[i].scale = Vector3(1.0, maxf(length, 0.01), 1.0)

		_wheel_contacts[i].position = end_local
		_wheel_contacts[i].material_override = (
			_mat_contact_ok if wheel.on_ground else _mat_contact_air
		)

		# Red wheel disc: cylinder along X (axle), standing on contact.
		var radius := _car.setup.wheel_radius
		if wheel.on_ground:
			var center_world := wheel.hit_point + wheel.up * radius
			_wheel_discs[i].global_position = center_world
			# Align cylinder Y axis with wheel right (axle).
			var axle := wheel.right
			var basis := Basis()
			basis.y = axle
			basis.z = wheel.forward
			basis.x = wheel.up
			basis = basis.orthonormalized()
			_wheel_discs[i].global_transform = Transform3D(basis, center_world)
		else:
			_wheel_discs[i].position = end_local + Vector3(0.0, radius, 0.0)
			_wheel_discs[i].rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))


func _apply_visibility() -> void:
	visible = enabled
	if _car == null:
		return
	var model := _car.get_node_or_null("Model")
	if model:
		model.visible = not (hide_visual_model and enabled)
