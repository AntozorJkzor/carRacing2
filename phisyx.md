class_name PlayerController
extends CharacterBody3D

@export var walk_speed: float = 4.5
@export var run_speed: float = 7.5
@export var jump_velocity: float = 4.8
@export var mouse_sensitivity: float = 0.0025
@export var enter_distance: float = 4.5
@export var exit_offset: Vector3 = Vector3(2.2, 0.0, 0.0)
@export var anim_blend: float = 0.18
@export var look_around_idle_delay: float = 15.0
@export var turn_speed: float = 14.0
@export var model_yaw_offset: float = PI
@export var model_scale: float = 2.0

@onready var _head: Node3D = %Head
@onready var _camera: Camera3D = %Camera3D
@onready var _model: Node3D = $Model

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _hips_bone: int = -1
var _anim_idle: String = ""
var _anim_walk: String = ""
var _anim_run: String = ""
var _anim_look: String = ""
var _anim_dance: String = ""
var _pitch: float = 0.0
var _cam_yaw: float = 0.0
var _body_yaw: float = PI
var _active: bool = true
var _current_car: CarController = null
var _was_on_floor: bool = true
var _idle_time: float = 0.0
var _looking_around: bool = false
var _dancing: bool = false


func _ready() -> void:
	add_to_group("player_character")
	_body_yaw = model_yaw_offset
	_apply_model_yaw(_body_yaw)
	_resolve_animations()
	set_on_foot(true)


func _resolve_animations() -> void:
	_anim = _find_animation_player(_model)
	_skeleton = _find_skeleton(_model)
	if _skeleton != null:
		_hips_bone = _find_hips_bone(_skeleton)
	if _anim == null:
		push_warning("Player model has no AnimationPlayer")
		return

	_anim_idle = _match_anim(["idle"])
	_anim_walk = _match_anim(["walk"])
	_anim_run = _match_anim(["run"])
	_anim_look = _match_anim(["look_around", "look around", "lookaround"])
	_anim_dance = _match_anim(["танц", "dance", "blackhole", "muse"])
	_fallback_single_animation()
	_strip_root_xz_motion()

	for anim_name in _anim.get_animation_list():
		var animation := _anim.get_animation(anim_name)
		if animation == null:
			continue
		var lower := String(anim_name).to_lower()
		if anim_name == _anim_look:
			animation.loop_mode = Animation.LOOP_NONE
		elif anim_name == _anim_dance or "walk" in lower or "run" in lower or "idle" in lower:
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			animation.loop_mode = Animation.LOOP_NONE

	if not _anim.animation_finished.is_connected(_on_animation_finished):
		_anim.animation_finished.connect(_on_animation_finished)

	if _anim_idle != "":
		_anim.play(_anim_idle)


func _strip_root_xz_motion() -> void:
	## Mixamo hip position tracks slide the mesh away from the capsule while running.
	if _anim == null:
		return
	for anim_name in _anim.get_animation_list():
		var animation := _anim.get_animation(anim_name)
		if animation == null:
			continue
		for track_i in range(animation.get_track_count()):
			if animation.track_get_type(track_i) != Animation.TYPE_POSITION_3D:
				continue
			var path := String(animation.track_get_path(track_i)).to_lower()
			if "hip" not in path:
				continue
			for key_i in range(animation.track_get_key_count(track_i)):
				var pos: Vector3 = animation.track_get_key_value(track_i, key_i)
				pos.x = 0.0
				pos.z = 0.0
				animation.track_set_key_value(track_i, key_i, pos)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_hips_bone(skeleton: Skeleton3D) -> int:
	for i in range(skeleton.get_bone_count()):
		var lower := skeleton.get_bone_name(i).to_lower()
		if "hip" in lower or "pelvis" in lower:
			return i
	return -1


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
			var lower := String(anim_name).to_lower()
			if key in lower:
				return anim_name
	return ""


