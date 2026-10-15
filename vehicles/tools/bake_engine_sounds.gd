@tool
extends EditorScript

## File → Run to bake EngineSim banks every 250 RPM for one car.
## Change only CAR_NAME (folder + setup/audio names use the same slug).

const CAR_NAME := "volga"
const DURATION_SEC := 1.0


func _run() -> void:
	var car := CAR_NAME.strip_edges().to_lower()
	if car.is_empty():
		push_error("Bake: CAR_NAME is empty")
		return
	var car_setup := "res://assets/scenes/cars/%s/%s_setup.tres" % [car, car]
	var audio_profile := "res://assets/scenes/cars/%s/%s_audio.tres" % [car, car]
	var out_dir := "res://assets/audio/engines/%s" % car

	var setup := load(car_setup)
	if setup == null:
		push_error("Bake: missing setup %s" % car_setup)
		return
	var result: Dictionary = EngineBankBaker.bake_setup(setup, out_dir, DURATION_SEC)
	var names: PackedStringArray = result.get("names", PackedStringArray())
	print("Bake %s → %d bands" % [car, names.size()])

	var profile := load(audio_profile)
	if profile == null:
		push_warning("Bake: no audio profile at %s (creating new)" % audio_profile)
		profile = CarAudioProfile.new()
	# Pack profile still has 4 slots — stash idle / ~1/3 / ~2/3 / max as fallbacks.
	if names.size() > 0:
		var last := names.size() - 1
		profile.set("idle_stream", load(str(result.get(names[0], ""))))
		profile.set("low_stream", load(str(result.get(names[last / 3], ""))))
		profile.set("mid_stream", load(str(result.get(names[(last * 2) / 3], ""))))
		profile.set("max_stream", load(str(result.get(names[last], ""))))
	if profile.get("master_volume_db") == null:
		profile.set("master_volume_db", -9.1)
	var err := ResourceSaver.save(profile, audio_profile)
	print("Profile save (%s): %s" % [audio_profile, error_string(err)])
