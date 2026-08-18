extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")

## Rubber marks on the ground when a tire spins, slides, or locks.
## Attach to a child of CarController (SkidMarks on the car pack scene).
## Decals live under a scene-level pool so they stay in the world.

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0
@export_range(0.05, 0.6, 0.01) var min_intensity: float = 0.16

@export_group("Marks")
@export_range(24, 256, 8) var max_marks: int = 96
@export_range(0.2, 1.2, 0.05) var spawn_distance: float = 0.38
@export_range(0.08, 0.4, 0.01) var mark_width_scale: float = 1.15
@export_range(0.15, 0.8, 0.01) var projection_depth: float = 0.35
@export_range(4.0, 40.0, 0.5) var mark_lifetime: float = 14.0
@export var mark_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var _car: CarController
var _pool: Array[Decal] = []
var _born: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _last_pos: Array[Vector3] = []
var _has_last: Array[bool] = []
var _streak_tex: Texture2D
var _world: Node3D


func _ready() -> void:
	_car = get_parent() as CarController
	_streak_tex = _make_streak_texture()
	call_deferred("_ensure_world")


func _ensure_world() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	_world = tree.current_scene.get_node_or_null("SkidMarkWorld") as Node3D
	if _world == null:
		_world = Node3D.new()
		_world.name = "SkidMarkWorld"
		tree.current_scene.add_child(_world)
	_rebuild_pool()


func _physics_process(_delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _car.setup == null or _world == null:
		return
	var wheels := _car.get_wheels()
	_ensure_wheel_state(wheels.size())
	for i in wheels.size():
		var wheel: Wheel = wheels[i]
		var intensity: float = _TireFx.intensity(_car, wheel, spin_kappa, slide_angle_deg)
		if intensity < min_intensity:
			_has_last[i] = false
			continue
		var pos := wheel.hit_point + wheel.up * 0.03
		if not _has_last[i]:
			_last_pos[i] = pos
			_has_last[i] = true
			continue
		var delta := pos - _last_pos[i]
		var dist := delta.length()
		if dist < spawn_distance:
			continue
		var along := delta / dist
		var width := maxf(_car.setup.get_wheel_width(i), 0.12) * mark_width_scale
		_stamp(pos, along, wheel.up, dist, width, intensity)
		_last_pos[i] = pos


func _process(_delta: float) -> void:
	if _pool.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	for i in _pool.size():
		var decal := _pool[i]
		if not decal.visible:
			continue
		var age := now - _born[i]
		if age >= mark_lifetime:
			decal.visible = false
			continue
		var fade := 1.0
		var tail := mark_lifetime * 0.35
		if age > mark_lifetime - tail:
			fade = 1.0 - (age - (mark_lifetime - tail)) / tail
		decal.modulate = Color(mark_color.r, mark_color.g, mark_color.b, mark_color.a * fade)


func _ensure_wheel_state(count: int) -> void:
	while _last_pos.size() < count:
		_last_pos.append(Vector3.ZERO)
		_has_last.append(false)


func _rebuild_pool() -> void:
	for old in _pool:
		if is_instance_valid(old):
			old.queue_free()
	_pool.clear()
	_born = PackedFloat32Array()
	_born.resize(max_marks)
	_next = 0
	for i in max_marks:
		var decal := Decal.new()
		decal.name = "Skid_%d" % i
		decal.texture_albedo = _streak_tex
		decal.cull_mask = 1
		decal.upper_fade = 0.06
		decal.lower_fade = 0.4
		decal.albedo_mix = 1.0
		decal.visible = false
		_world.add_child(decal)
		_pool.append(decal)
		_born[i] = 0.0


func _stamp(
	pos: Vector3,
	along: Vector3,
	up: Vector3,
	length: float,
	width: float,
	intensity: float
) -> void:
	if _pool.is_empty():
		return
	var y_axis := up.normalized()
	var z_axis := along - y_axis * along.dot(y_axis)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.FORWARD
	else:
		z_axis = z_axis.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	var decal := _pool[_next]
	_born[_next] = Time.get_ticks_msec() * 0.001
	_next = (_next + 1) % _pool.size()
	decal.visible = true
	decal.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), pos)
	var len := clampf(length * 1.15, spawn_distance, spawn_distance * 2.4)
	decal.size = Vector3(width, projection_depth, len)
	var a := mark_color.a * clampf(lerpf(0.72, 1.0, intensity), 0.0, 1.0)
	decal.modulate = Color(mark_color.r, mark_color.g, mark_color.b, a)


func _make_streak_texture() -> Texture2D:
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mid := (w - 1) * 0.5
	for y in h:
		var v := (float(y) + 0.5) / float(h)
		var along := 1.0
		if v < 0.14:
			along = v / 0.14
		elif v > 0.86:
			along = (1.0 - v) / 0.14
		for x in w:
			var across := 1.0 - absf((float(x) - mid) / mid)
			across = pow(across, 0.55)
			var a := clampf(across * along, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return ImageTexture.create_from_image(img)
