extends Node

signal engine_bake_progress(current: int, total: int, rpm: float, phase: String)

## Per-car debug overrides. Scene CarSetup + WheelLayout/Collision are source of truth for layout.
const CATALOG_PATH := "res://vehicles/cars_catalog.tres"
const LEGACY_SAVE_PATH := "user://car_tuning.cfg"

var catalog: CarsCatalog
var active_car_id: StringName = &"volga"
## Working copy edited by Settings (physics fields only).
var setup: CarSetup
## Runtime visual offset; does not rewrite scene node bases permanently.
var clearance: float = 0.0


var SAVE_PATH: String:
	get:
		return save_path_for(active_car_id)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = load(CATALOG_PATH) as CarsCatalog
	_reset_working_from_pack(active_car_id)
	load_from_disk()


func save_path_for(car_id: StringName) -> String:
	return "user://tuning_%s.cfg" % String(car_id)


func _pack_setup_path(car_id: StringName) -> String:
	match String(car_id):
		"demo":
			return "res://assets/scenes/cars/demo/demo_setup.tres"
		"volga":
			return "res://assets/scenes/cars/volga/volga_setup.tres"
		"golf":
			return "res://assets/scenes/cars/golf/golf_setup.tres"
		_:
			if catalog != null:
				var def := catalog.get_by_id(car_id)
				if def != null and def.scene != null:
					# Fallback: volga setup if unknown pack.
					pass
			return "res://assets/scenes/cars/volga/volga_setup.tres"


func _reset_working_from_pack(car_id: StringName) -> void:
	active_car_id = car_id
	var base := load(_pack_setup_path(car_id)) as CarSetup
	if base:
		setup = base.duplicate(true) as CarSetup
	else:
		setup = CarSetup.new()
	setup.ensure_torque_curve()
	setup.ensure_steer_angle_curve()
	setup.migrate_legacy_fields()
	clearance = 0.0


