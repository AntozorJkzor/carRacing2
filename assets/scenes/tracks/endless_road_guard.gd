extends Node

## Keeps the car on a straight endless road: no reverse, limited yaw, no U-turn.

@export var car_path: NodePath
@export var road_forward: Vector3 = Vector3(0, 0, 1)
@export var max_heading_deg: float = 28.0
@export var heading_correct_strength: float = 18.0
@export var kill_backward_speed: bool = true

var _car: CarController


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	if _car != null:
		_car.allow_reverse = false


func _physics_process(delta: float) -> void:
	if _car == null:
		return

	var desired := Vector3(road_forward.x, 0.0, road_forward.z)
	if desired.length_squared() < 0.0001:
		desired = Vector3(0.0, 0.0, 1.0)
	desired = desired.normalized()

	# Car forward in Godot is -Z of the basis.
	var car_forward := -_car.global_transform.basis.z
	var flat_forward := Vector3(car_forward.x, 0.0, car_forward.z)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = desired
	else:
		flat_forward = flat_forward.normalized()

	var heading_error := flat_forward.signed_angle_to(desired, Vector3.UP)
	var max_rad := deg_to_rad(max_heading_deg)

	# Soften steering that pushes further from road forward.
	var headroom := 1.0 - clampf(absf(heading_error) / max_rad, 0.0, 1.0)
	if absf(heading_error) > max_rad * 0.5 and absf(_car.steering) > 0.01:
		# Positive steering turns left (CCW yaw). If already left of the road axis
		# (heading_error < 0 when flat_forward is left of desired), block more left input.
		var turning_away := (
			(_car.steering > 0.0 and heading_error < 0.0)
			or (_car.steering < 0.0 and heading_error > 0.0)
		)
		if turning_away:
			_car.steering *= headroom * headroom

	if absf(heading_error) > max_rad:
		# heading_error = angle to rotate car_forward toward road_forward.
		var overshoot := heading_error - signf(heading_error) * max_rad
		var yaw_torque := overshoot * heading_correct_strength
		_car.apply_torque(Vector3(0.0, yaw_torque * _car.mass * delta, 0.0))
		if absf(heading_error) > max_rad * 1.15:
			# Car offset from road axis is the opposite of heading_error.
			_clamp_heading(desired, clampf(-heading_error, -max_rad, max_rad))

	# Never allow net travel backward along the road.
	if kill_backward_speed:
		var along := _car.linear_velocity.dot(desired)
		if along < 0.0:
			_car.linear_velocity -= desired * along

	# Force reverse gear off every frame as a safety net.
	if _car.current_gear < 0:
		_car.current_gear = 1


func _clamp_heading(desired: Vector3, clamped_angle: float) -> void:
	var yaw_basis := Basis(Vector3.UP, clamped_angle)
	var new_forward := yaw_basis * desired
	# RigidBody faces -Z, so look_at uses forward = -Z → target = position - new_forward? 
	# Basis.looking_at expects the -Z axis to point toward target direction... 
	# looking_at(direction) makes -Z align with direction.
	var origin := _car.global_position
	var xf := Transform3D(Basis.looking_at(new_forward, Vector3.UP), origin)
	# Preserve pitch/roll approximately by keeping Y up only (straight road).
	PhysicsServer3D.body_set_state(
		_car.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM,
		xf
	)
	_car.global_transform = xf
	var ang := _car.angular_velocity
	ang.y = 0.0
	_car.angular_velocity = ang
