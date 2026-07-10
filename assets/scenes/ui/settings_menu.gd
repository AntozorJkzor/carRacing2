extends Control

## Builds slider UI for every tunable car parameter and persists via TuningStore.

@onready var _list: VBoxContainer = %ParamList
@onready var _path_label: Label = %PathLabel
@onready var _back_button: Button = %BackButton
@onready var _save_button: Button = %SaveButton
@onready var _reset_button: Button = %ResetButton

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _drive_option: OptionButton


func _ready() -> void:
	_path_label.text = "Файл: %s" % ProjectSettings.globalize_path(TuningStore.SAVE_PATH)
	_back_button.pressed.connect(_on_back)
	_save_button.pressed.connect(_on_save)
	_reset_button.pressed.connect(_on_reset)
	_rebuild_ui()


func _rebuild_ui() -> void:
	for child in _list.get_children():
		child.queue_free()
	_sliders.clear()
	_value_labels.clear()
	_drive_option = null

	_add_section("Визуал / высота")
	_add_slider("model_y_offset", "Высота модели", 0.0, 0.8, 0.01, TuningStore.model_y_offset)
	_add_slider("collision_y", "Высота коллизии", 0.1, 1.0, 0.01, TuningStore.collision_y)
	_add_slider("suspension_mount_y", "Высота крепления подвески", 0.1, 0.9, 0.01, TuningStore.suspension_mount_y)

	_add_section("Кузов")
	_add_slider("mass", "Масса, кг", 600.0, 2500.0, 10.0, TuningStore.setup.mass)
	_add_slider("com_x", "Центр масс X", -0.5, 0.5, 0.01, TuningStore.setup.center_of_mass_offset.x)
	_add_slider("com_y", "Центр масс Y", -0.8, 0.3, 0.01, TuningStore.setup.center_of_mass_offset.y)
	_add_slider("com_z", "Центр масс Z", -0.5, 0.5, 0.01, TuningStore.setup.center_of_mass_offset.z)

	_add_section("Двигатель")
	_add_slider("max_power_kw", "Мощность, кВт", 40.0, 400.0, 1.0, TuningStore.setup.max_power_kw)
	_add_slider("torque_boost", "Множитель момента", 0.8, 3.0, 0.05, TuningStore.setup.torque_boost)
	_add_slider("idle_rpm", "Холостые, об/мин", 600.0, 1500.0, 10.0, TuningStore.setup.idle_rpm)
	_add_slider("max_rpm", "Макс. обороты", 4000.0, 10000.0, 50.0, TuningStore.setup.max_rpm)

	_add_section("КПП / привод")
	_add_drive_type()
	_add_slider("final_drive", "Главная пара", 2.0, 6.0, 0.05, TuningStore.setup.final_drive)
	_add_slider("reverse_ratio", "Задняя передача", 1.5, 5.0, 0.05, TuningStore.setup.reverse_ratio)
	_add_slider("shift_time", "Время переключения, с", 0.05, 0.5, 0.01, TuningStore.setup.shift_time)
	for i in TuningStore.setup.gear_ratios.size():
		_add_slider(
			"gear_%d" % (i + 1),
			"Передача %d" % (i + 1),
			0.5,
			5.0,
			0.05,
			TuningStore.setup.gear_ratios[i]
		)

	_add_section("Колёса")
	_add_slider("wheel_radius", "Радиус колеса", 0.2, 0.5, 0.01, TuningStore.setup.wheel_radius)
	_add_slider("wheel_width", "Ширина колеса", 0.1, 0.4, 0.01, TuningStore.setup.wheel_width)
	var track := 0.52
	var front_z := -0.81
	var rear_z := 0.7
	if TuningStore.setup.wheel_positions.size() >= 4:
		track = absf(TuningStore.setup.wheel_positions[0].x)
		front_z = TuningStore.setup.wheel_positions[0].z
		rear_z = TuningStore.setup.wheel_positions[2].z
	_add_slider("track", "Колея (половина)", 0.3, 1.0, 0.01, track)
	_add_slider("front_z", "Передняя ось Z", -1.5, -0.3, 0.01, front_z)
	_add_slider("rear_z", "Задняя ось Z", 0.3, 1.5, 0.01, rear_z)

	_add_section("Подвеска")
	_add_slider("rest_length", "Длина пружины (rest)", 0.3, 1.0, 0.01, TuningStore.setup.rest_length)
	_add_slider("travel", "Ход подвески", 0.05, 0.4, 0.01, TuningStore.setup.travel)
	_add_slider("stiffness", "Жёсткость пружин", 10000.0, 100000.0, 500.0, TuningStore.setup.stiffness)
	_add_slider("damping", "Демпфер", 1000.0, 15000.0, 100.0, TuningStore.setup.damping)
	_add_slider("anti_roll", "Стабилизатор", 0.0, 15000.0, 100.0, TuningStore.setup.anti_roll)

	_add_section("Сцепление / тормоза")
	_add_slider("grip_longitudinal", "Сцепление продольное", 0.5, 4.0, 0.05, TuningStore.setup.grip_longitudinal)
	_add_slider("grip_lateral", "Сцепление перед (бок)", 0.5, 4.0, 0.05, TuningStore.setup.grip_lateral)
	_add_slider("grip_lateral_rear", "Сцепление зад (бок)", 0.5, 5.0, 0.05, TuningStore.setup.grip_lateral_rear)
	_add_slider("rolling_resistance", "Сопр. качению", 0.0, 0.05, 0.001, TuningStore.setup.rolling_resistance)
	_add_slider("brake_force", "Сила тормоза", 2000.0, 30000.0, 100.0, TuningStore.setup.brake_force)
	_add_slider("handbrake_force", "Сила ручника", 5000.0, 40000.0, 100.0, TuningStore.setup.handbrake_force)
	_add_slider("handbrake_lat_grip", "Зацеп зада на ручнике", 0.0, 1.0, 0.01, TuningStore.setup.handbrake_lat_grip)

	_add_section("Руль")
	_add_slider("max_steer_angle", "Макс. угол руля", 10.0, 45.0, 0.5, TuningStore.setup.max_steer_angle)
	_add_slider("steer_speed", "Скорость отклика руля", 0.3, 6.0, 0.05, TuningStore.setup.steer_speed)


