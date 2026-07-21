extends Node3D

const LEADERBOARD_PATH := "user://lap_leaderboard.cfg"
const LEADERBOARD_SECTION := "track_physics_test"
const READY_HOLD_SEC := 3.0
const COUNTDOWN_SEC := 3.0
const READY_SPEED_MS := 0.6
const MAX_LEADERBOARD_ROWS := 10

signal lap_finished(time_sec: float)

@export var start_area_path: NodePath

var elapsed: float = 0.0
var countdown_text: String = ""
var status_text: String = ""

var _start_area: Area3D
var _checkpoints: Array[Area3D] = []
var _target_car: CarController
var _lap_active := false
var _countdown_active := false
var _ready_hold := 0.0
var _countdown_left := 0.0
var _next_checkpoint := 0
var _was_in_start := false
var _was_in_checkpoint := false


func _ready() -> void:
	if start_area_path != NodePath():
		_start_area = get_node_or_null(start_area_path) as Area3D
	var cp_root := get_node_or_null("Checkpoints")
	if cp_root != null:
		var names: Array[String] = []
		for child in cp_root.get_children():
			if child is Area3D:
				names.append(child.name)
		names.sort()
		for name in names:
			var cp := cp_root.get_node_or_null(name) as Area3D
			if cp != null:
				_checkpoints.append(cp)
	_update_status()


func _physics_process(delta: float) -> void:
	_target_car = _find_active_car()
	if _target_car == null or _start_area == null:
		_reset_idle_state()
		return

	var in_start := _area_has_body(_start_area, _target_car)
	var speed_ok := _target_car.linear_velocity.length() <= READY_SPEED_MS

	if _lap_active:
		elapsed += delta
		_update_checkpoint_progress()
		if in_start and not _was_in_start and _next_checkpoint >= _checkpoints.size():
			_finish_lap()
	elif _countdown_active:
		if not in_start or not speed_ok:
			_cancel_countdown()
		else:
			_countdown_left = maxf(_countdown_left - delta, 0.0)
			var shown := maxi(int(ceil(_countdown_left)), 0)
			countdown_text = str(shown) if shown > 0 else "СТАРТ"
			if _countdown_left <= 0.0:
				_begin_lap()
	elif in_start and speed_ok:
		_ready_hold += delta
		var left := maxi(int(ceil(READY_HOLD_SEC - _ready_hold)), 0)
		status_text = "Старт через %d…" % left if left > 0 else "Готовься…"
		if _ready_hold >= READY_HOLD_SEC:
			_countdown_active = true
			_countdown_left = COUNTDOWN_SEC
			countdown_text = "3"
			status_text = "Приготовься"
	else:
		_ready_hold = 0.0
		if not _lap_active:
			status_text = "Встань на старт и остановись"

	_was_in_start = in_start


func _find_active_car() -> CarController:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("player_cars"):
		var car := node as CarController
		if car != null and car.occupied:
			return car
	return null


func _area_has_body(area: Area3D, body: Node) -> bool:
	if area == null or body == null:
		return false
	for item in area.get_overlapping_bodies():
		if item == body:
			return true
	return false


func _update_checkpoint_progress() -> void:
	if _next_checkpoint >= _checkpoints.size():
		_was_in_checkpoint = false
		status_text = "Все чекпоинты пройдены, едь на финиш"
		return
	var cp := _checkpoints[_next_checkpoint]
	var in_cp := _area_has_body(cp, _target_car)
	if in_cp and not _was_in_checkpoint:
		_next_checkpoint += 1
		_was_in_checkpoint = false
		if _next_checkpoint >= _checkpoints.size():
			status_text = "Все чекпоинты пройдены, едь на финиш"
		else:
			status_text = "Чекпоинт %d / %d" % [_next_checkpoint, _checkpoints.size()]
		return
	_was_in_checkpoint = in_cp


func _begin_lap() -> void:
	_lap_active = true
	_countdown_active = false
	_ready_hold = 0.0
	_next_checkpoint = 0
	_was_in_checkpoint = false
	elapsed = 0.0
	countdown_text = ""
	status_text = "Круг начат: чекпоинт 1 / %d" % _checkpoints.size()


func _finish_lap() -> void:
	_lap_active = false
	var lap_time := elapsed
	countdown_text = ""
	status_text = "Финиш: %s" % _format_time(lap_time)
	_write_leaderboard(lap_time)
	lap_finished.emit(lap_time)
	elapsed = lap_time
	_ready_hold = 0.0
	_next_checkpoint = 0
	_was_in_checkpoint = false


func _cancel_countdown() -> void:
	_countdown_active = false
	_countdown_left = 0.0
	_ready_hold = 0.0
	countdown_text = ""
	status_text = "Встань на старт и остановись"


func _reset_idle_state() -> void:
	_ready_hold = 0.0
	_countdown_active = false
	_countdown_left = 0.0
	countdown_text = ""
	if not _lap_active:
		status_text = "Сядь в машину и встань на старт"


func _update_status() -> void:
	if _checkpoints.is_empty():
		status_text = "Нет чекпоинтов"
	else:
		status_text = "Встань на старт и остановись"


func _write_leaderboard(time_sec: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(LEADERBOARD_PATH)
	var rows: Array = []
	for i in range(MAX_LEADERBOARD_ROWS):
		if not cfg.has_section_key(LEADERBOARD_SECTION, "lap_%d_time" % i):
			break
		rows.append({
			"time_sec": float(cfg.get_value(LEADERBOARD_SECTION, "lap_%d_time" % i, 0.0)),
			"car_id": str(cfg.get_value(LEADERBOARD_SECTION, "lap_%d_car" % i, "")),
			"stamp": str(cfg.get_value(LEADERBOARD_SECTION, "lap_%d_stamp" % i, "")),
		})
	rows.append({
		"time_sec": time_sec,
		"car_id": String(_target_car.car_id) if _target_car != null else "",
		"stamp": Time.get_datetime_string_from_system(),
	})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time_sec"]) < float(b["time_sec"])
	)
	while rows.size() > MAX_LEADERBOARD_ROWS:
		rows.pop_back()
	for i in range(rows.size()):
		cfg.set_value(LEADERBOARD_SECTION, "lap_%d_time" % i, float(rows[i]["time_sec"]))
		cfg.set_value(LEADERBOARD_SECTION, "lap_%d_car" % i, str(rows[i]["car_id"]))
		cfg.set_value(LEADERBOARD_SECTION, "lap_%d_stamp" % i, str(rows[i]["stamp"]))
	cfg.save(LEADERBOARD_PATH)


func _format_time(time_sec: float) -> String:
	var total_ms := maxi(int(round(time_sec * 1000.0)), 0)
	var mins := total_ms / 60000
	var secs := (total_ms / 1000) % 60
	var centis := (total_ms % 1000) / 10
	return "%02d:%02d.%02d" % [mins, secs, centis]