func reset_to_defaults() -> void:
	_reset_working_from_pack(active_car_id)
	var path := save_path_for(active_car_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	EngineBankBaker.clear_user(active_car_id)
	_push_working_to_live_cars()
	_restore_pack_audio_on_live_cars()


func bind_car_id(car_id: StringName) -> void:
	if car_id == StringName():
		return
	_reset_working_from_pack(car_id)
	load_from_disk()


func apply_overrides_to_car(car: Node) -> void:
	if car == null:
		return
	var car_id: StringName = car.get("car_id") as StringName
	if car_id == StringName():
		car_id = &"volga"
	var target_setup: CarSetup = car.get("setup") as CarSetup
	if target_setup == null:
		return
	var cfg := ConfigFile.new()
	var path := save_path_for(car_id)
	if cfg.load(path) != OK:
		if car_id == &"volga" and cfg.load(LEGACY_SAVE_PATH) == OK:
			_apply_physics_cfg(target_setup, cfg)
			_apply_clearance_cfg(car, cfg)
		_restore_pack_axle_layout(car_id, target_setup)
		return
	_apply_physics_cfg(target_setup, cfg)
	_apply_clearance_cfg(car, cfg)
	_restore_pack_axle_layout(car_id, target_setup)


func _restore_pack_axle_layout(car_id: StringName, target: CarSetup) -> void:
	var pack := load(_pack_setup_path(car_id)) as CarSetup
	if pack == null or target == null:
		return
	_copy_axle_layout(pack, target)
	target.rebuild_wheel_positions()


func _apply_clearance_cfg(car: Node, cfg: ConfigFile) -> void:
	if cfg.has_section_key("visual", "clearance"):
		car.set("clearance", float(cfg.get_value("visual", "clearance", 0.0)))
	elif cfg.has_section_key("visual", "model_y_offset"):
		var old_model := float(cfg.get_value("visual", "model_y_offset", -0.082))
		var old_col := float(cfg.get_value("visual", "collision_y", 0.456))
		car.set("clearance", 0.5 * ((old_model - (-0.082)) + (old_col - 0.456)))


func apply_clearance_to_cars() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player_cars"):
		if String(node.get("car_id")) != String(active_car_id):
			continue
		node.set("clearance", clearance)
		if node.has_method("refresh_visual_tuning"):
			node.call("refresh_visual_tuning")


func _push_working_to_live_cars() -> void:
	if not is_inside_tree() or setup == null:
		return
	var pack := load(_pack_setup_path(active_car_id)) as CarSetup
	for node in get_tree().get_nodes_in_group("player_cars"):
		if String(node.get("car_id")) != String(active_car_id):
			continue
		var live: CarSetup = node.get("setup") as CarSetup
		if live == null:
			continue
		var copy := setup.duplicate(true) as CarSetup
		# Geometry is pack-owned (WheelLayout / .tres) — never override from game settings.
		if pack != null:
			_copy_axle_layout(pack, copy)
		else:
			_copy_axle_layout(live, copy)
		copy.ensure_torque_curve()
		copy.ensure_steer_angle_curve()
		copy.migrate_legacy_fields()
		copy.rebuild_wheel_positions()
		if node.has_method("set_setup"):
			node.call("set_setup", copy)
		else:
			node.set("setup", copy)
		node.set("clearance", clearance)
		if node.has_method("refresh_visual_tuning"):
			node.call("refresh_visual_tuning")


## Axle geometry + tire ISO size — authored in editor WheelLayout / pack .tres only.
func _copy_axle_layout(from_setup: CarSetup, to_setup: CarSetup) -> void:
	if from_setup == null or to_setup == null:
		return
	to_setup.front_axle_z = from_setup.front_axle_z
	to_setup.front_mount_y = from_setup.front_mount_y
	to_setup.front_track = from_setup.front_track
	to_setup.front_rim_inches = from_setup.front_rim_inches
	to_setup.front_tire_width_mm = from_setup.front_tire_width_mm
	to_setup.front_tire_aspect = from_setup.front_tire_aspect
	to_setup.front_wheel_radius = from_setup.front_wheel_radius
	to_setup.front_wheel_width = from_setup.front_wheel_width
	to_setup.front_mesh_scale = from_setup.front_mesh_scale
	to_setup.rear_axle_z = from_setup.rear_axle_z
	to_setup.rear_mount_y = from_setup.rear_mount_y
	to_setup.rear_track = from_setup.rear_track
	to_setup.rear_rim_inches = from_setup.rear_rim_inches
	to_setup.rear_tire_width_mm = from_setup.rear_tire_width_mm
	to_setup.rear_tire_aspect = from_setup.rear_tire_aspect
	to_setup.rear_wheel_radius = from_setup.rear_wheel_radius
	to_setup.rear_wheel_width = from_setup.rear_wheel_width
	to_setup.rear_mesh_scale = from_setup.rear_mesh_scale
	to_setup.wheel_radius = from_setup.front_wheel_radius
	to_setup.wheel_width = from_setup.front_wheel_width
	to_setup.wheel_positions = from_setup.wheel_positions.duplicate()


func save_to_disk() -> Dictionary:
	if setup == null:
		return {}
	_write_config_to_disk()
	_push_working_to_live_cars()
	return rebake_engine_sounds()


func save_to_disk_async() -> Dictionary:
	if setup == null:
		return {}
	_write_config_to_disk()
	_push_working_to_live_cars()
	return await rebake_engine_sounds_async()


## Persist tuning without touching engine banks.
func save_config_only() -> void:
	if setup == null:
		return
	_write_config_to_disk()
	_push_working_to_live_cars()


## True when current engine-sound params differ from the last successful user bake.
func engine_bake_is_stale() -> bool:
	if setup == null or not EngineBankBaker.has_engine_sim():
		return false
	var fp := _engine_sound_fingerprint()
	if fp.is_empty():
		return false
	return EngineBankBaker.user_fingerprint(active_car_id) != fp


func _write_config_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("visual", "clearance", clearance)

	cfg.set_value("body", "mass", setup.mass)
	cfg.set_value("body", "com_x", setup.center_of_mass_offset.x)
	cfg.set_value("body", "com_y", setup.center_of_mass_offset.y)
	cfg.set_value("body", "com_z", setup.center_of_mass_offset.z)

	cfg.set_value("engine", "max_power_hp", setup.max_power_hp)
	cfg.set_value("engine", "max_power_kw", setup.max_power_hp * CarSetup.KW_PER_HP)
	cfg.set_value("engine", "idle_rpm", setup.idle_rpm)
	cfg.set_value("engine", "max_rpm", setup.max_rpm)
	cfg.set_value("engine", "torque_boost", setup.torque_boost)
	cfg.set_value("engine", "engine_inertia", setup.engine_inertia)

	cfg.set_value("engine_sound", "cylinders", setup.cylinders)
	cfg.set_value("engine_sound", "displacement_cc", setup.displacement_cc)
	cfg.set_value("engine_sound", "bore_mm", setup.bore_mm)
	cfg.set_value("engine_sound", "stroke_mm", setup.stroke_mm)
	cfg.set_value("engine_sound", "engine_layout", int(setup.engine_layout))
	cfg.set_value("engine_sound", "bank_angle_deg", setup.bank_angle_deg)
	cfg.set_value("engine_sound", "valves_per_cylinder", setup.valves_per_cylinder)
	cfg.set_value("engine_sound", "exhaust_length_mm", setup.exhaust_length_mm)
	cfg.set_value("engine_sound", "cam_duration_deg", setup.cam_duration_deg)
	cfg.set_value("engine_sound", "cam_lift_mm", setup.cam_lift_mm)
	cfg.set_value("engine_sound", "hf_gain", setup.hf_gain)
	cfg.set_value("engine_sound", "noise", setup.noise)
	cfg.set_value("engine_sound", "jitter", setup.jitter)
	cfg.set_value("engine_sound", "engine_sound_volume_db", setup.engine_sound_volume_db)

	cfg.set_value("drivetrain", "reverse_ratio", setup.reverse_ratio)
	cfg.set_value("drivetrain", "final_drive", setup.final_drive)
	cfg.set_value("drivetrain", "drive_type", int(setup.drive_type))
	cfg.set_value("drivetrain", "shift_time", setup.shift_time)
	cfg.set_value("drivetrain", "clutch_max_torque", setup.clutch_max_torque)
	cfg.set_value("drivetrain", "clutch_engage_time", setup.clutch_engage_time)
	cfg.set_value("drivetrain", "awd_front_bias", setup.awd_front_bias)
	cfg.set_value("drivetrain", "rear_diff_type", int(setup.rear_diff_type))
	cfg.set_value("drivetrain", "diff_preload", setup.diff_preload)
	cfg.set_value("drivetrain", "diff_power_lock", setup.diff_power_lock)
	cfg.set_value("drivetrain", "diff_coast_lock", setup.diff_coast_lock)
	cfg.set_value("drivetrain", "locked_diff_stiffness", setup.locked_diff_stiffness)
	for i in setup.gear_ratios.size():
		cfg.set_value("drivetrain", "gear_%d" % (i + 1), setup.gear_ratios[i])

	# Wheel inertia only — axle geometry / tire ISO live in pack WheelLayout.
	cfg.set_value("wheels", "wheel_inertia", setup.wheel_inertia)

	cfg.set_value("suspension", "front_rest_length", setup.front_rest_length)
	cfg.set_value("suspension", "rear_rest_length", setup.rear_rest_length)
	cfg.set_value("suspension", "front_travel", setup.front_travel)
	cfg.set_value("suspension", "rear_travel", setup.rear_travel)
	cfg.set_value("suspension", "front_stiffness", setup.front_stiffness)
	cfg.set_value("suspension", "rear_stiffness", setup.rear_stiffness)
	cfg.set_value("suspension", "front_damping_compression", setup.front_damping_compression)
	cfg.set_value("suspension", "front_damping_rebound", setup.front_damping_rebound)
	cfg.set_value("suspension", "rear_damping_compression", setup.rear_damping_compression)
	cfg.set_value("suspension", "rear_damping_rebound", setup.rear_damping_rebound)
	cfg.set_value("suspension", "front_anti_roll", setup.front_anti_roll)
	cfg.set_value("suspension", "rear_anti_roll", setup.rear_anti_roll)

	cfg.set_value("tires", "tire_mu_front", setup.tire_mu_front)
	cfg.set_value("tires", "tire_mu_rear", setup.tire_mu_rear)
	cfg.set_value("tires", "tire_v_low", setup.tire_v_low)
	cfg.set_value("tires", "pacejka_b_long", setup.pacejka_b_long)
	cfg.set_value("tires", "pacejka_c_long", setup.pacejka_c_long)
	cfg.set_value("tires", "pacejka_e_long", setup.pacejka_e_long)
	cfg.set_value("tires", "pacejka_b_lat", setup.pacejka_b_lat)
	cfg.set_value("tires", "pacejka_c_lat", setup.pacejka_c_lat)
	cfg.set_value("tires", "pacejka_e_lat", setup.pacejka_e_lat)
	cfg.set_value("tires", "rolling_resistance", setup.rolling_resistance)
	cfg.set_value("tires", "brake_force", setup.brake_force)
	cfg.set_value("tires", "handbrake_force", setup.handbrake_force)
	cfg.set_value("tires", "handbrake_lat_grip", setup.handbrake_lat_grip)
	cfg.set_value("tires", "brake_bias_front", setup.brake_bias_front)

	cfg.set_value("aero", "drag_coefficient", setup.drag_coefficient)
	cfg.set_value("aero", "downforce_coefficient", setup.downforce_coefficient)
	cfg.set_value("aero", "frontal_area", setup.frontal_area)

	cfg.set_value("steering", "max_steer_angle", setup.max_steer_angle)
	cfg.set_value("steering", "steer_speed", setup.steer_speed)
	cfg.set_value("steering", "steer_curve_max_kmh", setup.steer_curve_max_kmh)
	cfg.set_value("steering", "steer_speed_ref", setup.steer_speed_ref)
	cfg.set_value("steering", "steer_high_speed_factor", setup.steer_high_speed_factor)
	cfg.set_value("steering", "steer_input_gamma", setup.steer_input_gamma)
	cfg.set_value("steering", "counter_steer_slip_deg", setup.counter_steer_slip_deg)
	cfg.set_value("steering", "counter_steer_lock_max", setup.counter_steer_lock_max)
	cfg.set_value("steering", "counter_steer_rate_mult", setup.counter_steer_rate_mult)
	cfg.set_value("steering", "counter_steer_recover_rate", setup.counter_steer_recover_rate)
	cfg.set_value("steering", "steer_lock_smooth", setup.steer_lock_smooth)
	cfg.set_value("throttle", "throttle_rise_rate", setup.throttle_rise_rate)
	cfg.set_value("throttle", "throttle_fall_rate", setup.throttle_fall_rate)
	cfg.set_value("assist", "drift_assist", setup.drift_assist)
	cfg.set_value("fwd", "fwd_lat_priority", setup.fwd_lat_priority)
	cfg.set_value("fwd", "fwd_slip_angle_start_deg", setup.fwd_slip_angle_start_deg)
	cfg.set_value("fwd", "fwd_counter_steer_scale", setup.fwd_counter_steer_scale)
	cfg.set_value("fwd", "fwd_recover_bleed", setup.fwd_recover_bleed)
	cfg.set_value("simulation", "physics_substeps", setup.physics_substeps)
	cfg.set_value("simulation", "traction_control", setup.traction_control)
	cfg.set_value("simulation", "tc_slip_ratio", setup.tc_slip_ratio)
	cfg.set_value("simulation", "tc_gain", setup.tc_gain)
	cfg.set_value("simulation", "tc_min_scale", setup.tc_min_scale)

	cfg.save(save_path_for(active_car_id))


## EngineSimBaker bake → user:// banks + swap on live cars.
## Skips render if fingerprint matches last user bake (still re-applies banks).
func rebake_engine_sounds(duration_sec: float = EngineBankBaker.DEFAULT_DURATION_SEC) -> Dictionary:
	if setup == null:
		return {}
	var car_id := active_car_id
	var fp := _engine_sound_fingerprint()
	if not fp.is_empty() and EngineBankBaker.user_fingerprint(car_id) == fp:
		var cached := EngineBankBaker.load_user(car_id)
		if not cached.is_empty():
			_apply_engine_banks_to_live_cars(cached)
			cached["skipped"] = true
			return cached
		## Fingerprint matches but banks unreadable — fall through to rebake.
	var bake_setup := setup.duplicate(true) as CarSetup
	var banks := EngineBankBaker.bake_user(bake_setup, car_id, duration_sec, fp)
	_apply_engine_banks_to_live_cars(banks)
	banks["skipped"] = false
	return banks


func rebake_engine_sounds_async(duration_sec: float = EngineBankBaker.DEFAULT_DURATION_SEC) -> Dictionary:
	if setup == null:
		return {}
	## Fingerprint + setup snapshot BEFORE any await — cars call TuningStore.bind_car_id()
	## on ready/enter and would otherwise mutate setup mid-check / mid-bake.
	var car_id := active_car_id
	var fp := _engine_sound_fingerprint()
	var bake_setup := setup.duplicate(true) as CarSetup
	if not fp.is_empty() and EngineBankBaker.user_fingerprint(car_id) == fp:
		var cached := EngineBankBaker.load_user(car_id)
		if not cached.is_empty():
			_apply_engine_banks_to_live_cars(cached)
			cached["skipped"] = true
			return cached
	engine_bake_progress.emit(0, 1, 0.0, "check")
	await get_tree().process_frame
	## Re-check after yield in case another path just finished baking.
	if not fp.is_empty() and EngineBankBaker.user_fingerprint(car_id) == fp:
		var cached2 := EngineBankBaker.load_user(car_id)
		if not cached2.is_empty():
			engine_bake_progress.emit(1, 1, 0.0, "cached")
			await get_tree().process_frame
			_apply_engine_banks_to_live_cars(cached2)
			cached2["skipped"] = true
			return cached2
	setup = bake_setup
	active_car_id = car_id
	return await _bake_engine_sweep_async(duration_sec, fp)


const _SWEEP_PROGRESS_STEPS := 4


func _bake_engine_sweep_async(duration_sec: float, fingerprint: String) -> Dictionary:
	if EngineBankBaker.has_engine_sim():
		var bake_setup := setup
		var bake_car_id := active_car_id
		var rpms := EngineBankBaker.band_rpms(bake_setup)
		var band_count := rpms.size()
		var idle_rpm := rpms[0] if band_count > 0 else bake_setup.idle_rpm
		var max_rpm := rpms[band_count - 1] if band_count > 0 else bake_setup.max_rpm
		engine_bake_progress.emit(0, _SWEEP_PROGRESS_STEPS, idle_rpm, "start")
		await get_tree().process_frame
		engine_bake_progress.emit(1, _SWEEP_PROGRESS_STEPS, max_rpm, "sweep")
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		## Re-bind working setup in case another car stole TuningStore during awaits.
		if setup != bake_setup or active_car_id != bake_car_id:
			active_car_id = bake_car_id
			setup = bake_setup
		var banks := EngineBankBaker.bake_user(bake_setup, bake_car_id, duration_sec, fingerprint)
		if banks.is_empty():
			engine_bake_progress.emit(0, _SWEEP_PROGRESS_STEPS, 0.0, "error")
			return {}
		print("TuningStore: engine sweep bake %s → %d bands in %d ms" % [
			String(bake_car_id), band_count, Time.get_ticks_msec() - t0,
		])
		engine_bake_progress.emit(2, _SWEEP_PROGRESS_STEPS, max_rpm, "promote")
		await get_tree().process_frame
		engine_bake_progress.emit(_SWEEP_PROGRESS_STEPS, _SWEEP_PROGRESS_STEPS, max_rpm, "apply")
		await get_tree().process_frame
		_apply_engine_banks_to_live_cars(banks)
		banks["skipped"] = false
		return banks

	return await _bake_engine_legacy_incremental(duration_sec, fingerprint)


func _bake_engine_legacy_incremental(duration_sec: float, fingerprint: String) -> Dictionary:
	push_warning("TuningStore: EngineSimBaker missing — legacy incremental bake")
	var out_dir := EngineBankBaker.user_bake_dir(active_car_id)
	var tmp_dir := "user://engine_bake/_tmp_%s" % String(active_car_id).to_lower()
	EngineBankBaker.clear_dir(tmp_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp_dir))

	var rpms := EngineBankBaker.band_rpms(setup)
	var names := EngineBankBaker.band_names(rpms)
	var total := rpms.size()
	engine_bake_progress.emit(0, total, 0.0, "start")
	await get_tree().process_frame

	var loads := EngineBankBaker.band_loads_for(rpms)
	for i in total:
		var rpm := rpms[i]
		var name: String = names[i]
		engine_bake_progress.emit(i + 1, total, rpm, "rpm")
		await get_tree().process_frame
		var stream: AudioStreamWAV = EngineBankBaker.samples_to_stream(
			EngineBankBaker.render_band(setup, rpm, loads[i], duration_sec)
		)
		var err := ResourceSaver.save(stream, tmp_dir.path_join("%s.tres" % name))
		if err != OK:
			EngineBankBaker.clear_dir(tmp_dir)
			engine_bake_progress.emit(0, total, rpm, "error")
			return {}
		await get_tree().process_frame

	EngineBankBaker.write_bake_meta(tmp_dir, rpms, names, fingerprint)
	engine_bake_progress.emit(total, total, 0.0, "promote")
	await get_tree().process_frame
	if not EngineBankBaker.promote_bake_dir(tmp_dir, out_dir):
		EngineBankBaker.clear_dir(tmp_dir)
		engine_bake_progress.emit(0, total, 0.0, "error")
		return {}
	var banks := EngineBankBaker.load_user(active_car_id)
	engine_bake_progress.emit(total, total, 0.0, "apply")
	await get_tree().process_frame
	_apply_engine_banks_to_live_cars(banks)
	banks["skipped"] = false
	return banks