func _add_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_list.add_child(label)
	var sep := HSeparator.new()
	_list.add_child(sep)


func _add_drive_type() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := Label.new()
	name_l.text = "Тип привода"
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)
	_drive_option = OptionButton.new()
	_drive_option.add_item("FWD", CarSetup.DriveType.FWD)
	_drive_option.add_item("RWD", CarSetup.DriveType.RWD)
	_drive_option.add_item("AWD", CarSetup.DriveType.AWD)
	_drive_option.select(int(TuningStore.setup.drive_type))
	_drive_option.item_selected.connect(_on_drive_selected)
	row.add_child(_drive_option)
	_list.add_child(row)


func _add_slider(
	key: String,
	title: String,
	min_v: float,
	max_v: float,
	step: float,
	value: float
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_l := Label.new()
	name_l.text = title
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 0)
	row.add_child(slider)

	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(80, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.text = _format_value(value, step)
	row.add_child(val_l)

	slider.value_changed.connect(func(v: float) -> void:
		val_l.text = _format_value(v, step)
		_apply_key(key, v)
	)

	_list.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = val_l


func _format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	if step >= 0.1:
		return "%.1f" % value
	if step >= 0.01:
		return "%.2f" % value
	return "%.3f" % value


func _on_drive_selected(index: int) -> void:
	TuningStore.setup.drive_type = _drive_option.get_item_id(index) as CarSetup.DriveType


func _apply_key(key: String, value: float) -> void:
	var s := TuningStore.setup
	match key:
		"model_y_offset":
			TuningStore.model_y_offset = value
		"collision_y":
			TuningStore.collision_y = value
		"suspension_mount_y":
			TuningStore.suspension_mount_y = value
			TuningStore.apply_mount_height()
		"mass":
			s.mass = value
		"com_x":
			s.center_of_mass_offset.x = value
		"com_y":
			s.center_of_mass_offset.y = value
		"com_z":
			s.center_of_mass_offset.z = value
		"max_power_kw":
			s.max_power_kw = value
		"torque_boost":
			s.torque_boost = value
		"idle_rpm":
			s.idle_rpm = value
		"max_rpm":
			s.max_rpm = value
		"final_drive":
			s.final_drive = value
		"reverse_ratio":
			s.reverse_ratio = value
		"shift_time":
			s.shift_time = value
		"wheel_radius":
			s.wheel_radius = value
		"wheel_width":
			s.wheel_width = value
		"track", "front_z", "rear_z":
			_apply_wheel_layout()
		"rest_length":
			s.rest_length = value
		"travel":
			s.travel = value
		"stiffness":
			s.stiffness = value
		"damping":
			s.damping = value
		"anti_roll":
			s.anti_roll = value
		"grip_longitudinal":
			s.grip_longitudinal = value
		"grip_lateral":
			s.grip_lateral = value
		"grip_lateral_rear":
			s.grip_lateral_rear = value
		"rolling_resistance":
			s.rolling_resistance = value
		"brake_force":
			s.brake_force = value
		"handbrake_force":
			s.handbrake_force = value
		"handbrake_lat_grip":
			s.handbrake_lat_grip = value
		"max_steer_angle":
			s.max_steer_angle = value
		"steer_speed":
			s.steer_speed = value
		_:
			if key.begins_with("gear_"):
				var idx := int(key.get_slice("_", 1)) - 1
				if idx >= 0 and idx < s.gear_ratios.size():
					s.gear_ratios[idx] = value


func _apply_wheel_layout() -> void:
	var track: float = _sliders["track"].value if _sliders.has("track") else 0.52
	var front_z: float = _sliders["front_z"].value if _sliders.has("front_z") else -0.81
	var rear_z: float = _sliders["rear_z"].value if _sliders.has("rear_z") else 0.7
	var y := TuningStore.suspension_mount_y
	TuningStore.setup.wheel_positions = [
		Vector3(-track, y, front_z),
		Vector3(track, y, front_z),
		Vector3(-track, y, rear_z),
		Vector3(track, y, rear_z),
	]


func _on_save() -> void:
	_apply_wheel_layout()
	TuningStore.save_to_disk()
	_path_label.text = "Сохранено: %s" % ProjectSettings.globalize_path(TuningStore.SAVE_PATH)


func _on_reset() -> void:
	TuningStore.reset_to_defaults()
	_rebuild_ui()
	_path_label.text = "Сброшено к дефолту и сохранено"


func _on_back() -> void:
	_apply_wheel_layout()
	TuningStore.save_to_disk()
	get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")
