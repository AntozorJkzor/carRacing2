extends Node3D

const PAUSE_MENU_SCENE := preload("res://assets/scenes/ui/pause_menu.tscn")

var _bootstrap_layer: CanvasLayer
var _pause_menu: CanvasLayer


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	call_deferred("_apply_graphics")
	call_deferred("_bootstrap_engine_sounds")
	GameAudio.restart_music()
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)


func _apply_graphics() -> void:
	GraphicsConfig.apply_all(get_tree())


func _bootstrap_engine_sounds() -> void:
	if not EngineBankBaker.has_engine_sim():
		return
	## Quick check first — don't flash the bake UI when banks are already valid.
	var pending: Array[StringName] = TuningStore.cars_needing_engine_bake()
	if pending.is_empty():
		TuningStore.refresh_all_car_engine_audio()
		return
	_show_bootstrap_ui()
	var on_progress := Callable(self, "_on_engine_bake_progress")
	if not TuningStore.engine_bake_progress.is_connected(on_progress):
		TuningStore.engine_bake_progress.connect(on_progress)
	var result: Dictionary = await TuningStore.ensure_engine_sounds_on_startup(pending)
	if TuningStore.engine_bake_progress.is_connected(on_progress):
		TuningStore.engine_bake_progress.disconnect(on_progress)
	_hide_bootstrap_ui()
	if int(result.get("baked", 0)) > 0:
		print(
			"PhysicsTestTrack: generated engine sounds for %d car(s)" % int(result.get("baked", 0))
		)


func _show_bootstrap_ui() -> void:
	if _bootstrap_layer != null:
		return
	_bootstrap_layer = CanvasLayer.new()
	_bootstrap_layer.layer = 100
	add_child(_bootstrap_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.82)
	dim.name = "Dim"
	_bootstrap_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220.0
	panel.offset_top = -72.0
	panel.offset_right = 220.0
	panel.offset_bottom = 72.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18.0
	style.content_margin_top = 14.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	_bootstrap_layer.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "Preparing engine sounds…"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var status := Label.new()
	status.name = "Status"
	status.text = "Checking…"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	box.add_child(status)

	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.custom_minimum_size = Vector2(360.0, 18.0)
	bar.show_percentage = false
	bar.value = 0.0
	box.add_child(bar)


func _hide_bootstrap_ui() -> void:
	if _bootstrap_layer != null:
		_bootstrap_layer.queue_free()
		_bootstrap_layer = null


func _on_engine_bake_progress(current: int, total: int, rpm: float, phase: String) -> void:
	if _bootstrap_layer == null:
		return
	var panel := _bootstrap_layer.get_node_or_null("Panel")
	if panel == null:
		return
	var status: Label = panel.get_node_or_null("VBox/Status") as Label
	var bar: ProgressBar = panel.get_node_or_null("VBox/Progress") as ProgressBar
	if bar != null:
		bar.max_value = maxf(float(maxi(total, 1)), 1.0)
		bar.value = clampf(float(current), 0.0, bar.max_value)
	if status == null:
		return
	if phase.begins_with("car|"):
		var parts := phase.split("|")
		var car_name := parts[1] if parts.size() > 1 else "?"
		var step := parts[2] if parts.size() > 2 else "start"
		match step:
			"start":
				status.text = "Car %s — checking…" % car_name
			"sweep":
				status.text = "Car %s — synthesizing sweep…" % car_name
			"promote":
				status.text = "Car %s — saving…" % car_name
			"apply":
				status.text = "Car %s — applying…" % car_name
			_:
				status.text = "Car %s…" % car_name
		return
	match phase:
		"check":
			status.text = "Checking sound cache…"
		"cached":
			status.text = "Sound already exists — skipping"
		"start":
			status.text = "Preparing sweep bake…"
		"sweep":
			status.text = "Synthesizing sweep up to %.0f rpm…" % rpm
		"promote":
			status.text = "Saving banks…"
		"apply":
			status.text = "Applying to cars…"
		"error":
			status.text = "Sound generation error"
		"done":
			status.text = "Done"
		_:
			status.text = phase


func _unhandled_input(event: InputEvent) -> void:
	if _bootstrap_layer != null:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _pause_menu != null and _pause_menu.has_method("is_open") and _pause_menu.is_open():
		return
	if _pause_menu != null and _pause_menu.has_method("open"):
		_pause_menu.open()
		get_viewport().set_input_as_handled()
