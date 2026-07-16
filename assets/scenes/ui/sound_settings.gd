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


func _ready() -> void:
	_master_slider.value = GameAudio.master_linear * 100.0
	_car_slider.value = GameAudio.car_linear * 100.0
	_music_slider.value = GameAudio.music_linear * 100.0
	_refresh_labels()
	_master_slider.value_changed.connect(_on_master)
	_car_slider.value_changed.connect(_on_car)
	_music_slider.value_changed.connect(_on_music)
	_back_button.pressed.connect(_on_back)
	_save_button.pressed.connect(_on_save)
	_back_button.grab_focus()


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
	get_tree().change_scene_to_file("res://assets/scenes/ui/settings_hub.tscn")
