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
	UiStyle.dress(self)
	UiStyle.mount_art(self, 0.08)
	UiStyle.dock_left($Center/Panel, 76.0, 0.4, true)
	_install_logo()
	_vignette.visible = false
	_main_box.add_theme_constant_override("separation", 0)
	UiStyle.button(_new_game_button, UiStyle.AMBER, 28)
	UiStyle.button(_settings_button, UiStyle.AMBER, 28)
	UiStyle.button(_exit_button, UiStyle.RED, 28)
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_main_box.visible = true
	_new_game_button.grab_focus()


func _install_logo() -> void:
	var parent := _title.get_parent()
	if parent.get_node_or_null("LogoBlock") != null:
		return
	var block := UiStyle.logo_mark(500)
	block.name = "LogoBlock"
	parent.add_child(block)
	parent.move_child(block, _title.get_index())
	_title.visible = false


func _refresh_language() -> void:
	_subtitle.text = Lang.t("menu.subtitle")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.add_theme_color_override("font_color", UiStyle.MUTED)
	_subtitle.add_theme_constant_override("outline_size", 0)
	_subtitle.add_theme_constant_override("shadow_size", 0)
	_new_game_button.text = Lang.t("menu.new_game")
	_settings_button.text = Lang.t("menu.settings")
	_exit_button.text = Lang.t("menu.quit")


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_hub.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
