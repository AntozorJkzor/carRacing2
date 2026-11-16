extends Node3D

## Two rows of street lamps. The car starts in the gap between them.
## 60 m between the rows, 40 m between poles in a row.
## Cones sit on the road side of each pole.

const LAMP_SCENE := preload("res://assets/scenes/props/street_lamp.tscn")
const CONE_SCENE := preload("res://assets/scenes/props/traffic_cone.tscn")

@export var poles_per_row: int = 8
@export var row_gap: float = 60.0
@export var pole_spacing: float = 40.0


func _ready() -> void:
	var half_gap := row_gap * 0.5
	var z0 := -pole_spacing * float(poles_per_row - 1) * 0.5
	for side in [-1.0, 1.0]:
		var x := float(side) * half_gap
		for i in poles_per_row:
			var z := z0 + pole_spacing * float(i)
			var lamp := LAMP_SCENE.instantiate()
			lamp.position = Vector3(x, 0.0, z)
			lamp.rotation.y = PI * 0.5 if side > 0.0 else -PI * 0.5
			add_child(lamp)
			for along in [-1.3, 1.3]:
				var cone := CONE_SCENE.instantiate() as RigidBody3D
				cone.position = Vector3(x - side * 2.5, 0.03, z + along)
				cone.rotation.y = randf() * TAU
				add_child(cone)
