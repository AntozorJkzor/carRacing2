@tool
extends Node3D

## Automotive material polish for imported GLB car bodies (civic / ae86).
## AI/photogrammetry exports ship chalky defaults: paint with metallic=0 and
## roughness=1. Upgrade in place at load: paint gets metallic + clearcoat,
## bright metals become chrome, windows become glossy dark tint.
## Attach as a child of the car's Model node.

var _done: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_polish()


func _polish() -> void:
	if _done:
		return
	_done = true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			_upgrade(mat)


func _upgrade(mat: StandardMaterial3D) -> void:
	var n := mat.resource_name.to_lower()
	if ("body" in n) or ("paint" in n):
		mat.metallic = 0.35
		mat.roughness = 0.32
		if mat.get("clearcoat_enabled") != null:
			mat.set("clearcoat_enabled", true)
			mat.set("clearcoat", 0.6)
			mat.set("clearcoat_roughness", 0.15)
		mat.rim_enabled = true
		mat.rim = 0.2
		mat.rim_tint = 0.5
	elif (
		("chrome" in n)
		or ("polished" in n)
		or ("metal" in n)
		or ("exhaust" in n)
		or ("echaust" in n)
		or ("steel" in n)
	):
		mat.metallic = 1.0
		mat.roughness = 0.22
	elif ("glass" in n) or ("window" in n) or ("windshield" in n) or ("backglass" in n):
		## Opaque glossy dark tint — a transparent swap would expose missing interior.
		mat.roughness = 0.06
		mat.metallic = 0.0
		var c := mat.albedo_color
		c.r = minf(c.r, 0.08)
		c.g = minf(c.g, 0.09)
		c.b = minf(c.b, 0.11)
		mat.albedo_color = c
	elif ("tire" in n) or ("rubber" in n):
		mat.roughness = 0.9
		mat.metallic = 0.0
	elif "trim" in n:
		mat.roughness = 0.55
