extends Node

## Endless-road progression: 15 gears; HP grows every power_interval_sec.

const KW_PER_HP := 0.7457

@export var car_path: NodePath
@export var power_interval_sec: float = 20.0
@export var hp_per_minute_early: float = 100.0
@export var hp_per_minute_late: float = 200.0
@export var late_after_minutes: int = 5
## First 5 = stock. Extra overdrive gears get progressively longer.
@export var base_gear_ratios: Array[float] = [3.67, 2.1, 1.36, 1.0, 0.82]
@export var total_gears: int = 15
@export var top_gear_ratio: float = 0.12
@export var final_drive: float = 3.4

var _car: CarController
var _enabled: bool = false
var _elapsed: float = 0.0
var _base_power_kw: float = 180.0
var _last_tick: int = -1


func _ready() -> void:
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	set_physics_process(false)


func start_progression() -> void:
	if _car == null:
		return
	_ensure_runtime_setup()
	_base_power_kw = _car.setup.max_power_kw
	_apply_gears()
	_elapsed = 0.0
	_last_tick = -1
	_apply_power_for_ticks(0)
	_enabled = true
	set_physics_process(true)


func get_elapsed() -> float:
	return _elapsed


func get_bonus_hp() -> float:
	return _bonus_hp_for_ticks(_current_tick())


func get_total_hp() -> float:
	if _car == null or _car.setup == null:
		return 0.0
	return _car.setup.max_power_kw / KW_PER_HP


func _physics_process(delta: float) -> void:
	if not _enabled or _car == null or _car.setup == null:
		return
	_elapsed += delta
	var ticks := _current_tick()
	if ticks != _last_tick:
		_last_tick = ticks
		_apply_power_for_ticks(ticks)


func _current_tick() -> int:
	var interval := maxf(power_interval_sec, 0.01)
	return int(floor(_elapsed / interval))


func _ensure_runtime_setup() -> void:
	if _car.setup == null:
		_car.setup = CarSetup.new()
	var copy: CarSetup = _car.setup.duplicate(true) as CarSetup
	if copy == null:
		copy = CarSetup.new()
	copy.ensure_torque_curve()
	_car.set_setup(copy)


func _apply_gears() -> void:
	var ratios: Array[float] = []
	var base: Array[float] = base_gear_ratios
	if base.is_empty():
		base = [3.67, 2.1, 1.36, 1.0, 0.82]

	var keep := mini(base.size(), total_gears)
	for i in range(keep):
		ratios.append(base[i])

	# Gears after the stock five: each step longer (smaller ratio).
	var extra := total_gears - ratios.size()
	if extra > 0:
		var start_ratio := ratios[ratios.size() - 1]
		var end_ratio := minf(top_gear_ratio, start_ratio * 0.5)
		for i in range(extra):
			var t := float(i + 1) / float(extra)
			# Ease so later gears stretch more aggressively.
			var shaped := pow(t, 1.15)
			ratios.append(lerpf(start_ratio, end_ratio, shaped))

	_car.setup.gear_ratios = ratios
	_car.setup.final_drive = final_drive
	_car.setup.shift_time = 0.12
	var n := ratios.size()
	if _car.current_gear > n:
		_car.current_gear = n
	elif _car.current_gear < 1:
		_car.current_gear = 1


func _hp_per_tick_early() -> float:
	return hp_per_minute_early * (power_interval_sec / 60.0)


func _hp_per_tick_late() -> float:
	return hp_per_minute_late * (power_interval_sec / 60.0)


func _late_after_ticks() -> int:
	return int(round(float(late_after_minutes) * 60.0 / maxf(power_interval_sec, 0.01)))


func _bonus_hp_for_ticks(ticks: int) -> float:
	var t := maxi(ticks, 0)
	var late_at := _late_after_ticks()
	if t <= late_at:
		return float(t) * _hp_per_tick_early()
	return float(late_at) * _hp_per_tick_early() + float(t - late_at) * _hp_per_tick_late()


func _apply_power_for_ticks(ticks: int) -> void:
	if _car == null or _car.setup == null:
		return
	var bonus_hp := _bonus_hp_for_ticks(ticks)
	_car.setup.max_power_kw = _base_power_kw + bonus_hp * KW_PER_HP
