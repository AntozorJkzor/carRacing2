extends Node3D

## Builds a small rectangular city block with a road loop around the center.

@export var block_size: Vector2 = Vector2(70.0, 50.0)
@export var road_width: float = 10.0
@export var sidewalk_width: float = 2.0
@export var building_seed: int = 42


func _ready() -> void:
	_build_city()


func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed

	var half_x := block_size.x * 0.5
	var half_z := block_size.y * 0.5
	var asphalt := _make_material(Color(0.18, 0.18, 0.2))
	var curb := _make_material(Color(0.45, 0.45, 0.48))
	var grass := _make_material(Color(0.22, 0.35, 0.2))
	var line_mat := _make_material(Color(0.85, 0.82, 0.55))

	# Ground fill under everything
	_add_box(
		"Ground",
		Vector3(block_size.x + 40.0, 1.0, block_size.y + 40.0),
		Vector3(0.0, -0.5, 0.0),
		grass
	)

	# Outer asphalt ring (four segments)
	var outer_x := half_x + road_width * 0.5
	var outer_z := half_z + road_width * 0.5
	var len_x := block_size.x + road_width * 2.0
	var len_z := block_size.y

	_add_box("RoadNorth", Vector3(len_x, 0.12, road_width), Vector3(0.0, 0.06, -outer_z), asphalt)
	_add_box("RoadSouth", Vector3(len_x, 0.12, road_width), Vector3(0.0, 0.06, outer_z), asphalt)
	_add_box("RoadWest", Vector3(road_width, 0.12, len_z), Vector3(-outer_x, 0.06, 0.0), asphalt)
	_add_box("RoadEast", Vector3(road_width, 0.12, len_z), Vector3(outer_x, 0.06, 0.0), asphalt)

	# Corner pads so the ring is continuous
	_add_box("CornerNW", Vector3(road_width, 0.12, road_width), Vector3(-outer_x, 0.06, -outer_z), asphalt)
	_add_box("CornerNE", Vector3(road_width, 0.12, road_width), Vector3(outer_x, 0.06, -outer_z), asphalt)
	_add_box("CornerSW", Vector3(road_width, 0.12, road_width), Vector3(-outer_x, 0.06, outer_z), asphalt)
	_add_box("CornerSE", Vector3(road_width, 0.12, road_width), Vector3(outer_x, 0.06, outer_z), asphalt)

	# Center plaza
	_add_box(
		"Plaza",
		Vector3(block_size.x, 0.1, block_size.y),
		Vector3(0.0, 0.05, 0.0),
		_make_material(Color(0.28, 0.3, 0.32))
	)

	# Sidewalks around plaza
	var walk := sidewalk_width
	_add_box("WalkN", Vector3(block_size.x + walk * 2.0, 0.16, walk), Vector3(0.0, 0.08, -half_z - walk * 0.5), curb)
	_add_box("WalkS", Vector3(block_size.x + walk * 2.0, 0.16, walk), Vector3(0.0, 0.08, half_z + walk * 0.5), curb)
	_add_box("WalkW", Vector3(walk, 0.16, block_size.y), Vector3(-half_x - walk * 0.5, 0.08, 0.0), curb)
	_add_box("WalkE", Vector3(walk, 0.16, block_size.y), Vector3(half_x + walk * 0.5, 0.08, 0.0), curb)

	# Center line dashes on long roads
	_add_center_lines(line_mat, half_x, half_z, outer_x, outer_z)

	# Low barriers on outer edge of road
	var barrier := _make_material(Color(0.75, 0.2, 0.18))
	_add_box("BarrierN", Vector3(len_x + road_width, 0.6, 0.35), Vector3(0.0, 0.3, -outer_z - road_width * 0.5 - 0.2), barrier)
	_add_box("BarrierS", Vector3(len_x + road_width, 0.6, 0.35), Vector3(0.0, 0.3, outer_z + road_width * 0.5 + 0.2), barrier)
	_add_box("BarrierW", Vector3(0.35, 0.6, len_z + road_width), Vector3(-outer_x - road_width * 0.5 - 0.2, 0.3, 0.0), barrier)
	_add_box("BarrierE", Vector3(0.35, 0.6, len_z + road_width), Vector3(outer_x + road_width * 0.5 + 0.2, 0.3, 0.0), barrier)

	_spawn_buildings(rng, half_x, half_z)
	_spawn_outer_buildings(rng, half_x, half_z, outer_x, outer_z)


