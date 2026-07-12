extends Node

## Reads input and drives the parent CarController when occupied.

@onready var car: CarController = get_parent() as CarController

var active: bool = false
## When false, E cannot exit the car (main endless-road mode).
var can_exit: bool = true


func _physics_process(_delta: float) -> void:
	if not active or car == null:
		if car != null:
			car.throttle = 0.0
			car.brake = 0.0
			car.handbrake = 0.0
			car.steering = 0.0
		return

	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.handbrake = Input.get_action_strength("handbrake")
	car.steering = (
		Input.get_action_strength("steer_left")
		- Input.get_action_strength("steer_right")
	)

	if Input.is_action_just_pressed("toggle_transmission"):
		car.toggle_transmission()

	if Input.is_action_just_pressed("restart_car"):
		car.reset_to_spawn()

	if can_exit and Input.is_action_just_pressed("interact"):
		_exit_to_character()

	if not car.automatic:
		if Input.is_action_just_pressed("shift_up"):
			car.shift_up()
		if Input.is_action_just_pressed("shift_down"):
			car.shift_down()


func _exit_to_character() -> void:
	var player := car.occupant as PlayerController
	if player:
		player.exit_car()
