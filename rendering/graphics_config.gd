class_name GraphicsConfig
extends RefCounted

## Persists and applies Godot 4 graphics options (viewport + environment + lights).

const SAVE_PATH := "user://graphics_settings.cfg"

enum Preset { CUSTOM = 0, LOW = 1, MEDIUM = 2, HIGH = 3, ULTRA = 4 }
enum UpscaleMode { BILINEAR = 0, FSR1 = 1, FSR2 = 2 }
enum MsaaMode { OFF = 0, X2 = 1, X4 = 2, X8 = 3 }
enum ShadowQuality { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3 }

static var preset: int = Preset.HIGH
static var render_scale: float = 1.0
static var upscale_mode: int = UpscaleMode.BILINEAR
static var fsr_sharpness: float = 0.2
static var msaa: int = MsaaMode.X2
static var use_taa: bool = false
static var use_fxaa: bool = true
static var glow_enabled: bool = true
static var glow_intensity: float = 0.35
static var ssao_enabled: bool = true
static var ssil_enabled: bool = false
static var ssr_enabled: bool = false
static var sdfgi_enabled: bool = false
static var fog_enabled: bool = true
static var volumetric_fog_enabled: bool = false
static var use_aces_tonemap: bool = true
static var shadow_quality: int = ShadowQuality.HIGH
static var fullscreen: bool = false
static var vsync: bool = true
static var night: bool = true


static func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		apply_preset(Preset.HIGH)
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		apply_preset(Preset.HIGH)
		return
	preset = int(cfg.get_value("graphics", "preset", preset))
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	upscale_mode = int(cfg.get_value("graphics", "upscale_mode", upscale_mode))
	fsr_sharpness = clampf(float(cfg.get_value("graphics", "fsr_sharpness", fsr_sharpness)), 0.0, 2.0)
	msaa = int(cfg.get_value("graphics", "msaa", msaa))
	use_taa = bool(cfg.get_value("graphics", "use_taa", use_taa))
	use_fxaa = bool(cfg.get_value("graphics", "use_fxaa", use_fxaa))
	glow_enabled = bool(cfg.get_value("graphics", "glow_enabled", glow_enabled))
	glow_intensity = clampf(float(cfg.get_value("graphics", "glow_intensity", glow_intensity)), 0.0, 2.0)
	ssao_enabled = bool(cfg.get_value("graphics", "ssao_enabled", ssao_enabled))
	ssil_enabled = bool(cfg.get_value("graphics", "ssil_enabled", ssil_enabled))
	ssr_enabled = bool(cfg.get_value("graphics", "ssr_enabled", ssr_enabled))
	sdfgi_enabled = bool(cfg.get_value("graphics", "sdfgi_enabled", sdfgi_enabled))
	fog_enabled = bool(cfg.get_value("graphics", "fog_enabled", fog_enabled))
	volumetric_fog_enabled = bool(cfg.get_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled))
	use_aces_tonemap = bool(cfg.get_value("graphics", "use_aces_tonemap", use_aces_tonemap))
	shadow_quality = int(cfg.get_value("graphics", "shadow_quality", shadow_quality))
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("graphics", "vsync", vsync))
	night = bool(cfg.get_value("graphics", "night", night))
	_sanitize_unsafe_settings()


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "upscale_mode", upscale_mode)
	cfg.set_value("graphics", "fsr_sharpness", fsr_sharpness)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.set_value("graphics", "use_taa", use_taa)
	cfg.set_value("graphics", "use_fxaa", use_fxaa)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "glow_intensity", glow_intensity)
	cfg.set_value("graphics", "ssao_enabled", ssao_enabled)
	cfg.set_value("graphics", "ssil_enabled", ssil_enabled)
	cfg.set_value("graphics", "ssr_enabled", ssr_enabled)
	cfg.set_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value("graphics", "fog_enabled", fog_enabled)
	cfg.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	cfg.set_value("graphics", "use_aces_tonemap", use_aces_tonemap)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "night", night)
	cfg.save(SAVE_PATH)


static func apply_preset(p: int) -> void:
	preset = p
	match p:
		Preset.LOW:
			render_scale = 0.7
			upscale_mode = UpscaleMode.FSR2
			fsr_sharpness = 0.3
			msaa = MsaaMode.OFF
			use_taa = false
			use_fxaa = true
			glow_enabled = false
			glow_intensity = 0.2
			ssao_enabled = false
			ssil_enabled = false
			ssr_enabled = false
			sdfgi_enabled = false
			fog_enabled = true
			volumetric_fog_enabled = false
			use_aces_tonemap = true
			shadow_quality = ShadowQuality.LOW
		Preset.MEDIUM:
			render_scale = 0.85
			upscale_mode = UpscaleMode.FSR2
			fsr_sharpness = 0.25
			msaa = MsaaMode.X2
			use_taa = false
			use_fxaa = true
			glow_enabled = true
			glow_intensity = 0.28
			ssao_enabled = true
			ssil_enabled = false
			ssr_enabled = false
			sdfgi_enabled = false
			fog_enabled = true
			volumetric_fog_enabled = false
			use_aces_tonemap = true
			shadow_quality = ShadowQuality.MEDIUM
		Preset.HIGH:
			render_scale = 1.0
			upscale_mode = UpscaleMode.BILINEAR
			fsr_sharpness = 0.2
			msaa = MsaaMode.X2
			use_taa = true
			use_fxaa = false
			glow_enabled = true
			glow_intensity = 0.35
			ssao_enabled = true
			ssil_enabled = false
			ssr_enabled = true
			sdfgi_enabled = false
			fog_enabled = true
			volumetric_fog_enabled = true
			use_aces_tonemap = true
			shadow_quality = ShadowQuality.HIGH
		Preset.ULTRA:
			render_scale = 1.0
			upscale_mode = UpscaleMode.BILINEAR
			fsr_sharpness = 0.2
			msaa = MsaaMode.X2
			use_taa = true
			use_fxaa = false
			glow_enabled = true
			glow_intensity = 0.45
			ssao_enabled = true
			ssil_enabled = true
			ssr_enabled = true
			sdfgi_enabled = false
			fog_enabled = true
			volumetric_fog_enabled = true
			use_aces_tonemap = true
			shadow_quality = ShadowQuality.ULTRA
		_:
			pass
	_sanitize_unsafe_settings()


