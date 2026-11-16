extends Node3D

## Poly Haven street_lamp_01 (CC0). Pole collision plus a pool of light under the lantern.


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			var label := mat.resource_name.to_lower()
			if "bulb" in label:
				var glow := mat.duplicate() as StandardMaterial3D
				glow.emission_enabled = true
				glow.emission = Color(1.0, 0.8, 0.42)
				glow.emission_energy_multiplier = 8.0
				mesh.set_surface_override_material(surface, glow)
			elif "glass" in label:
				var glass := mat.duplicate() as StandardMaterial3D
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				glass.alpha_scissor_threshold = 0.4
				mesh.set_surface_override_material(surface, glass)
