extends Node3D

## Spawns / recycles road.glb + grass field strips into an infinite road along +Z.

@export var road_scene: PackedScene
@export var home_scene: PackedScene
@export var follow_path: NodePath
@export var grass_texture: Texture2D
## Raw model is ~2x2 m; scale up to a driveable lane.
@export var road_scale: float = 8.0
@export var segments_ahead: int = 50
@export var segments_behind: int = 10
## Total grass strip width (X), centered on the road.
@export var grass_strip_width: float = 96.0
## World meters covered by one repeat of the grass texture.
@export var grass_uv_meters: float = 10.0
## Fraction of half-width used for side barriers (leaves a bit of shoulder).
@export var barrier_inset: float = 0.92
@export var barrier_height: float = 2.2
@export var barrier_thickness: float = 0.6
## home.glb is ~1 m wide; scale up to a roadside house.
@export var home_scale: float = 10.0
@export var houses_per_side_min: int = 0
@export var houses_per_side_max: int = 2
## Extra gap between road edge and house wall (0 = flush).
@export var house_road_gap: float = 0.0
@export var world_seed: int = 42

## World half-width of the driveable corridor (set after measure).
var driveable_half_width: float = 7.0
## Length of one segment along Z after scale + 90° yaw.
var segment_length: float = 16.0
## Full road mesh width along X after 90° yaw.
var road_width: float = 16.66

const _MAX_HOUSES_PER_SIDE := 2

var _follow: Node3D
var _segments: Dictionary = {} # int -> Node3D
var _pool: Array[Node3D] = []
var _barrier_left: StaticBody3D
var _barrier_right: StaticBody3D
var _grass_material: StandardMaterial3D
var _min_index: int = 0
var _max_index: int = -1


func _ready() -> void:
	if follow_path != NodePath():
		_follow = get_node_or_null(follow_path) as Node3D
	_measure_segment()
	_build_grass_material()
	_build_barriers()
	_ensure_window(0)


func _physics_process(_delta: float) -> void:
	if _follow == null:
		return
	var center_index := int(floor(_follow.global_position.z / segment_length))
	_ensure_window(center_index)
	_update_barriers()


func _measure_segment() -> void:
	# road.glb Plane AABB: X = ±1 (width), Z = ±1.041 (length).
	# After +90° Y rotation: model X → world -Z, model Z → world X.
	# So travel tiling uses former width; road span on X uses former length.
	const RAW_X := 2.0
	const RAW_Z := 2.0829949378967285
	segment_length = RAW_X * road_scale
	road_width = RAW_Z * road_scale
	driveable_half_width = (road_width * 0.5) * barrier_inset


func _build_grass_material() -> void:
	_grass_material = StandardMaterial3D.new()
	_grass_material.roughness = 0.95
	if grass_texture != null:
		_grass_material.albedo_texture = grass_texture
		_grass_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		_grass_material.albedo_color = Color(0.28, 0.42, 0.2)
	# UV tiling: PlaneMesh maps 0..1 across size; scale UVs by world meters.
	var u := grass_strip_width / maxf(grass_uv_meters, 0.1)
	var v := segment_length / maxf(grass_uv_meters, 0.1)
	_grass_material.uv1_scale = Vector3(u, v, 1.0)


func _ensure_window(center_index: int) -> void:
	var want_min := center_index - segments_behind
	var want_max := center_index + segments_ahead
	var to_remove: Array[int] = []
	for index: int in _segments.keys():
		if index < want_min or index > want_max:
			to_remove.append(index)
	for index: int in to_remove:
		_recycle_segment(index)
	for index in range(want_min, want_max + 1):
		if not _segments.has(index):
			_spawn_segment(index)
	_min_index = want_min
	_max_index = want_max


func _spawn_segment(index: int) -> void:
	var segment: Node3D
	if _pool.is_empty():
		segment = _create_segment()
		add_child(segment)
	else:
		segment = _pool.pop_back()
		segment.visible = true
		_set_segment_collision_enabled(segment, true)
	segment.position = Vector3(0.0, 0.0, float(index) * segment_length)
	_configure_houses(segment, index)
	_segments[index] = segment


func _recycle_segment(index: int) -> void:
	var segment: Node3D = _segments[index]
	_segments.erase(index)
	segment.visible = false
	_set_segment_collision_enabled(segment, false)
	segment.position = Vector3(0.0, -500.0, 0.0)
	_pool.append(segment)


func _set_segment_collision_enabled(segment: Node3D, enabled: bool) -> void:
	for child_name: String in ["RoadCollision", "GrassCollision"]:
		var body := segment.get_node_or_null(child_name) as StaticBody3D
		if body == null:
			continue
		body.set_collision_layer_value(1, enabled)
		body.process_mode = (
			Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		)