func _engine_sound_fingerprint(setup_override: CarSetup = null) -> String:
	var target := setup_override if setup_override != null else setup
	if target == null:
		return ""
	# Bump BAKE_REV when native synth / mapping changes so caches rebuild.
	# Only fields that affect EngineSimBaker.params_from_setup belong here
	# (max_power_hp does NOT — changing HP must not force a rebake).
	const BAKE_REV := "enginesim7-limiter"
	return "%s|%d|%.0f|%.0f|%.0f|%d|%.0f|%d|%.0f|%.0f|%.1f|%.2f|%.2f|%.2f|%.0f|%.0f" % [
		BAKE_REV,
		target.cylinders,
		target.displacement_cc,
		target.bore_mm,
		target.stroke_mm,
		int(target.engine_layout),
		target.bank_angle_deg,
		target.valves_per_cylinder,
		target.exhaust_length_mm,
		target.cam_duration_deg,
		target.cam_lift_mm,
		target.hf_gain,
		target.noise,
		target.jitter,
		target.idle_rpm,
		target.max_rpm,
	]


func _apply_engine_banks_to_live_cars(banks: Dictionary) -> void:
	if banks.is_empty() or not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player_cars"):
		if String(node.get("car_id")) != String(active_car_id):
			continue
		var engine_audio: Node = node.get_node_or_null("EngineAudio")
		if engine_audio != null and engine_audio.has_method("apply_banks"):
			engine_audio.call("apply_banks", banks)