func _fallback_single_animation() -> void:
	if _anim == null:
		return
	var list := _anim.get_animation_list()
	if list.is_empty():
		return
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
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var rel: Vector2 = motion.relative
		# Camera only — body stays put while idle / turns toward move dir while walking.
		_cam_yaw -= rel.x * mouse_sensitivity
		_pitch = clampf(_pitch - rel.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		_head.rotation = Vector3(_pitch, _cam_yaw, 0.0)
	if event.is_action_pressed("dance"):
		_try_start_dance()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	FrameClock.measure("phys:player", _profiled_physics_process, delta)


func _profiled_physics_process(delta: float) -> void:
	if not _active:
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_cancel_idle_extras()

	var input_dir := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var cam_basis := Basis(Vector3.UP, _cam_yaw)
	var direction := (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y))
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	var speed := run_speed if Input.is_action_pressed("sprint") else walk_speed
	var moving := direction != Vector3.ZERO

	if moving:
		_cancel_idle_extras()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Face the actual move direction so side / diagonal walks look correct.
		var target_yaw: float = atan2(direction.x, direction.z) + model_yaw_offset
		_body_yaw = lerp_angle(_body_yaw, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		_apply_model_yaw(_body_yaw)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_stabilize_hips()
	_update_animation(delta, moving, speed)

	if Input.is_action_just_pressed("interact"):
		_try_enter_car()

	_was_on_floor = is_on_floor()


func _apply_model_yaw(yaw: float) -> void:
	if _model == null:
		return
	_model.scale = Vector3(model_scale, model_scale, model_scale)
	_model.rotation = Vector3(0.0, yaw, 0.0)


func _stabilize_hips() -> void:
	if _skeleton == null or _hips_bone < 0:
		return
	var pos := _skeleton.get_bone_pose_position(_hips_bone)
	if absf(pos.x) < 0.0001 and absf(pos.z) < 0.0001:
		return
	pos.x = 0.0
	pos.z = 0.0
	_skeleton.set_bone_pose_position(_hips_bone, pos)


func _update_animation(delta: float, moving: bool, speed: float) -> void:
	if _anim == null:
		return

	var horizontal := Vector2(velocity.x, velocity.z).length()

	if _dancing:
		if _anim_dance != "" and _anim.current_animation != _anim_dance:
			_anim.play(_anim_dance, anim_blend)
		return

	if _looking_around:
		return

	var target := _anim_idle
	if moving or horizontal > 0.35:
		_idle_time = 0.0
		var sprinting := Input.is_action_pressed("sprint")
		if horizontal > run_speed * 0.75 or (moving and sprinting):
			target = _anim_run if _anim_run != "" else _anim_walk
		else:
			target = _anim_walk if _anim_walk != "" else _anim_idle
	else:
		_idle_time += delta
		target = _anim_idle
		if (
			_idle_time >= look_around_idle_delay
			and _anim_look != ""
			and is_on_floor()
		):
			_idle_time = 0.0
			_looking_around = true
			_anim.play(_anim_look, anim_blend)
			return

	_play_locomotion(target)


func _play_locomotion(target: String) -> void:
	if target == "":
		return
	if _anim.current_animation == target and _anim.is_playing():
		return
	_anim.play(target, anim_blend)


func _try_start_dance() -> void:
	if not _active or _anim == null or _anim_dance == "":
		return
	if not is_on_floor():
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if horizontal > 0.35:
		return
	_looking_around = false
	_dancing = true
	_idle_time = 0.0
	_anim.play(_anim_dance, anim_blend)


func _cancel_idle_extras() -> void:
	_dancing = false
	_looking_around = false
	_idle_time = 0.0


func _on_animation_finished(anim_name: StringName) -> void:
	if String(anim_name) == _anim_look and _looking_around:
		_looking_around = false
		_idle_time = 0.0
		if _anim_idle != "":
			_anim.play(_anim_idle, anim_blend)


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
		_rebind_minimap()
		_cancel_idle_extras()
		_head.rotation = Vector3(_pitch, _cam_yaw, 0.0)
		_apply_model_yaw(_body_yaw)
		if _anim and _anim_idle != "":
			_anim.play(_anim_idle, anim_blend)
		elif _anim and _anim_run != "":
			_anim.play(_anim_run, anim_blend)
	else:
		velocity = Vector3.ZERO
		_cancel_idle_extras()
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	_cancel_idle_extras()
	if _anim.current_animation == _anim_run and _anim.is_playing():
		return
	_anim.play(_anim_run, 0.0)


func exit_car() -> void:
	if _current_car == null:
		return
	var car := _current_car
	var exit_pos := _find_exit_position(car)
	car.set_occupied(false, null)
	_current_car = null
	global_position = exit_pos
	velocity = Vector3.ZERO
	var away := global_position - car.global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		var face := away.normalized()
		_body_yaw = atan2(face.x, face.z) + model_yaw_offset
		_apply_model_yaw(_body_yaw)
	set_on_foot(true)


func _find_exit_position(car: CarController) -> Vector3:
	## Prefer right side, then left — snap Y to ground under the mountain road.
	var candidates: Array[Vector3] = [
		exit_offset,
		Vector3(-exit_offset.x, exit_offset.y, exit_offset.z),
	]
	for local_off: Vector3 in candidates:
		var probe := car.to_global(local_off)
		var snapped := _snap_to_ground(probe, car)
		if snapped != Vector3.INF:
			return snapped
	## Last resort: keep lateral offset, use car height (never force Y=0).
	var fallback := car.to_global(exit_offset)
	fallback.y = car.global_position.y + 0.2
	return fallback


func _snap_to_ground(around: Vector3, exclude: Node3D) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var from_y := maxf(around.y + 3.0, exclude.global_position.y + 2.5)
	var from := Vector3(around.x, from_y, around.z)
	var to := from + Vector3.DOWN * 40.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var exclude_rids: Array[RID] = [get_rid()]
	if exclude is CollisionObject3D:
		exclude_rids.append((exclude as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("player_cars"):
		if node is CollisionObject3D:
			exclude_rids.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude_rids
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var pos: Vector3 = hit.position
	pos.y += 0.1
	return pos


func _rebind_minimap() -> void:
	if not is_inside_tree():
		return
	for hud in get_tree().get_nodes_in_group("car_huds"):
		var minimap := hud.get_node_or_null("Minimap")
		if minimap != null and minimap.has_method("bind_target"):
			minimap.bind_target(self)
