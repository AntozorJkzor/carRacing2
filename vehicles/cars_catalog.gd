class_name CarsCatalog
extends Resource

## List of cars available to spawn / pick in UI.
@export var cars: Array[CarDefinition] = []


func get_by_id(car_id: StringName) -> CarDefinition:
	for def: CarDefinition in cars:
		if def != null and def.id == car_id:
			return def
	return null


func get_scene(car_id: StringName) -> PackedScene:
	var def := get_by_id(car_id)
	if def == null:
		return null
	return def.scene


func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for def: CarDefinition in cars:
		if def != null and def.id != StringName():
			ids.append(def.id)
	return ids