func _refresh_all_car_engine_audio() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player_cars"):
		var car_id: StringName = node.get("car_id") as StringName
		if car_id == StringName():
			continue
		var banks := EngineBankBaker.load_user(car_id)
		if banks.is_empty():
			continue
		var engine_audio: Node = node.get_node_or_null("EngineAudio")
		if engine_audio != null and engine_audio.has_method("apply_banks"):
			engine_audio.call("apply_banks", banks)


func _enumerate_bake_car_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var seen := {}
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("player_cars"):
			var car_id: StringName = node.get("car_id") as StringName
			if car_id == StringName() or seen.has(car_id):
				continue
			seen[car_id] = true
			ids.append(car_id)
	if ids.is_empty() and catalog != null:
		for car_id in catalog.all_ids():
			if not seen.has(car_id):
				ids.append(car_id)
	return ids


func _snapshot_car_setup(car_id: StringName) -> CarSetup:
	var saved_active := active_car_id
	_reset_working_from_pack(car_id)
	load_from_disk()
	var snap := setup.duplicate(true) as CarSetup
	_reset_working_from_pack(saved_active)
	load_from_disk()
	return snap


func _car_needs_engine_bake(car_id: StringName) -> bool:
	if not EngineBankBaker.has_engine_sim():
		return false
	var snap := _snapshot_car_setup(car_id)
	if snap == null:
		return false
	var fp := _engine_sound_fingerprint(snap)
	if fp.is_empty():
		return false
	var stored := EngineBankBaker.user_fingerprint(car_id)
	## Fingerprint is written only after a successful bake — match means banks are valid.
	if stored == fp:
		return false
	return true


