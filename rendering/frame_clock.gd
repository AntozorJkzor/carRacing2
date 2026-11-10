class_name FrameClock
extends RefCounted

## Adds microseconds spent in named scopes. The frame analyzer reads and clears this.

static var _usec: Dictionary = {}


static func add(bucket: String, usec: int) -> void:
	if usec <= 0:
		return
	var prev: int = int(_usec.get(bucket, 0))
	_usec[bucket] = prev + usec


## Times fn(arg) and adds elapsed µs to bucket. One-liner process wrappers:
##     FrameClock.measure("proc:engine_audio", _profiled_process, delta)
static func measure(bucket: String, fn: Callable, arg: Variant = null) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call(arg)
	add(bucket, Time.get_ticks_usec() - t0)


static func take() -> Dictionary:
	var snap: Dictionary = _usec.duplicate()
	_usec.clear()
	return snap
