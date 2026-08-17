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


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	add_to_group("car_huds")


func bind_car(car: CarController) -> void:
	_car = car
	if car != null:
		car_path = get_path_to(car) if is_inside_tree() else car_path
	if _minimap != null and _minimap.has_method("bind_target"):
		_minimap.bind_target(car)


func _process(_delta: float) -> void:
	if _car == null:
		return
	_speed_label.text = "%d км/ч" % int(round(_car.get_speed_kmh()))
	_rpm_label.text = "%d об/мин  ·  %d л.с." % [
		int(round(_car.engine_rpm)),
		int(round(_car.get_power_hp())),
	]
	_gear_label.text = "%s  %s" % [_car.get_transmission_label(), _car.get_gear_label()]


func _on_score_changed(score: int) -> void:
	if _score_label:
		_score_label.text = "Очки: %d" % score


func _on_xp_changed(xp: float, max_xp: float) -> void:
	if _xp_bar:
		_xp_bar.max_value = max_xp
		_xp_bar.value = xp
	if _xp_label:
		_xp_label.text = "XP  %d / %d" % [int(round(xp)), int(round(max_xp))]
