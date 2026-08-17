extends Control

const PHYSICS_TRACK := "res://assets/scenes/tracks/physics_test_track.tscn"

@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle
@onready var _main_box: VBoxContainer = %MainBox


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	GameAudio.restart_music()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_subtitle.text = "Тест физики"
	_main_box.visible = true
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(PHYSICS_TRACK)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_hub.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
