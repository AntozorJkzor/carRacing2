extends Node3D

const _TireFx = preload("res://vehicles/tire_fx.gd")
const _SMOKE_ATLAS_PATH := "res://assets/materials/smokeAtlas.png"

## Per-wheel tire smoke when spinning (κ) or sliding hard (α).
## Dual-layer GPUParticles + flipbook atlas on QuadMesh. Tune via WheelSmoke exports.
## Particles are built at runtime — do not place GPUParticles on track scenes.

@export_group("Trigger")
@export_range(0.05, 0.6, 0.01) var spin_kappa: float = 0.12
@export_range(5.0, 40.0, 0.5) var slide_angle_deg: float = 10.0

@export_group("Amount / life")
@export_range(24, 256, 8) var amount: int = 120
@export_range(0.6, 4.0, 0.1) var lifetime: float = 2.8
@export_range(0.0, 0.3, 0.01) var explosiveness: float = 0.0
@export_range(0.0, 1.0, 0.05) var randomness: float = 0.55
@export_range(0.5, 2.5, 0.05) var density_boost: float = 1.35

@export_group("Motion")
## How much car velocity is inherited (trail behind the tire).
@export_range(0.0, 1.0, 0.05) var inherit_velocity: float = 0.55
@export_range(0.0, 2.5, 0.05) var rise_speed_min: float = 0.15
@export_range(0.0, 3.5, 0.05) var rise_speed_max: float = 1.05
@export_range(10.0, 120.0, 1.0) var spread_deg: float = 70.0
@export var gravity: Vector3 = Vector3(0.0, 0.35, 0.0)
@export_range(0.0, 4.0, 0.05) var damping_min: float = 0.8
@export_range(0.0, 4.0, 0.05) var damping_max: float = 1.8
@export_range(0.0, 2.0, 0.05) var drift_strength: float = 0.55

@export_group("Wind")
## World-space direction; normalized internally so only the side matters.
@export var wind_direction: Vector3 = Vector3(0.85, 0.0, 0.35)
@export_range(0.0, 3.0, 0.05) var wind_strength: float = 0.65
@export_range(0.0, 1.5, 0.05) var wind_gust_strength: float = 0.25
@export_range(0.1, 4.0, 0.05) var wind_gust_speed: float = 0.7

@export_group("Look")
@export_range(0.3, 3.0, 0.05) var puff_size: float = 1.35
@export_range(0.2, 2.0, 0.05) var scale_min: float = 0.45
@export_range(0.4, 3.0, 0.05) var scale_max: float = 2.1
## Dense rubber smoke near the contact patch (base layer).
@export var smoke_color_hot: Color = Color(0.02, 0.02, 0.02, 0.9)
@export var smoke_color_cool: Color = Color(0.08, 0.08, 0.09, 0.0)
## Soft white plume above the wheels.
@export var plume_color_hot: Color = Color(0.92, 0.92, 0.94, 0.55)
@export var plume_color_cool: Color = Color(0.85, 0.85, 0.88, 0.0)
## If on, smoke takes sun / moon / headlights instead of glowing the same day and night.
@export var receive_light: bool = true

@export_group("Atlas")
## smokeAtlas.png is a 6×4 birth→dissipate flipbook (not 4×4).
@export_range(1, 16, 1) var atlas_h_frames: int = 6
@export_range(1, 16, 1) var atlas_v_frames: int = 4
@export var atlas_loop: bool = false
## 1.0 ≈ play the whole sheet once over particle lifetime.
@export_range(0.1, 3.0, 0.05) var anim_speed_min: float = 0.85
@export_range(0.1, 3.0, 0.05) var anim_speed_max: float = 1.15

@export_group("Turbulence")
@export var turbulence_enabled: bool = true
@export_range(0.0, 4.0, 0.05) var turbulence_strength: float = 0.35
@export_range(0.5, 20.0, 0.5) var turbulence_scale: float = 3.5
@export_range(0.0, 2.0, 0.05) var turbulence_speed: float = 0.35

var _car: CarController
var _base_emitters: Array[GPUParticles3D] = []
var _plume_emitters: Array[GPUParticles3D] = []
var _wind_phases: Array[float] = []
var _atlas_texture: Texture2D


func _ready() -> void:
	_car = get_parent() as CarController
	_rebuild_emitters()
	call_deferred("_rebuild_emitters")


