extends Control

## Builds slider UI for every tunable car parameter and persists via TuningStore.

@onready var _list: VBoxContainer = %ParamList
@onready var _path_label: Label = %PathLabel
@onready var _bake_row: VBoxContainer = %BakeRow
@onready var _bake_status: Label = %BakeStatusLabel
@onready var _bake_progress: ProgressBar = %BakeProgressBar
@onready var _back_button: Button = %BackButton
@onready var _save_button: Button = %SaveButton
@onready var _reset_button: Button = %ResetButton

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _drive_option: OptionButton
var _rear_diff_option: OptionButton
var _layout_option: OptionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_path_label.text = "Машина: %s  ·  %s" % [
		String(TuningStore.active_car_id),
		ProjectSettings.globalize_path(TuningStore.SAVE_PATH),
	]
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
	_layout_option = null

	_add_section("Визуал / высота")
	_add_slider("clearance", "Клиренс (модель + коллизия)", -0.3, 0.5, 0.01, TuningStore.clearance)

	_add_section("Кузов")
	_add_slider("mass", "Масса, кг", 600.0, 2500.0, 10.0, TuningStore.setup.mass)
	_add_slider("com_x", "Центр масс X", -0.5, 0.5, 0.01, TuningStore.setup.center_of_mass_offset.x)
	_add_slider("com_y", "Центр масс Y", -0.8, 0.3, 0.01, TuningStore.setup.center_of_mass_offset.y)
	_add_slider("com_z", "Центр масс Z", -0.5, 0.5, 0.01, TuningStore.setup.center_of_mass_offset.z)

	_add_section("Двигатель")
	_add_slider("max_power_hp", "Мощность, л.с.", 50.0, 550.0, 1.0, TuningStore.setup.max_power_hp)
	_add_slider("idle_rpm", "Холостые, об/мин", 600.0, 1500.0, 10.0, TuningStore.setup.idle_rpm)
	_add_slider("max_rpm", "Макс. обороты", 4000.0, 10000.0, 50.0, TuningStore.setup.max_rpm)

	_add_section("Звук двигателя (EngineSim)")
	_add_slider("cylinders", "Цилиндры", 2.0, 12.0, 1.0, float(TuningStore.setup.cylinders))
	_add_slider("displacement_cc", "Объём, cc", 500.0, 10000.0, 50.0, TuningStore.setup.displacement_cc)
	_add_slider("bore_mm", "Диаметр цилиндра, мм (0=авто)", 0.0, 120.0, 1.0, TuningStore.setup.bore_mm)
	_add_slider("stroke_mm", "Ход поршня, мм", 50.0, 120.0, 1.0, TuningStore.setup.stroke_mm)
	_add_engine_layout()
	_add_slider("bank_angle_deg", "Угол развала, °", 0.0, 180.0, 1.0, TuningStore.setup.bank_angle_deg)
	_add_slider("valves_per_cylinder", "Клапанов на цилиндр", 2.0, 4.0, 2.0, float(TuningStore.setup.valves_per_cylinder))
	_add_slider("exhaust_length_mm", "Длина выхлопа, мм", 300.0, 900.0, 10.0, TuningStore.setup.exhaust_length_mm)
	_add_slider("cam_duration_deg", "Длительность кулачка, °", 180.0, 280.0, 1.0, TuningStore.setup.cam_duration_deg)
	_add_slider("cam_lift_mm", "Подъём кулачка, мм", 6.0, 14.0, 0.1, TuningStore.setup.cam_lift_mm)
	_add_slider("hf_gain", "HF gain", 0.0, 1.0, 0.01, TuningStore.setup.hf_gain)
	_add_slider("noise", "Noise", 0.0, 2.0, 0.01, TuningStore.setup.noise)
	_add_slider("jitter", "Jitter", 0.0, 1.0, 0.01, TuningStore.setup.jitter)
	_add_slider(
		"engine_sound_volume_db",
		"Громкость в игре, дБ",
		-24.0,
		12.0,
		0.5,
		TuningStore.setup.engine_sound_volume_db
	)

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

	_add_section("Колёса (физика)")
	_add_slider("wheel_inertia", "Инерция колеса", 0.3, 3.0, 0.05, TuningStore.setup.wheel_inertia)

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
	_add_slider("steer_curve_max_kmh", "Мягкий лок: скорость полной урезки (км/ч)", 60.0, 260.0, 5.0, TuningStore.setup.steer_curve_max_kmh)
	_add_slider("steer_high_speed_factor", "Отклик на скорости (меньше=спокойнее)", 0.15, 1.0, 0.05, TuningStore.setup.steer_high_speed_factor)
	_add_slider("steer_input_gamma", "Точность у центра (gamma)", 1.0, 2.5, 0.05, TuningStore.setup.steer_input_gamma)
	_add_slider("drift_assist", "Помощь дрифта (RWD; 0=выкл)", 0.0, 2.0, 0.05, TuningStore.setup.drift_assist)
	_add_slider("fwd_lat_priority", "FWD: приоритет бокового зацепа", 0.0, 1.0, 0.05, TuningStore.setup.fwd_lat_priority)
	_add_slider(
		"fwd_slip_angle_start_deg",
		"FWD: старт реза тяги (угол увода °)",
		2.0,
		18.0,
		0.5,
		TuningStore.setup.fwd_slip_angle_start_deg
	)
	_add_slider(
		"fwd_counter_steer_scale",
		"FWD: сила контрруля (меньше=стабильнее)",
		0.15,
		1.0,
		0.05,
		TuningStore.setup.fwd_counter_steer_scale
	)
	_add_slider(
		"fwd_recover_bleed",
		"FWD: скорость отпускания руля из слайда",
		0.8,
		2.0,
		0.05,
		TuningStore.setup.fwd_recover_bleed
	)


