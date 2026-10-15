@tool
extends Node3D

## Editor helper: place Front / Rear axle markers, set track & tire ISO size per axle.
## Tire size (rim″ / width mm / profile %) drives physical radius & width for the ghost
## and CarSetup — scale the visual mesh/body to match the orange ghost.
## Hidden at runtime — VisualWheels owns gameplay meshes.

const AXLE_NAMES: Array[String] = ["Front", "Rear"]
const WHEEL_NAMES: Array[String] = ["FL", "FR", "RL", "RR"]

var _last_axle_pos: Array[Vector3] = []
var _busy: bool = false

## Optional override. If empty, uses CarController.wheel_scene from the car pack.
@export var wheel_scene: PackedScene
@export var mirror_right: bool = true
@export var mesh_euler_degrees: Vector3 = Vector3.ZERO

@export_group("Front axle")
## Track width in mm (center-to-center of tires).
@export_range(800.0, 2000.0, 1.0) var front_track_mm: float = 1490.0:
	set(value):
		front_track_mm = clampf(value, 800.0, 2000.0)
		if _busy:
			return
		_busy = true
		front_track = front_track_mm * 0.001
		_busy = false
		_editor_axle_changed()
## Track width in meters (synced from mm).
@export_range(0.8, 2.0, 0.001) var front_track: float = 1.49:
	set(value):
		front_track = maxf(value, 0.2)
		if _busy:
			return
		_busy = true
		front_track_mm = front_track * 1000.0
		_busy = false
		_editor_axle_changed()

@export_subgroup("Front tire ISO")
## Rim diameter in inches (R14 → 14).
@export_range(10.0, 22.0, 0.5) var front_rim_inches: float = 14.0:
	set(value):
		front_rim_inches = value
		_apply_front_tire_iso()
## Section width in mm (205/70 R14 → 205).
@export_range(125.0, 355.0, 5.0) var front_tire_width_mm: float = 205.0:
	set(value):
		front_tire_width_mm = value
		_apply_front_tire_iso()
## Profile / aspect % (205/70 R14 → 70).
@export_range(25.0, 85.0, 5.0) var front_tire_aspect: float = 70.0:
	set(value):
		front_tire_aspect = value
		_apply_front_tire_iso()
## Computed overall radius (m). Edited by tire ISO; can still override manually.
@export_range(0.05, 0.8, 0.001) var front_wheel_radius: float = 0.321:
	set(value):
		front_wheel_radius = value
		_editor_axle_changed()
@export_range(0.08, 0.45, 0.001) var front_wheel_width: float = 0.205:
	set(value):
		front_wheel_width = value
		_editor_axle_changed()
@export var front_mesh_scale: float = 2.875:
	set(value):
		front_mesh_scale = value
		_editor_axle_changed()

@export_group("Rear axle")
@export_range(800.0, 2000.0, 1.0) var rear_track_mm: float = 1500.0:
	set(value):
		rear_track_mm = clampf(value, 800.0, 2000.0)
		if _busy:
			return
		_busy = true
		rear_track = rear_track_mm * 0.001
		_busy = false
		_editor_axle_changed()
@export_range(0.8, 2.0, 0.001) var rear_track: float = 1.5:
	set(value):
		rear_track = maxf(value, 0.2)
		if _busy:
			return
		_busy = true
		rear_track_mm = rear_track * 1000.0
		_busy = false
		_editor_axle_changed()

@export_subgroup("Rear tire ISO")
@export_range(10.0, 22.0, 0.5) var rear_rim_inches: float = 14.0:
	set(value):
		rear_rim_inches = value
		_apply_rear_tire_iso()
@export_range(125.0, 355.0, 5.0) var rear_tire_width_mm: float = 205.0:
	set(value):
		rear_tire_width_mm = value
		_apply_rear_tire_iso()
@export_range(25.0, 85.0, 5.0) var rear_tire_aspect: float = 70.0:
	set(value):
		rear_tire_aspect = value
		_apply_rear_tire_iso()
