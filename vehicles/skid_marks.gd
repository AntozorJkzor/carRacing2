extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")

## Paints continuous skid ribbons into the track skid texture (SkidMarkBaker).
## Attach as SkidMarks under CarController.

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0
@export_range(0.05, 0.6, 0.01) var min_intensity: float = 0.16

@export_group("Paint")
@export_range(0.04, 0.4, 0.01) var segment_distance: float = 0.06
@export_range(0.08, 0.5, 0.01) var mark_width_scale: float = 0.85
@export_range(0.3, 1.5, 0.05) var paint_strength: float = 1.0

var _car: CarController
var _baker: SkidMarkBaker
var _last_pos: Array[Vector3] = []
var _last_width: Array[float] = []
var _has_last: Array[bool] = []


func _ready() -> void:
	_car = get_parent() as CarController
	call_deferred("_resolve_baker")


func _resolve_baker() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group(SkidMarkBaker.GROUP)
	if not nodes.is_empty():
		_baker = nodes[0] as SkidMarkBaker
		return
	# Fallback: create baker on the current track if the scene forgot one.
	if tree.current_scene != null:
		_baker = SkidMarkBaker.new()
		_baker.name = "SkidMarkBaker"
		tree.current_scene.add_child(_baker)


func _physics_process(_delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _car.setup == null:
		return
	if _baker == null or not is_instance_valid(_baker):
		_resolve_baker()
		if _baker == null:
			return
	var wheels := _car.get_wheels()
	_ensure_wheel_state(wheels.size())
	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var intensity: float = _TireFx.intensity(_car, wheel, spin_kappa, slide_angle_deg)
		if not wheel.on_ground or intensity < min_intensity:
			_has_last[i] = false
			continue
		var pos := wheel.hit_point
		# Contact patch half-width in meters (clamped so marks stay tire-thin).
		var half_w := clampf(
			_car.setup.get_wheel_width(i) * mark_width_scale * 0.5,
			0.05,
			0.12
		)
		var strength := paint_strength * clampf(lerpf(0.55, 1.0, intensity), 0.0, 1.0)
		if not _has_last[i]:
			_last_pos[i] = pos
			_last_width[i] = half_w
			_has_last[i] = true
			continue
		var dist := pos.distance_to(_last_pos[i])
		if dist < segment_distance:
			continue
		_baker.stamp_segment(_last_pos[i], pos, (_last_width[i] + half_w) * 0.5, strength)
		_last_pos[i] = pos
		_last_width[i] = half_w


func _ensure_wheel_state(count: int) -> void:
	while _last_pos.size() < count:
		_last_pos.append(Vector3.ZERO)
		_last_width.append(0.1)
		_has_last.append(false)
