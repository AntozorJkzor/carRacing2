extends CanvasLayer

## Screen cockpit drawn over the 3D view, chase camera and cabin camera alike.
## Layout is in torpedo.png pixels. Move Wheel / Speedo / Tacho in the cockpit scene.
## Scale those nodes to resize. Their origin is the spin point.
##
## Needle degrees are Godot rotation (positive is clockwise) and are not clamped:
## past the calibrated mark the needle keeps the same degrees-per-unit step.
## The wheel stops at ±120°, which is full road-wheel lock.

const COCKPIT_LAYER := 10

const SPEEDO_DEG_AT_0 := -115.0
const SPEEDO_DEG_AT_180 := 105.0
const SPEEDO_REF_KMH := 180.0

const TACHO_DEG_AT_0 := -115.0
const TACHO_DEG_AT_8000 := 95.0
const TACHO_REF_RPM := 8000.0

const WHEEL_FULL_LOCK_DEG := 120.0

@onready var _rig: Node2D = $Rig
@onready var _torpedo: Sprite2D = $Rig/Torpedo
@onready var _speedo: Node2D = $Rig/Speedo
@onready var _tacho: Node2D = $Rig/Tacho
@onready var _wheel: Node2D = $Rig/Wheel


func _enter_tree() -> void:
	# Hidden before the first draw, so the garage never flashes the cockpit.
	visible = false


func _ready() -> void:
	layer = COCKPIT_LAYER
	visible = false
	_fit()
	if not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var car := get_parent() as CarController
	var show_cockpit := _should_show(car)
	if visible != show_cockpit:
		visible = show_cockpit
	if not show_cockpit or car == null:
		return
	if _speedo != null:
		_speedo.rotation = deg_to_rad(_speedo_degrees(car.get_speed_kmh()))
	if _tacho != null:
		_tacho.rotation = deg_to_rad(_tacho_degrees(float(car.engine_rpm)))
	if _wheel != null:
		_wheel.rotation = deg_to_rad(_wheel_degrees(car))


func _should_show(car: CarController) -> bool:
	if car == null or not bool(car.occupied):
		return false
	if car.has_meta("showroom") and bool(car.get_meta("showroom")):
		return false
	return true


func _speedo_degrees(kmh: float) -> float:
	return lerpf(SPEEDO_DEG_AT_0, SPEEDO_DEG_AT_180, kmh / SPEEDO_REF_KMH)


func _tacho_degrees(rpm: float) -> float:
	return lerpf(TACHO_DEG_AT_0, TACHO_DEG_AT_8000, rpm / TACHO_REF_RPM)


func _wheel_degrees(car: CarController) -> float:
	var max_deg := 32.0
	if car.setup != null:
		max_deg = maxf(float(car.setup.max_steer_angle), 1.0)
	# Positive rack angle is a left turn. From the seat that is counter-clockwise.
	var t := clampf(float(car.debug_steer_rad) / deg_to_rad(max_deg), -1.0, 1.0)
	return -t * WHEEL_FULL_LOCK_DEG


func _fit() -> void:
	if _rig == null or _torpedo == null or _torpedo.texture == null:
		return
	var tex := _torpedo.texture.get_size()
	var vp := get_viewport().get_visible_rect().size
	if tex.x < 1.0 or tex.y < 1.0 or vp.x < 1.0 or vp.y < 1.0:
		return
	# Cover the window. Parts stay in texture pixels, so they stay on the gauges.
	var s := maxf(vp.x / tex.x, vp.y / tex.y)
	_rig.scale = Vector2(s, s)
	_rig.position = (vp - tex * s) * 0.5
