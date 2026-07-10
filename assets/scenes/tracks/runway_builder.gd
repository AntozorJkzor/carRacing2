extends Node3D

## Two long parallel runways linked at both ends, with jump ramps.

@export var runway_length: float = 520.0
@export var runway_width: float = 18.0
@export var runway_gap: float = 28.0
@export var connector_width: float = 18.0
@export var ramp_length: float = 22.0
@export var ramp_height: float = 4.5
@export var ramp_angle_deg: float = 16.0


func _ready() -> void:
	_build()


func _build() -> void:
	var asphalt := _mat(Color(0.22, 0.22, 0.24))
	var paint := _mat(Color(0.92, 0.9, 0.75))
	var grass := _mat(Color(0.28, 0.4, 0.22))
	var dirt := _mat(Color(0.35, 0.32, 0.25))
	var ramp_mat := _mat(Color(0.4, 0.38, 0.36))
	var barrier := _mat(Color(0.85, 0.55, 0.12))

	var half_len := runway_length * 0.5
	var lane_offset := (runway_width + runway_gap) * 0.5

	# Big ground pad
	_add_box(
		"Ground",
		Vector3(runway_width * 2.0 + runway_gap + 80.0, 1.0, runway_length + 120.0),
		Vector3(0.0, -0.5, 0.0),
		grass
	)

	# Two parallel runways along Z.
	_add_box("RunwayLeft", Vector3(runway_width, 0.2, runway_length), Vector3(-lane_offset, 0.1, 0.0), asphalt)
	_add_box("RunwayRight", Vector3(runway_width, 0.2, runway_length), Vector3(lane_offset, 0.1, 0.0), asphalt)

	# End connectors (link left ↔ right).
	var connector_span := runway_width * 2.0 + runway_gap
	_add_box(
		"ConnectorNorth",
		Vector3(connector_span, 0.2, connector_width),
		Vector3(0.0, 0.1, -half_len - connector_width * 0.5),
		asphalt
	)
	_add_box(
		"ConnectorSouth",
		Vector3(connector_span, 0.2, connector_width),
		Vector3(0.0, 0.1, half_len + connector_width * 0.5),
		asphalt
	)

	# Corner fillets so turns aren't razor-edged gaps.
	var corner := runway_width * 0.5
	_add_box("CornerNW", Vector3(corner, 0.2, corner), Vector3(-lane_offset, 0.1, -half_len - corner * 0.5), asphalt)
	_add_box("CornerNE", Vector3(corner, 0.2, corner), Vector3(lane_offset, 0.1, -half_len - corner * 0.5), asphalt)
	_add_box("CornerSW", Vector3(corner, 0.2, corner), Vector3(-lane_offset, 0.1, half_len + corner * 0.5), asphalt)
	_add_box("CornerSE", Vector3(corner, 0.2, corner), Vector3(lane_offset, 0.1, half_len + corner * 0.5), asphalt)

	_add_centerline(-lane_offset, half_len, paint)
	_add_centerline(lane_offset, half_len, paint)

	# Ramps at both ends of both runways (flipped 180° vs first version).
	_add_ramp("RampLN", Vector3(-lane_offset, 0.0, -half_len + ramp_length * 0.45), false, ramp_mat)
	_add_ramp("RampRN", Vector3(lane_offset, 0.0, -half_len + ramp_length * 0.45), false, ramp_mat)
	_add_ramp("RampLS", Vector3(-lane_offset, 0.0, half_len - ramp_length * 0.45), true, ramp_mat)
	_add_ramp("RampRS", Vector3(lane_offset, 0.0, half_len - ramp_length * 0.45), true, ramp_mat)

	# Outer barriers
	var outer_x := lane_offset + runway_width * 0.5 + 1.5
	_add_box("BarrierL", Vector3(0.4, 1.0, runway_length + connector_width * 2.0), Vector3(-outer_x, 0.5, 0.0), barrier)
	_add_box("BarrierR", Vector3(0.4, 1.0, runway_length + connector_width * 2.0), Vector3(outer_x, 0.5, 0.0), barrier)
	_add_box(
		"BarrierN",
		Vector3(connector_span + 4.0, 1.0, 0.4),
		Vector3(0.0, 0.5, -half_len - connector_width - 1.0),
		barrier
	)
	_add_box(
		"BarrierS",
		Vector3(connector_span + 4.0, 1.0, 0.4),
		Vector3(0.0, 0.5, half_len + connector_width + 1.0),
		barrier
	)

	# Simple hangars / props beside the strip.
	_add_box("Hangar1", Vector3(24.0, 10.0, 40.0), Vector3(-outer_x - 20.0, 5.0, -80.0), dirt)
	_add_box("Hangar2", Vector3(24.0, 10.0, 40.0), Vector3(-outer_x - 20.0, 5.0, 80.0), dirt)
	_add_box("Tower", Vector3(8.0, 22.0, 8.0), Vector3(outer_x + 16.0, 11.0, 0.0), _mat(Color(0.55, 0.58, 0.62)))


func _add_centerline(x: float, half_len: float, paint: Material) -> void:
	var z := -half_len + 8.0
	while z < half_len - 8.0:
		_add_box("Dash", Vector3(0.35, 0.04, 6.0), Vector3(x, 0.22, z), paint, false)
		z += 14.0


func _add_ramp(node_name: String, pos: Vector3, face_north: bool, material: Material) -> void:
	# Inclined slab. face_north = high end toward -Z.
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var angle := deg_to_rad(ramp_angle_deg)
	if face_north:
		body.rotation = Vector3(-angle, 0.0, 0.0)
	else:
		body.rotation = Vector3(angle, 0.0, 0.0)

	var slab := Vector3(runway_width * 0.92, 0.45, ramp_length)
	body.position.y = 0.2 + sin(angle) * ramp_length * 0.25

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = slab
	shape.shape = box
	body.add_child(shape)

	var mesh_i := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = slab
	mesh_i.mesh = mesh
	mesh_i.material_override = material
	body.add_child(mesh_i)
	add_child(body)

	var lip_z := pos.z
	if face_north:
		lip_z -= ramp_length * 0.55
	else:
		lip_z += ramp_length * 0.55
	var lip_h := sin(angle) * ramp_length * 0.85
	_add_box(
		node_name + "Lip",
		Vector3(runway_width * 0.85, 0.35, 4.0),
		Vector3(pos.x, lip_h * 0.5 + 0.15, lip_z),
		material
	)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _add_box(
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: Material,
	with_collision: bool = true
) -> void:
	var root: Node3D
	if with_collision:
		var body := StaticBody3D.new()
		body.name = node_name
		body.position = position
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		root = body
	else:
		var holder := Node3D.new()
		holder.name = node_name
		holder.position = position
		root = holder

	var mesh_i := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_i.mesh = mesh
	mesh_i.material_override = material
	root.add_child(mesh_i)
	add_child(root)
