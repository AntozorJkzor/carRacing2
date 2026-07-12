extends Node3D

## Crosses the road, falls from the sky, or chases the player car.

enum Mode { CROSS, SKY_DROP, CHASE }

@export var move_speed: float = 5.5
@export var car_hit_radius: float = 2.2
@export var car_hit_min_speed: float = 6.0
@export var npc_kind: String = "npc1"

var _mode: Mode = Mode.CROSS
var _goal_x: float = 0.0
var _anim: AnimationPlayer
var _done: bool = false
var _launched: bool = false
var _hit_reported: bool = false
var _falling: bool = false
var _landed: bool = false
var _fall_velocity: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _tumble_axis: Vector3 = Vector3.RIGHT
var _rng := RandomNumberGenerator.new()
var _chase_target: Node3D
var _chase_after_land: bool = false
var _hit_even_if_slow: bool = false


func setup_cross(
	from_x: float,
	to_x: float,
	z: float,
	speed: float,
	anim_name: String = "run",
	kind: String = "npc1"
) -> void:
	_rng.randomize()
	_mode = Mode.CROSS
	npc_kind = kind
	_chase_target = null
	_chase_after_land = false
	_hit_even_if_slow = false
	global_position = Vector3(from_x, 0.0, z)
	_goal_x = to_x
	move_speed = speed
	_done = false
	_launched = false
	_hit_reported = false
	_falling = false
	_landed = true
	_resolve_anim()
	_play_anim(anim_name if anim_name != "" else "run")
	_face_toward_goal()


func setup_sky_drop(x: float, z: float, kind: String = "npc1", height: float = 28.0) -> void:
	_rng.randomize()
	_mode = Mode.SKY_DROP
	npc_kind = kind
	_chase_target = null
	_chase_after_land = false
	_hit_even_if_slow = false
	global_position = Vector3(x, height, z)
	_goal_x = x
	_done = false
	_launched = false
	_hit_reported = false
	_falling = true
	_landed = false
	_fall_velocity = 0.0
	_resolve_anim()
	var pool: Array[String] = ["sits", "run", "fight", "an1", "an2", "an3", "an4"]
	var pick := pool[_rng.randi_range(0, pool.size() - 1)]
	_play_anim(pick)
	rotation_degrees = Vector3(_rng.randf_range(-20.0, 20.0), _rng.randf_range(0.0, 360.0), _rng.randf_range(-20.0, 20.0))


## Spawn on ground and immediately run at the car.
func setup_chase(
	from_pos: Vector3,
	target: Node3D,
	speed: float,
	kind: String = "npc1"
) -> void:
	_rng.randomize()
	_mode = Mode.CHASE
	npc_kind = kind
	_chase_target = target
	_chase_after_land = false
	_hit_even_if_slow = true
	global_position = Vector3(from_pos.x, 0.0, from_pos.z)
	move_speed = speed
	_done = false
	_launched = false
	_hit_reported = false
	_falling = false
	_landed = true
	_resolve_anim()
	_play_anim("run")
	_face_toward_target()


## Drop from sky, then run straight at the car.
func setup_sky_chase(
	x: float,
	z: float,
	target: Node3D,
	kind: String = "npc1",
	height: float = 28.0,
	speed: float = 8.0
) -> void:
	_rng.randomize()
	_mode = Mode.SKY_DROP
	npc_kind = kind
	_chase_target = target
	_chase_after_land = true
	_hit_even_if_slow = true
	move_speed = speed
	global_position = Vector3(x, height, z)
	_goal_x = x
	_done = false
	_launched = false
	_hit_reported = false
	_falling = true
	_landed = false
	_fall_velocity = 0.0
	_resolve_anim()
	_play_anim("run")
	rotation_degrees = Vector3(_rng.randf_range(-15.0, 15.0), _rng.randf_range(0.0, 360.0), _rng.randf_range(-15.0, 15.0))