func _add_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_list.add_child(label)
	var sep := HSeparator.new()
	_list.add_child(sep)


func _add_engine_layout() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := Label.new()
	name_l.text = "Компоновка"
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)
	_layout_option = OptionButton.new()
	_layout_option.add_item("Inline", CarSetup.EngineLayout.INLINE)
	_layout_option.add_item("V", CarSetup.EngineLayout.V)
	_layout_option.add_item("Boxer", CarSetup.EngineLayout.BOXER)
	_layout_option.select(int(TuningStore.setup.engine_layout))
	_layout_option.item_selected.connect(_on_layout_selected)
	row.add_child(_layout_option)
	_list.add_child(row)


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


func _add_checkbox(key: String, title: String, value: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := Label.new()
	name_l.text = title
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)
	var box := CheckBox.new()
	box.button_pressed = value
	box.toggled.connect(func(on: bool) -> void:
		_apply_bool_key(key, on)
	)
	row.add_child(box)
	_list.add_child(row)


func _format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	if step >= 0.1:
		return "%.1f" % value
	if step >= 0.01:
		return "%.2f" % value
	return "%.3f" % value


func _on_layout_selected(index: int) -> void:
	TuningStore.setup.engine_layout = _layout_option.get_item_id(index) as CarSetup.EngineLayout


func _on_drive_selected(index: int) -> void:
	TuningStore.setup.drive_type = _drive_option.get_item_id(index) as CarSetup.DriveType


func _on_rear_diff_selected(index: int) -> void:
	TuningStore.setup.rear_diff_type = _rear_diff_option.get_item_id(index) as CarSetup.RearDiffType


func _apply_bool_key(_key: String, _value: bool) -> void:
	pass


func _apply_key(key: String, value: float) -> void:
	var s := TuningStore.setup
	match key:
		"clearance":
			TuningStore.clearance = value
			TuningStore.apply_clearance_to_cars()
		"mass":
			s.mass = value
		"com_x":
			s.center_of_mass_offset.x = value
		"com_y":
			s.center_of_mass_offset.y = value
		"com_z":
			s.center_of_mass_offset.z = value
		"max_power_hp":
			s.max_power_hp = value
			s.max_power_kw = value * CarSetup.KW_PER_HP
		"max_power_kw":
			# Legacy settings key → convert into HP.
			s.max_power_kw = value
			s.max_power_hp = value / CarSetup.KW_PER_HP
		"idle_rpm":
			s.idle_rpm = value
		"max_rpm":
			s.max_rpm = value
		"cylinders":
			s.cylinders = clampi(int(round(value)), 2, 12)
		"displacement_cc":
			s.displacement_cc = value
		"bore_mm":
			s.bore_mm = value
		"stroke_mm":
			s.stroke_mm = value
		"bank_angle_deg":
			s.bank_angle_deg = value
		"valves_per_cylinder":
			s.valves_per_cylinder = 4 if int(round(value)) >= 4 else 2
		"exhaust_length_mm":
			s.exhaust_length_mm = value
		"cam_duration_deg":
			s.cam_duration_deg = value
		"cam_lift_mm":
			s.cam_lift_mm = value
		"hf_gain":
			s.hf_gain = value
		"noise":
			s.noise = value
		"jitter":
			s.jitter = value
		"engine_sound_volume_db":
			s.engine_sound_volume_db = value
		"final_drive":
			s.final_drive = value
		"reverse_ratio":
			s.reverse_ratio = value
		"shift_time":
			s.shift_time = value
		"diff_preload":
			s.diff_preload = value
		"diff_power_lock":
			s.diff_power_lock = value
		"diff_coast_lock":
			s.diff_coast_lock = value
		"locked_diff_stiffness":
			s.locked_diff_stiffness = value
		"awd_front_bias":
			s.awd_front_bias = value
		"wheel_inertia":
			s.wheel_inertia = value
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
		"steer_high_speed_factor":
			s.steer_high_speed_factor = value
		"steer_input_gamma":
			s.steer_input_gamma = value
		"drift_assist":
			s.drift_assist = value
		"fwd_lat_priority":
			s.fwd_lat_priority = value
		"fwd_slip_angle_start_deg":
			s.fwd_slip_angle_start_deg = value
		"fwd_counter_steer_scale":
			s.fwd_counter_steer_scale = value
		"fwd_recover_bleed":
			s.fwd_recover_bleed = value
		_:
			if key.begins_with("gear_"):
				var idx := int(key.get_slice("_", 1)) - 1
				if idx >= 0 and idx < s.gear_ratios.size():
					s.gear_ratios[idx] = value


