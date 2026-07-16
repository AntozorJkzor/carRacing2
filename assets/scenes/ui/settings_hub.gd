extends Control

## Settings root: car / sound / graphics.

@onready var _car_button: Button = %CarButton
@onready var _sound_button: Button = %SoundButton
@onready var _graphics_button: Button = %GraphicsButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	GameAudio.restart_music()
	_car_button.pressed.connect(_on_car)
	_sound_button.pressed.connect(_on_sound)
	_graphics_button.pressed.connect(_on_graphics)
	_back_button.pressed.connect(_on_back)
	_car_button.grab_focus()


func _on_car() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_menu.tscn")


func _on_sound() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/sound_settings.tscn")


func _on_graphics() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/graphics_settings.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")