func is_finished() -> bool:
	return _done


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _launched:
		_tick_launch(delta)
		return
	if _falling:
		_tick_fall(delta)
		_check_car_hit()
		return
	_check_car_hit()
	if _mode == Mode.CROSS:
		var dx := _goal_x - global_position.x
		if absf(dx) <= 0.35:
			_done = true
			return
		var dir := signf(dx)
		global_position.x += dir * move_speed * delta
		global_position.y = 0.0
		_face_toward_goal()
	elif _mode == Mode.CHASE:
		_tick_chase(delta)


func _tick_chase(delta: float) -> void:
	if _chase_target == null or not is_instance_valid(_chase_target):
		_done = true
		return
	var to := _chase_target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.15:
		global_position += to / dist * move_speed * delta
	global_position.y = 0.0
	_face_toward_target()
	_play_anim("run")


func _tick_fall(delta: float) -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_fall_velocity += gravity * delta
	global_position.y -= _fall_velocity * delta
	rotate(Vector3.UP, 1.5 * delta)
	if global_position.y <= 0.0:
		global_position.y = 0.0
		_falling = false
		_landed = true
		_fall_velocity = 0.0
		rotation = Vector3(0.0, rotation.y, 0.0)
		if _chase_after_land and _chase_target != null and is_instance_valid(_chase_target):
			_mode = Mode.CHASE
			_play_anim("run")
			_face_toward_target()
		else:
			_play_anim("sits")


func _face_toward_goal() -> void:
	var look := Vector3(_goal_x - global_position.x, 0.0, 0.0)
	if look.length_squared() < 0.0001:
		return
	look_at(global_position + look.normalized(), Vector3.UP)


func _face_toward_target() -> void:
	if _chase_target == null or not is_instance_valid(_chase_target):
		return
	var look := _chase_target.global_position - global_position
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return
	look_at(global_position + look.normalized(), Vector3.UP)


func _check_car_hit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player_cars"):
		var car := node as RigidBody3D
		if car == null:
			continue
		var speed := car.linear_velocity.length()
		if speed < car_hit_min_speed and not _hit_even_if_slow:
			continue
		var flat := Vector2(global_position.x, global_position.z).distance_to(
			Vector2(car.global_position.x, car.global_position.z)
		)
		if flat > car_hit_radius:
			continue
		if absf(global_position.y - car.global_position.y) > 3.5:
			continue
		_apply_hit(car)
		return


func _apply_hit(car: RigidBody3D) -> void:
	if _hit_reported:
		return
	_hit_reported = true
	_falling = false
	var push := car.linear_velocity
	push.y = 0.0
	if push.length_squared() < 0.01:
		push = global_position - car.global_position
		push.y = 0.0
	if push.length_squared() < 0.01:
		push = -car.global_transform.basis.z
	push = push.normalized()
	var speed := maxf(car.linear_velocity.length(), car_hit_min_speed)
	_velocity = push * speed * 1.2
	_velocity.y = 16.0 + speed * 0.25
	_launched = true
	_tumble_axis = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(0.2, 1.0),
		_rng.randf_range(-1.0, 1.0)
	).normalized()
	if _anim:
		_anim.stop()
	if GameAudio and GameAudio.has_method("play_npc_hit"):
		GameAudio.play_npc_hit(npc_kind)
	get_tree().call_group("run_stats", "on_npc_hit", npc_kind)


func _tick_launch(delta: float) -> void:
	_velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	_velocity.x = move_toward(_velocity.x, 0.0, 1.2 * delta)
	_velocity.z = move_toward(_velocity.z, 0.0, 1.2 * delta)
	global_position += _velocity * delta
	rotate(_tumble_axis, 10.0 * delta)
	if global_position.y < 0.0 and _velocity.y <= 0.0:
		_done = true


func _resolve_anim() -> void:
	_anim = _find_animation_player(self)


func _play_anim(anim_name: String) -> void:
	if _anim == null or anim_name == "":
		return
	var play_name := anim_name
	if not _anim.has_animation(play_name) and _anim.has_animation("run"):
		play_name = "run"
	if not _anim.has_animation(play_name):
		return
	if _anim.current_animation == play_name and _anim.is_playing():
		return
	var animation := _anim.get_animation(play_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	_anim.play(play_name)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
