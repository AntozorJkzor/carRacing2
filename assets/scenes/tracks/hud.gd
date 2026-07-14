extends CanvasLayer

@export var car_path: NodePath
@export var run_stats_path: NodePath

@onready var _speed_label: Label = %SpeedLabel
@onready var _rpm_label: Label = %RpmLabel
@onready var _gear_label: Label = %GearLabel
@onready var _score_label: Label = get_node_or_null("%ScoreLabel") as Label
@onready var _timer_label: Label = get_node_or_null("%TimerLabel") as Label
@onready var _xp_bar: ProgressBar = get_node_or_null("%XpBar") as ProgressBar
@onready var _xp_label: Label = get_node_or_null("%XpLabel") as Label

var _car: CarController
var _stats: Node


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	if run_stats_path != NodePath():
		_stats = get_node_or_null(run_stats_path)
	if _stats != null:
		if _stats.has_signal("score_changed"):
			_stats.score_changed.connect(_on_score_changed)
		if _stats.has_signal("xp_changed"):
			_stats.xp_changed.connect(_on_xp_changed)
		_on_score_changed(int(_stats.get("score")))
		_on_xp_changed(float(_stats.get("xp")), float(_stats.get("max_xp")))
	_update_timer_label(0.0)
	add_to_group("car_huds")


func bind_car(car: CarController) -> void:
	_car = car
	if car != null:
		car_path = get_path_to(car) if is_inside_tree() else car_path


func _process(_delta: float) -> void:
	if _stats != null and "elapsed" in _stats:
		_update_timer_label(float(_stats.get("elapsed")))
	if _car == null:
		return
	_speed_label.text = "%d км/ч" % int(round(_car.get_speed_kmh()))
	_rpm_label.text = "%d об/мин  ·  %d л.с." % [
		int(round(_car.engine_rpm)),
		int(round(_car.get_power_hp())),
	]
	_gear_label.text = "%s  %s" % [_car.get_transmission_label(), _car.get_gear_label()]


func _update_timer_label(elapsed_sec: float) -> void:
	if _timer_label == null:
		return
	var total := maxi(int(floor(elapsed_sec)), 0)
	var mins := total / 60
	var secs := total % 60
	_timer_label.text = "%02d:%02d" % [mins, secs]


func _on_score_changed(score: int) -> void:
	if _score_label:
		_score_label.text = "Очки: %d" % score


func _on_xp_changed(xp: float, max_xp: float) -> void:
	if _xp_bar:
		_xp_bar.max_value = max_xp
		_xp_bar.value = xp
	if _xp_label:
		_xp_label.text = "XP  %d / %d" % [int(round(xp)), int(round(max_xp))]
