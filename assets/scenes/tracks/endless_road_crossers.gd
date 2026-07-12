extends Node

## After gameplay starts: spawn npc1/npc2 across the road; after 1 min also from the sky.
## Mass flood: after 20s if under early_kmh; after 2 min if under late_kmh.

@export var npc_scene: PackedScene
@export var npc2_scene: PackedScene
@export var car_path: NodePath
@export var road_path: NodePath
@export var spawn_interval_min: float = 0.7
@export var spawn_interval_max: float = 1.8
@export var spawn_ahead_min: float = 28.0
@export var spawn_ahead_max: float = 70.0
@export var shoulder_extra: float = 3.5
@export var max_alive: int = 18
@export var max_alive_cap: int = 36
@export var cross_speed_min: float = 6.5
@export var cross_speed_max: float = 9.5
@export var npc2_chance: float = 0.08
@export var rate_grow_per_sec: float = 0.045
@export var rate_multiplier_max: float = 4.5
@export var sky_drop_after_sec: float = 60.0
@export var sky_drop_chance: float = 0.45
@export var sky_drop_ahead_mult: float = 3.0
@export var sky_drop_height_min: float = 22.0
@export var sky_drop_height_max: float = 38.0
@export var slow_punish_early_after_sec: float = 20.0
@export var slow_punish_early_below_kmh: float = 100.0
@export var slow_punish_late_after_sec: float = 120.0
@export var slow_punish_late_below_kmh: float = 200.0
@export var slow_punish_spawn_mult: float = 200.0
@export var slow_punish_alive_cap: int = 700
@export var slow_punish_sky_chance: float = 0.55
@export var slow_punish_chase_speed_min: float = 9.0
@export var slow_punish_chase_speed_max: float = 13.5
@export var slow_punish_burst_min: int = 50
@export var slow_punish_burst_max: int = 90
@export var terror_subtitle_path: NodePath
@export var terror_subtitle_text: String = "О НЕТ, ЭЛ УЗНАЛ ЧТО Я КИРА"

var _car: Node3D
var _road: Node3D
var _enabled: bool = false
var _timer: float = 0.0
var _elapsed: float = 0.0
var _rate_mult: float = 1.0
var _rng := RandomNumberGenerator.new()
var _alive: Array[Node3D] = []
var _punish_active: bool = false
var _terror_layer: CanvasLayer
var _terror_label: Label
var _flood_remaining: int = 0


func _ready() -> void:
	_rng.randomize()
	if car_path != NodePath():
		_car = get_node_or_null(car_path) as Node3D
	if road_path != NodePath():
		_road = get_node_or_null(road_path) as Node3D
	if terror_subtitle_path != NodePath():
		_terror_layer = get_node_or_null(terror_subtitle_path) as CanvasLayer
		if _terror_layer:
			_terror_label = _terror_layer.get_node_or_null("Panel/Label") as Label
			_terror_layer.visible = false
	set_physics_process(false)


func start_spawning() -> void:
	_enabled = true
	_elapsed = 0.0
	_rate_mult = 1.0
	_punish_active = false
	_flood_remaining = 0
	_timer = _rng.randf_range(0.2, 0.8)
	_set_terror_ui(false)
	set_physics_process(true)


func stop_spawning() -> void:
	_enabled = false
	_set_punish_state(false)
	set_physics_process(false)
	_clear_all()


func get_elapsed() -> float:
	return _elapsed


func _physics_process(delta: float) -> void:
	if not _enabled or _car == null:
		return
	_elapsed += delta
	_rate_mult = clampf(1.0 + _elapsed * rate_grow_per_sec, 1.0, rate_multiplier_max)
	_cleanup_finished()
	_timer -= delta
	var punish := _is_slow_punish()
	_set_punish_state(punish)
	var spawn_mult := _rate_mult
	if punish:
		spawn_mult *= slow_punish_spawn_mult
	var alive_cap := mini(max_alive_cap, max_alive + int(_elapsed / 12.0))
	if punish:
		alive_cap = maxi(alive_cap, slow_punish_alive_cap)
		_drain_flood(alive_cap)
	if _timer <= 0.0 and _alive.size() < alive_cap:
		var burst := 1
		if punish:
			burst = _rng.randi_range(slow_punish_burst_min, slow_punish_burst_max)
		else:
			if _rate_mult > 2.0 and _rng.randf() < 0.35:
				burst = 2
			if _rate_mult > 3.2 and _rng.randf() < 0.25:
				burst = 3
		for _i in range(burst):
			if _alive.size() >= alive_cap:
				break
			_spawn_one(punish)
		var base := _rng.randf_range(spawn_interval_min, spawn_interval_max)
		var min_gap := 0.0 if punish else 0.18
		_timer = maxf(min_gap, base / spawn_mult)


func _is_slow_punish() -> bool:
	var kmh := _car_speed_kmh()
	# After 2 min: keep speed above 200 km/h or get flooded.
	if _elapsed >= slow_punish_late_after_sec:
		return kmh < slow_punish_late_below_kmh
	# After 20 sec: keep speed above 100 km/h or get flooded.
	if _elapsed >= slow_punish_early_after_sec:
		return kmh < slow_punish_early_below_kmh
	return false


