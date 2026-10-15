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
