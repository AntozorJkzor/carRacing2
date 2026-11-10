extends Control

const GARAGE_SCENE := "res://assets/scenes/ui/garage.tscn"

@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _subtitle: Label = %Subtitle
@onready var _background: ColorRect = $Background
@onready var _vignette: ColorRect = $Vignette
@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _main_box: VBoxContainer = %MainBox


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	GameAudio.restart_music()
	UiStyle.night_sky(_background)
	_vignette.color = Color(0.0, 0.0, 0.02, 0.32)
	UiStyle.button(_new_game_button, UiStyle.AMBER, 24)
	UiStyle.button(_settings_button, UiStyle.AMBER, 24)
	UiStyle.button(_exit_button, UiStyle.RED, 24)
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_main_box.visible = true
	_new_game_button.grab_focus()


func _refresh_language() -> void:
	_title.text = "TOUGE 95"
	UiStyle.headline_style(_title, 64)
	_subtitle.text = Lang.t("menu.subtitle")
	_new_game_button.text = Lang.t("menu.new_game")
	_settings_button.text = Lang.t("menu.settings")
	_exit_button.text = Lang.t("menu.quit")


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_hub.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