func _physics_process(_delta: float) -> void:
	if _car == null:
		_car = get_parent() as CarController
	if _car == null or _car.setup == null:
		return
	var smoke_on := GraphicsConfig.tire_smoke_enabled
	var wheels := _car.get_wheels()
	var needed := maxi(wheels.size(), _car.setup.wheel_positions.size())
	if needed > 0 and (_base_emitters.size() != needed or _plume_emitters.size() != needed):
		_rebuild_emitters()
	for i in needed:
		var base_emitter := _base_emitters[i]
		var plume_emitter := _plume_emitters[i]
		if not smoke_on or i >= wheels.size():
			base_emitter.emitting = false
			plume_emitter.emitting = false
			continue
		var wheel: Wheel = wheels[i]
		if not wheel.on_ground:
			base_emitter.emitting = false
			plume_emitter.emitting = false
			continue
		var vel := _car.linear_velocity
		var speed := vel.length()

		var intensity: float = _TireFx.intensity(_car, wheel, spin_kappa, slide_angle_deg)
		_update_emitter(base_emitter, i, wheel, vel, speed, intensity, false)
		_update_emitter(plume_emitter, i, wheel, vel, speed, intensity, true)


func _rebuild_emitters() -> void:
	if _car == null:
		_car = get_parent() as CarController
	var count := 4
	if _car != null and _car.setup != null and _car.setup.wheel_positions.size() > 0:
		count = _car.setup.wheel_positions.size()
	# Always rebuild so inspector tweaks apply after save / hot-reload in editor play.
	for emitter in _base_emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	for emitter in _plume_emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_base_emitters.clear()
	_plume_emitters.clear()
	_wind_phases.clear()
	_atlas_texture = _load_atlas_texture()
	for i in count:
		_wind_phases.append(randf_range(0.0, TAU))
		_base_emitters.append(_make_emitter("TireSmokeBase_%d" % i, false))
		_plume_emitters.append(_make_emitter("TireSmokePlume_%d" % i, true))


func _update_emitter(
	emitter: GPUParticles3D,
	emitter_index: int,
	wheel: Wheel,
	vel: Vector3,
	speed: float,
	intensity: float,
	is_plume: bool
) -> void:
	var lift := 0.03 if is_plume else 0.015
	emitter.global_position = wheel.hit_point + wheel.up * lift
	if speed > 1.0:
		var trail_scale := 0.14 if is_plume else 0.06
		emitter.global_position -= vel / speed * trail_scale
	emitter.emitting = intensity > 0.04
	# Base = sparse black near tires; plume = denser white volume above.
	var layer_floor := 0.45 if is_plume else 0.18
	var layer_density := density_boost * (1.0 if is_plume else 0.45)
	emitter.amount_ratio = clampf(lerpf(layer_floor, 1.0, intensity) * layer_density, 0.0, 1.0)

	var proc := emitter.process_material as ParticleProcessMaterial
	if proc != null:
		var wind := _get_wind_vector(emitter_index)
		var wind_push := Vector3(wind.x, 0.0, wind.z)
		var up_weight := 0.9 if is_plume else 0.58
		var back_weight := 0.28 if is_plume else 0.5
		var drift_weight := drift_strength * (1.45 if is_plume else 0.85)
		if speed > 0.5:
			var back := -vel / speed
			proc.direction = (Vector3.UP * up_weight + back * back_weight + wind_push * drift_weight).normalized()
		else:
			proc.direction = (Vector3.UP * up_weight + wind_push * drift_weight).normalized()
		proc.gravity = gravity + wind * (1.35 if is_plume else 0.75)


func _load_atlas_texture() -> Texture2D:
	var tex: Texture2D = load(_SMOKE_ATLAS_PATH) as Texture2D
	if tex != null:
		return tex
	push_warning("WheelSmoke: failed to load %s — using fallback puff." % _SMOKE_ATLAS_PATH)
	return _make_fallback_puff_texture()


