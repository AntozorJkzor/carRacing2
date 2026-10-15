extends EditorScript
## File → Run to bake a sample bank into res://audio/engines/i4_2_5L_8v
## Requires EngineSimBaker GDExtension.

func _run() -> void:
	if not ClassDB.class_exists("EngineSimBaker"):
		push_error("EngineSimBaker missing — enable addons/engine_sim_audio")
		return

	var baker: RefCounted = ClassDB.instantiate("EngineSimBaker")
	baker.call("apply_params", {
		"name": "i4_2_5L_8v",
		"cylinders": 4,
		"displacement_cc": 2500.0,
		"valves_per_cylinder": 2,
		"layout": 0, # Inline
		"min_rpm": 800.0,
		"max_rpm": 5600.0,
		"rpm_step": 250.0,
		"throttle": 1.0,
		"settle_seconds": 1.0,
		"capture_seconds": 1.5,
		"exhaust_length_mm": 500.0,
		"cam_duration_deg": 220.0,
		"cam_lift_mm": 9.5,
	})
	var result: Dictionary = baker.call("bake_and_save", "res://audio/engines/i4_2_5L_8v")
	print(result)
	if result.get("ok", false):
		EditorInterface.get_resource_filesystem().scan()
