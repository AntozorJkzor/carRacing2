extends Control

## Graphics quality UI wired to GraphicsConfig.

@onready var _list: VBoxContainer = %ParamList
@onready var _preset_option: OptionButton = %PresetOption
@onready var _back_button: Button = %BackButton
@onready var _save_button: Button = %SaveButton
@onready var _reset_button: Button = %ResetButton
@onready var _status: Label = %StatusLabel

var _suppress: bool = false
var _checkboxes: Dictionary = {}
var _sliders: Dictionary = {}
var _options: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GraphicsConfig.load_from_disk()
	GraphicsConfig.apply_all(get_tree())
	_back_button.pressed.connect(_on_back)
	_save_button.pressed.connect(_on_save)
	_reset_button.pressed.connect(_on_reset)
	_preset_option.clear()
	_preset_option.add_item("Свой", GraphicsConfig.Preset.CUSTOM)
	_preset_option.add_item("Низко", GraphicsConfig.Preset.LOW)
	_preset_option.add_item("Средне", GraphicsConfig.Preset.MEDIUM)
	_preset_option.add_item("Высоко", GraphicsConfig.Preset.HIGH)
	_preset_option.add_item("Ультра", GraphicsConfig.Preset.ULTRA)
	_preset_option.item_selected.connect(_on_preset_selected)
	_rebuild_ui()
	_sync_preset_option()
	_status.text = "MSAA выше 2x и SDFGI отключены как нестабильные"
	_back_button.grab_focus()


func _rebuild_ui() -> void:
	for child in _list.get_children():
		child.queue_free()
	_checkboxes.clear()
	_sliders.clear()
	_options.clear()

	_add_section("Масштаб и сглаживание")
	_add_slider("render_scale", "Масштаб 3D", 0.5, 1.0, 0.05, GraphicsConfig.render_scale)
	_add_option("upscale_mode", "Апскейл", [
		["Bilinear", GraphicsConfig.UpscaleMode.BILINEAR],
		["FSR 1.0", GraphicsConfig.UpscaleMode.FSR1],
		["FSR 2.2", GraphicsConfig.UpscaleMode.FSR2],
	], GraphicsConfig.upscale_mode)
	_add_slider("fsr_sharpness", "FSR резкость", 0.0, 2.0, 0.05, GraphicsConfig.fsr_sharpness)
	_add_option("msaa", "MSAA", [
		["Выкл", GraphicsConfig.MsaaMode.OFF],
		["2x", GraphicsConfig.MsaaMode.X2],
	], GraphicsConfig.msaa)
	_add_check("use_taa", "TAA", GraphicsConfig.use_taa)
	_add_check("use_fxaa", "FXAA", GraphicsConfig.use_fxaa)

	_add_section("Освещение и эффекты")
	_add_check("glow_enabled", "Glow / Bloom", GraphicsConfig.glow_enabled)
	_add_slider("glow_intensity", "Интенсивность glow", 0.05, 1.5, 0.05, GraphicsConfig.glow_intensity)
	_add_check("ssao_enabled", "SSAO", GraphicsConfig.ssao_enabled)
	_add_check("ssil_enabled", "SSIL", GraphicsConfig.ssil_enabled)
	_add_check("ssr_enabled", "SSR (отражения)", GraphicsConfig.ssr_enabled)
	_add_check("sdfgi_enabled", "SDFGI (временно отключено)", false)
	_add_check("fog_enabled", "Туман", GraphicsConfig.fog_enabled)
	_add_check("volumetric_fog_enabled", "Объёмный туман", GraphicsConfig.volumetric_fog_enabled)
	_add_check("use_aces_tonemap", "Tonemap ACES", GraphicsConfig.use_aces_tonemap)
	_add_option("shadow_quality", "Качество теней", [
		["Низко", GraphicsConfig.ShadowQuality.LOW],
		["Средне", GraphicsConfig.ShadowQuality.MEDIUM],
		["Высоко", GraphicsConfig.ShadowQuality.HIGH],
		["Ультра", GraphicsConfig.ShadowQuality.ULTRA],
	], GraphicsConfig.shadow_quality)

	_add_section("Мир")
	_add_check("night", "Ночь", GraphicsConfig.night)
	_add_check("tire_smoke_enabled", "Дым шин", GraphicsConfig.tire_smoke_enabled)

	_add_section("Экран")
	_add_check("fullscreen", "Полный экран", GraphicsConfig.fullscreen)
	_add_check("vsync", "VSync", GraphicsConfig.vsync)