@export_range(0.05, 0.8, 0.001) var rear_wheel_radius: float = 0.321:
	set(value):
		rear_wheel_radius = value
		_editor_axle_changed()
@export_range(0.08, 0.45, 0.001) var rear_wheel_width: float = 0.205:
	set(value):
		rear_wheel_width = value
		_editor_axle_changed()
@export var rear_mesh_scale: float = 2.875:
	set(value):
		rear_mesh_scale = value
		_editor_axle_changed()

@export_group("Preview")
@export var show_physics_ghost: bool = true:
	set(value):
		show_physics_ghost = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()
@export var show_rim_ghost: bool = true:
	set(value):
		show_rim_ghost = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()
@export var show_track_ghost: bool = true:
	set(value):
		show_track_ghost = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()
@export var show_size_labels: bool = true:
	set(value):
		show_size_labels = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()
@export var auto_save_setup: bool = true


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)
		return
	_ensure_markers()
	_load_from_setup()
	_rebuild_previews()
	set_process(true)


func resolve_wheel_scene() -> PackedScene:
	if wheel_scene != null:
		return wheel_scene
	var car := get_parent()
	if car != null and "wheel_scene" in car:
		var pack_wheel: PackedScene = car.get("wheel_scene") as PackedScene
		if pack_wheel != null:
			return pack_wheel
	if car == null:
		return null
	var visual := car.get_node_or_null("VisualWheels")
	if visual != null and visual.has_method("resolve_wheel_scene"):
		return visual.call("resolve_wheel_scene") as PackedScene
	if visual != null and "wheel_scene" in visual:
		return visual.get("wheel_scene") as PackedScene
	return null


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _busy:
		return
	_ensure_markers()
	if _axles_moved():
		_write_axles_to_setup()
	_sync_corner_markers_from_axles()
	_update_preview_transforms()


func _get_setup() -> CarSetup:
	var car := get_parent()
	if car != null and "setup" in car:
		return car.setup as CarSetup
	return null


func _edited_root() -> Node:
	var root := get_tree().edited_scene_root if get_tree() else null
	return root if root else self


func _editor_axle_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and not _busy:
		_write_axles_to_setup()


func _tire_radius_m(rim_inches: float, width_mm: float, aspect: float) -> float:
	# r = rim/2 + sidewall; sidewall = width_mm * aspect% / 1000
	return rim_inches * 0.0127 + width_mm * aspect * 0.00001


func _tire_width_m(width_mm: float) -> float:
	return width_mm * 0.001


func _tire_label(rim_inches: float, width_mm: float, aspect: float) -> String:
	var radius := _tire_radius_m(rim_inches, width_mm, aspect)
	return "%d/%d R%.0f  Ø%.0f mm" % [
		int(round(width_mm)),
		int(round(aspect)),
		rim_inches,
		radius * 2000.0,
	]


func _apply_front_tire_iso() -> void:
	if _busy:
		return
	_busy = true
	front_wheel_radius = _tire_radius_m(front_rim_inches, front_tire_width_mm, front_tire_aspect)
	front_wheel_width = _tire_width_m(front_tire_width_mm)
	_busy = false
	_editor_axle_changed()


func _apply_rear_tire_iso() -> void:
	if _busy:
		return
	_busy = true
	rear_wheel_radius = _tire_radius_m(rear_rim_inches, rear_tire_width_mm, rear_tire_aspect)
	rear_wheel_width = _tire_width_m(rear_tire_width_mm)
	_busy = false
	_editor_axle_changed()


