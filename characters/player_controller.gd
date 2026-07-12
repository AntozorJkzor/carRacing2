class_name PlayerController
extends CharacterBody3D

@export var walk_speed: float = 4.5
@export var run_speed: float = 7.5
@export var jump_velocity: float = 4.8
@export var mouse_sensitivity: float = 0.0025
@export var enter_distance: float = 4.5
@export var exit_offset: Vector3 = Vector3(2.2, 0.0, 0.0)
@export var anim_blend: float = 0.18

@onready var _head: Node3D = %Head
@onready var _camera: Camera3D = %Camera3D
@onready var _model: Node3D = $Model

var _anim: AnimationPlayer
var _anim_idle: String = ""
var _anim_walk: String = ""
var _anim_run: String = ""
var _anim_jump: String = ""
var _pitch: float = 0.0
var _active: bool = true
var _current_car: CarController = null
var _was_on_floor: bool = true


func _ready() -> void:
	add_to_group("player_character")
	_resolve_animations()
	set_on_foot(true)


func _resolve_animations() -> void:
	_anim = _find_animation_player(_model)
	if _anim == null:
		push_warning("Player model has no AnimationPlayer")
		return

	_anim_idle = _match_anim(["expectation", "idle", "Expectation"])
	_anim_walk = _match_anim(["walk", "Walk"])
	_anim_run = _match_anim(["run", "Run"])
	_anim_jump = _match_anim(["jump", "Jump"])
	_fallback_single_animation()

	# Loop locomotion / idle; jump plays once.
	for anim_name in _anim.get_animation_list():
		var animation := _anim.get_animation(anim_name)
		if animation == null:
			continue
		var lower := anim_name.to_lower()
		if "jump" in lower or "bow" in lower or "u-turn" in lower or "uturn" in lower:
			animation.loop_mode = Animation.LOOP_NONE
		else:
			animation.loop_mode = Animation.LOOP_LINEAR

	if _anim_idle != "":
		_anim.play(_anim_idle)
	elif _anim_run != "":
		_anim.play(_anim_run)


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
			# Prefer exact / suffix match; skip expectation.001 when looking for expectation
			# by taking the shortest matching name.
			if lower == key or lower.ends_with("/" + key) or lower.ends_with("|" + key):
				return anim_name
		for anim_name in list:
			var lower := String(anim_name).to_lower()
			if key in lower and not (key == "expectation" and ".001" in lower):
				return anim_name
	return ""


func _fallback_single_animation() -> void:
	if _anim == null:
		return
	var list := _anim.get_animation_list()
	if list.is_empty():
		return
	# player2-style models: one run clip only — use it for all locomotion states.
	if list.size() == 1:
		var only := list[0]
		_anim_run = only
		_anim_walk = only
		_anim_idle = only
		return
	if _anim_run == "":
		_anim_run = list[0]
	if _anim_walk == "":
		_anim_walk = _anim_run
	if _anim_idle == "":
		_anim_idle = _anim_run


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		_head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not _active:
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var jumped := false
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		jumped = true

	var input_dir := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := run_speed if Input.is_action_pressed("sprint") else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_update_animation(jumped)

	if Input.is_action_just_pressed("interact"):
		_try_enter_car()

	_was_on_floor = is_on_floor()


func _update_animation(jumped: bool) -> void:
	if _anim == null:
		return

	var horizontal := Vector2(velocity.x, velocity.z).length()
	var target := _anim_idle

	if not is_on_floor() or jumped:
		target = _anim_jump if _anim_jump != "" else target
	elif horizontal > run_speed * 0.75:
		target = _anim_run if _anim_run != "" else _anim_walk
	elif horizontal > 0.35:
		target = _anim_walk if _anim_walk != "" else _anim_idle
	else:
		target = _anim_idle

	if target == "":
		return
	if _anim.current_animation == target and _anim.is_playing():
		return
	# Don't interrupt jump mid-air with idle/walk until we land / jump ends.
	if (
		_anim.current_animation == _anim_jump
		and _anim.is_playing()
		and not is_on_floor()
		and target != _anim_jump
	):
		return
	_anim.play(target, anim_blend)


func set_on_foot(enabled: bool) -> void:
	_active = enabled
	visible = enabled
	$CollisionShape3D.disabled = not enabled
	set_physics_process(enabled)
	set_process_unhandled_input(enabled)
	if enabled:
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_current_car = null
		if _anim and _anim_idle != "":
			_anim.play(_anim_idle, anim_blend)
		elif _anim and _anim_run != "":
			_anim.play(_anim_run, anim_blend)
	else:
		velocity = Vector3.ZERO
		if _anim:
			_anim.stop()


func is_on_foot() -> bool:
	return _active


func _try_enter_car() -> void:
	var car := _find_nearest_car()
	if car == null:
		return
	_enter_car(car)


func _find_nearest_car() -> CarController:
	var best: CarController = null
	var best_dist := enter_distance
	for node in get_tree().get_nodes_in_group("player_cars"):
		var car := node as CarController
		if car == null or car.occupied:
			continue
		var d := global_position.distance_to(car.global_position)
		if d < best_dist:
			best_dist = d
			best = car
	return best


func _enter_car(car: CarController) -> void:
	_current_car = car
	set_on_foot(false)
	car.set_occupied(true, self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Used by cutscenes / scripted boarding.
func force_enter_car(car: CarController) -> void:
	if car == null:
		return
	_enter_car(car)


func play_run_animation() -> void:
	if _anim == null:
		_resolve_animations()
	if _anim == null:
		return
	if _anim_run == "":
		_fallback_single_animation()
	if _anim_run == "":
		return
	if _anim.current_animation == _anim_run and _anim.is_playing():
		return
	_anim.play(_anim_run, 0.0)


func exit_car() -> void:
	if _current_car == null:
		return
	var car := _current_car
	var exit_pos := car.to_global(exit_offset)
	exit_pos.y = 0.05
	car.set_occupied(false, null)
	_current_car = null
	global_position = exit_pos
	var away := global_position - car.global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		look_at(global_position + away.normalized(), Vector3.UP)
	set_on_foot(true)
