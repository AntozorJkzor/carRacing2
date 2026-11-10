extends Control

## Settings root: car / sound / graphics + game language.

@onready var _car_button: Button = %CarButton
@onready var _sound_button: Button = %SoundButton
@onready var _graphics_button: Button = %GraphicsButton
@onready var _back_button: Button = %BackButton
@onready var _title: Label = %Title
@onready var _language_label: Label = %LanguageLabel
@onready var _language_option: OptionButton = %LanguageOption
@onready var _background: ColorRect = $Background


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	UiStyle.night_sky(_background)
	if not SettingsNav.is_overlay(self):
		GameAudio.restart_music()
	_car_button.pressed.connect(_on_car)
	_sound_button.pressed.connect(_on_sound)
	_graphics_button.pressed.connect(_on_graphics)
	_back_button.pressed.connect(_on_back)
	_language_option.item_selected.connect(_on_language_selected)
	_language_option.add_item("Русский", 0)
	_language_option.add_item("English", 1)
	_language_option.selected = 0 if Lang.language == "ru" else 1
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	_car_button.grab_focus()


func _refresh_language() -> void:
	_title.text = Lang.t("hub.title")
	UiStyle.section_label_style(_title, 34)
	UiStyle.button(_car_button, UiStyle.AMBER, 22)
	UiStyle.button(_sound_button, UiStyle.AMBER, 22)
	UiStyle.button(_graphics_button, UiStyle.AMBER, 22)
	UiStyle.button(_back_button, UiStyle.RED, 22)
	_car_button.text = Lang.t("hub.car")
	_sound_button.text = Lang.t("hub.sound")
	_graphics_button.text = Lang.t("hub.graphics")
	_back_button.text = Lang.t("common.back")
	_language_label.text = Lang.t("hub.language")


func _on_language_selected(index: int) -> void:
	Lang.set_language("ru" if index == 0 else "en")


func _on_car() -> void:
	SettingsNav.go(self, "res://assets/scenes/ui/settings_menu.tscn")


func _on_sound() -> void:
	SettingsNav.go(self, "res://assets/scenes/ui/sound_settings.tscn")


func _on_graphics() -> void:
	SettingsNav.go(self, "res://assets/scenes/ui/graphics_settings.tscn")


func _on_back() -> void:
	SettingsNav.back(self, "res://assets/scenes/ui/main_menu.tscn")
