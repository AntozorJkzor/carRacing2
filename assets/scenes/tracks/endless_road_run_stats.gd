extends Node

## Endless-run score + XP (life) for hitting crossers.
## npc1 XP cost scales with time: 1 in first minute, 2 after min 1, 3 after min 2, ...

signal score_changed(score: int)
signal xp_changed(xp: float, max_xp: float)
signal xp_depleted
signal run_ended(score: int, duration_sec: float)

@export var max_xp: float = 100.0
@export var start_xp: float = 100.0
@export var npc1_score: int = 100
@export var npc1_xp_cost: float = 1.0
@export var npc2_xp_gain: float = 10.0

var score: int = 0
var xp: float = 100.0
var elapsed: float = 0.0
var _active: bool = false
var _ended: bool = false


func _ready() -> void:
	add_to_group("run_stats")
	xp = start_xp
	score = 0
	set_physics_process(false)


func start_run() -> void:
	score = 0
	xp = start_xp
	elapsed = 0.0
	_active = true
	_ended = false
	set_physics_process(true)
	score_changed.emit(score)
	xp_changed.emit(xp, max_xp)


func stop_run() -> void:
	_active = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _active and not _ended:
		elapsed += delta


func on_npc_hit(kind: String) -> void:
	if not _active or _ended:
		return
	var key := kind.to_lower()
	if key == "npc2":
		_add_xp(npc2_xp_gain)
	else:
		score += npc1_score
		score_changed.emit(score)
		_add_xp(-_npc1_xp_cost_now())


func _npc1_xp_cost_now() -> float:
	# Minute 0: base cost (1). After 1st minute: 2, after 2nd: 3, ...
	var minutes := int(floor(elapsed / 60.0))
	return npc1_xp_cost + float(minutes)


func _add_xp(delta_xp: float) -> void:
	var prev := xp
	xp = clampf(xp + delta_xp, 0.0, max_xp)
	if not is_equal_approx(prev, xp):
		xp_changed.emit(xp, max_xp)
	if prev > 0.0 and xp <= 0.0:
		_finish_run()


func _finish_run() -> void:
	if _ended:
		return
	_ended = true
	_active = false
	set_physics_process(false)
	xp_depleted.emit()
	run_ended.emit(score, elapsed)
