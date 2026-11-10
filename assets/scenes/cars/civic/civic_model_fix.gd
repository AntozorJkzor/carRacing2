@tool
extends Node

## civic.glb quirks:
## - Steering rim imported as VehicleWheel3D → strip so RigidBody owns physics.
## - Lamp glass is nearly-opaque alpha+emission → draws over smoke; harden depth.


func _ready() -> void:
	var car := get_parent()
	if car == null:
		return
	_harden_lamp_materials(car)
	if Engine.is_editor_hint():
		return
	_strip_vehicle_wheels(car)


func _strip_vehicle_wheels(car: Node) -> void:
	for node in car.find_children("*", "VehicleWheel3D", true, false):
		var wheel := node as VehicleWheel3D
		if wheel == null:
			continue
		var keep: Array[Node] = []
		for child in wheel.get_children():
			keep.append(child)
		var parent := wheel.get_parent()
		for child in keep:
			wheel.remove_child(child)
			parent.add_child(child)
			child.owner = wheel.owner
			if child is Node3D and wheel is Node3D:
				(child as Node3D).transform = wheel.transform * (child as Node3D).transform
		wheel.queue_free()


func _harden_lamp_materials(car: Node) -> void:
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var mesh_key := String(mesh.name).to_lower()
		var is_lamp_mesh := (
			"frontlight" in mesh_key
			or "backlight" in mesh_key
			or "backdouble" in mesh_key
			or "headlight" in mesh_key
			or "taillight" in mesh_key
		)
		if not is_lamp_mesh:
			continue
		for surface in mesh.mesh.get_surface_count():
			var active := mesh.get_active_material(surface)
			if active == null or not (active is StandardMaterial3D):
				continue
			var src := active as StandardMaterial3D
			var mat_key := src.resource_name.to_lower()
			var is_lamp_mat := (
				"headlight" in mat_key
				or "taillight" in mat_key
				or "turnsignal" in mat_key
				or "turn_signal" in mat_key
				or "amber" in mat_key
			)
			if not is_lamp_mat and src.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var copy := src.duplicate() as StandardMaterial3D
			## Opaque emissive lamps write depth so wheel smoke can cover them.
			copy.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			var albedo := copy.albedo_color
			albedo.a = 1.0
			copy.albedo_color = albedo
			copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			copy.no_depth_test = false
			mesh.set_surface_override_material(surface, copy)
