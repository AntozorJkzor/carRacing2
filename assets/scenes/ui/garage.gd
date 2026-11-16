extends Node3D

## Car picker: podium with mouse-drag rotation, arrows switch catalog cars.

const MENU_SCENE := "res://assets/scenes/ui/main_menu.tscn"
## Drive-only systems. Freed before the car enters the tree so their _ready
## (engine-bank decode, tire wavs, GPU smoke) does not run on every switch.
const _SHOWROOM_STRIP: PackedStringArray = [
	"EngineAudio", "DebugDraw", "Telemetry",
	"WheelSmoke", "SkidMarks", "TireAudio", "ExhaustFlame",
	"CockpitOverlay",
]
## Still in the catalog, just not offered on the podium.
const _GARAGE_HIDDEN: Array[StringName] = [&"volga", &"golf"]

@onready var _anchor: Node3D = $Anchor
@onready var _camera: Camera3D = $Camera3D
@onready var _car_name: Label = %CarName
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _track_option: OptionButton = %TrackOption
@onready var _track_label: Label = %TrackLabel
@onready var _drive_button: Button = %DriveButton
@onready var _menu_button: Button = %MenuButton
@onready var _title: Label = %Title
@onready var _hint: Label = %Hint
@onready var _tuning_button: Button = %TuningButton
@onready var _tuning_panel: CanvasLayer = $TuningPanel

var _ids: Array[StringName] = []
var _track_ids: Array[StringName] = []
var _index: int = 0
var _car: CarController = null


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	GameAudio.restart_music()
	_dress_showroom()
	var catalog: CarsCatalog = TuningStore.catalog
	if catalog != null:
		for def: CarDefinition in catalog.cars:
			if def != null and def.scene != null and def.id != StringName() and def.id not in _GARAGE_HIDDEN:
				_ids.append(def.id)
	if _ids.is_empty():
		push_error("Garage: catalog has no driveable cars")
		return
	var found := _ids.find(TuningStore.selected_car_id)
	_index = found if found >= 0 else 0
	UiStyle.button(_prev_button, UiStyle.AMBER, 22)
	UiStyle.button(_next_button, UiStyle.AMBER, 22)
	UiStyle.button(_menu_button, UiStyle.AMBER, 18)
	UiStyle.button(_drive_button, UiStyle.AMBER, 22)
	UiStyle.button(_tuning_button, UiStyle.AMBER, 18)
	_pin_hud_actions()
	UiStyle.headline_style(_car_name, 34)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(UiStyle.MUTED.r, UiStyle.MUTED.g, UiStyle.MUTED.b, 0.85))
	_hint.add_theme_constant_override("shadow_size", 0)
	var ui := get_node_or_null("UI")
	if ui != null and ui.get_node_or_null("LogoMark") == null:
		var mark := UiStyle.logo_mark(210)
		mark.name = "LogoMark"
		mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
		mark.offset_left = 28.0
		mark.offset_top = 14.0
		mark.offset_right = 238.0
		mark.offset_bottom = 64.0
		ui.add_child(mark)
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_drive_button.pressed.connect(_on_drive)
	_menu_button.pressed.connect(_on_menu)
	_tuning_button.pressed.connect(_on_tuning)
	_track_option.item_selected.connect(_on_track_selected)
	_populate_tracks()
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	if ui != null:
		for child in ui.get_children():
			if child is Control:
				UiStyle.dress(child)
	_camera.position = Vector3(0.7, 1.85, 7.6)
	_camera.fov = 40.0
	_camera.look_at(_anchor.global_position + Vector3(0, 0.4, 0), Vector3.UP)
	_spawn_current()