func _collect_cars_needing_bake() -> Array[StringName]:
	var pending: Array[StringName] = []
	for car_id in _enumerate_bake_car_ids():
		if _car_needs_engine_bake(car_id):
			pending.append(car_id)
	return pending


## First launch / missing user:// banks: bake every car on the track (or catalog).
## Pass `precollected` to avoid scanning twice when the caller already checked.
func ensure_engine_sounds_on_startup(precollected: Array[StringName] = []) -> Dictionary:
	if not EngineBankBaker.has_engine_sim():
		return {"skipped": true, "reason": "no_baker"}
	if not is_inside_tree():
		return {}
	var pending: Array[StringName] = precollected if not precollected.is_empty() else _collect_cars_needing_bake()
	if pending.is_empty():
		_refresh_all_car_engine_audio()
		return {"baked": 0, "skipped": true}
	var saved_active := active_car_id
	var baked := 0
	var total := pending.size()
	for i in total:
		var car_id := pending[i]
		engine_bake_progress.emit(i, total, 0.0, "car|%s|start" % String(car_id))
		await get_tree().process_frame
		active_car_id = car_id
		_reset_working_from_pack(car_id)
		load_from_disk()
		## Snapshot setup so awaits inside rebake can't lose the car we're baking.
		var bake_setup := setup.duplicate(true) as CarSetup
		setup = bake_setup
		var result: Dictionary = await rebake_engine_sounds_async()
		if not result.is_empty() and not bool(result.get("skipped", false)):
			baked += 1
	_refresh_all_car_engine_audio()
	_reset_working_from_pack(saved_active)
	load_from_disk()
	engine_bake_progress.emit(total, total, 0.0, "done")
	return {"baked": baked, "total": total}


func cars_needing_engine_bake() -> Array[StringName]:
	return _collect_cars_needing_bake()


func refresh_all_car_engine_audio() -> void:
	_refresh_all_car_engine_audio()


func _restore_pack_audio_on_live_cars() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player_cars"):
		if String(node.get("car_id")) != String(active_car_id):
			continue
		var profile = node.get("audio_profile")
		var engine_audio: Node = node.get_node_or_null("EngineAudio")
		if engine_audio != null and profile != null and engine_audio.has_method("apply_profile"):
			engine_audio.call("apply_profile", profile, false)


