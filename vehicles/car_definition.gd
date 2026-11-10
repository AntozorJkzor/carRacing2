class_name CarDefinition
extends Resource

## Catalog entry for one driveable car pack.
## Pack workflow: duplicate assets/scenes/cars/<id>/ → set Model/Collision →
## FL–RR markers → *_setup.tres → *_wheel.tscn → *_audio.tres →
## assign setup / wheel_scene / audio_profile on the car root →
## PlayerDriver is part of the pack (also auto-created at runtime) → add here.
@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
## CarSetup .tres for this pack. Empty = convention res://assets/scenes/cars/<id>/<id>_setup.tres.
@export var setup_path: String = ""
## Podium yaw so the car shows a 3/4 view with the nose to the left.
@export var showroom_yaw_deg: float = 0.0


func get_setup_path() -> String:
	if not setup_path.is_empty():
		return setup_path
	return "res://assets/scenes/cars/%s/%s_setup.tres" % [String(id), String(id)]
