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
@onready var _title: Label = %Title

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _drive_option: OptionButton
var _rear_diff_option: OptionButton
var _layout_option: OptionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	add_child(bg)
	UiStyle.night_sky(bg)
	move_child(bg, 0)
	UiStyle.button(_back_button, UiStyle.RED, 18)
	UiStyle.button(_save_button, UiStyle.AMBER, 18)
	UiStyle.button(_reset_button, UiStyle.RED, 18)
	Lang.language_changed.connect(_refresh_language)
	_refresh_language()
	_back_button.pressed.connect(_on_back)
	_save_button.pressed.connect(_on_save)
	_reset_button.pressed.connect(_on_reset)
	_rebuild_ui()


func _refresh_language() -> void:
	_title.text = Lang.t("car.title")
	UiStyle.section_label_style(_title, 28)
	UiStyle.lcd_label_style(_path_label, 13)
	_back_button.text = Lang.t("common.back")
	_save_button.text = Lang.t("common.save")
	_reset_button.text = Lang.t("common.reset_defaults")
	_path_label.text = Lang.t("car.path_label") % [
		String(TuningStore.active_car_id),
		ProjectSettings.globalize_path(TuningStore.SAVE_PATH),
	]
	_rebuild_ui()


## Declarative UI table. Entry kinds:
## {"section": title} / {"key", "label", "min", "max", "step"} / {"options": id} / {"gears": true}
const PARAMS: Array[Dictionary] = [
	{"section": "car.sec.visual"},
	{"key": "clearance", "tkey": "car.clearance", "min": -0.3, "max": 0.5, "step": 0.01},
	{"section": "car.sec.body"},
	{"key": "mass", "tkey": "car.mass", "min": 600.0, "max": 2500.0, "step": 10.0},
	{"key": "com_x", "tkey": "car.com_x", "min": -0.5, "max": 0.5, "step": 0.01},
	{"key": "com_y", "tkey": "car.com_y", "min": -0.8, "max": 0.3, "step": 0.01},
	{"key": "com_z", "tkey": "car.com_z", "min": -0.5, "max": 0.5, "step": 0.01},
	{"section": "car.sec.engine"},
	{"key": "max_power_hp", "tkey": "car.max_power_hp", "min": 50.0, "max": 550.0, "step": 1.0},
	{"key": "idle_rpm", "tkey": "car.idle_rpm", "min": 600.0, "max": 1500.0, "step": 10.0},
	{"key": "max_rpm", "tkey": "car.max_rpm", "min": 4000.0, "max": 10000.0, "step": 50.0},
	{"section": "car.sec.engine_sound"},
	{"key": "cylinders", "tkey": "car.cylinders", "min": 2.0, "max": 12.0, "step": 1.0},
	{"key": "displacement_cc", "tkey": "car.displacement_cc", "min": 500.0, "max": 10000.0, "step": 50.0},
	{"key": "bore_mm", "tkey": "car.bore_mm", "min": 0.0, "max": 120.0, "step": 1.0},
	{"key": "stroke_mm", "tkey": "car.stroke_mm", "min": 50.0, "max": 120.0, "step": 1.0},
	{"options": "engine_layout"},
	{"key": "bank_angle_deg", "tkey": "car.bank_angle_deg", "min": 0.0, "max": 180.0, "step": 1.0},
	{"key": "valves_per_cylinder", "tkey": "car.valves_per_cylinder", "min": 2.0, "max": 4.0, "step": 2.0},
	{"key": "exhaust_length_mm", "tkey": "car.exhaust_length_mm", "min": 300.0, "max": 900.0, "step": 10.0},
	{"key": "cam_duration_deg", "tkey": "car.cam_duration_deg", "min": 180.0, "max": 280.0, "step": 1.0},
	{"key": "cam_lift_mm", "tkey": "car.cam_lift_mm", "min": 6.0, "max": 14.0, "step": 0.1},
	{"key": "hf_gain", "tkey": "car.hf_gain", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "noise", "tkey": "car.noise", "min": 0.0, "max": 2.0, "step": 0.01},
	{"key": "jitter", "tkey": "car.jitter", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "engine_sound_volume_db", "tkey": "car.engine_sound_volume_db", "min": -24.0, "max": 12.0, "step": 0.5},
	{"section": "car.sec.drivetrain"},
	{"options": "drive_type"},
	{"key": "final_drive", "tkey": "car.final_drive", "min": 2.0, "max": 6.0, "step": 0.05},
	{"key": "reverse_ratio", "tkey": "car.reverse_ratio", "min": 1.5, "max": 5.0, "step": 0.05},
	{"key": "shift_time", "tkey": "car.shift_time", "min": 0.05, "max": 0.5, "step": 0.01},
	{"gears": true},
	{"section": "car.sec.differential"},
	{"options": "rear_diff_type"},
	{"key": "diff_preload", "tkey": "car.diff_preload", "min": 0.0, "max": 400.0, "step": 5.0},
	{"key": "diff_power_lock", "tkey": "car.diff_power_lock", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "diff_coast_lock", "tkey": "car.diff_coast_lock", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "locked_diff_stiffness", "tkey": "car.locked_diff_stiffness", "min": 100.0, "max": 2000.0, "step": 25.0},
	{"key": "awd_front_bias", "tkey": "car.awd_front_bias", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "brake_elsd", "tkey": "car.brake_elsd", "min": 0.0, "max": 2.0, "step": 0.05},
	{"section": "car.sec.wheels"},
	{"key": "wheel_inertia", "tkey": "car.wheel_inertia", "min": 0.3, "max": 3.0, "step": 0.05},
	{"section": "car.sec.susp_front"},
	{"key": "front_rest_length", "tkey": "car.front_rest_length", "min": 0.3, "max": 1.0, "step": 0.01},
	{"key": "front_travel", "tkey": "car.front_travel", "min": 0.05, "max": 0.4, "step": 0.01},
	{"key": "front_stiffness", "tkey": "car.front_stiffness", "min": 10000.0, "max": 100000.0, "step": 500.0},
	{"key": "front_damping_compression", "tkey": "car.front_damping_compression", "min": 1000.0, "max": 15000.0, "step": 100.0},
	{"key": "front_damping_rebound", "tkey": "car.front_damping_rebound", "min": 1000.0, "max": 15000.0, "step": 100.0},
	{"key": "front_anti_roll", "tkey": "car.front_anti_roll", "min": 0.0, "max": 15000.0, "step": 100.0},
	{"section": "car.sec.susp_rear"},
	{"key": "rear_rest_length", "tkey": "car.rear_rest_length", "min": 0.3, "max": 1.0, "step": 0.01},
	{"key": "rear_travel", "tkey": "car.rear_travel", "min": 0.05, "max": 0.4, "step": 0.01},
	{"key": "rear_stiffness", "tkey": "car.rear_stiffness", "min": 10000.0, "max": 100000.0, "step": 500.0},
	{"key": "rear_damping_compression", "tkey": "car.rear_damping_compression", "min": 1000.0, "max": 15000.0, "step": 100.0},
	{"key": "rear_damping_rebound", "tkey": "car.rear_damping_rebound", "min": 1000.0, "max": 15000.0, "step": 100.0},
	{"key": "rear_anti_roll", "tkey": "car.rear_anti_roll", "min": 0.0, "max": 15000.0, "step": 100.0},
	{"section": "car.sec.tires"},
	{"key": "tire_mu_front", "tkey": "car.tire_mu_front", "min": 0.6, "max": 2.5, "step": 0.05},
	{"key": "tire_mu_rear", "tkey": "car.tire_mu_rear", "min": 0.6, "max": 2.5, "step": 0.05},
	{"key": "rolling_resistance", "tkey": "car.rolling_resistance", "min": 0.0, "max": 0.05, "step": 0.001},
	{"key": "brake_force", "tkey": "car.brake_force", "min": 2000.0, "max": 30000.0, "step": 100.0},
	{"key": "handbrake_force", "tkey": "car.handbrake_force", "min": 5000.0, "max": 40000.0, "step": 100.0},
	{"key": "handbrake_lat_grip", "tkey": "car.handbrake_lat_grip", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "brake_bias_front", "tkey": "car.brake_bias_front", "min": 0.3, "max": 0.85, "step": 0.01},
	{"section": "car.sec.clutch"},
	{"key": "clutch_max_torque", "tkey": "car.clutch_max_torque", "min": 200.0, "max": 1500.0, "step": 10.0},
	{"key": "clutch_engage_time", "tkey": "car.clutch_engage_time", "min": 0.05, "max": 0.8, "step": 0.01},
	{"key": "engine_inertia", "tkey": "car.engine_inertia", "min": 0.08, "max": 0.8, "step": 0.01},
	{"section": "car.sec.aero"},
	{"key": "drag_coefficient", "tkey": "car.drag_coefficient", "min": 0.15, "max": 0.8, "step": 0.01},
	{"key": "downforce_coefficient", "tkey": "car.downforce_coefficient", "min": 0.0, "max": 2.0, "step": 0.05},
	{"key": "frontal_area", "tkey": "car.frontal_area", "min": 1.2, "max": 3.0, "step": 0.05},
	{"key": "physics_substeps", "tkey": "car.physics_substeps", "min": 1.0, "max": 8.0, "step": 1.0},
	{"key": "tc_slip_ratio", "tkey": "car.tc_slip_ratio", "min": 0.05, "max": 0.45, "step": 0.01},
	{"key": "tc_gain", "tkey": "car.tc_gain", "min": 0.5, "max": 12.0, "step": 0.1},
	{"key": "tc_min_scale", "tkey": "car.tc_min_scale", "min": 0.0, "max": 1.0, "step": 0.05},
	{"section": "car.sec.steering"},
	{"key": "max_steer_angle", "tkey": "car.max_steer_angle", "min": 10.0, "max": 45.0, "step": 0.5},
	{"key": "steer_speed", "tkey": "car.steer_speed", "min": 0.3, "max": 6.0, "step": 0.05},
	{"key": "steer_curve_max_kmh", "tkey": "car.steer_curve_max_kmh", "min": 60.0, "max": 260.0, "step": 5.0},
	{"key": "steer_high_speed_factor", "tkey": "car.steer_high_speed_factor", "min": 0.15, "max": 1.0, "step": 0.05},
	{"key": "steer_input_gamma", "tkey": "car.steer_input_gamma", "min": 1.0, "max": 2.5, "step": 0.05},
	{"key": "drift_assist", "tkey": "car.drift_assist", "min": 0.0, "max": 2.0, "step": 0.05},
	{"key": "arcade_assist", "tkey": "car.arcade_assist", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "fwd_lat_priority", "tkey": "car.fwd_lat_priority", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "fwd_slip_angle_start_deg", "tkey": "car.fwd_slip_angle_start_deg", "min": 2.0, "max": 18.0, "step": 0.5},
	{"key": "fwd_counter_steer_scale", "tkey": "car.fwd_counter_steer_scale", "min": 0.15, "max": 1.0, "step": 0.05},
	{"key": "fwd_recover_bleed", "tkey": "car.fwd_recover_bleed", "min": 0.8, "max": 2.0, "step": 0.05},
	{"section": "car.sec.alignment"},
	{"key": "front_caster_deg", "tkey": "car.front_caster_deg", "min": 0.0, "max": 10.0, "step": 0.25},
	{"key": "rear_camber_deg", "tkey": "car.rear_camber_deg", "min": -6.0, "max": 2.0, "step": 0.25},
]


