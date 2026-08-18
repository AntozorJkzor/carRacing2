extends CanvasLayer

@export var car_path: NodePath

@onready var _speed_label: Label = %SpeedLabel
@onready var _rpm_label: Label = %RpmLabel
@onready var _gear_label: Label = %GearLabel
@onready var _minimap: Node = get_node_or_null("Minimap")
@onready var _score_label: Label = get_node_or_null("%ScoreLabel") as Label
@onready var _xp_bar: ProgressBar = get_node_or_null("%XpBar") as ProgressBar
@onready var _xp_label: Label = get_node_or_null("%XpLabel") as Label

var _car: CarController
var _stats: Node
var _fps_label: Label
var _fps_accum: float = 0.0


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	add_to_group("car_huds")
	_fps_label = get_node_or_null("%FpsLabel") as Label
	if _fps_label == null:
		_fps_label = Label.new()
		_fps_label.name = "FpsLabel"
		_fps_label.unique_name_in_owner = true
		_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_fps_label.offset_left = 16.0
		_fps_label.offset_top = 16.0
		_fps_label.offset_right = 180.0
		_fps_label.offset_bottom = 44.0
		_fps_label.add_theme_font_size_override("font_size", 20)
		_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_fps_label.add_theme_constant_override("outline_size", 6)
		add_child(_fps_label)
	_update_fps(true)


func bind_car(car: CarController) -> void:
	_car = car
	if car != null:
		car_path = get_path_to(car) if is_inside_tree() else car_path
	if _minimap != null and _minimap.has_method("bind_target"):
		_minimap.bind_target(car)


func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum >= 0.2:
		_fps_accum = 0.0
		_update_fps(false)
	if _car == null:
		return
	_speed_label.text = "%d км/ч" % int(round(_car.get_speed_kmh()))
	_rpm_label.text = "%d об/мин  ·  %d л.с." % [
		int(round(_car.engine_rpm)),
		int(round(_car.get_power_hp())),
	]
	_gear_label.text = "%s  %s" % [_car.get_transmission_label(), _car.get_gear_label()]


func _update_fps(_force: bool) -> void:
	if _fps_label == null:
		return
	var fps := int(round(Engine.get_frames_per_second()))
	_fps_label.text = "FPS  %d" % fps
	if fps >= 55:
		_fps_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1.0))
	elif fps >= 30:
		_fps_label.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32, 1.0))
	else:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.32, 1.0))


func _on_score_changed(score: int) -> void:
	if _score_label:
		_score_label.text = "Очки: %d" % score


func _on_xp_changed(xp: float, max_xp: float) -> void:
	if _xp_bar:
		_xp_bar.max_value = max_xp
		_xp_bar.value = xp
	if _xp_label:
		_xp_label.text = "XP  %d / %d" % [int(round(xp)), int(round(max_xp))]
