@tool
extends EditorScript

## File → Run to bake waveguide banks for one car.
## Change only CAR_NAME (folder + setup/audio names use the same slug).

const CAR_NAME := "volga"
const DURATION_SEC := 2.0


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
	var result: Dictionary = EngineSoundBaker.bake_setup(setup, out_dir, DURATION_SEC)
	print("Bake %s → %s" % [car, result])

	var profile := load(audio_profile)
	if profile == null:
		push_warning("Bake: no audio profile at %s (creating new)" % audio_profile)
		profile = CarAudioProfile.new()
	profile.set("idle_stream", load(str(result.get("idle", ""))))
	profile.set("low_stream", load(str(result.get("low", ""))))
	profile.set("mid_stream", load(str(result.get("mid", ""))))
	profile.set("max_stream", load(str(result.get("max", ""))))
	if profile.get("master_volume_db") == null:
		profile.set("master_volume_db", -9.1)
	var err := ResourceSaver.save(profile, audio_profile)
	print("Profile save (%s): %s" % [audio_profile, error_string(err)])