func _set_punish_state(active: bool) -> void:
	if active == _punish_active:
		return
	_punish_active = active
	_set_terror_ui(active)
	if active:
		if GameAudio and GameAudio.has_method("play_terror_music"):
			GameAudio.play_terror_music()
		# Ramp to 500–700 npc1 without spawning them all in one frame.
		var target := _rng.randi_range(500, mini(700, slow_punish_alive_cap))
		_flood_remaining = maxi(0, target - _alive.size())
		_timer = 0.0
	else:
		_flood_remaining = 0
		if GameAudio and GameAudio.has_method("stop_terror_music"):
			GameAudio.stop_terror_music()


func _drain_flood(alive_cap: int) -> void:
	if _flood_remaining <= 0:
		return
	var chunk := mini(45, _flood_remaining)
	for _i in range(chunk):
		if _alive.size() >= alive_cap:
			_flood_remaining = 0
			return
		_spawn_one(true)
		_flood_remaining -= 1


func _set_terror_ui(visible_now: bool) -> void:
	if _terror_layer:
		_terror_layer.visible = visible_now
	if _terror_label and visible_now:
		_terror_label.text = terror_subtitle_text


func _car_speed_kmh() -> float:
	if _car == null:
		return 0.0
	if _car.has_method("get_speed_kmh"):
		return float(_car.call("get_speed_kmh"))
	if _car is RigidBody3D:
		return (_car as RigidBody3D).linear_velocity.length() * 3.6
	return 0.0


func _spawn_one(punish: bool = false) -> void:
	var scene := npc_scene
	# Slow-punish flood is npc1 only.
	if not punish and npc2_scene != null and _rng.randf() < npc2_chance:
		scene = npc2_scene
	if scene == null:
		return
	var kind := "npc2" if scene == npc2_scene else "npc1"
	var road_half := 8.0
	if _road != null and "road_width" in _road:
		road_half = float(_road.get("road_width")) * 0.5

	var use_sky := false
	if punish:
		use_sky = _rng.randf() < slow_punish_sky_chance
	elif _elapsed >= sky_drop_after_sec:
		use_sky = _rng.randf() < sky_drop_chance

	var ahead := _rng.randf_range(spawn_ahead_min, spawn_ahead_max)
	if use_sky:
		ahead *= sky_drop_ahead_mult
	elif punish:
		ahead = _rng.randf_range(spawn_ahead_min * 0.55, spawn_ahead_max * 0.9)
	var z := _car.global_position.z + ahead

	var npc := scene.instantiate() as Node3D
	if npc == null:
		return
	add_child(npc)

	if punish:
		var chase_speed := _rng.randf_range(slow_punish_chase_speed_min, slow_punish_chase_speed_max)
		if use_sky and npc.has_method("setup_sky_chase"):
			var x := _rng.randf_range(-road_half * 1.1, road_half * 1.1)
			var height := _rng.randf_range(sky_drop_height_min, sky_drop_height_max)
			npc.call("setup_sky_chase", x, z, _car, kind, height, chase_speed)
		elif npc.has_method("setup_chase"):
			var from_side := -1 if _rng.randf() < 0.5 else 1
			# Mix sides and some ahead/behind offsets so they swarm the car.
			var from_x := float(from_side) * (road_half + shoulder_extra + _rng.randf_range(0.0, 6.0))
			var from_z := z + _rng.randf_range(-8.0, 8.0)
			npc.call("setup_chase", Vector3(from_x, 0.0, from_z), _car, chase_speed, kind)
		else:
			npc.global_position = Vector3(0.0, 0.0, z)
			if "npc_kind" in npc:
				npc.npc_kind = kind
	elif use_sky and npc.has_method("setup_sky_drop"):
		var x := _rng.randf_range(-road_half * 0.85, road_half * 0.85)
		var height := _rng.randf_range(sky_drop_height_min, sky_drop_height_max)
		npc.call("setup_sky_drop", x, z, kind, height)
	else:
		var from_side := -1 if _rng.randf() < 0.5 else 1
		var from_x := float(from_side) * (road_half + shoulder_extra)
		var to_x := float(-from_side) * (road_half + shoulder_extra)
		var speed := _rng.randf_range(cross_speed_min, cross_speed_max)
		speed *= lerpf(1.0, 1.2, clampf((_rate_mult - 1.0) / maxf(rate_multiplier_max - 1.0, 0.01), 0.0, 1.0))
		if npc.has_method("setup_cross"):
			npc.call("setup_cross", from_x, to_x, z, speed, "run", kind)
		else:
			npc.global_position = Vector3(from_x, 0.0, z)
			if "npc_kind" in npc:
				npc.npc_kind = kind
	_alive.append(npc)


func _cleanup_finished() -> void:
	var kept: Array[Node3D] = []
	for npc in _alive:
		if not is_instance_valid(npc):
			continue
		var finished := false
		if npc.has_method("is_finished"):
			finished = bool(npc.call("is_finished"))
		if _car and npc.global_position.z < _car.global_position.z - 40.0:
			finished = true
		if finished:
			npc.queue_free()
		else:
			kept.append(npc)
	_alive = kept


func _clear_all() -> void:
	for npc in _alive:
		if is_instance_valid(npc):
			npc.queue_free()
	_alive.clear()