func _rebuild_ui() -> void:
	for child in _list.get_children():
		child.queue_free()
	_sliders.clear()
	_value_labels.clear()
	_drive_option = null
	_rear_diff_option = null
	_layout_option = null

	for entry: Dictionary in PARAMS:
		if entry.has("section"):
			_add_section(Lang.t(entry.section))
		elif entry.has("options"):
			match String(entry.options):
				"engine_layout":
					_add_engine_layout()
				"drive_type":
					_add_drive_type()
				"rear_diff_type":
					_add_rear_diff_type()
		elif entry.has("gears"):
			for i in TuningStore.setup.gear_ratios.size():
				_add_slider(
					"gear_%d" % (i + 1),
					Lang.t("car.gear_n") % (i + 1),
					0.5,
					5.0,
					0.05,
					TuningStore.setup.gear_ratios[i]
				)
		else:
			_add_slider(entry.key, Lang.t(entry.tkey), entry.min, entry.max, entry.step, _param_value(entry.key))


func _param_value(key: String) -> float:
	var s := TuningStore.setup
	match key:
		"clearance":
			return TuningStore.clearance
		"com_x":
			return s.center_of_mass_offset.x
		"com_y":
			return s.center_of_mass_offset.y
		"com_z":
			return s.center_of_mass_offset.z
		"cylinders":
			return float(s.cylinders)
		"valves_per_cylinder":
			return float(s.valves_per_cylinder)
		"physics_substeps":
			return float(s.physics_substeps)
		_:
			return float(s.get(key))


