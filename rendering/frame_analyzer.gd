class_name FrameAnalyzer
extends CanvasLayer

## On-screen frame breakdown. Toggle with F4.
## Splits the frame into physics, measured scripts, and draw calls
## (main view, shadow passes, minimap).

const _WINDOW_SEC := 0.4
const _LOG_PATH := "res://frame_analyzer.log"

var _label: Label
var _visible_panel: bool = false
var _accum: float = 0.0
var _frames: int = 0
var _frame_ms_sum: float = 0.0
var _worst_ms: float = 0.0
var _phys_sum: float = 0.0
var _proc_sum: float = 0.0
var _buckets: Dictionary = {}
var _main_visible_draws: int = 0
var _main_shadow_draws: int = 0
var _main_visible_prims: int = 0
var _main_shadow_prims: int = 0
var _mini_visible_draws: int = 0
var _mini_shadow_draws: int = 0
var _mini_visible_prims: int = 0
var _subviews: Array[SubViewport] = []
var _subviews_ready: bool = false


func _ready() -> void:
	layer = 30
	_label = Label.new()
	_label.name = "Report"
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.offset_left = 12.0
	_label.offset_top = 48.0
	_label.offset_right = 560.0
	_label.offset_bottom = 640.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.92))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_label.visible = _visible_panel
	_label.text = "Анализ кадра…  F4 показать"
	_start_log()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F4:
			_visible_panel = not _visible_panel
			_label.visible = _visible_panel
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_frames += 1
	var frame_ms := delta * 1000.0
	_frame_ms_sum += frame_ms
	if frame_ms > _worst_ms:
		_worst_ms = frame_ms
	_phys_sum += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_proc_sum += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_sample_viewports()
	var snap: Dictionary = FrameClock.take()
	for key in snap.keys():
		var name := str(key)
		_buckets[name] = int(_buckets.get(name, 0)) + int(snap[key])
	_accum += delta
	if _accum < _WINDOW_SEC:
		return
	_publish()
	_reset_window()


func _sample_viewports() -> void:
	var root := get_tree().root
	if root == null:
		return
	_main_visible_draws = _draws(root, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE)
	_main_shadow_draws = _draws(root, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW)
	_main_visible_prims = _prims(root, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE)
	_main_shadow_prims = _prims(root, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW)
	if not _subviews_ready:
		var scene := get_tree().current_scene
		if scene == null:
			return
		_subviews_ready = true
		for node in scene.find_children("*", "SubViewport", true, false):
			var vp := node as SubViewport
			if vp != null:
				_subviews.append(vp)
	_mini_visible_draws = 0
	_mini_shadow_draws = 0
	_mini_visible_prims = 0
	for vp in _subviews:
		_mini_visible_draws += _draws(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE)
		_mini_shadow_draws += _draws(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW)
		_mini_visible_prims += _prims(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE)


func _draws(vp: Viewport, kind: int) -> int:
	return RenderingServer.viewport_get_render_info(
		vp.get_viewport_rid(),
		kind,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	)


func _prims(vp: Viewport, kind: int) -> int:
	return RenderingServer.viewport_get_render_info(
		vp.get_viewport_rid(),
		kind,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	)


func _publish() -> void:
	var n := maxi(_frames, 1)
	var frame_ms := _frame_ms_sum / float(n)
	var phys_ms := _phys_sum / float(n)
	var proc_ms := _proc_sum / float(n)
	var fps := 1000.0 / maxf(frame_ms, 0.001)
	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("КАДР  %d fps   %.1f мс   худший %.1f    F4 скрыть" % [int(round(fps)), frame_ms, _worst_ms])
	lines.append("Физика движка      %6.2f мс   (тик %d Гц)" % [phys_ms, ticks])
	lines.append("Кадр без физики    %6.2f мс   скрипты _process + отрисовка" % proc_ms)
	lines.append("")
	lines.append("Скрипты, мс на кадр:")
	var shown := 0
	for row in _sorted_buckets(n):
		if shown >= 8:
			break
		var ms: float = float(row[1]) / 1000.0
		if ms < 0.05:
			continue
		lines.append("  %-22s %6.2f" % [str(row[0]), ms])
		shown += 1
	if shown == 0:
		lines.append("  (пока пусто)")
	lines.append("")
	lines.append("Вызовы отрисовки   сцена %d   тени %d   миникарта %d" % [
		_main_visible_draws, _main_shadow_draws, _mini_visible_draws,
	])
	if _mini_shadow_draws > 0:
		lines.append("Тени миникарты     %d" % _mini_shadow_draws)
	lines.append("Треугольники       сцена %d   тени %d   миникарта %d" % [
		_main_visible_prims, _main_shadow_prims, _mini_visible_prims,
	])
	lines.append("Физика 3D          тел %d   пар столкновений %d" % [
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
	])
	lines.append(_census_line())
	lines.append("")
	lines.append(_verdict(frame_ms, phys_ms, proc_ms, n))
	var text := "\n".join(lines)
	if _visible_panel:
		_label.text = text
	_write_log(text)


