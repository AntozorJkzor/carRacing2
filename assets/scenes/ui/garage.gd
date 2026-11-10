extends Node3D

## Car picker: podium with mouse-drag rotation, arrows switch catalog cars.

const TRACK_SCENE := "res://assets/scenes/tracks/physics_test_track.tscn"
const MENU_SCENE := "res://assets/scenes/ui/main_menu.tscn"

@onready var _anchor: Node3D = $Anchor
@onready var _camera: Camera3D = $Camera3D
@onready var _car_name: Label = %CarName
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _drive_button: Button = %DriveButton
@onready var _menu_button: Button = %MenuButton
@onready var _title: Label = %Title
@onready var _hint: Label = %Hint
@onready var _tuning_button: Button = %TuningButton
@onready var _tuning_panel: CanvasLayer = $TuningPanel

var _ids: Array[StringName] = []
var _index: int = 0
var _car: CarController = null


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GameAudio.restart_music()
	var catalog: CarsCatalog = TuningStore.catalog
	if catalog != null:
		for def: CarDefinition in catalog.cars:
			if def != null and def.scene != null and def.id != StringName():
				_ids.append(def.id)
	if _ids.is_empty():
		push_error("Garage: catalog has no driveable cars")
		return
	var found := _ids.find(TuningStore.selected_car_id)
	_index = found if found >= 0 else 0
	UiStyle.button(_prev_button, UiStyle.AMBER, 22)
	UiStyle.button(_next_button, UiStyle.AMBER, 22)
	UiStyle.button(_menu_button, UiStyle.RED, 20)
	UiStyle.button(_drive_button, UiStyle.RED, 22)
	UiStyle.button(_tuning_button, UiStyle.AMBER, 20)
	UiStyle.headline_style(_car_name, 30)
	UiStyle.section_label_style(_title, 24)
	UiStyle.lcd_label_style(_hint, 13)
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_drive_button.pressed.connect(_on_drive)
	_menu_button.pressed.connect(_on_menu)
	_tuning_button.pressed.connect(_on_tuning)
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	_camera.look_at(_anchor.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	_spawn_current()


func _refresh_language() -> void:
	_title.text = "TOUGE · " + Lang.t("garage.title")
	_drive_button.text = Lang.t("garage.drive")
	_menu_button.text = Lang.t("menu.main_menu")
	_hint.text = Lang.t("garage.hint")
	_tuning_button.text = Lang.t("garage.tuning")
	_update_name()


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
	_anchor.add_child(_car)
	_car.position = Vector3(0.0, 0.45, 0.0)
	_car.rotation = Vector3.ZERO
	## 3/4 view, nose to the left; also normalizes the angle when switching cars.
	_anchor.rotation.y = deg_to_rad(def.showroom_yaw_deg)
	var driver := _car.get_node_or_null("PlayerDriver")
	if driver != null:
		driver.set("active", false)
		driver.set("can_exit", false)
	## Display only: no cabin camera hijack, no smoke/skid/exhaust FX on settle.
	for cam in _car.find_children("*", "Camera3D", true, false):
		(cam as Camera3D).current = false
	for fx_name in ["WheelSmoke", "SkidMarks", "TireAudio", "ExhaustFlame"]:
		var fx := _car.get_node_or_null(fx_name)
		if fx != null:
			fx.queue_free()
	_camera.current = true
	_update_name()


func _process(delta: float) -> void:
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
	get_tree().change_scene_to_file(TRACK_SCENE)


func _on_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_tuning() -> void:
	if _ids.is_empty():
		return
	## Editing always targets the car on the podium.
	TuningStore.bind_car_id(_ids[_index])
	_tuning_panel.open_panel()