func load_from_disk() -> void:
	if setup == null:
		_reset_working_from_pack(active_car_id)
	var cfg := ConfigFile.new()
	var path := save_path_for(active_car_id)
	if cfg.load(path) != OK:
		if active_car_id == &"volga" and cfg.load(LEGACY_SAVE_PATH) == OK:
			_apply_physics_cfg(setup, cfg)
			if cfg.has_section_key("visual", "clearance"):
				clearance = float(cfg.get_value("visual", "clearance", clearance))
			elif cfg.has_section_key("visual", "model_y_offset"):
				var old_model := float(cfg.get_value("visual", "model_y_offset", -0.082))
				var old_col := float(cfg.get_value("visual", "collision_y", 0.456))
				clearance = 0.5 * ((old_model - (-0.082)) + (old_col - 0.456))
		_restore_pack_axle_layout(active_car_id, setup)
		return
	_apply_physics_cfg(setup, cfg)
	clearance = float(cfg.get_value("visual", "clearance", clearance))
	_restore_pack_axle_layout(active_car_id, setup)


func _apply_engine_sound_cfg(target: CarSetup, cfg: ConfigFile) -> void:
	## New EngineSimBaker keys, with migration from pre-enginesim3 tuning.cfg.
	if cfg.has_section_key("engine_sound", "cylinders") or cfg.has_section_key("engine_sound", "displacement_cc"):
		target.cylinders = int(cfg.get_value("engine_sound", "cylinders", target.cylinders))
		target.displacement_cc = float(cfg.get_value("engine_sound", "displacement_cc", target.displacement_cc))
		target.bore_mm = float(cfg.get_value("engine_sound", "bore_mm", target.bore_mm))
		target.stroke_mm = float(cfg.get_value("engine_sound", "stroke_mm", target.stroke_mm))
		target.engine_layout = int(cfg.get_value("engine_sound", "engine_layout", int(target.engine_layout))) as CarSetup.EngineLayout
		target.bank_angle_deg = float(cfg.get_value("engine_sound", "bank_angle_deg", target.bank_angle_deg))
		target.valves_per_cylinder = int(cfg.get_value("engine_sound", "valves_per_cylinder", target.valves_per_cylinder))
		target.exhaust_length_mm = float(cfg.get_value("engine_sound", "exhaust_length_mm", target.exhaust_length_mm))
		target.cam_duration_deg = float(cfg.get_value("engine_sound", "cam_duration_deg", target.cam_duration_deg))
		target.cam_lift_mm = float(cfg.get_value("engine_sound", "cam_lift_mm", target.cam_lift_mm))
		target.hf_gain = float(cfg.get_value("engine_sound", "hf_gain", target.hf_gain))
		target.noise = float(cfg.get_value("engine_sound", "noise", target.noise))
		target.jitter = float(cfg.get_value("engine_sound", "jitter", target.jitter))
	else:
		# Legacy synth-oriented keys → approximate EngineSim params.
		var cyl := int(cfg.get_value("engine_sound", "cylinder_count", target.cylinders))
		var liters := float(cfg.get_value("engine_sound", "displacement_liters", target.get_displacement_liters()))
		var tip := float(cfg.get_value("engine_sound", "exhaust_diameter_mm", 55.0))
		var muffler := bool(cfg.get_value("engine_sound", "has_muffler", true))
		var resonators := int(cfg.get_value("engine_sound", "resonator_count", 1))
		var turbo := bool(cfg.get_value("engine_sound", "has_turbo", false))
		var sc := bool(cfg.get_value("engine_sound", "has_supercharger", false))
		target.cylinders = clampi(cyl, 2, 12)
		target.displacement_cc = clampf(liters, 0.5, 12.0) * 1000.0
		target.stroke_mm = float(cfg.get_value("engine_sound", "piston_stroke_mm", target.stroke_mm))
		target.bore_mm = 0.0
		if cyl >= 8:
			target.engine_layout = CarSetup.EngineLayout.V
			target.bank_angle_deg = 90.0
		elif cyl == 6 and liters >= 3.0:
			target.engine_layout = CarSetup.EngineLayout.V
			target.bank_angle_deg = 60.0
		else:
			target.engine_layout = CarSetup.EngineLayout.INLINE
			target.bank_angle_deg = 0.0
		target.valves_per_cylinder = 2
		var exhaust_len := lerpf(640.0, 360.0, clampf(inverse_lerp(35.0, 100.0, tip), 0.0, 1.0))
		exhaust_len *= 1.12 if muffler else 0.88
		exhaust_len *= lerpf(1.0, 1.08, float(clampi(resonators, 0, 3)) / 3.0)
		target.exhaust_length_mm = clampf(exhaust_len, 300.0, 900.0)
		target.cam_duration_deg = 220.0
		target.cam_lift_mm = 9.5
		if turbo:
			target.noise = 0.35
			target.hf_gain = 0.15
		elif sc:
			target.noise = 0.28
			target.hf_gain = 0.08
		else:
			target.noise = 1.0
			target.hf_gain = 0.01
		target.jitter = 0.5
	target.engine_sound_volume_db = float(
		cfg.get_value("engine_sound", "engine_sound_volume_db", target.engine_sound_volume_db)
	)


