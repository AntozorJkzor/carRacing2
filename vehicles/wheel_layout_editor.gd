@tool
extends Node3D

## Editor helper: drag FL/FR/RL/RR markers to place wheels on the body mesh.
## Radius / mesh_scale update live previews. Writes into the car's CarSetup.
## Hidden at runtime — VisualWheels owns gameplay meshes.

const WHEEL_NAMES: Array[String] = ["FL", "FR", "RL", "RR"]

@export var wheel_scene: PackedScene
@export var mirror_right: bool = true
@export var mesh_euler_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale: float = 2.875:
	set(value):
		mesh_scale = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_preview_scales()
			_sync_runtime_visual_scale()

@export_range(0.05, 0.6, 0.005) var wheel_radius: float = 0.213:
	set(value):
		wheel_radius = value
		if Engine.is_editor_hint() and is_inside_tree():
			_write_radius_to_setup()
			_apply_preview_scales()
			_update_preview_transforms()

@export var show_physics_ghost: bool = true:
	set(value):
		show_physics_ghost = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()

@export var auto_save_setup: bool = true

var _last_marker_pos: Array[Vector3] = []
var _busy: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)
		return
	if wheel_scene == null:
		wheel_scene = load("res://assets/models/cars/wheel.glb") as PackedScene
	_ensure_markers()
	_load_from_setup()
	_rebuild_previews()
	set_process(true)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _busy:
		return
	_ensure_markers()
	if _markers_moved():
		_write_positions_to_setup()
	_update_preview_transforms()


func _get_setup() -> CarSetup:
	var car := get_parent()
	if car != null and "setup" in car:
		return car.setup as CarSetup
	return null


func _ensure_markers() -> void:
	var setup := _get_setup()
	for i in WHEEL_NAMES.size():
		var name := WHEEL_NAMES[i]
		var marker := get_node_or_null(name) as Marker3D
		if marker == null:
			marker = Marker3D.new()
			marker.name = name
			marker.gizmo_extents = 0.25
			add_child(marker)
			marker.owner = _edited_root()
			if setup != null and i < setup.wheel_positions.size():
				marker.position = setup.wheel_positions[i]
			else:
				marker.position = Vector3(
					-0.5 if i % 2 == 0 else 0.5,
					0.4,
					-0.8 if i < 2 else 0.7
				)


func _edited_root() -> Node:
	var root := get_tree().edited_scene_root if get_tree() else null
	return root if root else self


func _load_from_setup() -> void:
	var setup := _get_setup()
	if setup == null:
		return
	_busy = true
	wheel_radius = setup.wheel_radius
	_last_marker_pos.clear()
	for i in WHEEL_NAMES.size():
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker == null:
			continue
		if i < setup.wheel_positions.size():
			marker.position = setup.wheel_positions[i]
		_last_marker_pos.append(marker.position)
	_busy = false


func _markers_moved() -> bool:
	if _last_marker_pos.size() != WHEEL_NAMES.size():
		return true
	for i in WHEEL_NAMES.size():
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker == null:
			continue
		if marker.position.distance_squared_to(_last_marker_pos[i]) > 0.0000001:
			return true
	return false


func _write_positions_to_setup() -> void:
	var setup := _get_setup()
	if setup == null:
		return
	var positions: Array[Vector3] = []
	_last_marker_pos.clear()
	for i in WHEEL_NAMES.size():
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker == null:
			positions.append(Vector3.ZERO)
			_last_marker_pos.append(Vector3.ZERO)
			continue
		positions.append(marker.position)
		_last_marker_pos.append(marker.position)
	setup.wheel_positions = positions
	setup.emit_changed()
	_save_setup(setup)


func _write_radius_to_setup() -> void:
	var setup := _get_setup()
	if setup == null:
		return
	if is_equal_approx(setup.wheel_radius, wheel_radius):
		return
	setup.wheel_radius = wheel_radius
	setup.emit_changed()
	_save_setup(setup)


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
	if visual != null and "mesh_scale" in visual:
		visual.mesh_scale = mesh_scale


func _rebuild_previews() -> void:
	var to_free: Array[Node] = []
	for child in get_children():
		if child is Marker3D:
			continue
		to_free.append(child)
	for node in to_free:
		node.free()

	if wheel_scene == null:
		return

	for i in WHEEL_NAMES.size():
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker == null:
			continue

		var preview := Node3D.new()
		preview.name = "Preview_%s" % WHEEL_NAMES[i]
		preview.set_meta("_wheel_index", i)
		# Don't own previews in the saved scene — regenerated in editor.
		add_child(preview)

		var mesh_root := wheel_scene.instantiate() as Node3D
		mesh_root.name = "Mesh"
		mesh_root.rotation_degrees = mesh_euler_degrees
		preview.add_child(mesh_root)

		var ghost := MeshInstance3D.new()
		ghost.name = "PhysicsGhost"
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 16
		cyl.rings = 1
		ghost.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.05, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ghost.material_override = mat
		# Cylinder height along Y → rotate so axle is along X (wheel plane).
		ghost.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		preview.add_child(ghost)

	_apply_preview_scales()
	_apply_ghost_visibility()
	_update_preview_transforms()


func _apply_ghost_visibility() -> void:
	for child in get_children():
		if not child.name.begins_with("Preview_"):
			continue
		var ghost := child.get_node_or_null("PhysicsGhost") as MeshInstance3D
		if ghost:
			ghost.visible = show_physics_ghost


func _apply_preview_scales() -> void:
	var setup := _get_setup()
	var width := 0.22
	if setup:
		var w = setup.get("wheel_width")
		if w != null:
			width = float(w)
	for child in get_children():
		if not child.name.begins_with("Preview_"):
			continue
		var i: int = int(child.get_meta("_wheel_index", 0))
		var local_x := 0.0
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker:
			local_x = marker.position.x
		var side_sign := 1.0
		if mirror_right and local_x < 0.0:
			side_sign = -1.0
		var mesh_root := child.get_node_or_null("Mesh") as Node3D
		if mesh_root:
			mesh_root.scale = Vector3(side_sign * mesh_scale, mesh_scale, mesh_scale)
			mesh_root.rotation_degrees = mesh_euler_degrees
		var ghost := child.get_node_or_null("PhysicsGhost") as MeshInstance3D
		if ghost and ghost.mesh is CylinderMesh:
			var cyl := ghost.mesh as CylinderMesh
			cyl.top_radius = wheel_radius
			cyl.bottom_radius = wheel_radius
			cyl.height = width


func _rest_length_for_index(setup: Resource, index: int) -> float:
	# Don't call CarSetup methods from @tool — without @tool on car_setup.gd
	# the resource is a placeholder and method calls spam errors.
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
		var marker := get_node_or_null(WHEEL_NAMES[i]) as Marker3D
		if marker == null:
			continue
		var rest := _rest_length_for_index(setup, i)
		# Rest pose: contact rest_length below mount, center radius above contact.
		var center := marker.position + Vector3(0.0, -(rest - wheel_radius), 0.0)
		child.position = center