func _make_fallback_puff_texture() -> Texture2D:
	## Soft radial alpha if the atlas is missing / not imported yet.
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - mid) / mid
			var dy := (float(y) - mid) / mid
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if r < 1.0:
				var t := clampf(1.0 - r, 0.0, 1.0)
				a = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _get_wind_vector(emitter_index: int) -> Vector3:
	var base := wind_direction
	if base.length_squared() < 0.0001:
		base = Vector3.RIGHT
	var dir := base.normalized()
	var phase := 0.0
	if emitter_index >= 0 and emitter_index < _wind_phases.size():
		phase = _wind_phases[emitter_index]
	var gust := 1.0 + sin(Time.get_ticks_msec() * 0.001 * wind_gust_speed + phase) * wind_gust_strength
	return dir * wind_strength * maxf(gust, 0.0)


func _make_emitter(node_name: String, is_plume: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	# Few dark puffs at the patch; most of the visible volume is the white plume.
	p.amount = maxi(int(round(float(amount) * (0.7 if is_plume else 0.22))), 6)
	p.lifetime = lifetime * (1.3 if is_plume else 0.55)
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
	proc.spread = spread_deg * (1.2 if is_plume else 0.72)
	proc.initial_velocity_min = rise_speed_min * (1.1 if is_plume else 0.55)
	proc.initial_velocity_max = rise_speed_max * (1.3 if is_plume else 0.75)
	proc.angular_velocity_min = -40.0 if is_plume else -22.0
	proc.angular_velocity_max = 40.0 if is_plume else 22.0
	proc.gravity = gravity
	proc.damping_min = damping_min * (0.7 if is_plume else 1.1)
	proc.damping_max = damping_max * (0.85 if is_plume else 1.15)
	proc.scale_min = scale_min * (1.35 if is_plume else 0.82)
	proc.scale_max = scale_max * (1.7 if is_plume else 0.92)
	if "inherit_velocity_ratio" in proc:
		proc.inherit_velocity_ratio = inherit_velocity * (0.9 if is_plume else 0.65)

	# Flipbook: 1.0 ≈ one full atlas pass over the particle lifetime.
	proc.anim_speed_min = anim_speed_min
	proc.anim_speed_max = anim_speed_max
	proc.anim_offset_min = 0.0
	proc.anim_offset_max = 0.08

	if turbulence_enabled and "turbulence_enabled" in proc:
		proc.turbulence_enabled = true
		proc.turbulence_noise_strength = turbulence_strength
		proc.turbulence_noise_scale = turbulence_scale
		proc.turbulence_noise_speed_random = turbulence_speed
		if "turbulence_influence_min" in proc:
			proc.turbulence_influence_min = 0.08
			proc.turbulence_influence_max = 0.35

	var hot := plume_color_hot if is_plume else smoke_color_hot
	var cool := plume_color_cool if is_plume else smoke_color_cool
	var mid_rgb := 0.96 if is_plume else 0.05
	var aged_rgb := 0.9 if is_plume else 0.07
	var thin_rgb := 0.86 if is_plume else 0.1
	var mid := Color(mid_rgb, mid_rgb, mid_rgb + (0.02 if is_plume else 0.0), hot.a * 0.75)
	var aged := Color(aged_rgb, aged_rgb, aged_rgb + (0.02 if is_plume else 0.0), hot.a * 0.38)
	var thin := Color(thin_rgb, thin_rgb, thin_rgb + (0.02 if is_plume else 0.0), hot.a * 0.14)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(hot.r, hot.g, hot.b, hot.a),
		mid,
		aged,
		thin,
		cool,
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.2, 1.05))
	scale_curve.add_point(Vector2(0.55, 1.65))
	scale_curve.add_point(Vector2(1.0, 2.35))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex

	p.process_material = proc

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * puff_size * (1.65 if is_plume else 1.0)
	var draw_mat := StandardMaterial3D.new()
	if receive_light:
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85) if is_plume else Color(0.08, 0.08, 0.08, 1.0)
	draw_mat.albedo_texture = _atlas_texture
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.roughness = 1.0
	draw_mat.metallic = 0.0
	draw_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	draw_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	draw_mat.emission_enabled = false
	draw_mat.disable_receive_shadows = true
	draw_mat.disable_ambient_light = false
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Particle billboard is required for Particles Anim UV sheet sampling.
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.billboard_keep_scale = true
	draw_mat.particles_anim_h_frames = atlas_h_frames
	draw_mat.particles_anim_v_frames = atlas_v_frames
	draw_mat.particles_anim_loop = atlas_loop
	draw_mat.no_depth_test = false
	draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	add_child(p)
	return p
