extends Node

## Bilingual UI strings (RU/EN). Persisted choice in user://game_settings.cfg.

signal language_changed

const SAVE_PATH := "user://game_settings.cfg"

var language: String = "ru"

const STRINGS := {
	# --- Common ---
	"common.back": {"ru": "Назад", "en": "Back"},
	"common.save": {"ru": "Сохранить", "en": "Save"},
	"common.reset": {"ru": "Сбросить", "en": "Reset"},
	"common.reset_defaults": {"ru": "Сбросить по умолчанию", "en": "Reset to default"},
	"common.on": {"ru": "Вкл", "en": "On"},
	"common.off": {"ru": "Выкл", "en": "Off"},

	# --- Main / pause menu ---
	"menu.subtitle": {"ru": "Тест физики", "en": "Physics test"},
	"menu.new_game": {"ru": "Новая игра", "en": "New game"},
	"menu.settings": {"ru": "Настройки", "en": "Settings"},
	"menu.quit": {"ru": "Выход", "en": "Quit"},
	"menu.resume": {"ru": "Продолжить", "en": "Resume"},
	"menu.main_menu": {"ru": "Главное меню", "en": "Main menu"},
	"menu.paused": {"ru": "Пауза", "en": "Paused"},
	"menu.game_paused": {"ru": "Игра на паузе", "en": "Game paused"},

	# --- Settings hub ---
	"hub.title": {"ru": "Настройки", "en": "Settings"},
	"hub.car": {"ru": "Автомобиль", "en": "Car"},
	"hub.sound": {"ru": "Звук", "en": "Sound"},
	"hub.graphics": {"ru": "Графика", "en": "Graphics"},
	"hub.language": {"ru": "Язык", "en": "Language"},

	# --- Garage ---
	"garage.title": {"ru": "Гараж", "en": "Garage"},
	"garage.drive": {"ru": "На трассу", "en": "To track"},
	"garage.hint": {"ru": "ЛКМ — вращать подиум", "en": "LMB — spin the podium"},

	# --- Sound settings ---
	"sound.title": {"ru": "Звук", "en": "Sound"},
	"sound.master": {"ru": "Общая громкость", "en": "Master volume"},
	"sound.car": {"ru": "Автомобиль", "en": "Car"},
	"sound.music": {"ru": "Музыка", "en": "Music"},

	# --- Graphics settings ---
	"gfx.title": {"ru": "Графика", "en": "Graphics"},
	"gfx.preset": {"ru": "Пресет", "en": "Preset"},
	"gfx.custom": {"ru": "Свой", "en": "Custom"},
	"gfx.low": {"ru": "Низко", "en": "Low"},
	"gfx.medium": {"ru": "Средне", "en": "Medium"},
	"gfx.high": {"ru": "Высоко", "en": "High"},
	"gfx.ultra": {"ru": "Ультра", "en": "Ultra"},
	"gfx.sec.scaling": {"ru": "Масштаб и сглаживание", "en": "Scaling & anti-aliasing"},
	"gfx.render_scale": {"ru": "3D-разрешение", "en": "3D scale"},
	"gfx.upscale_mode": {"ru": "Апскейл", "en": "Upscaling"},
	"gfx.bilinear": {"ru": "Билинейный", "en": "Bilinear"},
	"gfx.fsr_sharpness": {"ru": "Резкость FSR", "en": "FSR sharpness"},
	"gfx.msaa": {"ru": "MSAA", "en": "MSAA"},
	"gfx.taa": {"ru": "TAA", "en": "TAA"},
	"gfx.fxaa": {"ru": "FXAA", "en": "FXAA"},
	"gfx.sec.lighting": {"ru": "Свет и эффекты", "en": "Lighting & effects"},
	"gfx.glow_enabled": {"ru": "Свечение / Bloom", "en": "Glow / Bloom"},
	"gfx.glow_intensity": {"ru": "Интенсивность свечения", "en": "Glow intensity"},
	"gfx.ssao": {"ru": "SSAO", "en": "SSAO"},
	"gfx.ssil": {"ru": "SSIL", "en": "SSIL"},
	"gfx.ssr": {"ru": "SSR (отражения)", "en": "SSR (reflections)"},
	"gfx.sdfgi": {"ru": "SDFGI (временно отключено)", "en": "SDFGI (temporarily disabled)"},
	"gfx.fog": {"ru": "Туман", "en": "Fog"},
	"gfx.volumetric_fog": {"ru": "Объёмный туман", "en": "Volumetric fog"},
	"gfx.aces": {"ru": "Тонмаппинг ACES", "en": "Tonemap ACES"},
	"gfx.shadow_quality": {"ru": "Качество теней", "en": "Shadow quality"},
	"gfx.sec.world": {"ru": "Мир", "en": "World"},
	"gfx.night": {"ru": "Ночь", "en": "Night"},
	"gfx.tire_smoke": {"ru": "Дым от шин", "en": "Tire smoke"},
	"gfx.sec.display": {"ru": "Экран", "en": "Display"},
	"gfx.fullscreen": {"ru": "Полный экран", "en": "Fullscreen"},
	"gfx.vsync": {"ru": "Вертикальная синхронизация", "en": "VSync"},
	"gfx.status_unstable": {"ru": "MSAA выше 2x и SDFGI отключены как нестабильные", "en": "MSAA above 2x and SDFGI are disabled as unstable"},
	"gfx.preset_applied": {"ru": "Пресет применён", "en": "Preset applied"},
	"gfx.saved": {"ru": "Сохранено", "en": "Saved"},
	"gfx.reset_done": {"ru": "Сброшено к настройкам по умолчанию", "en": "Reset to defaults"},

	# --- Car settings sections ---
	"car.sec.visual": {"ru": "Клиренс", "en": "Visual / ride height"},
	"car.sec.body": {"ru": "Кузов", "en": "Body"},
	"car.sec.engine": {"ru": "Двигатель", "en": "Engine"},
	"car.sec.engine_sound": {"ru": "Звук двигателя (EngineSim)", "en": "Engine sound (EngineSim)"},
	"car.sec.drivetrain": {"ru": "Коробка / трансмиссия", "en": "Gearbox / drivetrain"},
	"car.sec.differential": {"ru": "Задний дифференциал", "en": "Rear differential"},
	"car.sec.wheels": {"ru": "Колёса (физика)", "en": "Wheels (physics)"},
	"car.sec.susp_front": {"ru": "Передняя подвеска", "en": "Front suspension"},
	"car.sec.susp_rear": {"ru": "Задняя подвеска", "en": "Rear suspension"},
	"car.sec.tires": {"ru": "Шины / тормоза", "en": "Tires / brakes"},
	"car.sec.clutch": {"ru": "Сцепление / инерция", "en": "Clutch / inertia"},
	"car.sec.aero": {"ru": "Аэродинамика / симуляция", "en": "Aero / simulation"},
	"car.sec.steering": {"ru": "Рулевое управление", "en": "Steering"},
	"car.sec.alignment": {"ru": "Углы установки", "en": "Alignment"},

	# --- Car settings params ---
	"car.clearance": {"ru": "Клиренс (модель + коллизия)", "en": "Ground clearance (model + collision)"},
	"car.mass": {"ru": "Масса, кг", "en": "Mass, kg"},
	"car.com_x": {"ru": "Центр масс X", "en": "Center of mass X"},
	"car.com_y": {"ru": "Центр масс Y", "en": "Center of mass Y"},
	"car.com_z": {"ru": "Центр масс Z", "en": "Center of mass Z"},
	"car.max_power_hp": {"ru": "Мощность, л.с.", "en": "Power, hp"},
	"car.idle_rpm": {"ru": "Холостые, об/мин", "en": "Idle, rpm"},
	"car.max_rpm": {"ru": "Макс. об/мин", "en": "Max rpm"},
	"car.cylinders": {"ru": "Цилиндры", "en": "Cylinders"},
	"car.displacement_cc": {"ru": "Объём, см³", "en": "Displacement, cc"},
	"car.bore_mm": {"ru": "Диаметр цилиндра, мм (0=авто)", "en": "Bore, mm (0=auto)"},
	"car.stroke_mm": {"ru": "Ход поршня, мм", "en": "Stroke, mm"},
	"car.layout": {"ru": "Компоновка", "en": "Layout"},
	"car.bank_angle_deg": {"ru": "Угол развала цилиндров, °", "en": "Bank angle, °"},
	"car.valves_per_cylinder": {"ru": "Клапанов на цилиндр", "en": "Valves per cylinder"},
	"car.exhaust_length_mm": {"ru": "Длина выпуска, мм", "en": "Exhaust length, mm"},
	"car.cam_duration_deg": {"ru": "Фаза распредвала, °", "en": "Cam duration, °"},
	"car.cam_lift_mm": {"ru": "Подъём клапана, мм", "en": "Cam lift, mm"},
	"car.hf_gain": {"ru": "ВЧ-усиление", "en": "HF gain"},
	"car.noise": {"ru": "Шум", "en": "Noise"},
	"car.jitter": {"ru": "Джиттер", "en": "Jitter"},
	"car.engine_sound_volume_db": {"ru": "Громкость в игре, дБ", "en": "In-game volume, dB"},
	"car.drive_type": {"ru": "Тип привода", "en": "Drive type"},
	"car.final_drive": {"ru": "Главная пара", "en": "Final drive"},
	"car.reverse_ratio": {"ru": "Задняя передача", "en": "Reverse gear"},
	"car.shift_time": {"ru": "Время переключения, с", "en": "Shift time, s"},
	"car.gear_n": {"ru": "Передача %d", "en": "Gear %d"},
	"car.rear_diff_type": {"ru": "Задний дифференциал", "en": "Rear differential"},
	"car.diff_preload": {"ru": "LSD: преднатяг", "en": "LSD preload"},
	"car.diff_power_lock": {"ru": "LSD: блокировка на тяге", "en": "LSD power lock"},
	"car.diff_coast_lock": {"ru": "LSD: блокировка на торможении", "en": "LSD coast lock"},
	"car.locked_diff_stiffness": {"ru": "Жёсткость заварки", "en": "Welded diff stiffness"},
	"car.awd_front_bias": {"ru": "AWD: доля на перед", "en": "AWD front bias"},
	"car.brake_elsd": {"ru": "Тормозной eLSD (ведущая ось)", "en": "Brake eLSD (driven axle)"},
	"car.wheel_inertia": {"ru": "Инерция колеса", "en": "Wheel inertia"},
	"car.front_rest_length": {"ru": "Перед: длина в покое", "en": "Front rest length"},
	"car.rear_rest_length": {"ru": "Зад: длина в покое", "en": "Rear rest length"},
	"car.front_travel": {"ru": "Перед: ход подвески", "en": "Front travel"},
	"car.rear_travel": {"ru": "Зад: ход подвески", "en": "Rear travel"},
	"car.front_stiffness": {"ru": "Перед: жёсткость пружин", "en": "Front stiffness"},
	"car.rear_stiffness": {"ru": "Зад: жёсткость пружин", "en": "Rear stiffness"},
	"car.front_damping_compression": {"ru": "Перед: демпфер сжатия", "en": "Front compression damping"},
	"car.rear_damping_compression": {"ru": "Зад: демпфер сжатия", "en": "Rear compression damping"},
	"car.front_damping_rebound": {"ru": "Перед: демпфер отбоя", "en": "Front rebound damping"},
	"car.rear_damping_rebound": {"ru": "Зад: демпфер отбоя", "en": "Rear rebound damping"},
	"car.front_anti_roll": {"ru": "Перед: стабилизатор", "en": "Front anti-roll bar"},
	"car.rear_anti_roll": {"ru": "Зад: стабилизатор", "en": "Rear anti-roll bar"},
	"car.tire_mu_front": {"ru": "Перед: μ сцепления", "en": "Front µ"},
	"car.tire_mu_rear": {"ru": "Зад: μ сцепления", "en": "Rear µ"},
	"car.rolling_resistance": {"ru": "Сопротивление качению", "en": "Rolling resistance"},
	"car.brake_force": {"ru": "Тормозное усилие", "en": "Brake force"},
	"car.handbrake_force": {"ru": "Усилие ручника", "en": "Handbrake force"},
	"car.handbrake_lat_grip": {"ru": "Ручник: заднее боковое сцепление", "en": "Handbrake: rear lateral grip"},
	"car.brake_bias_front": {"ru": "Распределение тормозов на перед", "en": "Front brake bias"},
	"car.clutch_max_torque": {"ru": "Момент сцепления", "en": "Clutch torque"},
	"car.clutch_engage_time": {"ru": "Время смыкания, с", "en": "Clutch engage time, s"},
	"car.engine_inertia": {"ru": "Инерция двигателя", "en": "Engine inertia"},
	"car.drag_coefficient": {"ru": "Cd (сопр. воздуха)", "en": "Cd"},
	"car.downforce_coefficient": {"ru": "Cl (прижимная сила)", "en": "Cl downforce"},
	"car.frontal_area": {"ru": "Лобовая площадь", "en": "Frontal area"},
	"car.physics_substeps": {"ru": "Физические подшаги", "en": "Physics substeps"},
	"car.tc_slip_ratio": {"ru": "TC: целевой κ", "en": "TC target κ"},
	"car.tc_gain": {"ru": "TC: усиление", "en": "TC gain"},
	"car.tc_min_scale": {"ru": "TC: мин. тяга", "en": "TC min traction"},
	"car.max_steer_angle": {"ru": "Макс. угол руля (lock)", "en": "Max steering angle (lock)"},
	"car.steer_speed": {"ru": "Скорость руления", "en": "Steering response speed"},
	"car.steer_curve_max_kmh": {"ru": "Soft-lock: скорость полного сокращения (км/ч)", "en": "Soft lock: full reduction speed (km/h)"},
	"car.steer_high_speed_factor": {"ru": "Отклик на скорости (меньше = спокойнее)", "en": "High-speed response (lower = calmer)"},
	"car.steer_input_gamma": {"ru": "Точность у центра (гамма)", "en": "Center precision (gamma)"},
	"car.drift_assist": {"ru": "Дрифт-ассистент (RWD; 0 = выкл)", "en": "Drift assist (RWD; 0 = off)"},
	"car.arcade_assist": {"ru": "Аркадный помощник (0 = чистый сим)", "en": "Arcade assist (0 = pure sim)"},
	"car.fwd_lat_priority": {"ru": "FWD: приоритет бокового сцепления", "en": "FWD: lateral grip priority"},
	"car.fwd_slip_angle_start_deg": {"ru": "FWD: начало среза тяги (угол сноса °)", "en": "FWD: traction cut start (slip angle °)"},
	"car.fwd_counter_steer_scale": {"ru": "FWD: сила контрруления (меньше = стабильнее)", "en": "FWD: counter-steer strength (lower = more stable)"},
	"car.fwd_recover_bleed": {"ru": "FWD: скорость отпускания руля после сноса", "en": "FWD: steering release speed after slide"},
	"car.front_caster_deg": {"ru": "Кастер передней оси, °", "en": "Front caster, °"},
	"car.rear_camber_deg": {"ru": "Развал задней оси, ° (минус = «домиком»)", "en": "Rear camber, ° (negative = top-in)"},

	# --- Car settings UI chrome ---
	"car.title": {"ru": "Настройки автомобиля", "en": "Car settings"},
	"car.path_label": {"ru": "Авто: %s · %s", "en": "Car: %s · %s"},
	"car.bake.prepare": {"ru": "Подготовка…", "en": "Preparing…"},
	"car.bake.check": {"ru": "Проверка кэша звука…", "en": "Checking sound cache…"},
	"car.bake.cached": {"ru": "Звук актуален — регенерация не нужна", "en": "Sound is up to date — no regeneration needed"},
	"car.bake.start": {"ru": "Подготовка свип-бейка (шаг %.0f об/мин)…", "en": "Preparing sweep bake (step %.0f rpm)…"},
	"car.bake.sweep": {"ru": "Синтез свипа холостые→%.0f об/мин…", "en": "Synthesizing sweep idle→%.0f rpm…"},
	"car.bake.rpm": {"ru": "Синтез %d / %d · %.0f об/мин", "en": "Synthesizing %d / %d · %.0f rpm"},
	"car.bake.promote": {"ru": "Сохранение банков на диск…", "en": "Saving banks to disk…"},
	"car.bake.apply": {"ru": "Применение звука к машине…", "en": "Applying sound to car…"},
	"car.bake.error": {"ru": "Ошибка генерации звука", "en": "Sound generation error"},

	# --- Tuning parts (garage) ---
	"garage.tuning": {"ru": "Тюнинг", "en": "Tuning"},
	"part.engine": {"ru": "ДВС", "en": "ENGINE"},
	"part.ecu": {"ru": "ECU", "en": "ECU"},
	"part.gearbox": {"ru": "КПП", "en": "GEARBOX"},
	"part.suspension": {"ru": "Подвеска", "en": "SUSPENSION"},
	"part.tires": {"ru": "Резина", "en": "TIRES"},
	"part.brakes": {"ru": "Тормоза", "en": "BRAKES"},
	"part.nos": {"ru": "Закись", "en": "NOS"},
	"part.turbo": {"ru": "Турбо", "en": "TURBO"},
	"part.stock": {"ru": "СТОК", "en": "STOCK"},
	"partname.engine.1": {"ru": "Спорт-впуск", "en": "Sport intake"},
	"partname.engine.2": {"ru": "Портинг ДВС", "en": "Head porting"},
	"partname.engine.3": {"ru": "Форсировка", "en": "Race build"},
	"partname.ecu.1": {"ru": "Чип-тюнинг", "en": "Chip tune"},
	"partname.ecu.2": {"ru": "Спорт-ПЗУ", "en": "Sport ECU"},
	"partname.ecu.3": {"ru": "Стадия 3", "en": "Stage 3 ECU"},
	"partname.gearbox.1": {"ru": "Близкий ряд", "en": "Close ratio"},
	"partname.gearbox.2": {"ru": "Секвентал", "en": "Sequential"},
	"partname.gearbox.3": {"ru": "Гоночный ряд", "en": "Race box"},
	"partname.suspension.1": {"ru": "Спорт-киты", "en": "Sport kit"},
	"partname.suspension.2": {"ru": "Койловеры", "en": "Coilovers"},
	"partname.suspension.3": {"ru": "Клуб-спорт", "en": "Club sport"},
	"partname.tires.1": {"ru": "Спорт", "en": "Sport"},
	"partname.tires.2": {"ru": "Слик стрит", "en": "Semi-slick"},
	"partname.tires.3": {"ru": "Слики", "en": "Full slick"},
	"partname.brakes.1": {"ru": "Спорт-колодки", "en": "Sport pads"},
	"partname.brakes.2": {"ru": "4-поршни", "en": "4-piston"},
	"partname.brakes.3": {"ru": "Гоночные", "en": "Race brakes"},
	"partname.nos.1": {"ru": "Kit 60 hp", "en": "60 hp shot"},
	"partname.nos.2": {"ru": "Kit 110 hp", "en": "110 hp shot"},
	"partname.nos.3": {"ru": "Kit 170 hp", "en": "170 hp shot"},
	"partname.turbo.1": {"ru": "Турбо 0.6 bar", "en": "Turbo 0.6 bar"},
	"partname.turbo.2": {"ru": "Турбо 0.9 bar", "en": "Turbo 0.9 bar"},
	"partname.turbo.3": {"ru": "Турбо 1.3 bar", "en": "Turbo 1.3 bar"},
	"partstat.stock": {"ru": "Заводская деталь", "en": "Factory part"},
	"partstat.engine.1": {"ru": "+12% мощности, +150 об/мин", "en": "+12% power, +150 rpm"},
	"partstat.engine.2": {"ru": "+28% мощности, +350 об/мин", "en": "+28% power, +350 rpm"},
	"partstat.engine.3": {"ru": "+50% мощности, +650 об/мин", "en": "+50% power, +650 rpm"},
	"partstat.ecu.1": {"ru": "+3% оборотов, острее педаль", "en": "+3% revs, sharper throttle"},
	"partstat.ecu.2": {"ru": "+6% оборотов, отсечка выше", "en": "+6% revs, higher cut"},
	"partstat.ecu.3": {"ru": "+10% оборотов, мгновенный отклик", "en": "+10% revs, instant response"},
	"partstat.gearbox.1": {"ru": "−4% передачи, быстрее смена", "en": "−4% gears, faster shifts"},
	"partstat.gearbox.2": {"ru": "−9% передачи, −38% смена", "en": "−9% gears, −38% shift time"},
	"partstat.gearbox.3": {"ru": "−14% передачи, главная +4%", "en": "−14% gears, +4% final drive"},
	"partstat.suspension.1": {"ru": "+15% жёсткость, −20 мм", "en": "+15% stiffness, −20 mm"},
	"partstat.suspension.2": {"ru": "+32% жёсткость, −40 мм", "en": "+32% stiffness, −40 mm"},
	"partstat.suspension.3": {"ru": "+50% жёсткость, −60 мм", "en": "+50% stiffness, −60 mm"},
	"partstat.tires.1": {"ru": "μ +0.08", "en": "μ +0.08"},
	"partstat.tires.2": {"ru": "μ +0.16, острее пик", "en": "μ +0.16, peakier"},
	"partstat.tires.3": {"ru": "μ +0.26, слик", "en": "μ +0.26, slicks"},
	"partstat.brakes.1": {"ru": "+15% усилие", "en": "+15% force"},
	"partstat.brakes.2": {"ru": "+32% усилие, ручник +10%", "en": "+32% force, +10% handbrake"},
	"partstat.brakes.3": {"ru": "+50% усилие, ручник +20%", "en": "+50% force, +20% handbrake"},
	"partstat.nos.1": {"ru": "+60 л.с. на полном газу", "en": "+60 hp at full throttle"},
	"partstat.nos.2": {"ru": "+110 л.с. на полном газу", "en": "+110 hp at full throttle"},
	"partstat.nos.3": {"ru": "+170 л.с. на полном газу", "en": "+170 hp at full throttle"},
	"partstat.turbo.1": {"ru": "+13% к моменту от 3000 об/мин", "en": "+13% torque from 3000 rpm"},
	"partstat.turbo.2": {"ru": "+26% к моменту, раньше наддув", "en": "+26% torque, early boost"},
	"partstat.turbo.3": {"ru": "+39% к моменту, жёсткий лаг", "en": "+39% torque, hard lag"},
	"tuning.back": {"ru": "Назад в гараж", "en": "Back to garage"},
	"car.saved_unchanged": {"ru": "Сохранено (звук без изменений): %s", "en": "Saved (sound unchanged): %s"},
	"car.reset_done": {"ru": "Сброшено к комплекту (%s), пользовательский бейк удалён", "en": "Reset to bundled (%s), user bake removed"},
	"car.bake.generating": {"ru": "Генерация звука двигателя…", "en": "Generating engine sound…"},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_locale_language() != "ru":
		language = "en"
	load_from_disk()


func t(key: String) -> String:
	var entry: Dictionary = STRINGS.get(key, {})
	if entry.is_empty():
		return key
	return str(entry.get(language, entry.get("en", key)))


func set_language(lang: String) -> void:
	if lang == language:
		return
	language = lang
	save_to_disk()
	language_changed.emit()


func load_from_disk() -> void:
	var cfg := ConfigStore.open(SAVE_PATH)
	if cfg == null:
		return
	var saved := str(cfg.get_value("game", "language", ""))
	if saved == "ru" or saved == "en":
		language = saved


func save_to_disk() -> void:
	ConfigStore.save(SAVE_PATH, {"game": {"language": language}})
