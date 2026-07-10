extends CanvasLayer

@export var car_path: NodePath

@onready var _speed_label: Label = %SpeedLabel
@onready var _rpm_label: Label = %RpmLabel
@onready var _gear_label: Label = %GearLabel

var _car: CarController


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController


func _process(_delta: float) -> void:
	if _car == null:
		return
	_speed_label.text = "%d км/ч" % int(round(_car.get_speed_kmh()))
	_rpm_label.text = "%d об/мин" % int(round(_car.engine_rpm))
	_gear_label.text = "%s  %s" % [_car.get_transmission_label(), _car.get_gear_label()]
