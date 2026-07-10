class_name NpcSpawner
extends Node3D

## Spawns a fixed count of each NPC type around the track.

@export var npc1_scene: PackedScene
@export var npc2_scene: PackedScene
@export var count_per_type: int = 30
@export var spawn_radius: float = 35.0
@export var min_spacing: float = 4.0
@export var spawn_y: float = 0.05
@export var spawn_seed: int = 77


func _ready() -> void:
	_spawn_all()


func _spawn_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	var used: Array[Vector3] = []

	if npc1_scene:
		for i in count_per_type:
			var pos := _next_pos(rng, used)
			_spawn_one(npc1_scene, pos, "Npc1_%d" % i)

	if npc2_scene:
		for i in count_per_type:
			var pos := _next_pos(rng, used)
			_spawn_one(npc2_scene, pos, "Npc2_%d" % i)


func _next_pos(rng: RandomNumberGenerator, used: Array[Vector3]) -> Vector3:
	for _attempt in 40:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(spawn_radius * 0.35, spawn_radius)
		var pos := global_position + Vector3(cos(angle) * dist, spawn_y, sin(angle) * dist)
		var ok := true
		for other in used:
			if Vector2(pos.x, pos.z).distance_to(Vector2(other.x, other.z)) < min_spacing:
				ok = false
				break
		if ok:
			used.append(pos)
			return pos
	var fallback := global_position + Vector3(rng.randf_range(-spawn_radius, spawn_radius), spawn_y, rng.randf_range(-spawn_radius, spawn_radius))
	used.append(fallback)
	return fallback


func _spawn_one(scene: PackedScene, pos: Vector3, node_name: String) -> void:
	var npc := scene.instantiate() as Node3D
	npc.name = node_name
	add_child(npc)
	npc.global_position = pos