func _dress_showroom() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.014, 0.04)
	sky_mat.sky_horizon_color = Color(0.09, 0.07, 0.12)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.008, 0.01, 0.016)
	sky_mat.ground_horizon_color = Color(0.03, 0.028, 0.04)
	sky_mat.sun_angle_max = 4.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.26)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.025, 0.03, 0.05)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.45
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.15
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment = env
	var floor := get_node_or_null("Floor") as MeshInstance3D
	if floor != null:
		floor.set_surface_override_material(0, _ground_material())
	var wall := get_node_or_null("BackWall")
	if wall is CanvasItem or wall is Node3D:
		(wall as Node3D).visible = false
	if get_node_or_null("Backdrop") == null:
		var backdrop := MeshInstance3D.new()
		backdrop.name = "Backdrop"
		var plane := PlaneMesh.new()
		plane.size = Vector2(26.0, 14.6)
		var art := StandardMaterial3D.new()
		art.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		art.albedo_texture = UiStyle.art_texture()
		art.albedo_color = Color(0.78, 0.8, 0.86)
		art.uv1_scale = Vector3(0.58, 1.0, 1.0)
		art.uv1_offset = Vector3(0.0, 0.0, 0.0)
		art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		plane.material = art
		backdrop.mesh = plane
		backdrop.rotation_degrees = Vector3(90, 0, 0)
		backdrop.position = Vector3(0, 3.6, -7.4)
		add_child(backdrop)
	var podium := get_node_or_null("Podium/Mesh") as MeshInstance3D
	if podium != null:
		var disc := CylinderMesh.new()
		disc.top_radius = 3.35
		disc.bottom_radius = 3.55
		# Visual top is 0.24, just under the tire meshes (they rest on the
		# collision at 0.30). A taller disc read as the sidewalls going in.
		disc.height = 0.12
		disc.radial_segments = 80
		disc.material = _ground_material()
		podium.mesh = disc
		podium.position = Vector3(0, 0.03, 0)
	# Thin ring lying in the disc. A fat torus stood up in front of the tires.
	_add_ring("AmberRing", 3.24, 3.32, Color(1.0, 0.52, 0.18), 2.4, 0.20)
	if get_node_or_null("Stage") == null:
		var stage := MeshInstance3D.new()
		stage.name = "Stage"
		var plate := CylinderMesh.new()
		plate.top_radius = 4.7
		plate.bottom_radius = 4.9
		plate.height = 0.06
		plate.radial_segments = 80
		plate.material = _ground_material()
		stage.mesh = plate
		stage.position = Vector3(0, 0.05, 0)
		add_child(stage)
	_add_front_wash()
	var key := get_node_or_null("KeyLight") as SpotLight3D
	if key != null:
		key.light_energy = 6.0
	var fill := get_node_or_null("FillLight") as OmniLight3D
	if fill != null:
		fill.light_energy = 0.0
	if get_node_or_null("ShowroomProbe") == null:
		var probe := ReflectionProbe.new()
		probe.name = "ShowroomProbe"
		probe.size = Vector3(18, 10, 18)
		probe.position = Vector3(0, 2.2, 0)
		probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		probe.interior = false
		add_child(probe)
	var ui := get_node_or_null("UI")
	if ui != null and ui.get_node_or_null("BottomScrim") == null:
		_add_scrim(ui, false)
		_add_scrim(ui, true)


func _ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.html("#111423")
	return mat


func _add_front_wash() -> void:
	if get_node_or_null("FrontWash") != null:
		return
	var spot := SpotLight3D.new()
	spot.name = "FrontWash"
	spot.light_color = Color(1.0, 0.94, 0.84)
	spot.light_energy = 3.0
	spot.spot_range = 14.0
	spot.spot_angle = 42.0
	spot.spot_attenuation = 0.45
	spot.shadow_enabled = true
	spot.position = Vector3(0.2, 3.8, 4.4)
	add_child(spot)
	spot.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)


func _add_ring(node_name: String, inner: float, outer: float, color: Color, energy: float, y: float) -> void:
	if get_node_or_null(node_name) != null:
		return
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 12
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = energy
	torus.material = glow
	ring.mesh = torus
	ring.position = Vector3(0, y, 0)
	add_child(ring)


func _add_scrim(ui: Node, top: bool) -> void:
	var g := Gradient.new()
	if top:
		g.colors = PackedColorArray([Color(0.01, 0.014, 0.03, 0.55), Color(0, 0, 0, 0)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
	else:
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.01, 0.012, 0.02, 0.72)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0)
	tex.fill_to = Vector2(0.5, 1)
	tex.width = 8
	tex.height = 256
	var rect := TextureRect.new()
	rect.name = "TopScrim" if top else "BottomScrim"
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	if top:
		rect.set_anchors_preset(Control.PRESET_TOP_WIDE)
		rect.offset_bottom = 200.0
	else:
		rect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		rect.offset_top = -260.0
	ui.add_child(rect)
	ui.move_child(rect, 0)


func _pin_hud_actions() -> void:
	var bar := _drive_button.get_parent() as HBoxContainer
	if bar != null and bar.get_node_or_null("HudGap") == null:
		var gap := Control.new()
		gap.name = "HudGap"
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(gap)
		bar.move_child(gap, _drive_button.get_index())
	for b in [_menu_button, _tuning_button, _drive_button]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_drive_button.add_theme_color_override("font_color", UiStyle.AMBER)
	_drive_button.add_theme_font_size_override("font_size", 24)


