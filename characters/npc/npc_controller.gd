class_name NpcController
extends CharacterBody3D

## Shared NPC body: movement, animations, wander. Behavior is a separate Resource.

@export var behavior: NpcBehavior
@export var run_speed: float = 4.2
@export var jump_velocity: float = 4.5
@export var anim_blend: float = 0.15
@export var wander_radius: float = 14.0
@export var wander_pause_min: float = 0.6
@export var wander_pause_max: float = 2.2
@export var jump_chance_per_sec: float = 0.12
@export var car_hit_radius: float = 2.4
@export var car_hit_min_speed: float = 5.0
@export var launch_up_speed: float = 22.0
@export var launch_horizontal_mult: float = 1.35
@export var launch_cooldown: float = 1.2

@onready var _model: Node3D = $Model

var anim_run: String = ""
var anim_sit: String = ""
var anim_fight: String = ""

var _anim: AnimationPlayer
var _home: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_pause: float = 0.0
var _rng := RandomNumberGenerator.new()
var _player: Node3D = null
var _player_refresh: float = 0.0
var _launched: bool = false
var _launch_age: float = 0.0
var _hit_cooldown: float = 0.0
var _tumble_axis: Vector3 = Vector3.RIGHT
var _model_base_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("npcs")
	_rng.randomize()
	_resolve_animations()
	if _model:
		_model_base_transform = _model.transform
	if behavior:
		behavior.setup(self)
	# Spawner sets global_position after add_child; capture home next frame.
	call_deferred("_init_home")


func _init_home() -> void:
	_home = global_position
	_wander_target = _home
	_pick_new_wander_target()


func _physics_process(delta: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)

	if _launched:
		_tick_launch(delta)
		return

	_check_car_hits()

	_player_refresh -= delta
	if _player_refresh <= 0.0:
		_player_refresh = 0.5
		_refresh_player()

	if behavior:
		behavior.physics_tick(self, delta)
	else:
		tick_wander(delta)


func get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		return null
	# Only react while the player is on foot (not inside a car).
	if _player.has_method("is_on_foot") and not _player.is_on_foot():
		return null
	return _player


func distance_to_node(node: Node3D) -> float:
	var a := Vector2(global_position.x, global_position.z)
	var b := Vector2(node.global_position.x, node.global_position.z)
	return a.distance_to(b)


func is_moving_horizontally(threshold: float = 0.25) -> bool:
	return Vector2(velocity.x, velocity.z).length() > threshold


func play_anim(anim_name: String) -> void:
	if _anim == null or anim_name == "":
		return
	if _anim.current_animation == anim_name and _anim.is_playing():
		return
	_anim.play(anim_name, anim_blend)


func face_towards(world_pos: Vector3) -> void:
	var dir := world_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	look_at(global_position + dir.normalized(), Vector3.UP)


func stop_moving() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func move_towards(world_pos: Vector3, speed: float) -> void:
	var dir := world_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		stop_moving()
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	face_towards(world_pos)


func tick_gravity_and_slide(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	move_and_slide()


func try_random_jump(delta: float) -> void:
	if not is_on_floor():
		return
	if _rng.randf() < jump_chance_per_sec * delta:
		velocity.y = jump_velocity


func tick_wander(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()
		return

	if _wander_pause > 0.0:
		_wander_pause -= delta
		stop_moving()
		move_and_slide()
		return

	var flat := Vector3(_wander_target.x - global_position.x, 0.0, _wander_target.z - global_position.z)
	if flat.length() < 0.6:
		_wander_pause = _rng.randf_range(wander_pause_min, wander_pause_max)
		_pick_new_wander_target()
		stop_moving()
		move_and_slide()
		return

	try_random_jump(delta)
	move_towards(_wander_target, run_speed)
	move_and_slide()


func _pick_new_wander_target() -> void:
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(wander_radius * 0.25, wander_radius)
	_wander_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_wander_target.y = _home.y


func _refresh_player() -> void:
	_player = null
	var nodes := get_tree().get_nodes_in_group("player_character")
	if nodes.is_empty():
		return
	_player = nodes[0] as Node3D


func _check_car_hits() -> void:
	if _hit_cooldown > 0.0:
		return
	for node in get_tree().get_nodes_in_group("player_cars"):
		var car := node as RigidBody3D
		if car == null:
			continue
		var speed := car.linear_velocity.length()
		if speed < car_hit_min_speed:
			continue
		var flat := Vector2(global_position.x, global_position.z).distance_to(
			Vector2(car.global_position.x, car.global_position.z)
		)
		var vertical := absf(global_position.y - car.global_position.y)
		if flat <= car_hit_radius and vertical <= 2.2:
			apply_vehicle_hit(car)
			return


func apply_vehicle_hit(car: RigidBody3D) -> void:
	if _launched or _hit_cooldown > 0.0:
		return

	var car_vel: Vector3 = car.linear_velocity
	var push := car_vel
	push.y = 0.0
	if push.length_squared() < 0.01:
		push = -car.global_transform.basis.z
	push = push.normalized()

	var speed := maxf(car_vel.length(), car_hit_min_speed)
	velocity = push * speed * launch_horizontal_mult
	velocity.y = launch_up_speed + speed * 0.35

	_launched = true
	_launch_age = 0.0
	_hit_cooldown = launch_cooldown
	_tumble_axis = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.2, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()

	if _anim:
		_anim.stop()

	GameAudio.play_npc_hit()


func _tick_launch(delta: float) -> void:
	_launch_age += delta
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	# Light air drag so they arc instead of flying forever horizontally.
	velocity.x = move_toward(velocity.x, 0.0, 1.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 1.5 * delta)
	move_and_slide()

	if _model:
		_model.rotate(_tumble_axis, 8.0 * delta)

	if _launch_age > 0.35 and is_on_floor():
		_finish_launch()


func _finish_launch() -> void:
	_launched = false
	velocity = Vector3.ZERO
	if _model:
		_model.transform = _model_base_transform
	_home = global_position
	_pick_new_wander_target()
	if anim_run != "":
		play_anim(anim_run)


func _resolve_animations() -> void:
	_anim = _find_animation_player(_model)
	if _anim == null:
		push_warning("%s: no AnimationPlayer on model" % name)
		return

	anim_run = _match_anim(["run", "Run"])
	anim_sit = _match_anim(["sits", "sit", "Sits", "Sit"])
	anim_fight = _match_anim(["fight", "Fight"])

	for anim_name in _anim.get_animation_list():
		var animation := _anim.get_animation(anim_name)
		if animation == null:
			continue
		var lower := String(anim_name).to_lower()
		if "fight" in lower:
			# Loop fight while in melee so it doesn't freeze on last frame.
			animation.loop_mode = Animation.LOOP_LINEAR
		elif "sit" in lower:
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			animation.loop_mode = Animation.LOOP_LINEAR

	if anim_run != "":
		_anim.play(anim_run)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _match_anim(candidates: Array) -> String:
	if _anim == null:
		return ""
	var list := _anim.get_animation_list()
	for candidate in candidates:
		var key := str(candidate).to_lower()
		for anim_name in list:
			var lower := String(anim_name).to_lower()
			if lower == key or lower.ends_with("/" + key) or lower.ends_with("|" + key):
				return anim_name
		for anim_name in list:
			if key in String(anim_name).to_lower():
				return anim_name
	return ""