func _ensure_markers() -> void:
	var setup := _get_setup()
	# Remove legacy FL/FR/RL/RR markers if present (axle-only editing).
	for legacy_name: String in WHEEL_NAMES:
		var legacy := get_node_or_null(legacy_name)
		if legacy != null and legacy is Marker3D:
			legacy.free()

	for i in AXLE_NAMES.size():
		var axle_name := AXLE_NAMES[i]
		var marker := get_node_or_null(axle_name) as Marker3D
		if marker == null:
			marker = Marker3D.new()
			marker.name = axle_name
			marker.gizmo_extents = 0.45
			add_child(marker)
			marker.owner = _edited_root()
			if setup != null:
				if i == 0:
					marker.position = Vector3(0.0, setup.front_mount_y, setup.front_axle_z)
				else:
					marker.position = Vector3(0.0, setup.rear_mount_y, setup.rear_axle_z)
			else:
				marker.position = Vector3(0.0, 0.4, -0.9 if i == 0 else 0.9)


func _load_from_setup() -> void:
	var setup := _get_setup()
	if setup == null:
		return
	_busy = true
	# Don't call CarSetup methods from @tool — placeholder resources have no script API.
	front_track = float(setup.get("front_track"))
	rear_track = float(setup.get("rear_track"))
	front_track_mm = front_track * 1000.0
	rear_track_mm = rear_track * 1000.0
	front_rim_inches = float(setup.get("front_rim_inches"))
	rear_rim_inches = float(setup.get("rear_rim_inches"))
	front_tire_width_mm = float(setup.get("front_tire_width_mm"))
	rear_tire_width_mm = float(setup.get("rear_tire_width_mm"))
	front_tire_aspect = float(setup.get("front_tire_aspect"))
	rear_tire_aspect = float(setup.get("rear_tire_aspect"))
	front_wheel_radius = float(setup.get("front_wheel_radius"))
	rear_wheel_radius = float(setup.get("rear_wheel_radius"))
	front_wheel_width = float(setup.get("front_wheel_width"))
	rear_wheel_width = float(setup.get("rear_wheel_width"))
	front_mesh_scale = float(setup.get("front_mesh_scale"))
	rear_mesh_scale = float(setup.get("rear_mesh_scale"))
	if front_track <= 0.01:
		front_track = 1.49
		front_track_mm = 1490.0
	if rear_track <= 0.01:
		rear_track = 1.5
		rear_track_mm = 1500.0
	if front_rim_inches < 8.0:
		front_rim_inches = 14.0
	if rear_rim_inches < 8.0:
		rear_rim_inches = 14.0
	if front_tire_width_mm < 100.0:
		front_tire_width_mm = 205.0
	if rear_tire_width_mm < 100.0:
		rear_tire_width_mm = 205.0
	if front_tire_aspect < 20.0:
		front_tire_aspect = 70.0
	if rear_tire_aspect < 20.0:
		rear_tire_aspect = 70.0
	# Prefer ISO → radius when specs look valid.
	front_wheel_radius = _tire_radius_m(front_rim_inches, front_tire_width_mm, front_tire_aspect)
	rear_wheel_radius = _tire_radius_m(rear_rim_inches, rear_tire_width_mm, rear_tire_aspect)
	front_wheel_width = _tire_width_m(front_tire_width_mm)
	rear_wheel_width = _tire_width_m(rear_tire_width_mm)
	if front_wheel_radius <= 0.01:
		front_wheel_radius = float(setup.get("wheel_radius"))
	if rear_wheel_radius <= 0.01:
		rear_wheel_radius = float(setup.get("wheel_radius"))
	_last_axle_pos.clear()
	for i in AXLE_NAMES.size():
		var marker := get_node_or_null(AXLE_NAMES[i]) as Marker3D
		if marker == null:
			continue
		if i == 0:
			marker.position = Vector3(0.0, float(setup.get("front_mount_y")), float(setup.get("front_axle_z")))
		else:
			marker.position = Vector3(0.0, float(setup.get("rear_mount_y")), float(setup.get("rear_axle_z")))
		_last_axle_pos.append(marker.position)
	_busy = false
	_sync_runtime_visual_scale()


func _axles_moved() -> bool:
	if _last_axle_pos.size() != AXLE_NAMES.size():
		return true
	for i in AXLE_NAMES.size():
		var marker := get_node_or_null(AXLE_NAMES[i]) as Marker3D
		if marker == null:
			continue
		# Keep axle on centerline (X=0).
		if absf(marker.position.x) > 0.0001:
			marker.position.x = 0.0
		if marker.position.distance_squared_to(_last_axle_pos[i]) > 0.0000001:
			return true
	return false