func _apply_physics_cfg(target: CarSetup, cfg: ConfigFile) -> void:
	target.mass = float(cfg.get_value("body", "mass", target.mass))
	target.center_of_mass_offset = Vector3(
		float(cfg.get_value("body", "com_x", target.center_of_mass_offset.x)),
		float(cfg.get_value("body", "com_y", target.center_of_mass_offset.y)),
		float(cfg.get_value("body", "com_z", target.center_of_mass_offset.z))
	)

	if cfg.has_section_key("engine", "max_power_hp"):
		target.max_power_hp = float(cfg.get_value("engine", "max_power_hp", target.max_power_hp))
		target.max_power_kw = target.max_power_hp * CarSetup.KW_PER_HP
	else:
		target.max_power_kw = float(cfg.get_value("engine", "max_power_kw", target.max_power_kw))
		target.max_power_hp = target.max_power_kw / CarSetup.KW_PER_HP
	target.idle_rpm = float(cfg.get_value("engine", "idle_rpm", target.idle_rpm))
	target.max_rpm = float(cfg.get_value("engine", "max_rpm", target.max_rpm))
	target.torque_boost = float(cfg.get_value("engine", "torque_boost", target.torque_boost))
	target.engine_inertia = float(cfg.get_value("engine", "engine_inertia", target.engine_inertia))

	_apply_engine_sound_cfg(target, cfg)

	target.reverse_ratio = float(cfg.get_value("drivetrain", "reverse_ratio", target.reverse_ratio))
	target.final_drive = float(cfg.get_value("drivetrain", "final_drive", target.final_drive))
	target.drive_type = int(cfg.get_value("drivetrain", "drive_type", int(target.drive_type))) as CarSetup.DriveType
	target.shift_time = float(cfg.get_value("drivetrain", "shift_time", target.shift_time))
	target.clutch_max_torque = float(cfg.get_value("drivetrain", "clutch_max_torque", target.clutch_max_torque))
	target.clutch_engage_time = float(cfg.get_value("drivetrain", "clutch_engage_time", target.clutch_engage_time))
	target.awd_front_bias = float(cfg.get_value("drivetrain", "awd_front_bias", target.awd_front_bias))
	target.rear_diff_type = int(cfg.get_value("drivetrain", "rear_diff_type", int(target.rear_diff_type))) as CarSetup.RearDiffType
	target.diff_preload = float(cfg.get_value("drivetrain", "diff_preload", target.diff_preload))
	target.diff_power_lock = float(cfg.get_value("drivetrain", "diff_power_lock", target.diff_power_lock))
	target.diff_coast_lock = float(cfg.get_value("drivetrain", "diff_coast_lock", target.diff_coast_lock))
	target.locked_diff_stiffness = float(cfg.get_value("drivetrain", "locked_diff_stiffness", target.locked_diff_stiffness))
	var gears: Array[float] = []
	for i in maxi(target.gear_ratios.size(), 5):
		var default_g := target.gear_ratios[i] if i < target.gear_ratios.size() else 1.0
		gears.append(float(cfg.get_value("drivetrain", "gear_%d" % (i + 1), default_g)))
	target.gear_ratios = gears

	# Layout geometry is pack-owned — ignore any legacy keys in user://tuning_*.cfg.
	target.wheel_inertia = float(cfg.get_value("wheels", "wheel_inertia", target.wheel_inertia))

	var legacy_rest := float(cfg.get_value("suspension", "rest_length", target.rest_length))
	var legacy_travel := float(cfg.get_value("suspension", "travel", target.travel))
	var legacy_stiff := float(cfg.get_value("suspension", "stiffness", target.stiffness))
	var legacy_damp := float(cfg.get_value("suspension", "damping", target.damping))
	var legacy_ar := float(cfg.get_value("suspension", "anti_roll", target.anti_roll))

	target.front_rest_length = float(cfg.get_value("suspension", "front_rest_length", legacy_rest))
	target.rear_rest_length = float(cfg.get_value("suspension", "rear_rest_length", legacy_rest))
	target.front_travel = float(cfg.get_value("suspension", "front_travel", legacy_travel))
	target.rear_travel = float(cfg.get_value("suspension", "rear_travel", legacy_travel))
	target.front_stiffness = float(cfg.get_value("suspension", "front_stiffness", legacy_stiff))
	target.rear_stiffness = float(cfg.get_value("suspension", "rear_stiffness", legacy_stiff))
	target.front_damping_compression = float(cfg.get_value("suspension", "front_damping_compression", legacy_damp))
	target.rear_damping_compression = float(cfg.get_value("suspension", "rear_damping_compression", legacy_damp))
	target.front_damping_rebound = float(cfg.get_value("suspension", "front_damping_rebound", legacy_damp * 1.2))
	target.rear_damping_rebound = float(cfg.get_value("suspension", "rear_damping_rebound", legacy_damp * 1.2))
	target.front_anti_roll = float(cfg.get_value("suspension", "front_anti_roll", legacy_ar))
	target.rear_anti_roll = float(cfg.get_value("suspension", "rear_anti_roll", legacy_ar))
	target.rest_length = target.front_rest_length
	target.travel = target.front_travel
	target.stiffness = target.front_stiffness
	target.damping = target.front_damping_compression
	target.anti_roll = target.front_anti_roll

	var legacy_grip_lat := float(cfg.get_value("tires", "grip_lateral", target.grip_lateral))
	var legacy_grip_rear := float(cfg.get_value("tires", "grip_lateral_rear", target.grip_lateral_rear))
	target.tire_mu_front = float(cfg.get_value("tires", "tire_mu_front", clampf(legacy_grip_lat * 0.72, 0.8, 2.4)))
	target.tire_mu_rear = float(cfg.get_value("tires", "tire_mu_rear", clampf(legacy_grip_rear * 0.45, 0.8, 2.4)))
	target.tire_v_low = float(cfg.get_value("tires", "tire_v_low", target.tire_v_low))
	target.pacejka_b_long = float(cfg.get_value("tires", "pacejka_b_long", target.pacejka_b_long))
	target.pacejka_c_long = float(cfg.get_value("tires", "pacejka_c_long", target.pacejka_c_long))
	target.pacejka_e_long = float(cfg.get_value("tires", "pacejka_e_long", target.pacejka_e_long))
	target.pacejka_b_lat = float(cfg.get_value("tires", "pacejka_b_lat", target.pacejka_b_lat))
	target.pacejka_c_lat = float(cfg.get_value("tires", "pacejka_c_lat", target.pacejka_c_lat))
	target.pacejka_e_lat = float(cfg.get_value("tires", "pacejka_e_lat", target.pacejka_e_lat))
	target.rolling_resistance = float(cfg.get_value("tires", "rolling_resistance", target.rolling_resistance))
	target.brake_force = float(cfg.get_value("tires", "brake_force", target.brake_force))
	target.handbrake_force = float(cfg.get_value("tires", "handbrake_force", target.handbrake_force))
	target.handbrake_lat_grip = float(cfg.get_value("tires", "handbrake_lat_grip", target.handbrake_lat_grip))
	target.brake_bias_front = float(cfg.get_value("tires", "brake_bias_front", target.brake_bias_front))

	target.drag_coefficient = float(cfg.get_value("aero", "drag_coefficient", target.drag_coefficient))
	target.downforce_coefficient = float(cfg.get_value("aero", "downforce_coefficient", target.downforce_coefficient))
	target.frontal_area = float(cfg.get_value("aero", "frontal_area", target.frontal_area))

	target.max_steer_angle = float(cfg.get_value("steering", "max_steer_angle", target.max_steer_angle))
	target.steer_speed = float(cfg.get_value("steering", "steer_speed", target.steer_speed))
	target.steer_curve_max_kmh = float(cfg.get_value("steering", "steer_curve_max_kmh", target.steer_curve_max_kmh))
	target.steer_speed_ref = float(cfg.get_value("steering", "steer_speed_ref", target.steer_speed_ref))
	var hs := float(cfg.get_value("steering", "steer_high_speed_factor", target.steer_high_speed_factor))
	# Old saves kept 1.0 (= no rate damping) while soft-lock was disabled — migrate.
	if is_equal_approx(hs, 1.0) and not cfg.has_section_key("steering", "steer_input_gamma"):
		hs = 0.35
	target.steer_high_speed_factor = hs
	target.steer_input_gamma = float(cfg.get_value("steering", "steer_input_gamma", target.steer_input_gamma))
	target.counter_steer_slip_deg = float(cfg.get_value("steering", "counter_steer_slip_deg", target.counter_steer_slip_deg))
	target.counter_steer_lock_max = float(cfg.get_value("steering", "counter_steer_lock_max", target.counter_steer_lock_max))
	target.counter_steer_rate_mult = float(cfg.get_value("steering", "counter_steer_rate_mult", target.counter_steer_rate_mult))
	target.counter_steer_recover_rate = float(cfg.get_value("steering", "counter_steer_recover_rate", target.counter_steer_recover_rate))
	target.steer_lock_smooth = float(cfg.get_value("steering", "steer_lock_smooth", target.steer_lock_smooth))
	target.throttle_rise_rate = float(cfg.get_value("throttle", "throttle_rise_rate", target.throttle_rise_rate))
	target.throttle_fall_rate = float(cfg.get_value("throttle", "throttle_fall_rate", target.throttle_fall_rate))
	if cfg.has_section_key("assist", "drift_assist"):
		target.drift_assist = float(cfg.get_value("assist", "drift_assist", target.drift_assist))
	elif cfg.has_section_key("yaw", "drift_assist"):
		target.drift_assist = float(cfg.get_value("yaw", "drift_assist", target.drift_assist))
	elif cfg.has_section_key("yaw", "yaw_stability_enabled"):
		# Legacy multi-knob assist → single strength (off or default).
		target.drift_assist = 1.0 if bool(cfg.get_value("yaw", "yaw_stability_enabled", true)) else 0.0
	target.fwd_lat_priority = float(cfg.get_value("fwd", "fwd_lat_priority", target.fwd_lat_priority))
	target.fwd_slip_angle_start_deg = float(
		cfg.get_value("fwd", "fwd_slip_angle_start_deg", target.fwd_slip_angle_start_deg)
	)
	target.fwd_counter_steer_scale = float(
		cfg.get_value("fwd", "fwd_counter_steer_scale", target.fwd_counter_steer_scale)
	)
	target.fwd_recover_bleed = float(cfg.get_value("fwd", "fwd_recover_bleed", target.fwd_recover_bleed))
	target.physics_substeps = int(cfg.get_value("simulation", "physics_substeps", target.physics_substeps))
	target.traction_control = bool(cfg.get_value("simulation", "traction_control", target.traction_control))
	target.tc_slip_ratio = float(cfg.get_value("simulation", "tc_slip_ratio", target.tc_slip_ratio))
	target.tc_gain = float(cfg.get_value("simulation", "tc_gain", target.tc_gain))
	target.tc_min_scale = float(cfg.get_value("simulation", "tc_min_scale", target.tc_min_scale))
	if target.clutch_max_torque < 600.0:
		target.clutch_max_torque = 1000.0
	target.ensure_torque_curve()
	target.ensure_steer_angle_curve()
	target.migrate_legacy_fields()
