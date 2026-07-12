extends Node

## Intro cutscene: player flees 50 chaotic NPCs, reaches the car, gameplay starts.

signal finished

enum Phase { IDLE, CHASE, TURN, APPROACH, ENTER, DONE }

@export var player_path: NodePath
@export var car_path: NodePath
@export var follow_camera_path: NodePath
@export var hud_path: NodePath
@export var npc_scene: PackedScene
@export var npc_count: int = 50
## Total intro length should match intro.mp3 (~16s).
@export var cutscene_duration: float = 16.0
@export var chase_duration: float = 10.5
@export var turn_duration: float = 2.5
@export var approach_duration: float = 3.0

@onready var _cutscene_cam: Camera3D = $CutsceneCamera
@onready var _subtitle_layer: CanvasLayer = $Subtitles
@onready var _subtitle_label: Label = $Subtitles/SubtitlePanel/SubtitleLabel

var _player: PlayerController
var _car: CarController
var _follow_cam: Camera3D
var _hud: CanvasLayer
var _driver: Node
var _npcs: Array[Node3D] = []
var _phase: Phase = Phase.IDLE
var _phase_t: float = 0.0
var _cutscene_elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()
var _subtitle_index: int = -1

var _player_start: Vector3 = Vector3(0.0, 0.05, -58.0)
var _player_chase_end: Vector3 = Vector3(0.0, 0.05, -14.0)
var _player_car_door: Vector3 = Vector3(2.4, 0.05, 3.2)

## Closer chase framing on the runner + dense mob behind him.
var _cam_chase_height: float = 1.35
var _cam_ahead: float = 2.4
var _cam_look_behind: float = 3.8

## Timed subtitle lines stretched across the full intro track.
var _subtitle_lines: Array[Dictionary] = [
	{"t": 0.0, "text": "АХАХАХХАХА АХАХАХХАХА АХАХАХХА"},
	{"t": 2.0, "text": "Я ПОБЕДИЛ, Я ПОБЕДИЛ"},
	{"t": 4.0, "text": "ТЫ ПРОИГРАЛ Л"},
	{"t": 5.8, "text": "Я ПОБЕДИЛ Я ПОБЕДИЛ"},
	{"t": 8.0, "text": "ПОТОМУ ЧТО Я ГЕНИЙ, Я УМНЫЙ"},
	{"t": 10.2, "text": "У МЕНЯ ЕСТЬ МАШИНА"},
	{"t": 12.2, "text": "ТЫ МЕНЯ НЕ ДОГОНИШЬ Л"},
	{"t": 14.0, "text": "АХАХХАХАХА"},
]


func _ready() -> void:
	_rng.randomize()
	if player_path != NodePath():
		_player = get_node_or_null(player_path) as PlayerController
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as CarController
	if follow_camera_path != NodePath():
		_follow_cam = get_node_or_null(follow_camera_path) as Camera3D
	if hud_path != NodePath():
		_hud = get_node_or_null(hud_path) as CanvasLayer
	if _car != null:
		_driver = _car.get_node_or_null("PlayerDriver")
	if _subtitle_layer:
		_subtitle_layer.visible = false
	set_physics_process(false)


func begin() -> void:
	_prepare_scene()
	_spawn_npcs()
	_sync_phase_durations()
	GameAudio.play_intro_music()
	_show_subtitles(true)
	_subtitle_index = -1
	_cutscene_elapsed = 0.0
	_update_subtitles()
	_phase = Phase.CHASE
	_phase_t = 0.0
	set_process_unhandled_input(true)
	set_physics_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	if event.is_action_pressed("ui_accept"):
		_skip_cutscene()
		get_viewport().set_input_as_handled()


func _skip_cutscene() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_finish_and_start_gameplay()


func _sync_phase_durations() -> void:
	# Keep exported ratios but force the whole cutscene to match the track length.
	var total := chase_duration + turn_duration + approach_duration
	if total <= 0.01:
		chase_duration = cutscene_duration * 0.66
		turn_duration = cutscene_duration * 0.16
		approach_duration = cutscene_duration * 0.18
		return
	var scale := cutscene_duration / total
	chase_duration *= scale
	turn_duration *= scale
	approach_duration *= scale