static func mark_custom() -> void:
	preset = Preset.CUSTOM


static func reset_to_defaults() -> void:
	apply_preset(Preset.HIGH)
	fullscreen = false
	vsync = true


static func apply_all(tree: SceneTree = null) -> void:
	var t := tree
	if t == null:
		t = Engine.get_main_loop() as SceneTree
	if t == null:
		return
	_apply_window()
	_apply_viewport(t.root)
	_apply_project_shadows()
	_apply_world(t.current_scene)


static func _apply_window() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


static func _apply_viewport(root: Window) -> void:
	if root == null:
		return
	_sanitize_unsafe_settings()
	root.scaling_3d_scale = render_scale
	match upscale_mode:
		UpscaleMode.FSR1:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		UpscaleMode.FSR2:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		_:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.fsr_sharpness = fsr_sharpness
	match msaa:
		MsaaMode.X2:
			root.msaa_3d = Viewport.MSAA_2X
		MsaaMode.X4:
			root.msaa_3d = Viewport.MSAA_4X
		MsaaMode.X8:
			root.msaa_3d = Viewport.MSAA_8X
		_:
			root.msaa_3d = Viewport.MSAA_DISABLED
	root.use_taa = use_taa
	root.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA if use_fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	)


static func _apply_project_shadows() -> void:
	var size := 2048
	var soft := 1
	match shadow_quality:
		ShadowQuality.LOW:
			size = 1024
			soft = 0
		ShadowQuality.MEDIUM:
			size = 2048
			soft = 1
		ShadowQuality.HIGH:
			size = 4096
			soft = 1
		ShadowQuality.ULTRA:
			size = 8192
			soft = 2
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", size)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", soft)
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", soft)


static func _apply_world(root: Node) -> void:
	if root == null:
		return
	_apply_node_recursive(root)
	var tree := root.get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("day_cycle"):
		if node.has_method("apply"):
			node.apply()


static func _apply_node_recursive(node: Node) -> void:
	if node is WorldEnvironment:
		var we := node as WorldEnvironment
		if we.environment != null:
			apply_environment(we.environment)
	if node is DirectionalLight3D:
		apply_directional_light(node as DirectionalLight3D)
	for child in node.get_children():
		_apply_node_recursive(child)


static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	_sanitize_unsafe_settings()
	env.glow_enabled = glow_enabled
	env.glow_intensity = glow_intensity
	env.ssao_enabled = ssao_enabled
	env.ssil_enabled = ssil_enabled
	env.ssr_enabled = ssr_enabled
	env.sdfgi_enabled = sdfgi_enabled
	env.fog_enabled = fog_enabled
	env.volumetric_fog_enabled = volumetric_fog_enabled
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if night:
		env.ambient_light_energy = minf(env.ambient_light_energy, 0.16)
		env.tonemap_exposure = minf(env.tonemap_exposure, 0.65)
		env.glow_intensity = minf(glow_intensity, 0.10)
	else:
		env.ambient_light_energy = maxf(env.ambient_light_energy, 0.75)
	if use_aces_tonemap:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if volumetric_fog_enabled and env.volumetric_fog_density < 0.0001:
		env.volumetric_fog_density = 0.02
	if fog_enabled and not night:
		env.fog_light_energy = maxf(env.fog_light_energy, 0.8)
	if ssao_enabled:
		env.ssao_radius = maxf(env.ssao_radius, 1.0)
		env.ssao_intensity = maxf(env.ssao_intensity, 1.5)


static func apply_directional_light(light: DirectionalLight3D) -> void:
	if light == null:
		return
	light.shadow_enabled = true
	if not night:
		light.light_energy = maxf(light.light_energy, 1.15)
	light.shadow_bias = maxf(light.shadow_bias, 0.04)
	light.shadow_normal_bias = maxf(light.shadow_normal_bias, 2.0)
	match shadow_quality:
		ShadowQuality.LOW:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			light.shadow_blur = 0.5
		ShadowQuality.MEDIUM:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			light.shadow_blur = 0.8
		ShadowQuality.HIGH:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			light.shadow_blur = 1.0
		ShadowQuality.ULTRA:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			light.shadow_blur = 1.2


static func _sanitize_unsafe_settings() -> void:
	# On this project/hardware, MSAA above x2 causes giant black pixel artifacts.
	if msaa > MsaaMode.X2:
		msaa = MsaaMode.X2
	# SDFGI currently makes car lighting, especially Volga, much too dark.
	sdfgi_enabled = false
