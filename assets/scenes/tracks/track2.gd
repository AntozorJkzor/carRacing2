extends Node3D

const MinimapLayers := preload("res://rendering/minimap_layers.gd")

## Terrain = off-road / underlay. TrackRoad = driving surface (now thickened).
## Both get trimesh; guardrails are walls.
const GROUND_MESHES := ["Terrain", "TrackRoad"]
const WALL_MESHES := ["Guardrail_L", "Guardrail_R"]


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return

	for mesh_name in GROUND_MESHES + WALL_MESHES:
		var mi := model.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		_strip_collision(mi)
		mi.create_trimesh_collision()
		_configure_bodies(mi)

	call_deferred("_snap_actors_to_ground")
	call_deferred("_batch_trees")


## The GLB ships ~630 trees as individual MeshInstance3D nodes (~630 draw
## calls, whole scene drawn twice — the minimap camera sees layer 1 too).
## Re-bake them into one MultiMeshInstance3D per tree mesh and move them to
## the EFFECTS layer so only the main camera renders them.
func _batch_trees() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var groups: Dictionary = {}
	var trees: Array[MeshInstance3D] = []
	for child in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or _is_ground_mesh(mi.name):
			continue
		if not _has_tripo_material(mi):
			continue
		trees.append(mi)
		if not groups.has(mi.mesh):
			groups[mi.mesh] = []
		(groups[mi.mesh] as Array).append(mi)
	if trees.size() < 4:
		return
	var inv := model.global_transform.affine_inverse()
	for mesh in groups:
		var list: Array = groups[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, inv * (list[i] as MeshInstance3D).global_transform)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_%s" % mesh.resource_name
		mmi.multimesh = mm
		mmi.layers = MinimapLayers.EFFECTS
		model.add_child(mmi)
	for t in trees:
		t.queue_free()
	print("track2: batched %d trees into %d MultiMesh draws" % [trees.size(), groups.size()])


func _is_ground_mesh(node_name: String) -> bool:
	for g in GROUND_MESHES + WALL_MESHES:
		if node_name == g:
			return true
	return false


func _has_tripo_material(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat != null and mat.resource_name.begins_with("tripo"):
			return true
	return false


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
	## Lift car/player if the scene spawn Y is below the road/terrain surface.
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		scene = owner
	_snap_node(scene.get_node_or_null("Car"), space, 1.0)
	_snap_node(scene.get_node_or_null("Player"), space, 1.1)
	# Also try relative to this track (physics_test_track parents)
	var parent := get_parent()
	if parent:
		_snap_node(parent.get_node_or_null("Car"), space, 1.0)
		_snap_node(parent.get_node_or_null("Player"), space, 1.1)


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
		print("track2: snapped %s to Y=%.2f (surface %.2f)" % [node.name, node.global_position.y, surface_y])