func _prepare_scene() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _hud:
		_hud.visible = false
	if _follow_cam and _follow_cam.has_method("set_active"):
		_follow_cam.call("set_active", false)
	elif _follow_cam:
		_follow_cam.current = false

	if _car != null:
		_car.allow_reverse = false
		_car.set_occupied(false, null)
		_car.throttle = 0.0
		_car.brake = 0.0
		_car.steering = 0.0
	if _driver != null and "active" in _driver:
		_driver.active = false
	if _driver != null and "can_exit" in _driver:
		_driver.can_exit = false

	if _player != null:
		_player.set_on_foot(true)
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
		_player.global_position = _player_start
		_player.velocity = Vector3.ZERO
		_player.look_at(_player_start + Vector3(0.0, 0.0, 1.0), Vector3.UP)
		_play_player_run()
		var player_cam := _player.get_node_or_null("Head/Camera3D") as Camera3D
		if player_cam:
			player_cam.current = false

	if _cutscene_cam:
		_cutscene_cam.current = true
		_place_chase_camera(1.0)


func _spawn_npcs() -> void:
	_clear_npcs()
	if npc_scene == null or _player == null:
		return
	var anim_pool: Array[String] = ["sits", "run", "fight", "an1", "an2", "an3", "an4"]
	# Tight column right behind the hero: a few ranks × several files.
	var cols := 5
	var rows := int(ceil(float(npc_count) / float(cols)))
	var col_spacing := 0.85
	var row_spacing := 0.95
	var first_row_behind := 1.6
	var march_dir := Vector3(0.0, 0.0, 1.0)
	var spawned := 0
	for row in range(rows):
		for col in range(cols):
			if spawned >= npc_count:
				break
			var npc := npc_scene.instantiate() as Node3D
			if npc == null:
				continue
			add_child(npc)
			var x := (float(col) - float(cols - 1) * 0.5) * col_spacing
			x += _rng.randf_range(-0.08, 0.08)
			var z := _player_start.z - first_row_behind - float(row) * row_spacing
			z += _rng.randf_range(-0.06, 0.06)
			npc.global_position = Vector3(_player_start.x + x, 0.0, z)
			# Same march pace as the staged hero run (~slightly slower so column stays behind).
			var speed := _rng.randf_range(3.7, 4.1)
			var anim_name := anim_pool[_rng.randi_range(0, anim_pool.size() - 1)]
			if npc.has_method("setup_march"):
				npc.call("setup_march", march_dir, speed, anim_pool, anim_name)
			elif npc.has_method("setup"):
				npc.call("setup", _player, anim_name, speed, 0.0)
			_npcs.append(npc)
			spawned += 1


func _clear_npcs() -> void:
	for npc in _npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_npcs.clear()


func _physics_process(delta: float) -> void:
	if _phase == Phase.DONE or _phase == Phase.IDLE:
		return
	_phase_t += delta
	_cutscene_elapsed += delta
	_update_subtitles()
	match _phase:
		Phase.CHASE:
			_tick_chase(delta)
		Phase.TURN:
			_tick_turn(delta)
		Phase.APPROACH:
			_tick_approach(delta)
		Phase.ENTER:
			_tick_enter()


