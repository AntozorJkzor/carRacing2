extends Control

const PHYSICS_TRACK := "res://assets/scenes/tracks/physics_test_track.tscn"

@onready var _new_game_button: Button = %NewGameButton
@onready var _leaders_button: Button = %LeadersButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle
@onready var _main_box: VBoxContainer = %MainBox
@onready var _board_box: VBoxContainer = %BoardBox
@onready var _board_back_button: Button = %BoardBackButton


func _ready() -> void:
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
	_board_back_button.grab_focus()


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
