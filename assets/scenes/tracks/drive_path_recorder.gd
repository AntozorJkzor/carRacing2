extends Node

## Records the driven car path so we can bake race waypoints later.
## F9 — save log · F10 — clear & restart recording

@export var car_path: NodePath = ^"../Car"
@export var min_distance_m: float = 1.5
@export var max_hz: float = 10.0
@export var auto_start: bool = false
@export var save_path: String = "res://assets/scenes/tracks/track2_drive_log.json"

var _car: Node3D
var _recording: bool = false
var _points: Array[Dictionary] = []
var _last_pos: Vector3 = Vector3.INF
var _accum: float = 0.0
var _hud: Label


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	call_deferred("_resolve_car")


func _resolve_car() -> void:
	_car = get_node_or_null(car_path) as Node3D
	_ensure_hud()


func start_recording() -> void:
	_recording = true
	_points.clear()
	_last_pos = Vector3.INF
	_accum = 0.0
	_update_hud()
	print("DrivePathRecorder: START")


func stop_and_save() -> void:
	_recording = false
	_save()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F9:
				stop_and_save()
				get_viewport().set_input_as_handled()
			KEY_F10:
				start_recording()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _recording or _car == null:
		return
	_accum += delta
	if _accum < 1.0 / maxf(max_hz, 1.0):
		return
	_accum = 0.0
	var pos := _car.global_position
	if _last_pos != Vector3.INF and pos.distance_to(_last_pos) < min_distance_m:
		return
	_last_pos = pos
	var yaw := _car.global_rotation.y
	_points.append({
		"x": snappedf(pos.x, 0.001),
		"y": snappedf(pos.y, 0.001),
		"z": snappedf(pos.z, 0.001),
		"yaw": snappedf(yaw, 0.0001),
		"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
	})
	_update_hud()


func _save() -> void:
	var payload := {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"point_count": _points.size(),
		"points": _points,
	}
	var text := JSON.stringify(payload, "\t")
	var abs_path := ProjectSettings.globalize_path(save_path)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		# Fallback to user:// if res:// is locked.
		var fallback := "user://track2_drive_log.json"
		f = FileAccess.open(fallback, FileAccess.WRITE)
		if f == null:
			push_error("DrivePathRecorder: cannot write log")
			return
		f.store_string(text)
		print("DrivePathRecorder: saved %d pts -> %s" % [_points.size(), ProjectSettings.globalize_path(fallback)])
		return
	f.store_string(text)
	print("DrivePathRecorder: saved %d pts -> %s" % [_points.size(), abs_path])


func _ensure_hud() -> void:
	if _hud != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 56)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	if _recording:
		_hud.text = "REC  %d pts   F9 save   F10 restart" % _points.size()
	elif _points.size() > 0:
		_hud.text = "SAVED/IDLE  %d pts   F10 record again" % _points.size()
	else:
		_hud.text = "PATH LOG idle   F10 start record"
