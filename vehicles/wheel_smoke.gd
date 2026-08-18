extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")

## Per-wheel tire smoke when spinning (κ) or sliding hard (α).
## Soft billboards + light turbulence. Tune via exports on the car's WheelSmoke node.
## Particles are built at runtime — do not place GPUParticles on track scenes.

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0

@export_group("Amount / life")
@export_range(24, 256, 8) var amount: int = 80
@export_range(0.6, 4.0, 0.1) var lifetime: float = 2.2
@export_range(0.0, 0.3, 0.01) var explosiveness: float = 0.0
@export_range(0.0, 1.0, 0.05) var randomness: float = 0.55

@export_group("Motion")
## How much car velocity is inherited (trail behind the tire).
@export_range(0.0, 1.0, 0.05) var inherit_velocity: float = 0.55
@export_range(0.0, 2.5, 0.05) var rise_speed_min: float = 0.15
@export_range(0.0, 3.5, 0.05) var rise_speed_max: float = 0.85
@export_range(10.0, 120.0, 1.0) var spread_deg: float = 55.0
@export var gravity: Vector3 = Vector3(0.0, 0.35, 0.0)
@export_range(0.0, 4.0, 0.05) var damping_min: float = 0.8
@export_range(0.0, 4.0, 0.05) var damping_max: float = 1.8

@export_group("Look")
@export_range(0.3, 3.0, 0.05) var puff_size: float = 1.15
@export_range(0.2, 2.0, 0.05) var scale_min: float = 0.45
@export_range(0.4, 3.0, 0.05) var scale_max: float = 1.6
@export var smoke_color_hot: Color = Color(0.14, 0.14, 0.145, 0.72)
@export var smoke_color_cool: Color = Color(0.28, 0.28, 0.3, 0.0)
@export_range(0.0, 1.0, 0.05) var soft_edge: float = 0.75
## If on, smoke takes sun / moon / headlights instead of glowing the same day and night.
@export var receive_light: bool = true

@export_group("Turbulence")
@export var turbulence_enabled: bool = true
@export_range(0.0, 4.0, 0.05) var turbulence_strength: float = 0.35
@export_range(0.5, 20.0, 0.5) var turbulence_scale: float = 3.5
@export_range(0.0, 2.0, 0.05) var turbulence_speed: float = 0.35

var _car: CarController
var _emitters: Array[GPUParticles3D] = []
var _soft_texture: Texture2D


func _ready() -> void:
	_car = get_parent() as CarController
	_rebuild_emitters()
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

		emitter.global_position = wheel.hit_point + wheel.up * 0.04
		var vel := _car.linear_velocity
		var speed := vel.length()
		if speed > 1.0:
			# Slightly behind the patch along travel; smoke then inherits velocity.
			emitter.global_position -= vel / speed * 0.08

		var intensity: float = _TireFx.intensity(_car, wheel, spin_kappa, slide_angle_deg)
		emitter.emitting = intensity > 0.04
		emitter.amount_ratio = clampf(lerpf(0.35, 1.0, intensity), 0.0, 1.0)

		var proc := emitter.process_material as ParticleProcessMaterial
		if proc != null:
			# Nudge initial direction with car travel so burnouts trail naturally.
			if speed > 0.5:
				var back := -vel / speed
				proc.direction = (Vector3.UP * 0.65 + back * 0.55).normalized()
			else:
				proc.direction = Vector3.UP


func _rebuild_emitters() -> void:
	if _car == null:
		_car = get_parent() as CarController
	var count := 4
	if _car != null and _car.setup != null and _car.setup.wheel_positions.size() > 0:
		count = _car.setup.wheel_positions.size()
	# Always rebuild so inspector tweaks apply after save / hot-reload in editor play.
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_emitters.clear()
	_soft_texture = _make_soft_puff_texture()
	for i in count:
		_emitters.append(_make_emitter("TireSmoke_%d" % i))



func _make_soft_puff_texture() -> Texture2D:
	## Radial soft alpha — edges dissolve instead of hard square billboards.
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) * 0.5
	var edge := clampf(soft_edge, 0.05, 1.0)
	for y in size:
		for x in size:
			var dx := (float(x) - mid) / mid
			var dy := (float(y) - mid) / mid
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if r < 1.0:
				# Smoothstep falloff toward rim.
				var t := clampf((1.0 - r) / edge, 0.0, 1.0)
				a = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _make_emitter(node_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = explosiveness
	p.randomness = randomness
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -4, -20), Vector3(40, 24, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var proc := ParticleProcessMaterial.new()
	proc.particle_flag_align_y = false
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = spread_deg
	proc.initial_velocity_min = rise_speed_min
	proc.initial_velocity_max = rise_speed_max
	proc.angular_velocity_min = -25.0
	proc.angular_velocity_max = 25.0
	proc.gravity = gravity
	proc.damping_min = damping_min
	proc.damping_max = damping_max
	proc.scale_min = scale_min
	proc.scale_max = scale_max
	if "inherit_velocity_ratio" in proc:
		proc.inherit_velocity_ratio = inherit_velocity

	if turbulence_enabled and "turbulence_enabled" in proc:
		proc.turbulence_enabled = true
		proc.turbulence_noise_strength = turbulence_strength
		proc.turbulence_noise_scale = turbulence_scale
		proc.turbulence_noise_speed_random = turbulence_speed
		if "turbulence_influence_min" in proc:
			proc.turbulence_influence_min = 0.08
			proc.turbulence_influence_max = 0.35

	# Dark rubber near the patch → thinner grey as it ages. Lit by sun / moon / headlights.
	var mid := Color(
		lerpf(smoke_color_hot.r, 0.32, 0.45),
		lerpf(smoke_color_hot.g, 0.32, 0.45),
		lerpf(smoke_color_hot.b, 0.33, 0.45),
		smoke_color_hot.a * 0.82
	)
	var aged := Color(0.34, 0.34, 0.36, 0.32)
	var thin := Color(0.3, 0.3, 0.32, 0.12)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(smoke_color_hot.r, smoke_color_hot.g, smoke_color_hot.b, smoke_color_hot.a),
		mid,
		aged,
		thin,
		smoke_color_cool,
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.2, 0.95))
	scale_curve.add_point(Vector2(0.55, 1.45))
	scale_curve.add_point(Vector2(1.0, 2.1))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex

	p.process_material = proc

	var mesh := QuadMesh.new()
	mesh.size = Vector2(puff_size, puff_size)
	var draw_mat := StandardMaterial3D.new()
	if receive_light:
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	draw_mat.albedo_color = Color(0.85, 0.85, 0.86, 1.0)
	draw_mat.albedo_texture = _soft_texture
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.roughness = 1.0
	draw_mat.metallic = 0.0
	draw_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	draw_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	draw_mat.emission_enabled = false
	draw_mat.disable_receive_shadows = true
	draw_mat.disable_ambient_light = false
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.billboard_keep_scale = true
	draw_mat.no_depth_test = false
	draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	add_child(p)
	return p
