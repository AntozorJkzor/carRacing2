extends Control

const PHYSICS_TRACK := "res://assets/scenes/tracks/physics_test_track.tscn"
const CITY_TRACK := "res://assets/scenes/tracks/city_track.tscn"
const RUNWAY_TRACK := "res://assets/scenes/tracks/runway_track.tscn"
const TERRAIN_TRACK := "res://assets/scenes/tracks/terrain_track.tscn"

@onready var _new_game_button: Button = %NewGameButton
@onready var _fun_button: Button = %FunButton
@onready var _leaders_button: Button = %LeadersButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle
@onready var _main_box: VBoxContainer = %MainBox
@onready var _fun_box: VBoxContainer = %FunBox
@onready var _board_box: VBoxContainer = %BoardBox
@onready var _city_button: Button = %CityButton
@onready var _runway_button: Button = %RunwayButton
@onready var _terrain_button: Button = %TerrainButton
@onready var _fun_back_button: Button = %FunBackButton
@onready var _board_back_button: Button = %BoardBackButton


func _ready() -> void:
	GameAudio.restart_music()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_fun_button.pressed.connect(_on_fun_pressed)
	_leaders_button.pressed.connect(_on_leaders_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_city_button.pressed.connect(_on_city_pressed)
	_runway_button.pressed.connect(_on_runway_pressed)
	_terrain_button.pressed.connect(_on_terrain_pressed)
	_fun_back_button.pressed.connect(_show_main)
	_board_back_button.pressed.connect(_show_main)
	_subtitle.text = "Тест физики"
	_city_button.visible = ResourceLoader.exists(CITY_TRACK)
	_runway_button.visible = ResourceLoader.exists(RUNWAY_TRACK)
	_terrain_button.visible = ResourceLoader.exists(TERRAIN_TRACK)
	_show_main()
	_new_game_button.grab_focus()


func _show_main() -> void:
	_main_box.visible = true
	_fun_box.visible = false
	_board_box.visible = false
	_subtitle.text = "Тест физики"
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(PHYSICS_TRACK)


func _on_fun_pressed() -> void:
	_main_box.visible = false
	_fun_box.visible = true
	_board_box.visible = false
	_subtitle.text = "Развлечения"
	if _terrain_button.visible:
		_terrain_button.grab_focus()
	elif _city_button.visible:
		_city_button.grab_focus()
	elif _runway_button.visible:
		_runway_button.grab_focus()
	else:
		_fun_back_button.grab_focus()


func _on_leaders_pressed() -> void:
	_main_box.visible = false
	_fun_box.visible = false
	_board_box.visible = true
	_subtitle.text = "Таблица лидеров"
	_board_back_button.grab_focus()


func _on_city_pressed() -> void:
	if ResourceLoader.exists(CITY_TRACK):
		get_tree().change_scene_to_file(CITY_TRACK)


func _on_runway_pressed() -> void:
	if ResourceLoader.exists(RUNWAY_TRACK):
		get_tree().change_scene_to_file(RUNWAY_TRACK)


func _on_terrain_pressed() -> void:
	if ResourceLoader.exists(TERRAIN_TRACK):
		get_tree().change_scene_to_file(TERRAIN_TRACK)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