func _sync_preset_option() -> void:
	_suppress = true
	for i in _preset_option.item_count:
		if _preset_option.get_item_id(i) == GraphicsConfig.preset:
			_preset_option.select(i)
			break
	_suppress = false


func _add_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	_list.add_child(label)


func _add_check(key: String, title: String, value: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := CheckButton.new()
	box.button_pressed = value
	box.toggled.connect(func(on: bool) -> void: _on_check(key, on))
	row.add_child(label)
	row.add_child(box)
	_list.add_child(row)
	_checkboxes[key] = box


func _add_slider(key: String, title: String, min_v: float, max_v: float, step: float, value: float) -> void:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = _fmt(value)
	header.add_child(label)
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(func(v: float) -> void: _on_slider(key, v, value_label))
	wrap.add_child(header)
	wrap.add_child(slider)
	_list.add_child(wrap)
	_sliders[key] = slider


func _add_option(key: String, title: String, items: Array, current_id: int) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(180, 0)
	for item in items:
		opt.add_item(str(item[0]), int(item[1]))
	for i in opt.item_count:
		if opt.get_item_id(i) == current_id:
			opt.select(i)
			break
	opt.item_selected.connect(func(index: int) -> void: _on_option(key, opt.get_item_id(index)))
	row.add_child(label)
	row.add_child(opt)
	_list.add_child(row)
	_options[key] = opt


func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.2f" % v


func _on_preset_selected(index: int) -> void:
	if _suppress:
		return
	var id := _preset_option.get_item_id(index)
	if id == GraphicsConfig.Preset.CUSTOM:
		return
	GraphicsConfig.apply_preset(id)
	GraphicsConfig.apply_all(get_tree())
	_rebuild_ui()
	_status.text = "Пресет применён"


func _on_check(key: String, on: bool) -> void:
	match key:
		"use_taa":
			GraphicsConfig.use_taa = on
		"use_fxaa":
			GraphicsConfig.use_fxaa = on
		"glow_enabled":
			GraphicsConfig.glow_enabled = on
		"ssao_enabled":
			GraphicsConfig.ssao_enabled = on
		"ssil_enabled":
			GraphicsConfig.ssil_enabled = on
		"ssr_enabled":
			GraphicsConfig.ssr_enabled = on
		"sdfgi_enabled":
			GraphicsConfig.sdfgi_enabled = false
		"fog_enabled":
			GraphicsConfig.fog_enabled = on
		"volumetric_fog_enabled":
			GraphicsConfig.volumetric_fog_enabled = on
		"use_aces_tonemap":
			GraphicsConfig.use_aces_tonemap = on
		"fullscreen":
			GraphicsConfig.fullscreen = on
		"vsync":
			GraphicsConfig.vsync = on
		"night":
			GraphicsConfig.night = on
			GraphicsConfig.apply_all(get_tree())
			return
		"tire_smoke_enabled":
			GraphicsConfig.tire_smoke_enabled = on
	GraphicsConfig.mark_custom()
	_sync_preset_option()
	GraphicsConfig.apply_all(get_tree())


func _on_slider(key: String, value: float, value_label: Label) -> void:
	value_label.text = _fmt(value)
	match key:
		"render_scale":
			GraphicsConfig.render_scale = value
		"fsr_sharpness":
			GraphicsConfig.fsr_sharpness = value
		"glow_intensity":
			GraphicsConfig.glow_intensity = value
	GraphicsConfig.mark_custom()
	_sync_preset_option()
	GraphicsConfig.apply_all(get_tree())


func _on_option(key: String, id: int) -> void:
	match key:
		"upscale_mode":
			GraphicsConfig.upscale_mode = id
		"msaa":
			GraphicsConfig.msaa = id
		"shadow_quality":
			GraphicsConfig.shadow_quality = id
	GraphicsConfig.mark_custom()
	_sync_preset_option()
	GraphicsConfig.apply_all(get_tree())

func _on_save() -> void:
	GraphicsConfig.save_to_disk()
	GraphicsConfig.apply_all(get_tree())
	_status.text = "Сохранено"


func _on_reset() -> void:
	GraphicsConfig.reset_to_defaults()
	GraphicsConfig.save_to_disk()
	GraphicsConfig.apply_all(get_tree())
	_rebuild_ui()
	_sync_preset_option()
	_status.text = "Сброшено к стандартным"


func _on_back() -> void:
	GraphicsConfig.save_to_disk()
	GraphicsConfig.apply_all(get_tree())
	SettingsNav.back(self, "res://assets/scenes/ui/settings_hub.tscn")
