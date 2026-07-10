extends Control

@onready var _city_button: Button = %CityButton
@onready var _runway_button: Button = %RunwayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton


func _ready() -> void:
	GameAudio.restart_music()
	_city_button.pressed.connect(_on_city_pressed)
	_runway_button.pressed.connect(_on_runway_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_city_button.grab_focus()


func _on_city_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/tracks/city_track.tscn")


func _on_runway_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/tracks/runway_track.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
