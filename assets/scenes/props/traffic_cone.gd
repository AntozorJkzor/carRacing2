extends RigidBody3D

## Light cone that tumbles and hops instead of sliding away in one piece.


func _ready() -> void:
	var mesh := $Mesh as MeshInstance3D
	var col := $Collision as CollisionShape3D
	if mesh == null or mesh.mesh == null or col == null:
		return
	col.transform = mesh.transform
	col.shape = mesh.mesh.create_convex_shape()
	contact_monitor = false
	can_sleep = true
	continuous_cd = true
