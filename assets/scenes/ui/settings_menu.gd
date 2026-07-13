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
var _rear_diff_option: OptionButton


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
	_rear_diff_option = null

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

	_add_section("Задний дифференциал")
	_add_rear_diff_type()
	_add_slider("diff_preload", "LSD preload", 0.0, 400.0, 5.0, TuningStore.setup.diff_preload)
	_add_slider("diff_power_lock", "LSD power lock", 0.0, 1.0, 0.05, TuningStore.setup.diff_power_lock)
	_add_slider("diff_coast_lock", "LSD coast lock", 0.0, 1.0, 0.05, TuningStore.setup.diff_coast_lock)
	_add_slider("locked_diff_stiffness", "Жёсткость заварки", 100.0, 2000.0, 25.0, TuningStore.setup.locked_diff_stiffness)
	_add_slider("awd_front_bias", "AWD bias перед", 0.0, 1.0, 0.05, TuningStore.setup.awd_front_bias)

	_add_section("Колёса")
	_add_slider("wheel_radius", "Радиус колеса", 0.15, 0.5, 0.01, TuningStore.setup.wheel_radius)
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

	_add_section("Подвеска перед")
	_add_slider("front_rest_length", "Перед rest", 0.3, 1.0, 0.01, TuningStore.setup.front_rest_length)
	_add_slider("front_travel", "Перед ход", 0.05, 0.4, 0.01, TuningStore.setup.front_travel)
	_add_slider("front_stiffness", "Перед жёсткость", 10000.0, 100000.0, 500.0, TuningStore.setup.front_stiffness)
	_add_slider("front_damping_compression", "Перед сжатие", 1000.0, 15000.0, 100.0, TuningStore.setup.front_damping_compression)
	_add_slider("front_damping_rebound", "Перед отбой", 1000.0, 15000.0, 100.0, TuningStore.setup.front_damping_rebound)
	_add_slider("front_anti_roll", "Перед стабилизатор", 0.0, 15000.0, 100.0, TuningStore.setup.front_anti_roll)

	_add_section("Подвеска зад")
	_add_slider("rear_rest_length", "Зад rest", 0.3, 1.0, 0.01, TuningStore.setup.rear_rest_length)
	_add_slider("rear_travel", "Зад ход", 0.05, 0.4, 0.01, TuningStore.setup.rear_travel)
	_add_slider("rear_stiffness", "Зад жёсткость", 10000.0, 100000.0, 500.0, TuningStore.setup.rear_stiffness)
	_add_slider("rear_damping_compression", "Зад сжатие", 1000.0, 15000.0, 100.0, TuningStore.setup.rear_damping_compression)
	_add_slider("rear_damping_rebound", "Зад отбой", 1000.0, 15000.0, 100.0, TuningStore.setup.rear_damping_rebound)
	_add_slider("rear_anti_roll", "Зад стабилизатор", 0.0, 15000.0, 100.0, TuningStore.setup.rear_anti_roll)

	_add_section("Шины / тормоза")
	_add_slider("tire_mu_front", "µ перед", 0.6, 2.5, 0.05, TuningStore.setup.tire_mu_front)
	_add_slider("tire_mu_rear", "µ зад", 0.6, 2.5, 0.05, TuningStore.setup.tire_mu_rear)
	_add_slider("rolling_resistance", "Сопр. качению", 0.0, 0.05, 0.001, TuningStore.setup.rolling_resistance)
	_add_slider("brake_force", "Сила тормоза", 2000.0, 30000.0, 100.0, TuningStore.setup.brake_force)
	_add_slider("handbrake_force", "Сила ручника", 5000.0, 40000.0, 100.0, TuningStore.setup.handbrake_force)
	_add_slider("handbrake_lat_grip", "Ручник: боковой зацеп зада", 0.0, 1.0, 0.01, TuningStore.setup.handbrake_lat_grip)
	_add_slider("brake_bias_front", "Brake bias перед", 0.3, 0.85, 0.01, TuningStore.setup.brake_bias_front)

	_add_section("Сцепление / инерция")
	_add_slider("clutch_max_torque", "Момент сцепления", 200.0, 1500.0, 10.0, TuningStore.setup.clutch_max_torque)
	_add_slider("clutch_engage_time", "Время сцепления, с", 0.05, 0.8, 0.01, TuningStore.setup.clutch_engage_time)
	_add_slider("wheel_inertia", "Инерция колеса", 0.3, 3.0, 0.05, TuningStore.setup.wheel_inertia)
	_add_slider("engine_inertia", "Инерция двигателя", 0.08, 0.8, 0.01, TuningStore.setup.engine_inertia)

	_add_section("Аэро / симуляция")
	_add_slider("drag_coefficient", "Cd", 0.15, 0.8, 0.01, TuningStore.setup.drag_coefficient)
	_add_slider("downforce_coefficient", "Cl downforce", 0.0, 2.0, 0.05, TuningStore.setup.downforce_coefficient)
	_add_slider("frontal_area", "Лобовая площадь", 1.2, 3.0, 0.05, TuningStore.setup.frontal_area)
	_add_slider("physics_substeps", "Physics substeps", 1.0, 8.0, 1.0, float(TuningStore.setup.physics_substeps))
	_add_slider("tc_slip_ratio", "TC целевой κ", 0.05, 0.45, 0.01, TuningStore.setup.tc_slip_ratio)
	_add_slider("tc_gain", "TC жёсткость", 0.5, 12.0, 0.1, TuningStore.setup.tc_gain)
	_add_slider("tc_min_scale", "TC мин. тяга", 0.0, 1.0, 0.05, TuningStore.setup.tc_min_scale)

	_add_section("Руль")
	_add_slider("max_steer_angle", "Макс. угол руля (стойка)", 10.0, 45.0, 0.5, TuningStore.setup.max_steer_angle)
	_add_slider("steer_speed", "Скорость отклика руля", 0.3, 6.0, 0.05, TuningStore.setup.steer_speed)
	_add_slider("steer_curve_max_kmh", "Кривая руля: скорость X=1, км/ч", 60.0, 220.0, 5.0, TuningStore.setup.steer_curve_max_kmh)


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