func _create_segment() -> Node3D:
	var root := Node3D.new()
	root.name = "RoadSegment"

	# Grass field block under / beside the road (same Z length as the road tile).
	var grass_mesh := MeshInstance3D.new()
	grass_mesh.name = "Grass"
	var plane := PlaneMesh.new()
	plane.size = Vector2(grass_strip_width, segment_length)
	grass_mesh.mesh = plane
	grass_mesh.position = Vector3(0.0, -0.04, 0.0)
	grass_mesh.material_override = _grass_material
	root.add_child(grass_mesh)

	var grass_body := StaticBody3D.new()
	grass_body.name = "GrassCollision"
	var grass_shape := CollisionShape3D.new()
	var grass_box := BoxShape3D.new()
	grass_box.size = Vector3(grass_strip_width, 0.2, segment_length)
	grass_shape.shape = grass_box
	grass_shape.position = Vector3(0.0, -0.14, 0.0)
	grass_body.add_child(grass_shape)
	root.add_child(grass_body)

	if road_scene == null:
		push_error("EndlessRoadBuilder: road_scene is not set")
		return root

	var visual := road_scene.instantiate() as Node3D
	visual.name = "RoadVisual"
	# 90° yaw: road runs along +Z instead of across the lane.
	visual.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	visual.scale = Vector3(road_scale, road_scale, road_scale)
	visual.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(visual)

	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollision"
	var road_shape := CollisionShape3D.new()
	var road_box := BoxShape3D.new()
	road_box.size = Vector3(road_width, 0.25, segment_length)
	road_shape.shape = road_box
	road_shape.position = Vector3(0.0, -0.08, 0.0)
	road_body.add_child(road_shape)
	root.add_child(road_body)

	var houses := Node3D.new()
	houses.name = "Houses"
	root.add_child(houses)
	var slots := _MAX_HOUSES_PER_SIDE * 2
	for i in range(slots):
		var house := _make_house_instance()
		house.name = "House_%d" % i
		house.visible = false
		houses.add_child(house)
	return root


func _make_house_instance() -> Node3D:
	var wrapper := Node3D.new()
	if home_scene == null:
		return wrapper
	var model := home_scene.instantiate() as Node3D
	model.name = "Model"
	wrapper.add_child(model)
	return wrapper


func _configure_houses(segment: Node3D, index: int) -> void:
	var houses := segment.get_node_or_null("Houses") as Node3D
	if houses == null:
		return

	for child in houses.get_children():
		(child as Node3D).visible = false

	if home_scene == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(world_seed) + ":" + str(index))

	# At ±180° yaw, model local X aligns with world X.
	# Raw home.glb X half-extent ≈ 0.499 → place flush against road edge.
	const HOME_HALF_WIDTH := 0.4990234375
	var road_edge := road_width * 0.5

	var slot := 0
	for side in [-1, 1]:
		var count := rng.randi_range(houses_per_side_min, houses_per_side_max)
		count = mini(count, _MAX_HOUSES_PER_SIDE)
		# Left/right both flipped 180° from previous (was 180 / 0).
		var yaw := 0.0 if side < 0 else 180.0
		for _i in range(count):
			if slot >= houses.get_child_count():
				return
			var house := houses.get_child(slot) as Node3D
			slot += 1
			var z := rng.randf_range(-segment_length * 0.35, segment_length * 0.35)
			var scale_mul := rng.randf_range(0.9, 1.1)
			var scaled_half := HOME_HALF_WIDTH * home_scale * scale_mul
			house.visible = true
			house.position = Vector3(
				float(side) * (road_edge + house_road_gap + scaled_half),
				0.0,
				z
			)
			house.rotation_degrees = Vector3(0.0, yaw, 0.0)
			house.scale = Vector3.ONE * (home_scale * scale_mul)


func _build_barriers() -> void:
	_barrier_left = _make_barrier("BarrierLeft")
	_barrier_right = _make_barrier("BarrierRight")
	add_child(_barrier_left)
	add_child(_barrier_right)


func _make_barrier(barrier_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = barrier_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_thickness, barrier_height, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, barrier_height * 0.5, 0.0)
	body.add_child(shape)
	return body


func _update_barriers() -> void:
	var z0 := float(_min_index) * segment_length
	var z1 := float(_max_index + 1) * segment_length
	var length := maxf(z1 - z0, segment_length)
	var mid_z := (z0 + z1) * 0.5
	_set_barrier(_barrier_left, -driveable_half_width, mid_z, length)
	_set_barrier(_barrier_right, driveable_half_width, mid_z, length)


func _set_barrier(body: StaticBody3D, x: float, z: float, length: float) -> void:
	var shape := body.get_child(0) as CollisionShape3D
	var box := shape.shape as BoxShape3D
	box.size = Vector3(barrier_thickness, barrier_height, length)
	body.position = Vector3(x, 0.0, z)