func _tick_chase(_delta: float) -> void:
	var t := clampf(_phase_t / maxf(chase_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	if _player:
		_player.global_position = _player_start.lerp(_player_chase_end, eased)
		_player.look_at(_player.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
		_play_player_run()
	_place_chase_camera(1.0)
	if _phase_t >= chase_duration:
		_phase = Phase.TURN
		_phase_t = 0.0


func _tick_turn(_delta: float) -> void:
	var t := clampf(_phase_t / maxf(turn_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	if _player:
		var pos := _player_chase_end.lerp(_player_car_door, eased * 0.35)
		_player.global_position = pos
		_player.look_at(_player.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
		_play_player_run()
	_blend_chase_to_car_camera(eased)
	if _phase_t >= turn_duration:
		_phase = Phase.APPROACH
		_phase_t = 0.0


func _tick_approach(_delta: float) -> void:
	var t := clampf(_phase_t / maxf(approach_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var from := _player_chase_end.lerp(_player_car_door, 0.35)
	if _player:
		_player.global_position = from.lerp(_player_car_door, eased)
		if _car:
			var to_car := _car.global_position - _player.global_position
			to_car.y = 0.0
			if to_car.length_squared() > 0.01:
				_player.look_at(_player.global_position + to_car.normalized(), Vector3.UP)
		_play_player_run()
	_place_car_focus_camera(eased)
	if _phase_t >= approach_duration:
		_phase = Phase.ENTER
		_phase_t = 0.0


func _tick_enter() -> void:
	_finish_and_start_gameplay()


func _place_chase_camera(_weight: float) -> void:
	if _cutscene_cam == null or _player == null:
		return
	var cam_pos := _player.global_position + Vector3(0.25, _cam_chase_height, _cam_ahead)
	var look_at_pos := _player.global_position + Vector3(0.0, 1.05, -_cam_look_behind)
	_cutscene_cam.global_position = cam_pos
	_cutscene_cam.look_at(look_at_pos, Vector3.UP)
	_cutscene_cam.fov = 52.0


func _blend_chase_to_car_camera(t: float) -> void:
	if _cutscene_cam == null or _player == null or _car == null:
		return
	var chase_pos := _player.global_position + Vector3(0.25, _cam_chase_height, _cam_ahead)
	var chase_look := _player.global_position + Vector3(0.0, 1.05, -_cam_look_behind)
	var car_pos := _car.global_position + Vector3(5.5, 3.2, -6.0)
	var car_look := _car.global_position + Vector3(0.0, 1.0, 2.0)
	_cutscene_cam.global_position = chase_pos.lerp(car_pos, t)
	var look := chase_look.lerp(car_look, t)
	_cutscene_cam.look_at(look, Vector3.UP)
	_cutscene_cam.fov = lerpf(52.0, 70.0, t)


func _place_car_focus_camera(t: float) -> void:
	if _cutscene_cam == null or _player == null or _car == null:
		return
	var from_pos := _car.global_position + Vector3(5.5, 3.2, -6.0)
	var to_pos := _car.global_position + Vector3(4.0, 2.8, -3.5)
	var from_look := _car.global_position + Vector3(0.0, 1.0, 2.0)
	var to_look := _player.global_position.lerp(_car.global_position, 0.55) + Vector3(0.0, 1.1, 0.0)
	_cutscene_cam.global_position = from_pos.lerp(to_pos, t)
	_cutscene_cam.look_at(from_look.lerp(to_look, t), Vector3.UP)


func _play_player_run() -> void:
	if _player == null:
		return
	if _player.has_method("play_run_animation"):
		_player.call("play_run_animation")
		return
	var model := _player.get_node_or_null("Model")
	if model == null:
		return
	var anim := _find_animation_player(model)
	if anim == null:
		return
	var list := anim.get_animation_list()
	if list.is_empty():
		return
	var run_name := list[0]
	for anim_name in list:
		if "run" in String(anim_name).to_lower():
			run_name = anim_name
			break
	if anim.current_animation != run_name or not anim.is_playing():
		anim.play(run_name, 0.0)


func _show_subtitles(enabled: bool) -> void:
	if _subtitle_layer:
		_subtitle_layer.visible = enabled
	if not enabled and _subtitle_label:
		_subtitle_label.text = ""


func _update_subtitles() -> void:
	if _subtitle_label == null:
		return
	var next_index := _subtitle_index
	for i in range(_subtitle_lines.size()):
		if _cutscene_elapsed >= float(_subtitle_lines[i]["t"]):
			next_index = i
	if next_index != _subtitle_index and next_index >= 0:
		_subtitle_index = next_index
		_subtitle_label.text = str(_subtitle_lines[_subtitle_index]["text"])


func _finish_and_start_gameplay() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	set_physics_process(false)
	set_process_unhandled_input(false)
	_clear_npcs()
	_show_subtitles(false)
	GameAudio.restore_game_music()

	if _cutscene_cam:
		_cutscene_cam.current = false

	if _player != null and _car != null:
		_player.force_enter_car(_car)
	elif _car != null:
		_car.set_occupied(true, _player)

	if _driver != null and "can_exit" in _driver:
		_driver.can_exit = false
	if _driver != null and "active" in _driver:
		_driver.active = true

	if _follow_cam and _follow_cam.has_method("set_active"):
		_follow_cam.call("set_active", true)
	elif _follow_cam:
		_follow_cam.current = true

	if _hud:
		_hud.visible = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