func _start_log() -> void:
	var file := FileAccess.open(_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Frame analyzer log failed: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_line("frame analyzer  %s" % Time.get_datetime_string_from_system())
	file.store_line("")
	file.close()


func _write_log(text: String) -> void:
	var file := FileAccess.open(_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("--- %s" % Time.get_datetime_string_from_system(false, true))
	file.store_string(text)
	file.store_line("")
	file.store_line("")
	file.close()


func _sorted_buckets(frames: int) -> Array:
	var rows: Array = []
	for key in _buckets.keys():
		var per_frame := int(_buckets[key]) / maxi(frames, 1)
		rows.append([str(key), per_frame])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return rows


func _census_line() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return "Сцена ещё не готова"
	var meshes := scene.find_children("*", "MeshInstance3D", true, false).size()
	var lights := 0
	var shadow_lights := 0
	for node in scene.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light == null:
			continue
		lights += 1
		if light.shadow_enabled:
			shadow_lights += 1
	var particles := 0
	var emitting := 0
	for node in scene.find_children("*", "GPUParticles3D", true, false):
		var p := node as GPUParticles3D
		if p == null:
			continue
		particles += 1
		if p.emitting:
			emitting += 1
	return "Сцена  мешей %d   ламп %d (с тенью %d)   частиц %d/%d" % [
		meshes, lights, shadow_lights, emitting, particles,
	]


func _verdict(frame_ms: float, phys_ms: float, proc_ms: float, frames: int) -> String:
	var car_ms := _bucket_ms("phys:car", frames)
	var script_phys := _sum_prefix("phys:", frames) 
	var script_proc := _sum_prefix("proc:", frames)
	if phys_ms >= frame_ms * 0.4:
		if car_ms >= phys_ms * 0.45:
			return "Причина: физика машины, %.1f мс из %.1f мс кадра. Частота физики %d Гц." % [
				car_ms, frame_ms, int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")),
			]
		return "Причина: физика, %.1f мс. Скрипты физики %.1f мс, машина %.1f мс." % [
			phys_ms, script_phys, car_ms,
		]
	if _main_shadow_draws > _main_visible_draws and _main_shadow_draws > 40:
		return "Причина: теневые проходы, %d вызовов против %d у обычной картинки." % [
			_main_shadow_draws, _main_visible_draws,
		]
	if _mini_visible_draws > 30 and _mini_visible_draws * 2 > _main_visible_draws:
		return "Причина: миникарта рисует мир второй раз, %d вызовов." % _mini_visible_draws
	var render_left := proc_ms - script_proc
	if render_left >= frame_ms * 0.45:
		return "Причина: отрисовка, около %.1f мс. Скрипты _process всего %.1f мс." % [
			render_left, script_proc,
		]
	if script_proc + script_phys >= frame_ms * 0.35:
		return "Причина: скрипты, %.1f мс. Смотрите список выше." % [script_proc + script_phys]
	return "Явного одного виновника нет. Сравните миллисекунды и вызовы отрисовки."


func _bucket_ms(bucket: String, frames: int) -> float:
	return float(int(_buckets.get(bucket, 0))) / 1000.0 / float(maxi(frames, 1))


func _sum_prefix(prefix: String, frames: int) -> float:
	var usec := 0
	for key in _buckets.keys():
		if str(key).begins_with(prefix):
			usec += int(_buckets[key])
	return float(usec) / 1000.0 / float(maxi(frames, 1))


func _reset_window() -> void:
	_accum = 0.0
	_frames = 0
	_frame_ms_sum = 0.0
	_worst_ms = 0.0
	_phys_sum = 0.0
	_proc_sum = 0.0
	_buckets.clear()
