extends Node3D

## Per-wheel tire smoke when spinning (κ) or sliding hard (α).
## Particles are built at runtime — do not place GPUParticles on track scenes.
## Attach as child of CarController (auto-created if missing).

@export var spin_kappa: float = 0.18
@export var slide_angle_deg: float = 14.0
@export var amount: int = 96
@export var lifetime: float = 1.4

var _car: CarController
var _emitters: Array[GPUParticles3D] = []


func _ready() -> void:
	_car = get_parent() as CarController
	_rebuild_emitters()
	# Wheels may finish rebuild after parent _ready; refresh count once.
	call_deferred("_rebuild_emitters")


func _physics_process(_delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _car.setup == null:
		return
	var wheels := _car.get_wheels()
	var needed := maxi(wheels.size(), _car.setup.wheel_positions.size())
	if needed > 0 and _emitters.size() != needed:
		_rebuild_emitters()
	for i in _emitters.size():
		var emitter := _emitters[i]
		if i >= wheels.size():
			emitter.emitting = false
			continue
		var wheel: Wheel = wheels[i]
		if not wheel.on_ground:
			emitter.emitting = false
			continue

		emitter.global_position = wheel.hit_point + wheel.up * 0.03
		# Drift smoke slightly behind the contact patch relative to car travel.
		var vel := _car.linear_velocity
		if vel.length_squared() > 1.0:
			emitter.global_position -= vel.normalized() * 0.05

		var intensity := _smoke_intensity(wheel)
		# No parked / idle crawl smoke (locked κ looks like a burnout).
		if _car.throttle < 0.05 and _car.get_speed_ms() < 2.0 and _car.handbrake < 0.1:
			intensity = 0.0
		emitter.emitting = intensity > 0.04
		# Keep a denser cloud once smoke kicks in (don't starve amount_ratio at low slip).
		emitter.amount_ratio = clampf(lerpf(0.45, 1.0, intensity), 0.0, 1.0)


func _rebuild_emitters() -> void:
	if _car == null:
		_car = get_parent() as CarController
	var count := 4
	if _car != null and _car.setup != null and _car.setup.wheel_positions.size() > 0:
		count = _car.setup.wheel_positions.size()
	if _emitters.size() == count:
		return
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_emitters.clear()
	for i in count:
		_emitters.append(_make_emitter("TireSmoke_%d" % i))


func _smoke_intensity(wheel: Wheel) -> float:
	var spin_i := 0.0
	var k := absf(wheel.slip_ratio)
	if k >= spin_kappa:
		spin_i = clampf((k - spin_kappa) / 0.55, 0.0, 1.0)

	var slide_i := 0.0
	var a_deg := absf(rad_to_deg(wheel.slip_angle))
	if a_deg >= slide_angle_deg:
		slide_i = clampf((a_deg - slide_angle_deg) / 28.0, 0.0, 1.0)

	return maxf(spin_i, slide_i)


func _make_emitter(node_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.02
	p.randomness = 0.4
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 8, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 70.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 1.35
	proc.angular_velocity_min = -1.5
	proc.angular_velocity_max = 1.5
	proc.gravity = Vector3(0.0, 0.85, 0.0)
	proc.damping_min = 0.55
	proc.damping_max = 1.4
	proc.scale_min = 0.55
	proc.scale_max = 1.35
	proc.color = Color(0.58, 0.58, 0.58, 0.78)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.72, 0.72, 0.72, 0.82),
		Color(0.58, 0.58, 0.58, 0.65),
		Color(0.48, 0.48, 0.48, 0.35),
		Color(0.38, 0.38, 0.38, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.3, 1.15))
	scale_curve.add_point(Vector2(1.0, 1.85))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex

	p.process_material = proc

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.65, 0.65)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.65, 0.65, 0.65, 0.72)
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	add_child(p)
	return p