func _add_rear_diff_type() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := Label.new()
	name_l.text = "Задний дифференциал"
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)
	_rear_diff_option = OptionButton.new()
	_rear_diff_option.add_item("Свободный", CarSetup.RearDiffType.OPEN)
	_rear_diff_option.add_item("Самоблок (LSD)", CarSetup.RearDiffType.LSD)
	_rear_diff_option.add_item("Заварка", CarSetup.RearDiffType.WELDED)
	_rear_diff_option.select(int(TuningStore.setup.rear_diff_type))
	_rear_diff_option.item_selected.connect(_on_rear_diff_selected)
	row.add_child(_rear_diff_option)
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


func _on_rear_diff_selected(index: int) -> void:
	TuningStore.setup.rear_diff_type = _rear_diff_option.get_item_id(index) as CarSetup.RearDiffType


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
		"front_rest_length":
			s.front_rest_length = value
			s.rest_length = value
		"rear_rest_length":
			s.rear_rest_length = value
		"front_travel":
			s.front_travel = value
			s.travel = value
		"rear_travel":
			s.rear_travel = value
		"front_stiffness":
			s.front_stiffness = value
			s.stiffness = value
		"rear_stiffness":
			s.rear_stiffness = value
		"front_damping_compression":
			s.front_damping_compression = value
			s.damping = value
		"front_damping_rebound":
			s.front_damping_rebound = value
		"rear_damping_compression":
			s.rear_damping_compression = value
		"rear_damping_rebound":
			s.rear_damping_rebound = value
		"front_anti_roll":
			s.front_anti_roll = value
			s.anti_roll = value
		"rear_anti_roll":
			s.rear_anti_roll = value
		"tire_mu_front":
			s.tire_mu_front = value
		"tire_mu_rear":
			s.tire_mu_rear = value
		"rolling_resistance":
			s.rolling_resistance = value
		"brake_force":
			s.brake_force = value
		"handbrake_force":
			s.handbrake_force = value
		"handbrake_lat_grip":
			s.handbrake_lat_grip = value
		"brake_bias_front":
			s.brake_bias_front = value
		"clutch_max_torque":
			s.clutch_max_torque = value
		"clutch_engage_time":
			s.clutch_engage_time = value
		"awd_front_bias":
			s.awd_front_bias = value
		"diff_preload":
			s.diff_preload = value
		"diff_power_lock":
			s.diff_power_lock = value
		"diff_coast_lock":
			s.diff_coast_lock = value
		"locked_diff_stiffness":
			s.locked_diff_stiffness = value
		"wheel_inertia":
			s.wheel_inertia = value
		"engine_inertia":
			s.engine_inertia = value
		"drag_coefficient":
			s.drag_coefficient = value
		"downforce_coefficient":
			s.downforce_coefficient = value
		"frontal_area":
			s.frontal_area = value
		"physics_substeps":
			s.physics_substeps = clampi(int(round(value)), 1, 8)
		"tc_slip_ratio":
			s.tc_slip_ratio = value
		"tc_gain":
			s.tc_gain = value
		"tc_min_scale":
			s.tc_min_scale = value
		"max_steer_angle":
			s.max_steer_angle = value
		"steer_speed":
			s.steer_speed = value
		"steer_curve_max_kmh":
			s.steer_curve_max_kmh = value
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