func _write_axles_to_setup() -> void:
	var setup := _get_setup()
	if setup == null:
		return
	var front := get_node_or_null("Front") as Marker3D
	var rear := get_node_or_null("Rear") as Marker3D
	_last_axle_pos.clear()
	if front:
		front.position.x = 0.0
		setup.front_axle_z = front.position.z
		setup.front_mount_y = front.position.y
		_last_axle_pos.append(front.position)
	else:
		_last_axle_pos.append(Vector3.ZERO)
	if rear:
		rear.position.x = 0.0
		setup.rear_axle_z = rear.position.z
		setup.rear_mount_y = rear.position.y
		_last_axle_pos.append(rear.position)
	else:
		_last_axle_pos.append(Vector3.ZERO)

	setup.front_track = front_track
	setup.rear_track = rear_track
	setup.set("front_rim_inches", front_rim_inches)
	setup.set("rear_rim_inches", rear_rim_inches)
	setup.set("front_tire_width_mm", front_tire_width_mm)
	setup.set("rear_tire_width_mm", rear_tire_width_mm)
	setup.set("front_tire_aspect", front_tire_aspect)
	setup.set("rear_tire_aspect", rear_tire_aspect)
	setup.front_wheel_radius = front_wheel_radius
	setup.rear_wheel_radius = rear_wheel_radius
	setup.front_wheel_width = front_wheel_width
	setup.rear_wheel_width = rear_wheel_width
	setup.front_mesh_scale = front_mesh_scale
	setup.rear_mesh_scale = rear_mesh_scale
	setup.wheel_radius = front_wheel_radius
	setup.wheel_width = front_wheel_width
	# Inline rebuild — avoid method calls on placeholder CarSetup in @tool.
	var ft := maxf(front_track, 0.2) * 0.5
	var rt := maxf(rear_track, 0.2) * 0.5
	var positions: Array[Vector3] = [
		Vector3(-ft, setup.front_mount_y, setup.front_axle_z),
		Vector3(ft, setup.front_mount_y, setup.front_axle_z),
		Vector3(-rt, setup.rear_mount_y, setup.rear_axle_z),
		Vector3(rt, setup.rear_mount_y, setup.rear_axle_z),
	]
	setup.wheel_positions = positions
	setup.emit_changed()
	_save_setup(setup)
	_apply_preview_scales()
	_sync_runtime_visual_scale()


func _sync_corner_markers_from_axles() -> void:
	## Corner preview positions use setup.wheel_positions (no separate markers).
	pass


func _save_setup(setup: CarSetup) -> void:
	if not auto_save_setup:
		return
	if setup.resource_path.is_empty():
		return
	ResourceSaver.save(setup)


func _sync_runtime_visual_scale() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var visual := parent.get_node_or_null("VisualWheels")
	if visual == null:
		return
	if "front_mesh_scale" in visual:
		visual.front_mesh_scale = front_mesh_scale
	if "rear_mesh_scale" in visual:
		visual.rear_mesh_scale = rear_mesh_scale
	if "mesh_scale" in visual:
		visual.mesh_scale = front_mesh_scale


