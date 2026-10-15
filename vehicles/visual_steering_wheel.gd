extends Node3D

## Rotates a body-mesh steering wheel to match CarController steer.
## Attach to a child of the car (Volga: VisualSteeringWheel on volga.tscn).
## Mesh pivot is often not the wheel center — a hub is inserted at AABB center.

@export var mesh_path: NodePath = NodePath("../Model/INT_Steering")
## Fallback names (node or ArrayMesh.resource_name) if mesh_path is empty/missing.
@export var mesh_names: PackedStringArray = [
	"INT_Steering",
	"volga_Torus_001",
	"volga_Torus001",
]
## Visual lock at full road-wheel lock. Road wheels are ~32°.
@export_range(90.0, 900.0, 5.0) var visual_lock_degrees: float = 450.0
## Flip if left steer turns the rim the wrong way from the cockpit.
@export var invert: bool = true
## Mesh-local spin axis. (0,0,0) = thinnest AABB axis (disc normal).
@export var local_axis: Vector3 = Vector3.ZERO

var _car: CarController
var _hub: Node3D
var _rest_basis: Basis = Basis.IDENTITY
var _axis: Vector3 = Vector3.BACK


func _ready() -> void:
	_car = get_parent() as CarController
	_bind_mesh()


func _physics_process(_delta: float) -> void:
	if _hub == null or _car == null or _car.setup == null:
		return
	var max_road := deg_to_rad(maxf(_car.setup.max_steer_angle, 1.0))
	var t := clampf(_car.debug_steer_rad / max_road, -1.0, 1.0)
	var angle := t * deg_to_rad(visual_lock_degrees)
	if invert:
		angle = -angle
	_hub.basis = _rest_basis * Basis(_axis, angle)


func _bind_mesh() -> void:
	var mesh := _find_mesh()
	if mesh == null:
		var id := String(_car.car_id) if _car != null else "?"
		push_warning("VisualSteeringWheel: steering mesh not found on '%s'" % id)
		return
	_insert_hub(mesh)


func _find_mesh() -> MeshInstance3D:
	if mesh_path != NodePath():
		var n := get_node_or_null(mesh_path)
		if n is MeshInstance3D:
			return n as MeshInstance3D
	if _car == null:
		return null
	var model := _car.get_node_or_null("Model")
	var root: Node = model if model != null else _car
	return _search_mesh(root)


func _search_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if _name_matches(String(mi.name)):
			return mi
		if mi.mesh != null and _name_matches(mi.mesh.resource_name):
			return mi
	for child: Node in node.get_children():
		var found := _search_mesh(child)
		if found != null:
			return found
	return null


func _name_matches(n: String) -> bool:
	var key := n.to_lower().replace(" ", "").replace("-", "_")
	for candidate: String in mesh_names:
		var c := candidate.to_lower().replace(" ", "").replace("-", "_")
		if key == c or key.contains(c) or c.contains(key):
			return true
	return false


func _insert_hub(mesh: MeshInstance3D) -> void:
	var parent := mesh.get_parent() as Node3D
	if parent == null:
		return
	if parent.name == "SteeringHub":
		_hub = parent
		_rest_basis = _hub.basis
		return
	var aabb := mesh.get_aabb()
	if local_axis.length_squared() > 0.0001:
		_axis = local_axis.normalized()
	else:
		_axis = _thinnest_axis(aabb.size)
	_hub = Node3D.new()
	_hub.name = "SteeringHub"
	parent.add_child(_hub)
	_hub.global_transform = Transform3D(
		mesh.global_transform.basis.orthonormalized(),
		mesh.to_global(aabb.get_center())
	)
	var keep := mesh.global_transform
	parent.remove_child(mesh)
	_hub.add_child(mesh)
	mesh.global_transform = keep
	_rest_basis = _hub.basis


func _thinnest_axis(size: Vector3) -> Vector3:
	if size.z <= size.x and size.z <= size.y:
		return Vector3.BACK
	if size.x <= size.y:
		return Vector3.RIGHT
	return Vector3.UP
