class_name TuningParts
extends RefCounted

## Upgrade parts catalog: 8 categories × (stock + 3 levels).
## All level effects are computed from the car's CURRENT pack setup, so every
## car stays balanced relative to its own base stats.

const CATEGORIES: Array[String] = [
	"engine", "ecu", "gearbox", "suspension", "tires", "brakes", "nos", "turbo",
]


static func category_label(category: String) -> String:
	return Lang.t("part.%s" % category)


## Level display name (0 = stock). Level names are per-category.
static func level_label(category: String, level: int) -> String:
	if level == 0:
		return Lang.t("part.stock")
	return Lang.t("partname.%s.%d" % [category, level])


## Short flavor line for the selected level (RU/EN).
static func level_desc(category: String, level: int) -> String:
	return Lang.t("partdesc.%s.%d" % [category, level])


## Apply one category level onto a CarSetup (mutates it).
## Level 0 = stock → no-op (the setup was rebuilt from the pack).
static func apply(setup: CarSetup, category: String, level: int) -> void:
	if level <= 0:
		return
	match category:
		"engine":
			var hp := setup.max_power_hp
			match level:
				1:
					setup.max_power_hp = roundf(hp * 1.12)
					setup.max_rpm += 150.0
					setup.noise = minf(setup.noise + 0.04, 2.0)
				2:
					setup.max_power_hp = roundf(hp * 1.28)
					setup.max_rpm += 350.0
					setup.engine_sound_volume_db += 0.5
					setup.noise = minf(setup.noise + 0.08, 2.0)
				3:
					setup.max_power_hp = roundf(hp * 1.5)
					setup.max_rpm += 650.0
					setup.engine_sound_volume_db += 1.0
					setup.hf_gain = minf(setup.hf_gain + 0.04, 1.0)
					setup.noise = minf(setup.noise + 0.12, 2.0)
			setup.max_power_kw = setup.max_power_hp * CarSetup.KW_PER_HP
		"ecu":
			match level:
				1:
					setup.max_rpm *= 1.03
					setup.throttle_rise_rate = maxf(setup.throttle_rise_rate, 3.0)
				2:
					setup.max_rpm *= 1.06
					setup.throttle_rise_rate = maxf(setup.throttle_rise_rate, 3.8)
					setup.rev_limiter_cut_high_frac = minf(setup.rev_limiter_cut_high_frac + 0.01, 1.02)
				3:
					setup.max_rpm *= 1.1
					setup.throttle_rise_rate = maxf(setup.throttle_rise_rate, 4.6)
					setup.throttle_fall_rate = maxf(setup.throttle_fall_rate, 7.0)
					setup.rev_limiter_cut_high_frac = minf(setup.rev_limiter_cut_high_frac + 0.02, 1.03)
		"gearbox":
			var ratio_scale := 1.0
			match level:
				1:
					ratio_scale = 0.96
					setup.shift_time = maxf(setup.shift_time * 0.8, 0.06)
				2:
					ratio_scale = 0.91
					setup.shift_time = maxf(setup.shift_time * 0.62, 0.05)
				3:
					ratio_scale = 0.86
					setup.shift_time = maxf(setup.shift_time * 0.5, 0.04)
					setup.final_drive *= 1.04
			for i in setup.gear_ratios.size():
				setup.gear_ratios[i] = setup.gear_ratios[i] * ratio_scale
		"suspension":
			var stiff := 1.0
			var damp := 1.0
			var bar := 1.0
			var drop := 0.0
			match level:
				1:
					stiff = 1.15
					damp = 1.15
					bar = 1.2
					drop = 0.02
				2:
					stiff = 1.32
					damp = 1.32
					bar = 1.42
					drop = 0.04
				3:
					stiff = 1.5
					damp = 1.5
					bar = 1.65
					drop = 0.06
			setup.front_stiffness *= stiff
			setup.rear_stiffness *= stiff
			setup.front_damping_compression *= damp
			setup.front_damping_rebound *= damp
			setup.rear_damping_compression *= damp
			setup.rear_damping_rebound *= damp
			setup.front_anti_roll *= bar
			setup.rear_anti_roll *= bar
			setup.front_rest_length = maxf(setup.front_rest_length - drop, 0.2)
			setup.rear_rest_length = maxf(setup.rear_rest_length - drop, 0.2)
			# Keep legacy single-axle mirrors in sync.
			setup.stiffness = setup.front_stiffness
			setup.damping = setup.front_damping_compression
			setup.anti_roll = setup.front_anti_roll
			setup.rest_length = setup.front_rest_length
		"tires":
			var mu := 0.0
			var bite := 0.0
			match level:
				1:
					mu = 0.08
					bite = 0.4
				2:
					mu = 0.16
					bite = 0.8
				3:
					mu = 0.26
					bite = 1.3
			setup.tire_mu_front += mu
			setup.tire_mu_rear += mu
			setup.pacejka_b_lat += bite
		"brakes":
			match level:
				1:
					setup.brake_force *= 1.15
					setup.brake_bias_front = maxf(setup.brake_bias_front - 0.01, 0.55)
				2:
					setup.brake_force *= 1.32
					setup.brake_bias_front = maxf(setup.brake_bias_front - 0.02, 0.55)
					setup.handbrake_force *= 1.1
				3:
					setup.brake_force *= 1.5
					setup.brake_bias_front = maxf(setup.brake_bias_front - 0.03, 0.55)
					setup.handbrake_force *= 1.2
		"nos":
			match level:
				1:
					setup.nos_power_add = 60.0
				2:
					setup.nos_power_add = 110.0
				3:
					setup.nos_power_add = 170.0
		"turbo":
			setup.turbo_level = level
			# Turbo hardware adds a little static power on top of boost.
			setup.max_power_hp = roundf(setup.max_power_hp * (1.0 + 0.04 * level))
			setup.max_power_kw = setup.max_power_hp * CarSetup.KW_PER_HP


## Simple stat line shown in the UI for a level (RU/EN via Lang).
static func stat_line(category: String, level: int) -> String:
	if level == 0:
		return Lang.t("partstat.stock")
	return Lang.t("partstat.%s.%d" % [category, level])