func _add_section(title: String) -> void:
	var label := UiStyle.section_label(title, 20)
	_list.add_child(label)
	var sep := HSeparator.new()
	_list.add_child(sep)


func _add_engine_layout() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := Label.new()
	name_l.text = Lang.t("car.layout")
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
	name_l.text = Lang.t("car.drive_type")
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
	name_l.text = Lang.t("car.rear_diff_type")
	name_l.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_l)
	_rear_diff_option = OptionButton.new()
	_rear_diff_option.add_item("Open", CarSetup.RearDiffType.OPEN)
	_rear_diff_option.add_item("Limited slip (LSD)", CarSetup.RearDiffType.LSD)
	_rear_diff_option.add_item("Welded", CarSetup.RearDiffType.WELDED)
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
	name_l.add_theme_color_override("font_color", UiStyle.CHROME)
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


func _on_layout_selected(index: int) -> void:
	TuningStore.setup.engine_layout = _layout_option.get_item_id(index) as CarSetup.EngineLayout


func _on_drive_selected(index: int) -> void:
	TuningStore.setup.drive_type = _drive_option.get_item_id(index) as CarSetup.DriveType


func _on_rear_diff_selected(index: int) -> void:
	TuningStore.setup.rear_diff_type = _rear_diff_option.get_item_id(index) as CarSetup.RearDiffType


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
		"brake_elsd":
			s.brake_elsd = value
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
		"arcade_assist":
			s.arcade_assist = value
		"front_caster_deg":
			s.front_caster_deg = value
		"rear_camber_deg":
			s.rear_camber_deg = value
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
		_path_label.text = Lang.t("car.bake.error")
		return
	if bool(banks.get("live", false)):
		_path_label.text = "Saved (live synth, no bake): %s" % String(TuningStore.active_car_id)
	elif bool(banks.get("skipped", false)):
		_path_label.text = Lang.t("car.saved_unchanged") % String(TuningStore.active_car_id)
	else:
		_path_label.text = "Saved + new sound: %s → %s" % [
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
		_path_label.text = Lang.t("car.saved_unchanged") % String(TuningStore.active_car_id)


func _begin_bake_ui() -> void:
	_save_button.disabled = true
	_reset_button.disabled = true
	_back_button.disabled = true
	_bake_row.visible = true
	_bake_progress.value = 0
	_bake_status.text = Lang.t("car.bake.prepare")
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
			_bake_status.text = Lang.t("car.bake.check")
			_bake_progress.value = 0.0
		"cached":
			_bake_status.text = Lang.t("car.bake.cached")
			_bake_progress.value = _bake_progress.max_value
		"start":
			_bake_status.text = Lang.t("car.bake.start") % EngineBankBaker.RPM_STEP
			_bake_progress.value = float(current)
		"sweep":
			_bake_status.text = Lang.t("car.bake.sweep") % rpm
			_bake_progress.value = float(current)
		"rpm":
			_bake_status.text = Lang.t("car.bake.rpm") % [current, total, rpm]
			_bake_progress.value = float(current)
		"promote":
			_bake_status.text = Lang.t("car.bake.promote")
			_bake_progress.value = float(current)
		"apply":
			_bake_status.text = Lang.t("car.bake.apply")
			_bake_progress.value = _bake_progress.max_value
		"error":
			_bake_status.text = Lang.t("car.bake.error")
		_:
			_bake_status.text = phase


func _on_reset() -> void:
	TuningStore.reset_to_defaults()
	_rebuild_ui()
	_path_label.text = Lang.t("car.reset_done") % String(TuningStore.active_car_id)


func _on_back() -> void:
	## Back must not flash bake UI / re-synth when sound params are unchanged.
	await _save_with_optional_bake(false)
	SettingsNav.back(self, "res://assets/scenes/ui/settings_hub.tscn")
