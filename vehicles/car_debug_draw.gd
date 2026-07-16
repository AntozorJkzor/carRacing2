extends Node3D

## Bright debug overlays for chassis collision and raycast wheels.
## Toggle with F3. Off by default — start with the normal car model.

@export var enabled: bool = false
@export var hide_visual_model: bool = true
@export var force_scale: float = 0.00012

@onready var _car: CarController = get_parent() as CarController

var _body_mesh: MeshInstance3D
var _wheel_mounts: Array[MeshInstance3D] = []
var _wheel_rays: Array[MeshInstance3D] = []
var _wheel_contacts: Array[MeshInstance3D] = []
var _wheel_discs: Array[MeshInstance3D] = []
var _force_long: Array[MeshInstance3D] = []
var _force_lat: Array[MeshInstance3D] = []
var _mat_body: StandardMaterial3D
var _mat_wheel: StandardMaterial3D
var _mat_ray: StandardMaterial3D
var _mat_contact_ok: StandardMaterial3D
var _mat_contact_air: StandardMaterial3D
var _mat_fx: StandardMaterial3D
var _mat_fy: StandardMaterial3D
var _built: bool = false
var _hud: Label
var _hud_layer: CanvasLayer


func _ready() -> void:
	_make_materials()
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 20
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.name = "TireDebugHud"
	_hud.position = Vector2(12, 12)
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	_hud.visible = false
	_hud_layer.add_child(_hud)
	_apply_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_F3:
			return
		if _car == null:
			_car = get_parent() as CarController
		# Only the car you're driving — otherwise another pack in the scene steals F3.
		if _car == null or not _car.occupied:
			return
		enabled = not enabled
		_apply_visibility()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not enabled or _car == null or _car.setup == null:
		return
	if not _built:
		_build_meshes()
	_update_meshes()
	_update_hud()


func _make_materials() -> void:
	_mat_body = _emissive(Color(1.0, 0.05, 0.05, 0.55))
	_mat_wheel = _emissive(Color(1.0, 0.2, 0.0, 0.95))
	_mat_ray = _emissive(Color(1.0, 0.45, 0.0, 0.85))
	_mat_contact_ok = _emissive(Color(0.1, 1.0, 0.25, 1.0))
	_mat_contact_air = _emissive(Color(1.0, 1.0, 0.15, 1.0))
	_mat_fx = _emissive(Color(0.2, 0.7, 1.0, 0.95))
	_mat_fy = _emissive(Color(1.0, 0.2, 0.9, 0.95))


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

	for i in wheel_count:
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
		var r0 := 0.22
		if _car.setup != null:
			if i < 2:
				r0 = float(_car.setup.get("front_wheel_radius"))
			else:
				r0 = float(_car.setup.get("rear_wheel_radius"))
			if r0 <= 0.01:
				r0 = float(_car.setup.get("wheel_radius"))
		d_mesh.top_radius = r0
		d_mesh.bottom_radius = r0
		d_mesh.height = 0.08
		disc.mesh = d_mesh
		disc.material_override = _mat_wheel
		add_child(disc)
		_wheel_discs.append(disc)

		_force_long.append(_make_force_arrow(_mat_fx))
		_force_lat.append(_make_force_arrow(_mat_fy))

	_built = true
	_apply_visibility()


func _make_force_arrow(mat: StandardMaterial3D) -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 1.0
	arrow.mesh = cyl
	arrow.material_override = mat
	add_child(arrow)
	return arrow


func _clear_meshes() -> void:
	for child in get_children():
		if child == _hud_layer:
			continue
		child.queue_free()
	_body_mesh = null
	_wheel_mounts.clear()
	_wheel_rays.clear()
	_wheel_contacts.clear()
	_wheel_discs.clear()
	_force_long.clear()
	_force_lat.clear()
	_built = false


