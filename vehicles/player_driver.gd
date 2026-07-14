extends Node

## Reads input and drives the parent CarController when occupied.

const REVERSE_ENTER_SPEED := 2.5
const REVERSE_NEAR_STOP := 1.5

@onready var car: CarController = get_parent() as CarController

var active: bool = false
## When false, E cannot exit the car (main endless-road mode).
var can_exit: bool = true
## Skip exit on the same frame we were activated (tree order: enter then exit).
var _exit_ready: bool = false


func _ready() -> void:
	# Run before parent CarController so pedals / want_reverse are ready this frame.
	process_priority = 100


func _physics_process(_delta: float) -> void:
	if not active or car == null:
		_exit_ready = false
		if car != null:
			car.throttle = 0.0
			car.brake = 0.0
			car.handbrake = 0.0
			car.steering = 0.0
			car.want_reverse = false
		return

	var accel_raw := Input.get_action_strength("accelerate")
	var brake_raw := Input.get_action_strength("brake")
	car.handbrake = Input.get_action_strength("handbrake")
	car.steering = (
		Input.get_action_strength("steer_left")
		- Input.get_action_strength("steer_right")
	)

	_apply_pedals(accel_raw, brake_raw)

	if Input.is_action_just_pressed("toggle_transmission"):
		car.toggle_transmission()

	if Input.is_action_just_pressed("restart_car"):
		car.reset_to_spawn()

	# Arm exit only after one occupied frame so Enter (E) can't instantly exit.
	if not _exit_ready:
		_exit_ready = true
	elif can_exit and Input.is_action_just_pressed("interact"):
		_exit_to_character()

	if not car.automatic:
		if Input.is_action_just_pressed("shift_up"):
			car.shift_up()
		if Input.is_action_just_pressed("shift_down"):
			car.shift_down()


func _apply_pedals(accel_raw: float, brake_raw: float) -> void:
	## Automatic: hold brake near stop / in R = reverse thrust (arcade dual-pedal).
	## Manual: accelerate = gas, brake = brake.
	if not car.automatic or not car.allow_reverse:
		car.want_reverse = false
		car.throttle = accel_raw
		car.brake = brake_raw
		return

	var forward_speed := car.linear_velocity.dot(-car.global_transform.basis.z)
	var in_reverse := car.current_gear < 0
	var near_stop := absf(forward_speed) < REVERSE_NEAR_STOP

	# Intent stays only while holding S; pressing W clears it so we can return to D.
	var want_r := false
	if in_reverse:
		want_r = brake_raw > 0.15 and accel_raw < 0.25
	elif (
		absf(forward_speed) < REVERSE_ENTER_SPEED
		and brake_raw > 0.2
		and accel_raw < 0.05
	):
		want_r = true

	car.want_reverse = want_r

	if in_reverse:
		# S = reverse gas, W = brake (at stop W exits R via want_reverse=false).
		car.throttle = brake_raw
		car.brake = accel_raw
	elif want_r and near_stop:
		# Enter / hold reverse intent: don't service-brake against reverse thrust.
		car.throttle = brake_raw
		car.brake = 0.0
	else:
		car.throttle = accel_raw
		car.brake = brake_raw


func _exit_to_character() -> void:
	var player := car.occupant as PlayerController
	if player:
		player.exit_car()