func _add_center_lines(
	mat: StandardMaterial3D,
	half_x: float,
	half_z: float,
	outer_x: float,
	outer_z: float
) -> void:
	var dash_len := 3.0
	var gap := 3.0
	var step := dash_len + gap
	# North / South roads (along X)
	var x := -half_x - road_width
	while x < half_x + road_width:
		_add_box("LineN", Vector3(dash_len, 0.02, 0.18), Vector3(x, 0.13, -outer_z), mat, false)
		_add_box("LineS", Vector3(dash_len, 0.02, 0.18), Vector3(x, 0.13, outer_z), mat, false)
		x += step
	# West / East roads (along Z)
	var z := -half_z
	while z < half_z:
		_add_box("LineW", Vector3(0.18, 0.02, dash_len), Vector3(-outer_x, 0.13, z), mat, false)
		_add_box("LineE", Vector3(0.18, 0.02, dash_len), Vector3(outer_x, 0.13, z), mat, false)
		z += step


func _spawn_buildings(rng: RandomNumberGenerator, half_x: float, half_z: float) -> void:
	var colors := [
		Color(0.55, 0.58, 0.62),
		Color(0.62, 0.55, 0.48),
		Color(0.45, 0.52, 0.58),
		Color(0.7, 0.68, 0.64),
		Color(0.4, 0.45, 0.5),
	]
	var margin := 4.0
	var cell := 8.0
	var x := -half_x + margin
	while x < half_x - margin:
		var z := -half_z + margin
		while z < half_z - margin:
			if rng.randf() > 0.35:
				var w := rng.randf_range(4.0, 7.0)
				var d := rng.randf_range(4.0, 7.0)
				var h := rng.randf_range(6.0, 18.0)
				var mat := _make_material(colors[rng.randi_range(0, colors.size() - 1)])
				_add_box(
					"Building",
					Vector3(w, h, d),
					Vector3(x + rng.randf_range(-1.0, 1.0), h * 0.5, z + rng.randf_range(-1.0, 1.0)),
					mat
				)
			z += cell
		x += cell


func _spawn_outer_buildings(
	rng: RandomNumberGenerator,
	half_x: float,
	half_z: float,
	outer_x: float,
	outer_z: float
) -> void:
	var colors := [
		Color(0.5, 0.53, 0.58),
		Color(0.58, 0.5, 0.45),
		Color(0.42, 0.48, 0.55),
	]
	var offset := road_width + 6.0
	# North strip
	for i in 6:
		var bx := lerpf(-half_x, half_x, float(i) / 5.0)
		var h := rng.randf_range(8.0, 22.0)
		_add_box(
			"OuterN",
			Vector3(rng.randf_range(5.0, 9.0), h, rng.randf_range(5.0, 8.0)),
			Vector3(bx, h * 0.5, -outer_z - offset),
			_make_material(colors[rng.randi_range(0, colors.size() - 1)])
		)
	# South strip
	for i in 6:
		var bx := lerpf(-half_x, half_x, float(i) / 5.0)
		var h := rng.randf_range(8.0, 22.0)
		_add_box(
			"OuterS",
			Vector3(rng.randf_range(5.0, 9.0), h, rng.randf_range(5.0, 8.0)),
			Vector3(bx, h * 0.5, outer_z + offset),
			_make_material(colors[rng.randi_range(0, colors.size() - 1)])
		)
	# West / East
	for i in 4:
		var bz := lerpf(-half_z, half_z, float(i) / 3.0)
		var h1 := rng.randf_range(8.0, 20.0)
		var h2 := rng.randf_range(8.0, 20.0)
		_add_box(
			"OuterW",
			Vector3(rng.randf_range(5.0, 8.0), h1, rng.randf_range(5.0, 9.0)),
			Vector3(-outer_x - offset, h1 * 0.5, bz),
			_make_material(colors[rng.randi_range(0, colors.size() - 1)])
		)
		_add_box(
			"OuterE",
			Vector3(rng.randf_range(5.0, 8.0), h2, rng.randf_range(5.0, 9.0)),
			Vector3(outer_x + offset, h2 * 0.5, bz),
			_make_material(colors[rng.randi_range(0, colors.size() - 1)])
		)


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


func _add_box(
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: Material,
	with_collision: bool = true
) -> void:
	var body: Node3D
	if with_collision:
		var static_body := StaticBody3D.new()
		static_body.name = node_name
		static_body.position = position
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		static_body.add_child(shape)
		body = static_body
	else:
		var holder := Node3D.new()
		holder.name = node_name
		holder.position = position
		body = holder

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
