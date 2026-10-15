@tool
extends Node3D

## Exhaust backfire flame on gear shifts.
## Place Marker3D children (e.g. Tip / Tip2) where the pipe ends — move them in the inspector.

@export_group("Burst")
@export_range(0.05, 0.6, 0.01) var burst_duration: float = 0.2
@export var require_throttle: bool = true
@export_range(0.0, 1.0, 0.05) var min_throttle: float = 0.25
@export var fire_on_upshift: bool = true
@export var fire_on_downshift: bool = true
@export var fire_on_rev_limiter: bool = true
## How often flames pop while sitting on the limiter (seconds between pops).
@export_range(0.04, 0.4, 0.01) var limiter_pop_interval: float = 0.09
@export_range(0.04, 0.35, 0.01) var limiter_burst_duration: float = 0.12

@export_group("Look")
@export_range(16, 128, 8) var amount: int = 48
@export_range(0.08, 0.5, 0.01) var lifetime: float = 0.22
@export_range(0.0, 0.2, 0.005) var puff_size: float = 0.12:
	set(value):
		puff_size = value
		_apply_puff_size()
@export var flame_color_core: Color = Color(1.0, 0.85, 0.35, 0.95)
@export var flame_color_outer: Color = Color(1.0, 0.25, 0.05, 0.0)

var _car: CarController
var _emitters: Array[GPUParticles3D] = []
var _burst_left: float = 0.0
var _burst_total: float = 0.2
var _connected: bool = false
var _limiter_was_active: bool = false
var _limiter_pop_cd: float = 0.0


func _ready() -> void:
	_car = get_parent() as CarController
	_ensure_default_markers()
	_rebuild_emitters()
	if not Engine.is_editor_hint():
		call_deferred("_connect_car")


func _connect_car() -> void:
	if _connected:
		return
	_car = get_parent() as CarController
	if _car == null:
		return
	if not _car.gear_shifted.is_connected(_on_gear_shifted):
		_car.gear_shifted.connect(_on_gear_shifted)
	_connected = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_rev_limiter_flames(delta)
	if _burst_left > 0.0:
		_burst_left = maxf(_burst_left - delta, 0.0)
		var on := _burst_left > 0.0
		for emitter in _emitters:
			emitter.emitting = on
			if on:
				emitter.amount_ratio = clampf(_burst_left / maxf(_burst_total, 0.01), 0.2, 1.0)
	else:
		for emitter in _emitters:
			emitter.emitting = false


func _update_rev_limiter_flames(delta: float) -> void:
	if not fire_on_rev_limiter or _car == null:
		_limiter_was_active = false
		return
	_limiter_pop_cd = maxf(_limiter_pop_cd - delta, 0.0)
	var active := _car.rev_limiter_active
	if active:
		# First hit + rhythmic pops while held on the cut.
		var rising := active and not _limiter_was_active
		if rising or _limiter_pop_cd <= 0.0:
			_fire_burst(limiter_burst_duration)
			_limiter_pop_cd = limiter_pop_interval
	_limiter_was_active = active


func _on_gear_shifted(from_gear: int, to_gear: int) -> void:
	if to_gear == from_gear:
		return
	if to_gear > from_gear and not fire_on_upshift:
		return
	if to_gear < from_gear and not fire_on_downshift:
		return
	if require_throttle and _car != null and _car.throttle < min_throttle:
		return
	_fire_burst(burst_duration)


func _fire_burst(duration: float) -> void:
	_burst_total = maxf(duration, 0.01)
	_burst_left = maxf(_burst_left, duration)
	for emitter in _emitters:
		emitter.restart()
		emitter.emitting = true


func _apply_puff_size() -> void:
	var s := maxf(puff_size, 0.0)
	for emitter in _emitters:
		if not is_instance_valid(emitter):
			continue
		var mesh := emitter.draw_pass_1 as QuadMesh
		if mesh != null:
			mesh.size = Vector2(s, s)


func _marker_count() -> int:
	var n := 0
	for child in get_children():
		if child is Marker3D:
			n += 1
	return n


func _ensure_default_markers() -> void:
	if _marker_count() > 0:
		return
	var tip := Marker3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0.35, 0.25, 1.55)
	tip.gizmo_extents = 0.15
	add_child(tip)
	if Engine.is_editor_hint():
		var tree := get_tree()
		tip.owner = tree.edited_scene_root if tree and tree.edited_scene_root else self


func _rebuild_emitters() -> void:
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_emitters.clear()

	for child in get_children():
		if not child is Marker3D:
			continue
		var marker := child as Marker3D
		for old in marker.get_children():
			if old is GPUParticles3D:
				old.queue_free()
		_emitters.append(_make_emitter(marker, "Flame"))


func _make_emitter(parent: Node3D, node_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.one_shot = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.85
	p.randomness = 0.45
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.15, 1.0)
	proc.spread = 18.0
	proc.initial_velocity_min = 2.5
	proc.initial_velocity_max = 6.5
	proc.gravity = Vector3(0.0, 1.5, 0.0)
	proc.damping_min = 1.5
	proc.damping_max = 3.0
	proc.scale_min = 0.35
	proc.scale_max = 1.1
	proc.angular_velocity_min = -40.0
	proc.angular_velocity_max = 40.0

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	grad.colors = PackedColorArray([
		flame_color_core,
		Color(1.0, 0.55, 0.12, 0.85),
		Color(0.9, 0.2, 0.05, 0.35),
		flame_color_outer,
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.25, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.15))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	p.process_material = proc

	var mesh := QuadMesh.new()
	mesh.size = Vector2(puff_size, puff_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = mat
	p.draw_pass_1 = mesh

	parent.add_child(p)
	return p
