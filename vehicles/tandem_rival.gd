extends Node

## O summons a Levin that ghosts your recent line, one car-width to the side
## and a little behind, with the same slide angle. The body is kinematic, so the
## pose is written every frame. Velocity alone does not move it.

const LEVIN_SCENE := preload("res://assets/scenes/cars/levin/levin.tscn")
const TRAIL_SECONDS := 14.0
const FOLLOW_DELAY := 0.48
const SIDE_M := 2.85
const BEHIND_M := 3.4
const SMOOTH_RATE := 8.0
const MAX_YAW_RATE := 4.0

var _trail: Array[Dictionary] = []
var _rival: CarController
var _active: bool = false
var _smooth_pos: Vector3
var _smooth_basis: Basis
var _smooth_ready: bool = false


func _ready() -> void:
	process_priority = -40
	set_physics_process(true)


func toggle() -> void:
	if _active:
		_dismiss()
	else:
		_summon()


func _physics_process(delta: float) -> void:
	var player := _player()
	if player != null:
		_record(player)
	if not _active or _rival == null or not is_instance_valid(_rival):
		return
	if player == null:
		return
	var sample := _sample_at(FOLLOW_DELAY)
	if sample.is_empty():
		sample = _behind_player(player)
	var basis: Basis = (sample["basis"] as Basis).orthonormalized()
	var pos: Vector3 = _clear_of_road(_slot(sample["pos"], basis))
	if not _smooth_ready:
		_smooth_pos = pos
		_smooth_basis = basis
		_smooth_ready = true
	else:
		var blend := 1.0 - exp(-SMOOTH_RATE * delta)
		_smooth_pos = _smooth_pos.lerp(pos, blend)
		_smooth_basis = _smooth_basis.slerp(basis, blend).orthonormalized()
	var error := _smooth_pos - _rival.global_position
	var cap := maxf(float(sample["speed"]) + 6.0, 8.0) * delta
	error = error.limit_length(cap)
	error = _avoid_overlap(error)
	var next_pos := _rival.global_position + error
	var step := 1.0 - exp(-SMOOTH_RATE * delta)
	var next_basis := _rival.global_transform.basis.slerp(_smooth_basis, step).orthonormalized()
	var velocity := error / maxf(delta, 0.0001)
	var angular := _turn_rate(_rival.global_transform.basis, next_basis)
	_rival.apply_scripted_motion(Transform3D(next_basis, next_pos), velocity, angular, float(sample["steer"]), float(sample["slip"]), true)


func _summon() -> void:
	var player := _player()
	if player == null:
		return
	_dismiss()
	var car := LEVIN_SCENE.instantiate() as CarController
	if car == null:
		return
	car.set_meta("tandem_rival", true)
	var host := get_tree().current_scene
	host.add_child(car)
	_silence_cameras(car)
	if player.has_method("refresh_camera"):
		player.refresh_camera()
	_rival = car
	_active = true
	# Layer 3 is the rival's layer. The player has to sit on it too, or the
	# two masks never agree and a bump does nothing.
	player.collision_layer = player.collision_layer | 4
	var sample := _sample_at(FOLLOW_DELAY)
	if sample.is_empty():
		sample = _behind_player(player)
	var basis: Basis = (sample["basis"] as Basis).orthonormalized()
	var pos := _clear_of_road(_slot(sample["pos"], basis))
	_smooth_pos = pos
	_smooth_basis = basis
	_smooth_ready = true
	car.apply_scripted_motion(Transform3D(basis, pos), -basis.z * float(sample["speed"]), Vector3.ZERO, float(sample["steer"]), float(sample["slip"]), true)


func _dismiss() -> void:
	_active = false
	_smooth_ready = false
	if _rival != null and is_instance_valid(_rival):
		_rival.queue_free()
	_rival = null
	var player := _player()
	if player != null and player.has_method("refresh_camera"):
		player.refresh_camera()


func _slot(pos: Vector3, basis: Basis) -> Vector3:
	return pos + basis.x.normalized() * SIDE_M + basis.z.normalized() * BEHIND_M