func _refresh_language() -> void:
	_title.visible = false
	_drive_button.text = Lang.t("garage.drive")
	_menu_button.text = Lang.t("menu.main_menu")
	_hint.text = Lang.t("garage.hint")
	_tuning_button.text = Lang.t("garage.tuning")
	_track_label.text = Lang.t("garage.track")
	_track_label.add_theme_color_override("font_color", UiStyle.MUTED)
	_track_label.add_theme_font_size_override("font_size", 15)
	_refresh_track_names()
	_update_name()


func _populate_tracks() -> void:
	_track_option.clear()
	_track_ids.clear()
	var catalog: TracksCatalog = TuningStore.tracks_catalog
	if catalog == null:
		return
	var selected := 0
	for def: TrackDefinition in catalog.tracks:
		if def == null or def.scene == null or def.id == StringName():
			continue
		_track_ids.append(def.id)
		_track_option.add_item(Lang.t(def.name_key))
		if def.id == TuningStore.selected_track_id:
			selected = _track_ids.size() - 1
	if not _track_ids.is_empty():
		_track_option.select(selected)
		TuningStore.selected_track_id = _track_ids[selected]


func _refresh_track_names() -> void:
	var catalog: TracksCatalog = TuningStore.tracks_catalog
	if catalog == null:
		return
	for i in _track_ids.size():
		var def := catalog.get_by_id(_track_ids[i])
		if def != null:
			_track_option.set_item_text(i, Lang.t(def.name_key))


func _on_track_selected(index: int) -> void:
	if index >= 0 and index < _track_ids.size():
		TuningStore.selected_track_id = _track_ids[index]


func _update_name() -> void:
	if _ids.is_empty():
		return
	var catalog: CarsCatalog = TuningStore.catalog
	var def := catalog.get_by_id(_ids[_index]) if catalog != null else null
	_car_name.text = def.display_name if def != null else String(_ids[_index])


func _step(delta: int) -> void:
	if _ids.is_empty():
		return
	_index = (_index + delta + _ids.size()) % _ids.size()
	_spawn_current()


func _spawn_current() -> void:
	if _car != null and is_instance_valid(_car):
		_car.queue_free()
		_car = null
	var catalog: CarsCatalog = TuningStore.catalog
	if catalog == null:
		return
	var def := catalog.get_by_id(_ids[_index])
	if def == null or def.scene == null:
		return
	_car = def.scene.instantiate() as CarController
	_car.set_meta("showroom", true)
	for node_name in _SHOWROOM_STRIP:
		var extra := _car.get_node_or_null(node_name)
		if extra != null:
			_car.remove_child(extra)
			extra.free()
	_anchor.add_child(_car)
	var lamps := _car.get_node_or_null("CarLights")
	if lamps != null and lamps.has_method("present_in_showroom"):
		lamps.call("present_in_showroom")
	_car.position = Vector3(0.0, 0.45, 0.0)
	_car.rotation = Vector3.ZERO
	## 3/4 view, nose to the left; also normalizes the angle when switching cars.
	_anchor.rotation.y = deg_to_rad(def.showroom_yaw_deg)
	var driver := _car.get_node_or_null("PlayerDriver")
	if driver != null:
		driver.set("active", false)
		driver.set("can_exit", false)
	## Display only: no cabin camera hijack.
	for cam in _car.find_children("*", "Camera3D", true, false):
		(cam as Camera3D).current = false
	_camera.current = true
	_update_name()


func _process(delta: float) -> void:
	var ui := get_node_or_null("UI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = not _tuning_panel.visible
	## Polled drag: 1:1 with the physical cursor, independent of event routing.
	if _tuning_panel.visible:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	## Clamped: ignores synthetic cursor warps, keeps real drags 1:1.
	var vx := clampf(Input.get_last_mouse_velocity().x, -2500.0, 2500.0)
	if vx != 0.0:
		_anchor.rotate_y(-vx * 0.012 * delta)


func _on_drive() -> void:
	if _ids.is_empty():
		return
	TuningStore.selected_car_id = _ids[_index]
	TuningStore.bind_car_id(_ids[_index])
	var track := TuningStore.get_selected_track_scene() as PackedScene
	if track != null:
		get_tree().change_scene_to_packed(track)


func _on_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_tuning() -> void:
	if _ids.is_empty():
		return
	## Editing always targets the car on the podium.
	TuningStore.bind_car_id(_ids[_index])
	_tuning_panel.open_panel()
