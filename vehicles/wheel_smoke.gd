extends Node3D

## Per-wheel tire smoke when spinning (κ) or sliding hard (α).
## Attached as child of CarController.

@export var spin_kappa: float = 0.18
@export var slide_angle_deg: float = 14.0
@export var amount: int = 40
@export var lifetime: float = 0.85

@onready var _car: CarController = get_parent() as CarController

var _emitters: Array[GPUParticles3D] = []


func _ready() -> void:
	for i in 4:
		_emitters.append(_make_emitter("TireSmoke_%d" % i))


func _physics_process(_delta: float) -> void:
	if _car == null or _car.setup == null:
		return
	var wheels := _car.get_wheels()
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
		emitter.emitting = intensity > 0.04
		emitter.amount_ratio = clampf(intensity, 0.0, 1.0)


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
	p.explosiveness = 0.05
	p.randomness = 0.35
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 5, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 55.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 1.8
	proc.angular_velocity_min = -2.0
	proc.angular_velocity_max = 2.0
	proc.gravity = Vector3(0.0, 1.2, 0.0)
	proc.damping_min = 0.4
	proc.damping_max = 1.2
	proc.scale_min = 0.25
	proc.scale_max = 0.7
	proc.color = Color(0.62, 0.62, 0.62, 0.55)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([
		Color(0.75, 0.75, 0.75, 0.55),
		Color(0.55, 0.55, 0.55, 0.35),
		Color(0.4, 0.4, 0.4, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.35, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.4))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex

	p.process_material = proc

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.35, 0.35)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.7, 0.7, 0.7, 0.5)
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	add_child(p)
	return p
