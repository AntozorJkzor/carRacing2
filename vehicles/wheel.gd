class_name Wheel
extends RefCounted

## Local attachment point on the car body.
var local_origin: Vector3 = Vector3.ZERO
var is_steering: bool = false
var is_driven: bool = false

var on_ground: bool = false
var hit_point: Vector3 = Vector3.ZERO
var hit_normal: Vector3 = Vector3.UP
var compression: float = 0.0
var suspension_length: float = 0.0

var suspension_force: float = 0.0
var long_force: float = 0.0
var lat_force: float = 0.0

## Wheel spin speed in rad/s (positive = forward).
var angular_velocity: float = 0.0
var steer_angle: float = 0.0
var drive_torque: float = 0.0
var brake_torque: float = 0.0

## Slip / tire debug state (updated each physics substep when grounded).
var slip_ratio: float = 0.0
var slip_angle: float = 0.0
var normal_load: float = 0.0

## World-space contact basis axes (updated each physics frame when grounded).
var forward: Vector3 = Vector3.FORWARD
var right: Vector3 = Vector3.RIGHT
var up: Vector3 = Vector3.UP


func reset_forces() -> void:
	suspension_force = 0.0
	long_force = 0.0
	lat_force = 0.0
	drive_torque = 0.0
	brake_torque = 0.0