func _rebuild_previews() -> void:
	var to_free: Array[Node] = []
	for child in get_children():
		if child is Marker3D:
			continue
		to_free.append(child)
	for node in to_free:
		node.free()

	var scene := resolve_wheel_scene()

	for i in WHEEL_NAMES.size():
		var preview := Node3D.new()
		preview.name = "Preview_%s" % WHEEL_NAMES[i]
		preview.set_meta("_wheel_index", i)
		add_child(preview)

		if scene != null:
			var mesh_root := scene.instantiate() as Node3D
			mesh_root.name = "Mesh"
			mesh_root.rotation_degrees = mesh_euler_degrees
			preview.add_child(mesh_root)

		var tire_ghost := MeshInstance3D.new()
		tire_ghost.name = "PhysicsGhost"
		var tire_cyl := CylinderMesh.new()
		tire_cyl.radial_segments = 24
		tire_cyl.rings = 1
		tire_ghost.mesh = tire_cyl
		var tire_mat := StandardMaterial3D.new()
		tire_mat.albedo_color = Color(1.0, 0.45, 0.05, 0.32)
		tire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tire_ghost.material_override = tire_mat
		tire_ghost.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		preview.add_child(tire_ghost)

		var rim_ghost := MeshInstance3D.new()
		rim_ghost.name = "RimGhost"
		var rim_cyl := CylinderMesh.new()
		rim_cyl.radial_segments = 20
		rim_cyl.rings = 1
		rim_ghost.mesh = rim_cyl
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.75, 0.78, 0.85, 0.55)
		rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		rim_ghost.material_override = rim_mat
		rim_ghost.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		preview.add_child(rim_ghost)

		var label := Label3D.new()
		label.name = "SizeLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.modulate = Color(1.0, 0.85, 0.35, 1.0)
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		label.outline_size = 6
		label.pixel_size = 0.004
		label.position = Vector3(0.0, 0.0, 0.0)
		preview.add_child(label)

	_create_track_ghost("Front")
	_create_track_ghost("Rear")

	_apply_preview_scales()
	_apply_ghost_visibility()
	_update_preview_transforms()


func _create_track_ghost(axle_name: String) -> void:
	var root := Node3D.new()
	root.name = "TrackGhost_%s" % axle_name
	add_child(root)

	var bar := MeshInstance3D.new()
	bar.name = "Bar"
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 0.02)
	bar.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	bar.material_override = mat
	root.add_child(bar)

	var label := Label3D.new()
	label.name = "TrackLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	label.modulate = Color(0.45, 0.9, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.outline_size = 6
	label.pixel_size = 0.0045
	root.add_child(label)


func _apply_ghost_visibility() -> void:
	for child in get_children():
		if child.name.begins_with("Preview_"):
			var tire := child.get_node_or_null("PhysicsGhost") as MeshInstance3D
			if tire:
				tire.visible = show_physics_ghost
			var rim := child.get_node_or_null("RimGhost") as MeshInstance3D
			if rim:
				rim.visible = show_physics_ghost and show_rim_ghost
			var label := child.get_node_or_null("SizeLabel") as Label3D
			if label:
				label.visible = show_size_labels
		elif child.name.begins_with("TrackGhost_"):
			child.visible = show_track_ghost
			var track_label := child.get_node_or_null("TrackLabel") as Label3D
			if track_label:
				track_label.visible = show_size_labels and show_track_ghost


func _radius_for_index(index: int) -> float:
	return front_wheel_radius if index < 2 else rear_wheel_radius


func _width_for_index(index: int) -> float:
	return front_wheel_width if index < 2 else rear_wheel_width


func _rim_radius_for_index(index: int) -> float:
	var inches := front_rim_inches if index < 2 else rear_rim_inches
	return inches * 0.0127


func _scale_for_index(index: int) -> float:
	return front_mesh_scale if index < 2 else rear_mesh_scale


func _label_for_index(index: int) -> String:
	if index < 2:
		return _tire_label(front_rim_inches, front_tire_width_mm, front_tire_aspect)
	return _tire_label(rear_rim_inches, rear_tire_width_mm, rear_tire_aspect)


func _mount_for_index(setup: Resource, index: int) -> Vector3:
	if setup != null:
		var positions = setup.get("wheel_positions")
		if positions is Array and index < positions.size():
			return positions[index] as Vector3
	var half_f := front_track * 0.5
	var half_r := rear_track * 0.5
	var front := get_node_or_null("Front") as Marker3D
	var rear := get_node_or_null("Rear") as Marker3D
	var fz := front.position.z if front else -1.25
	var fy := front.position.y if front else 0.4
	var rz := rear.position.z if rear else 1.25
	var ry := rear.position.y if rear else 0.4
	match index:
		0:
			return Vector3(-half_f, fy, fz)
		1:
			return Vector3(half_f, fy, fz)
		2:
			return Vector3(-half_r, ry, rz)
		_:
			return Vector3(half_r, ry, rz)