func _on_save() -> void:
	await _save_with_optional_bake(true)


func _run_save_with_progress() -> void:
	_begin_bake_ui()
	var banks: Dictionary = await TuningStore.save_to_disk_async()
	_end_bake_ui()
	if banks.is_empty():
		_path_label.text = "Ошибка сохранения / генерации звука"
		return
	if bool(banks.get("live", false)):
		_path_label.text = "Сохранено (live-synth, без bake): %s" % String(TuningStore.active_car_id)
	elif bool(banks.get("skipped", false)):
		_path_label.text = "Сохранено (звук уже актуален): %s" % String(TuningStore.active_car_id)
	else:
		_path_label.text = "Сохранено + новый звук: %s → %s" % [
			String(TuningStore.active_car_id),
			ProjectSettings.globalize_path(EngineBankBaker.user_bake_dir(TuningStore.active_car_id)),
		]


## Save tuning always. Bake only when engine-sound params changed (or force_bake_ui on Save).
func _save_with_optional_bake(show_status_when_skipped: bool) -> void:
	var stale := TuningStore.engine_bake_is_stale()
	if stale:
		await _run_save_with_progress()
		return
	TuningStore.save_config_only()
	if show_status_when_skipped:
		_path_label.text = "Сохранено (звук без изменений): %s" % String(TuningStore.active_car_id)


func _begin_bake_ui() -> void:
	_save_button.disabled = true
	_reset_button.disabled = true
	_back_button.disabled = true
	_bake_row.visible = true
	_bake_progress.value = 0
	_bake_status.text = "Подготовка…"
	if not TuningStore.engine_bake_progress.is_connected(_on_engine_bake_progress):
		TuningStore.engine_bake_progress.connect(_on_engine_bake_progress)


func _end_bake_ui() -> void:
	_save_button.disabled = false
	_reset_button.disabled = false
	_back_button.disabled = false
	_bake_row.visible = false
	if TuningStore.engine_bake_progress.is_connected(_on_engine_bake_progress):
		TuningStore.engine_bake_progress.disconnect(_on_engine_bake_progress)


func _on_engine_bake_progress(current: int, total: int, rpm: float, phase: String) -> void:
	_bake_progress.max_value = maxf(float(maxi(total, 1)), 1.0)
	match phase:
		"check":
			_bake_status.text = "Проверка кэша звука…"
			_bake_progress.value = 0.0
		"cached":
			_bake_status.text = "Звук уже актуален — перегенерация не нужна"
			_bake_progress.value = _bake_progress.max_value
		"start":
			_bake_status.text = "Подготовка sweep-бейка (шаг %.0f об/мин)…" % EngineBankBaker.RPM_STEP
			_bake_progress.value = float(current)
		"sweep":
			_bake_status.text = "Синтез sweep idle→%.0f об/мин (один прогон)…" % rpm
			_bake_progress.value = float(current)
		"rpm":
			_bake_status.text = "Синтез %d / %d  ·  %.0f об/мин" % [current, total, rpm]
			_bake_progress.value = float(current)
		"promote":
			_bake_status.text = "Сохранение банков на диск…"
			_bake_progress.value = float(current)
		"apply":
			_bake_status.text = "Подключение звука к машине…"
			_bake_progress.value = _bake_progress.max_value
		"error":
			_bake_status.text = "Ошибка генерации звука"
		_:
			_bake_status.text = phase


func _on_reset() -> void:
	TuningStore.reset_to_defaults()
	_rebuild_ui()
	_path_label.text = "Сброшено к пакету (%s), user-bake удалён" % String(TuningStore.active_car_id)


func _on_back() -> void:
	## Back must not flash bake UI / re-synth when sound params are unchanged.
	await _save_with_optional_bake(false)
	SettingsNav.back(self, "res://assets/scenes/ui/settings_hub.tscn")