## Box bottom sits about 0.12 m above the origin. Keep that above the road.
func _clear_of_road(pos: Vector3) -> Vector3:
	var body: Node3D = _rival if _rival != null and is_instance_valid(_rival) else _player()
	if body == null:
		return pos
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return pos
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 4.0, 0), pos + Vector3(0, -6.0, 0))
	query.collision_mask = 1
	if _rival != null and is_instance_valid(_rival):
		query.exclude = [_rival.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return pos
	var min_y := float(hit.position.y) - 0.08
	if pos.y < min_y:
		pos.y = min_y
	return pos


## Shorten a step that would pass through the player. A few centimetres of
## contact remain so the bump still pushes their car.
func _avoid_overlap(motion: Vector3) -> Vector3:
	if _rival == null or motion.length_squared() < 0.0000001:
		return motion
	var params := PhysicsTestMotionParameters3D.new()
	params.from = _rival.global_transform
	params.motion = motion
	params.margin = 0.04
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(_rival.get_rid(), params, result):
		return motion
	if result.get_collision_count() < 1:
		return motion
	var travel: Vector3 = result.get_travel()
	var normal: Vector3 = result.get_collision_normal()
	var depth := result.get_collision_depth()
	if depth > 0.25:
		return travel + normal * depth
	var leftover := motion - travel
	var into := leftover.dot(-normal)
	if into > 0.0:
		travel += -normal * minf(into, 0.025)
	return travel


func _silence_cameras(car: Node) -> void:
	for node in car.find_children("*", "Camera3D", true, false):
		var cam := node as Camera3D
		if cam == null:
			continue
		cam.current = false


func _turn_rate(current: Basis, want: Basis) -> Vector3:
	var dq := want.get_rotation_quaternion() * current.get_rotation_quaternion().inverse()
	var angle := dq.get_angle()
	if angle < 0.0008:
		return Vector3.ZERO
	if angle > PI:
		angle -= TAU
	return (dq.get_axis() * angle * SMOOTH_RATE).limit_length(MAX_YAW_RATE)


func _player() -> CarController:
	for node in get_tree().get_nodes_in_group("player_cars"):
		var car := node as CarController
		if car != null and car.occupied:
			return car
	return null


func _record(player: CarController) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_trail.append({
		"t": now,
		"pos": player.global_position,
		"basis": player.global_transform.basis,
		"speed": player.linear_velocity.length(),
		"steer": float(player.steering),
		"slip": float(player.debug_body_slip_deg),
	})
	var cutoff := now - TRAIL_SECONDS
	while _trail.size() > 2 and float(_trail[0]["t"]) < cutoff:
		_trail.remove_at(0)


func _sample_at(delay: float) -> Dictionary:
	if _trail.is_empty():
		return {}
	var want := Time.get_ticks_msec() / 1000.0 - delay
	if want <= float(_trail[0]["t"]):
		return _trail[0]
	for i in range(_trail.size() - 1, 0, -1):
		var a: Dictionary = _trail[i - 1]
		var b: Dictionary = _trail[i]
		if float(a["t"]) <= want and float(b["t"]) >= want:
			var span := float(b["t"]) - float(a["t"])
			var u := 0.0 if span <= 0.0001 else (want - float(a["t"])) / span
			var basis_a: Basis = a["basis"]
			var basis_b: Basis = b["basis"]
			var pos_a: Vector3 = a["pos"]
			var pos_b: Vector3 = b["pos"]
			return {
				"pos": pos_a.lerp(pos_b, u),
				"basis": basis_a.slerp(basis_b, u),
				"speed": lerpf(float(a["speed"]), float(b["speed"]), u),
				"steer": lerpf(float(a["steer"]), float(b["steer"]), u),
				"slip": lerpf(float(a["slip"]), float(b["slip"]), u),
			}
	return _trail[_trail.size() - 1]


func _behind_player(player: CarController) -> Dictionary:
	var basis := player.global_transform.basis
	return {
		"pos": player.global_position + basis.z * 6.5,
		"basis": basis,
		"speed": player.linear_velocity.length(),
		"steer": float(player.steering),
		"slip": float(player.debug_body_slip_deg),
	}
