class_name DayCycle
extends Node

## Day / night HDRI switch for the test track.
## Attach to node DayCycle on res://assets/scenes/tracks/physics_test_track.tscn.

const DAY_SKY := preload("res://assets/env/sky/malagas_ferry_road_4k.exr")
const NIGHT_SKY := preload("res://assets/env/sky/qwantani_moon_noon_puresky_4k.exr")

@export var world_environment_path: NodePath = NodePath("../WorldEnvironment")
@export var sun_path: NodePath = NodePath("../Sun")
@export var toggle_keycode: Key = KEY_N

@export_group("Day")
@export var day_dir: Vector3 = Vector3(-0.524, 0.449, -0.724)
@export var day_light_color: Color = Color(1.0, 0.96, 0.88)
@export_range(0.2, 4.0, 0.05) var day_light_energy: float = 1.35
@export_range(0.2, 3.0, 0.05) var day_sky_energy: float = 1.0
@export_range(0.2, 2.0, 0.05) var day_ambient_energy: float = 1.0

@export_group("Night")
@export var night_dir: Vector3 = Vector3(-0.289, 0.870, -0.400)
@export var night_light_color: Color = Color(0.55, 0.64, 0.82)
@export_range(0.01, 1.5, 0.01) var night_light_energy: float = 0.06
@export_range(0.02, 2.0, 0.01) var night_sky_energy: float = 0.10
@export_range(0.02, 1.5, 0.01) var night_ambient_energy: float = 0.10
@export_range(0.2, 1.2, 0.05) var night_tonemap_exposure: float = 0.55

var _sky_day: Sky
var _sky_night: Sky
var _applied_night: int = -1


func _ready() -> void:
	add_to_group("day_cycle")
	call_deferred("apply")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == toggle_keycode:
			set_night(not GraphicsConfig.night)
			get_viewport().set_input_as_handled()


func set_night(value: bool) -> void:
	GraphicsConfig.night = value
	apply()


func apply() -> void:
	var we := get_node_or_null(world_environment_path) as WorldEnvironment
	var sun := get_node_or_null(sun_path) as DirectionalLight3D
	if we == null or we.environment == null:
		return
	var env := we.environment
	var is_night := GraphicsConfig.night
	var sky := _sky_night if is_night else _sky_day
	if sky == null:
		sky = _make_sky(
			NIGHT_SKY if is_night else DAY_SKY,
			night_sky_energy if is_night else day_sky_energy
		)
		if is_night:
			_sky_night = sky
		else:
			_sky_day = sky
	else:
		var pano := sky.sky_material as PanoramaSkyMaterial
		var energy := night_sky_energy if is_night else day_sky_energy
		if pano != null and not is_equal_approx(pano.energy_multiplier, energy):
			pano.energy_multiplier = energy
	if env.sky != sky:
		env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = night_ambient_energy if is_night else day_ambient_energy
	if is_night:
		env.tonemap_exposure = night_tonemap_exposure
		env.glow_intensity = minf(GraphicsConfig.glow_intensity, 0.10)
		env.glow_hdr_threshold = 2.4
		env.glow_bloom = 0.0
		env.volumetric_fog_enabled = false
	else:
		env.tonemap_exposure = 1.0
		env.glow_intensity = GraphicsConfig.glow_intensity
		env.glow_hdr_threshold = 1.0
		env.volumetric_fog_enabled = GraphicsConfig.volumetric_fog_enabled
		if env.volumetric_fog_enabled:
			env.volumetric_fog_albedo = Color(1, 1, 1)
	if env.fog_enabled:
		if is_night:
			env.fog_light_color = Color(0.08, 0.11, 0.18)
			env.fog_light_energy = 0.35
		else:
			env.fog_light_color = Color(0.62, 0.68, 0.78)
			env.fog_light_energy = 0.85
	if sun != null:
		var look := night_dir if is_night else day_dir
		if look.length_squared() < 0.0001:
			look = Vector3.UP
		look = look.normalized()
		var up := Vector3.UP
		if absf(look.dot(up)) > 0.98:
			up = Vector3.RIGHT
		sun.basis = Basis.looking_at(-look, up)
		sun.position = look * 80.0
		sun.light_color = night_light_color if is_night else day_light_color
		sun.light_energy = night_light_energy if is_night else day_light_energy
	var night_flag := 1 if is_night else 0
	if _applied_night != night_flag:
		_applied_night = night_flag
		_apply_headlights(is_night)


func _make_sky(tex: Texture2D, energy: float) -> Sky:
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = tex
	pano.energy_multiplier = energy
	pano.filter = true
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.sky_material = pano
	return sky


func _apply_headlights(night: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("car_lights"):
		if night and not bool(node.get("lights_on")):
			node.set("lights_on", true)