func _update_meshes() -> void:
	var wheels := _car.get_wheels()
	if wheels.is_empty():
		return
	if wheels.size() != _wheel_mounts.size():
		_build_meshes()
		return

	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var mount_local: Vector3 = wheel.local_origin
		_wheel_mounts[i].position = mount_local

		var ray_length := _car.setup.get_rest_length(i) + _car.setup.get_travel(i)
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

		var radius := _car.setup.get_wheel_radius(i)
		if wheel.on_ground:
			var center_world := wheel.hit_point + wheel.up * radius
			var axle := wheel.right
			var basis := Basis()
			basis.y = axle
			basis.z = wheel.forward
			basis.x = wheel.up
			basis = basis.orthonormalized()
			_wheel_discs[i].global_transform = Transform3D(basis, center_world)
			_place_force_arrow(_force_long[i], wheel.hit_point, wheel.forward, wheel.long_force)
			_place_force_arrow(_force_lat[i], wheel.hit_point, wheel.right, wheel.lat_force)
		else:
			_wheel_discs[i].position = end_local + Vector3(0.0, radius, 0.0)
			_wheel_discs[i].rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
			_force_long[i].visible = false
			_force_lat[i].visible = false


func _place_force_arrow(node: MeshInstance3D, origin: Vector3, dir: Vector3, force: float) -> void:
	var mag := absf(force) * force_scale
	if mag < 0.02:
		node.visible = false
		return
	node.visible = true
	var axis := dir.normalized() * signf(force)
	if axis.length_squared() < 0.0001:
		node.visible = false
		return
	var tip := origin + axis * mag
	var mid := (origin + tip) * 0.5
	var basis := Basis()
	basis.y = axis
	basis.x = axis.cross(Vector3.UP)
	if basis.x.length_squared() < 0.0001:
		basis.x = axis.cross(Vector3.RIGHT)
	basis.x = basis.x.normalized()
	basis.z = basis.x.cross(basis.y).normalized()
	node.global_transform = Transform3D(basis.orthonormalized(), mid)
	node.scale = Vector3(1.0, maxf(mag, 0.02), 1.0)


func _update_hud() -> void:
	if _hud == null:
		return
	var lines: PackedStringArray = []
	lines.append(
		"%s  RPM %.0f  gear %s (i=%.2f)  clutch %.2f  km/h %.1f"
		% [
			_car.get_transmission_label(),
			_car.engine_rpm,
			_car.get_gear_label(),
			_car.debug_gear_ratio,
			_car.clutch,
			_car.get_speed_kmh(),
		]
	)
	lines.append(
		"engTq %.0f  clTq %.0f  slipW %.1f  transRPM %.0f  driveLine %.0f  TC×%.2f  rearSPIN=%d"
		% [
			_car.debug_eng_combustion,
			_car.debug_clutch_torque,
			_car.debug_clutch_slip_w,
			_car.debug_trans_rpm,
			_car.debug_driveline,
			_car.debug_tc_scale,
			_car.debug_rear_spin,
		]
	)
	lines.append(
		"effThr %.2f  shiftT %.2f  autoCD %.2f  estRPM %.0f→%.0f  up=%d down=%d"
		% [
			_car.debug_eff_throttle,
			_car.debug_shift_timer,
			_car.debug_auto_cd,
			_car.debug_est_rpm_cur,
			_car.debug_est_rpm_up,
			_car.debug_want_up,
			_car.debug_want_down,
		]
	)
	lines.append("Fx=cyan  Fy=magenta  |κ|>0.2=SPIN  TC=%s" % [
		"ON" if _car.setup.traction_control else "OFF"
	])
	var wheels := _car.get_wheels()
	for i in wheels.size():
		var w: Wheel = wheels[i]
		var spin := absf(w.slip_ratio) > 0.2
		var status := "AIR"
		if w.on_ground:
			status = "SPIN" if spin else "GND"
		lines.append(
			"W%d κ=%.2f α=%.1f° Fx=%.0f Fy=%.0f Fz=%.0f ω=%.1f drv=%.0f %s"
			% [
				i,
				w.slip_ratio,
				rad_to_deg(w.slip_angle),
				w.long_force,
				w.lat_force,
				w.normal_load,
				w.angular_velocity,
				w.drive_torque,
				status,
			]
		)
	_hud.text = "\n".join(lines)


func _apply_visibility() -> void:
	visible = enabled
	if _hud:
		_hud.visible = enabled
	if _car == null:
		return
	var model := _car.get_node_or_null("Model")
	if model:
		model.visible = not (hide_visual_model and enabled)
	var visual_wheels := _car.get_node_or_null("VisualWheels")
	if visual_wheels:
		visual_wheels.visible = not (hide_visual_model and enabled)
