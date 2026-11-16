class_name TracksCatalog
extends Resource

@export var tracks: Array[TrackDefinition] = []


func get_by_id(track_id: StringName) -> TrackDefinition:
	for def: TrackDefinition in tracks:
		if def != null and def.id == track_id:
			return def
	return null


func get_scene(track_id: StringName) -> PackedScene:
	var def := get_by_id(track_id)
	return def.scene if def != null else null
