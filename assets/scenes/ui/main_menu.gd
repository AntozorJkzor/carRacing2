extends Control

const PHYSICS_TRACK := "res://assets/scenes/tracks/physics_test_track.tscn"
const LEADERBOARD_PATH := "user://lap_leaderboard.cfg"
const LEADERBOARD_SECTION := "track_physics_test"

@onready var _new_game_button: Button = %NewGameButton
@onready var _leaders_button: Button = %LeadersButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle
@onready var _main_box: VBoxContainer = %MainBox
@onready var _board_box: VBoxContainer = %BoardBox
@onready var _board_label: Label = %BoardLabel
@onready var _board_back_button: Button = %BoardBackButton


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	GameAudio.restart_music()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_leaders_button.pressed.connect(_on_leaders_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_board_back_button.pressed.connect(_show_main)
	_subtitle.text = "Тест физики"
	_show_main()
	_new_game_button.grab_focus()


func _show_main() -> void:
	_main_box.visible = true
	_board_box.visible = false
	_subtitle.text = "Тест физики"
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(PHYSICS_TRACK)


func _on_leaders_pressed() -> void:
	_main_box.visible = false
	_board_box.visible = true
	_subtitle.text = "Таблица лидеров"
	_board_label.text = _build_leaderboard_text()
	_board_back_button.grab_focus()


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_hub.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()


func _build_leaderboard_text() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(LEADERBOARD_PATH) != OK:
		return "ТАБЛИЦА ЛИДЕРОВ\n\nПока нет записанных кругов."
	var lines := ["ТАБЛИЦА ЛИДЕРОВ", ""]
	var found := false
	for i in range(10):
		if not cfg.has_section_key(LEADERBOARD_SECTION, "lap_%d_time" % i):
			break
		found = true
		var time_sec := float(cfg.get_value(LEADERBOARD_SECTION, "lap_%d_time" % i, 0.0))
		var car_id := str(cfg.get_value(LEADERBOARD_SECTION, "lap_%d_car" % i, ""))
		lines.append("%d. %s  ·  %s" % [i + 1, _format_time(time_sec), car_id])
	if not found:
		lines.append("Пока нет записанных кругов.")
	return "\n".join(lines)


func _format_time(time_sec: float) -> String:
	var total_ms := maxi(int(round(time_sec * 1000.0)), 0)
	var mins := total_ms / 60000
	var secs := (total_ms / 1000) % 60
	var centis := (total_ms % 1000) / 10
	return "%02d:%02d.%02d" % [mins, secs, centis]
