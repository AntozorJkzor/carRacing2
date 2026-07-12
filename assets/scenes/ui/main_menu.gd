extends Control

@onready var _main_box: VBoxContainer = %MainBox
@onready var _fun_box: VBoxContainer = %FunBox
@onready var _board_box: VBoxContainer = %BoardBox
@onready var _new_game_button: Button = %NewGameButton
@onready var _fun_button: Button = %FunButton
@onready var _leaders_button: Button = %LeadersButton
@onready var _city_button: Button = %CityButton
@onready var _runway_button: Button = %RunwayButton
@onready var _fun_back_button: Button = %FunBackButton
@onready var _board_back_button: Button = %BoardBackButton
@onready var _board_label: Label = %BoardLabel
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle


func _ready() -> void:
	GameAudio.restart_music()
	EndlessLeaderboard.load_player_entries()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_fun_button.pressed.connect(_on_fun_pressed)
	_leaders_button.pressed.connect(_on_leaders_pressed)
	_city_button.pressed.connect(_on_city_pressed)
	_runway_button.pressed.connect(_on_runway_pressed)
	_fun_back_button.pressed.connect(_on_fun_back_pressed)
	_board_back_button.pressed.connect(_on_board_back_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_show_main()
	_new_game_button.grab_focus()


func _show_main() -> void:
	_main_box.visible = true
	_fun_box.visible = false
	_board_box.visible = false
	_subtitle.text = "Основной режим"


func _show_fun() -> void:
	_main_box.visible = false
	_fun_box.visible = true
	_board_box.visible = false
	_subtitle.text = "Развлечения"
	_city_button.grab_focus()


func _show_board() -> void:
	_main_box.visible = false
	_fun_box.visible = false
	_board_box.visible = true
	_subtitle.text = "Таблица лидеров"
	_board_label.text = EndlessLeaderboard.format_table(25)
	_board_back_button.grab_focus()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/tracks/endless_road_track.tscn")


func _on_fun_pressed() -> void:
	_show_fun()


func _on_leaders_pressed() -> void:
	_show_board()


func _on_fun_back_pressed() -> void:
	_show_main()
	_fun_button.grab_focus()


func _on_board_back_pressed() -> void:
	_show_main()
	_leaders_button.grab_focus()


func _on_city_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/tracks/city_track.tscn")


func _on_runway_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/tracks/runway_track.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
