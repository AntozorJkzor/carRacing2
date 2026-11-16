extends Node3D

## city.glb is a single multi-surface MeshInstance3D ("buildings"):
## asphalt/road markings + low building volumes. Trimesh the whole mesh.


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var mi := model.find_child("buildings", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		push_warning("city: buildings mesh not found")
		return
	_strip_collision(mi)
	mi.create_trimesh_collision()
	_configure_bodies(mi)
	call_deferred("_snap_actors_to_ground")


func _strip_collision(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is StaticBody3D or child is AnimatableBody3D:
			node.remove_child(child)
			child.free()


func _configure_bodies(mi: MeshInstance3D) -> void:
	for child in mi.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		body.collision_layer = 1
		body.collision_mask = 0


func _snap_actors_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		scene = owner
	_snap_node(scene.get_node_or_null("Car") as Node3D, space, 1.0)
	_snap_node(scene.get_node_or_null("Player") as Node3D, space, 1.1)
	var parent := get_parent()
	if parent:
		_snap_node(parent.get_node_or_null("Car") as Node3D, space, 1.0)
		_snap_node(parent.get_node_or_null("Player") as Node3D, space, 1.1)


func _snap_node(node: Node3D, space: PhysicsDirectSpaceState3D, clearance: float) -> void:
	if node == null:
		return
	var from := node.global_position + Vector3(0, 80, 0)
	var to := node.global_position + Vector3(0, -80, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [node.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var surface_y: float = hit.position.y
	if node.global_position.y < surface_y + clearance:
		node.global_position = Vector3(node.global_position.x, surface_y + clearance, node.global_position.z)