func _apply_preview_scales() -> void:
	for child in get_children():
		if not child.name.begins_with("Preview_"):
			continue
		var i: int = int(child.get_meta("_wheel_index", 0))
		var mount := _mount_for_index(_get_setup(), i)
		# Runtime VisualWheels flips local_x < 0. Preview here is in raw car space and
		# ends up 180° off that look if we flip the same side — so mirror the other side.
		var yaw_flip := 0.0
		if mirror_right and mount.x > 0.0:
			yaw_flip = 180.0
		var scale_v := _scale_for_index(i)
		var mesh_root := child.get_node_or_null("Mesh") as Node3D
		if mesh_root:
			mesh_root.scale = Vector3(scale_v, scale_v, scale_v)
			mesh_root.rotation_degrees = mesh_euler_degrees + Vector3(0.0, yaw_flip, 0.0)

		var radius := _radius_for_index(i)
		var width := _width_for_index(i)
		var rim_r := _rim_radius_for_index(i)

		var tire := child.get_node_or_null("PhysicsGhost") as MeshInstance3D
		if tire and tire.mesh is CylinderMesh:
			var cyl := tire.mesh as CylinderMesh
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			cyl.height = width

		var rim := child.get_node_or_null("RimGhost") as MeshInstance3D
		if rim and rim.mesh is CylinderMesh:
			var rim_cyl := rim.mesh as CylinderMesh
			rim_cyl.top_radius = rim_r
			rim_cyl.bottom_radius = rim_r
			rim_cyl.height = maxf(width * 0.72, 0.04)

		var label := child.get_node_or_null("SizeLabel") as Label3D
		if label:
			label.text = _label_for_index(i)
			label.position = Vector3(0.0, radius + 0.08, 0.0)

	_update_track_ghosts()


func _update_track_ghosts() -> void:
	var setup := _get_setup()
	_update_one_track_ghost("Front", front_track, front_track_mm, 0, setup)
	_update_one_track_ghost("Rear", rear_track, rear_track_mm, 2, setup)


func _update_one_track_ghost(
	axle_name: String,
	track_m: float,
	track_mm: float,
	left_index: int,
	setup: Resource
) -> void:
	var root := get_node_or_null("TrackGhost_%s" % axle_name) as Node3D
	if root == null:
		return
	var left_mount := _mount_for_index(setup, left_index)
	var rest := _rest_length_for_index(setup, left_index)
	var radius := _radius_for_index(left_index)
	var y := left_mount.y - (rest - radius)
	var z := left_mount.z
	root.position = Vector3(0.0, y, z)

	var bar := root.get_node_or_null("Bar") as MeshInstance3D
	if bar and bar.mesh is BoxMesh:
		var box := bar.mesh as BoxMesh
		box.size = Vector3(maxf(track_m, 0.2), 0.025, 0.025)

	var label := root.get_node_or_null("TrackLabel") as Label3D
	if label:
		label.text = "track %.0f mm" % track_mm
		label.position = Vector3(0.0, radius + 0.14, 0.0)


func _rest_length_for_index(setup: Resource, index: int) -> float:
	if setup == null:
		return 0.4
	var key := "front_rest_length" if index < 2 else "rear_rest_length"
	var value = setup.get(key)
	if value == null:
		return 0.4
	return float(value)


func _update_preview_transforms() -> void:
	var setup := _get_setup()
	for child in get_children():
		if not child.name.begins_with("Preview_"):
			continue
		var i: int = int(child.get_meta("_wheel_index", 0))
		var mount := _mount_for_index(setup, i)
		var rest := _rest_length_for_index(setup, i)
		var radius := _radius_for_index(i)
		child.position = mount + Vector3(0.0, -(rest - radius), 0.0)
	_update_track_ghosts()
