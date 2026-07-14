@tool
extends Node3D

## Editor helper: place Front / Rear axle markers, set track & radius per axle.
## Writes axle fields into CarSetup and rebuilds [FL,FR,RL,RR] mounts.
## Hidden at runtime — VisualWheels owns gameplay meshes.

const AXLE_NAMES: Array[String] = ["Front", "Rear"]
const WHEEL_NAMES: Array[String] = ["FL", "FR", "RL", "RR"]

## Optional override. If empty, uses CarController.wheel_scene from the car pack.
@export var wheel_scene: PackedScene
@export var mirror_right: bool = true
@export var mesh_euler_degrees: Vector3 = Vector3.ZERO

@export_group("Front axle")
@export var front_track: float = 1.5:
	set(value):
		front_track = maxf(value, 0.2)
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export_range(0.05, 0.6, 0.005) var front_wheel_radius: float = 0.22:
	set(value):
		front_wheel_radius = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export var front_wheel_width: float = 0.22:
	set(value):
		front_wheel_width = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export var front_mesh_scale: float = 2.875:
	set(value):
		front_mesh_scale = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()

@export_group("Rear axle")
@export var rear_track: float = 1.5:
	set(value):
		rear_track = maxf(value, 0.2)
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export_range(0.05, 0.6, 0.005) var rear_wheel_radius: float = 0.22:
	set(value):
		rear_wheel_radius = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export var rear_wheel_width: float = 0.22:
	set(value):
		rear_wheel_width = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()
@export var rear_mesh_scale: float = 2.875:
	set(value):
		rear_mesh_scale = value
		if Engine.is_editor_hint() and is_inside_tree() and not _busy:
			_write_axles_to_setup()

@export_group("Preview")
@export var show_physics_ghost: bool = true:
	set(value):
		show_physics_ghost = value
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_ghost_visibility()
@export var auto_save_setup: bool = true

var _last_axle_pos: Array[Vector3] = []
var _busy: bool = false


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
	front_wheel_radius = float(setup.get("front_wheel_radius"))
	rear_wheel_radius = float(setup.get("rear_wheel_radius"))
	front_wheel_width = float(setup.get("front_wheel_width"))
	rear_wheel_width = float(setup.get("rear_wheel_width"))
	front_mesh_scale = float(setup.get("front_mesh_scale"))
	rear_mesh_scale = float(setup.get("rear_mesh_scale"))
	if front_track <= 0.01:
		front_track = 1.5
	if rear_track <= 0.01:
		rear_track = 1.5
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
	if scene == null:
		return

	for i in WHEEL_NAMES.size():
		var preview := Node3D.new()
		preview.name = "Preview_%s" % WHEEL_NAMES[i]
		preview.set_meta("_wheel_index", i)
		add_child(preview)

		var mesh_root := scene.instantiate() as Node3D
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


func _radius_for_index(index: int) -> float:
	return front_wheel_radius if index < 2 else rear_wheel_radius


func _width_for_index(index: int) -> float:
	return front_wheel_width if index < 2 else rear_wheel_width


func _scale_for_index(index: int) -> float:
	return front_mesh_scale if index < 2 else rear_mesh_scale


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
		var yaw_flip := 0.0
		if mirror_right and mount.x < 0.0:
			yaw_flip = 180.0
		var scale_v := _scale_for_index(i)
		var mesh_root := child.get_node_or_null("Mesh") as Node3D
		if mesh_root:
			mesh_root.scale = Vector3(scale_v, scale_v, scale_v)
			mesh_root.rotation_degrees = mesh_euler_degrees + Vector3(0.0, yaw_flip, 0.0)
		var ghost := child.get_node_or_null("PhysicsGhost") as MeshInstance3D
		if ghost and ghost.mesh is CylinderMesh:
			var cyl := ghost.mesh as CylinderMesh
			var radius := _radius_for_index(i)
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			cyl.height = _width_for_index(i)


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
