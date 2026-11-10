extends Control

## Master / car / music volume sliders.

@onready var _master_slider: HSlider = %MasterSlider
@onready var _car_slider: HSlider = %CarSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _master_value: Label = %MasterValue
@onready var _car_value: Label = %CarValue
@onready var _music_value: Label = %MusicValue
@onready var _back_button: Button = %BackButton
@onready var _save_button: Button = %SaveButton
@onready var _title: Label = %Title
@onready var _master_label: Label = $Margin/VBox/Panel/List/MasterRow/MasterHeader/MasterLabel
@onready var _car_label: Label = $Margin/VBox/Panel/List/CarRow/CarHeader/CarLabel
@onready var _music_label: Label = $Margin/VBox/Panel/List/MusicRow/MusicHeader/MusicLabel
@onready var _background: ColorRect = $Background


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiStyle.night_sky(_background)
	UiStyle.button(_back_button, UiStyle.RED, 20)
	UiStyle.button(_save_button, UiStyle.AMBER, 20)
	UiStyle.section_label_style(_title, 30)
	UiStyle.section_label_style(_master_label, 18)
	UiStyle.section_label_style(_car_label, 18)
	UiStyle.section_label_style(_music_label, 18)
	UiStyle.lcd_label_style(_master_value)
	UiStyle.lcd_label_style(_car_value)
	UiStyle.lcd_label_style(_music_value)
	_master_slider.value = GameAudio.master_linear * 100.0
	_car_slider.value = GameAudio.car_linear * 100.0
	_music_slider.value = GameAudio.music_linear * 100.0
	_refresh_labels()
	_refresh_language()
	Lang.language_changed.connect(_refresh_language)
	_master_slider.value_changed.connect(_on_master)
	_car_slider.value_changed.connect(_on_car)
	_music_slider.value_changed.connect(_on_music)
	_back_button.pressed.connect(_on_back)
	_save_button.pressed.connect(_on_save)
	_back_button.grab_focus()


func _refresh_language() -> void:
	_title.text = Lang.t("sound.title")
	_master_label.text = Lang.t("sound.master")
	_car_label.text = Lang.t("sound.car")
	_music_label.text = Lang.t("sound.music")
	_back_button.text = Lang.t("common.back")
	_save_button.text = Lang.t("common.save")


func _on_master(value: float) -> void:
	GameAudio.set_master_linear(value / 100.0)
	_refresh_labels()


func _on_car(value: float) -> void:
	GameAudio.set_car_linear(value / 100.0)
	_refresh_labels()


func _on_music(value: float) -> void:
	GameAudio.set_music_linear(value / 100.0)
	_refresh_labels()


func _refresh_labels() -> void:
	_master_value.text = "%d%%" % int(round(_master_slider.value))
	_car_value.text = "%d%%" % int(round(_car_slider.value))
	_music_value.text = "%d%%" % int(round(_music_slider.value))


func _on_save() -> void:
	GameAudio.save_audio_settings()


func _on_back() -> void:
	GameAudio.save_audio_settings()
	SettingsNav.back(self, "res://assets/scenes/ui/settings_hub.tscn")