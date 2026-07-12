extends Node3D

## Main endless-road game mode with chase intro cutscene.

@onready var _car: CarController = $Car
@onready var _driver: Node = $Car/PlayerDriver
@onready var _intro: Node = $Intro
@onready var _road_guard: Node = $RoadGuard
@onready var _crossers: Node = $Crossers
@onready var _progression: Node = $Progression
@onready var _run_stats: Node = $RunStats
@onready var _game_over: CanvasLayer = $GameOver
@onready var _game_over_score: Label = $GameOver/Center/VBox/ScoreLabel
@onready var _name_row: HBoxContainer = $GameOver/Center/VBox/NameRow
@onready var _name_edit: LineEdit = $GameOver/Center/VBox/NameRow/NameEdit
@onready var _save_score_button: Button = $GameOver/Center/VBox/NameRow/SaveScoreButton
@onready var _game_over_board: Label = $GameOver/Center/VBox/LeaderboardLabel
@onready var _hint_again: Label = $GameOver/Center/VBox/HintAgain

var _pending_score: int = 0
var _pending_duration: float = 0.0
var _score_saved: bool = false
var _name_input_ready: bool = false
@export var name_focus_delay_sec: float = 1.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _game_over:
		_game_over.visible = false
	if _game_over_board:
		_game_over_board.visible = false
	if _name_row:
		_name_row.visible = false
	if _save_score_button:
		_save_score_button.pressed.connect(_submit_score)
	if _name_edit:
		_name_edit.text_submitted.connect(_on_name_submitted)
	if _road_guard:
		_road_guard.set_physics_process(false)
	if _driver != null and "active" in _driver:
		_driver.active = false
	if _car != null:
		_car.allow_reverse = false
		_car.set_occupied(false, null)
	if _run_stats != null:
		if _run_stats.has_signal("xp_depleted"):
			_run_stats.xp_depleted.connect(_on_xp_depleted)
		if _run_stats.has_signal("run_ended"):
			_run_stats.run_ended.connect(_on_run_ended)
	if _intro and _intro.has_method("begin"):
		if _intro.has_signal("finished"):
			_intro.finished.connect(_on_intro_finished)
		_intro.call("begin")
	else:
		GameAudio.restart_music()
		_on_intro_finished()


func _on_intro_finished() -> void:
	if _car != null:
		_car.allow_reverse = false
	if _driver != null and "can_exit" in _driver:
		_driver.can_exit = false
	if _road_guard:
		_road_guard.set_physics_process(true)
	if _crossers != null and _crossers.has_method("start_spawning"):
		_crossers.call("start_spawning")
	if _progression != null and _progression.has_method("start_progression"):
		_progression.call("start_progression")
	if _run_stats != null and _run_stats.has_method("start_run"):
		_run_stats.call("start_run")


func _on_xp_depleted() -> void:
	if _crossers != null and _crossers.has_method("stop_spawning"):
		_crossers.call("stop_spawning")
	if _driver != null and "active" in _driver:
		_driver.active = false
	if _car != null:
		_car.throttle = 0.0
		_car.brake = 1.0
		_car.steering = 0.0
	GameAudio.play_lose_music()
	if _game_over:
		_game_over.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_run_ended(final_score: int, duration_sec: float) -> void:
	_pending_score = final_score
	_pending_duration = duration_sec
	_score_saved = false
	_name_input_ready = false
	if _game_over_score:
		_game_over_score.text = "Очки: %d   время %s" % [
			final_score,
			EndlessLeaderboard.format_duration(duration_sec),
		]
	if _game_over_board:
		_game_over_board.visible = false
		_game_over_board.text = ""
	if _name_row:
		_name_row.visible = true
	if _save_score_button:
		_save_score_button.disabled = true
		_save_score_button.focus_mode = Control.FOCUS_NONE
	if _name_edit:
		_name_edit.text = ""
		_name_edit.editable = false
		_name_edit.focus_mode = Control.FOCUS_NONE
		_name_edit.release_focus()
	var viewport := get_viewport()
	if viewport:
		viewport.gui_release_focus()
	if _hint_again:
		_hint_again.text = "Сейчас можно ввести имя…"
	# Delay focus so leftover W/A/S/D / Enter from driving don't type into the field.
	get_tree().create_timer(name_focus_delay_sec).timeout.connect(_enable_name_input)


func _enable_name_input() -> void:
	if _score_saved or not is_instance_valid(self):
		return
	if _game_over == null or not _game_over.visible:
		return
	_name_input_ready = true
	if _name_edit:
		_name_edit.text = ""
		_name_edit.editable = true
		_name_edit.focus_mode = Control.FOCUS_ALL
		_name_edit.grab_focus()
	if _save_score_button:
		_save_score_button.disabled = false
		_save_score_button.focus_mode = Control.FOCUS_ALL
	if _hint_again:
		_hint_again.text = "Введи имя и нажми Сохранить / Enter"


func _on_name_submitted(_text: String) -> void:
	if not _name_input_ready:
		return
	_submit_score()


func _submit_score() -> void:
	if _score_saved or not _name_input_ready:
		return
	_score_saved = true
	var player_name := "Игрок"
	if _name_edit:
		player_name = _name_edit.text
		_name_edit.editable = false
	if _save_score_button:
		_save_score_button.disabled = true
	if _name_row:
		_name_row.visible = false
	var entries := EndlessLeaderboard.add_entry(player_name, _pending_score, _pending_duration)
	if _game_over_board:
		_game_over_board.visible = true
		_game_over_board.text = EndlessLeaderboard.format_table(mini(entries.size(), 15))
	if _hint_again:
		_hint_again.text = "Enter / Esc — в меню"
	if _save_score_button:
		_save_score_button.release_focus()


func _go_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_menu()
		return
	if _game_over and _game_over.visible and event.is_action_pressed("ui_accept"):
		if not _score_saved:
			if _name_input_ready:
				_submit_score()
		else:
			_go_menu()
