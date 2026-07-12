extends Node3D

## Cutscene mob member: marches forward in formation with random looping anims.

@export var move_speed: float = 4.0

var _march_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var _anim: AnimationPlayer
var _anim_pool: Array[String] = []
var _anim_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup_march(
	direction: Vector3,
	speed: float,
	anim_pool: Array,
	initial_anim: String = ""
) -> void:
	_rng.randomize()
	_march_dir = direction
	_march_dir.y = 0.0
	if _march_dir.length_squared() < 0.0001:
		_march_dir = Vector3(0.0, 0.0, 1.0)
	else:
		_march_dir = _march_dir.normalized()
	move_speed = speed
	_anim_pool.clear()
	for item in anim_pool:
		_anim_pool.append(str(item))
	_anim = _find_animation_player(self)
	if _anim != null:
		for anim_name: String in _anim_pool:
			if _anim.has_animation(anim_name):
				var animation := _anim.get_animation(anim_name)
				if animation != null:
					animation.loop_mode = Animation.LOOP_LINEAR
	_play_random_anim(initial_anim)
	_anim_timer = _rng.randf_range(0.6, 1.8)
	_face_march_dir()


## Backward-compatible alias used by older call sites.
func setup(target: Node3D, anim_name: String, speed: float, _face_yaw_offset_deg: float = 0.0) -> void:
	var dir := Vector3(0.0, 0.0, 1.0)
	if target != null and is_instance_valid(target):
		dir = -target.global_transform.basis.z
	setup_march(dir, speed, ["sits", "run", "fight", "an1", "an2", "an3", "an4"], anim_name)


func _physics_process(delta: float) -> void:
	global_position += _march_dir * move_speed * delta
	global_position.y = 0.0
	_face_march_dir()
	_anim_timer -= delta
	if _anim_timer <= 0.0:
		_play_random_anim("")
		_anim_timer = _rng.randf_range(0.5, 1.6)


func _face_march_dir() -> void:
	if _march_dir.length_squared() < 0.0001:
		return
	look_at(global_position + _march_dir, Vector3.UP)


func _play_random_anim(preferred: String) -> void:
	if _anim == null or _anim_pool.is_empty():
		return
	var pick := preferred
	if pick == "" or not _anim.has_animation(pick):
		pick = _anim_pool[_rng.randi_range(0, _anim_pool.size() - 1)]
	if not _anim.has_animation(pick):
		return
	if _anim.current_animation == pick and _anim.is_playing():
		return
	_anim.play(pick)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
