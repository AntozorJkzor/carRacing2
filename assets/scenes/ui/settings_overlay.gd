extends CanvasLayer

## In-game settings stack (pause overlay). Keeps the track loaded.
## Group: settings_overlay_host — settings pages call push_page / pop_page.

signal closed

var _stack: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false
	add_to_group("settings_overlay_host")


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_clear_stack()
	push_page("res://assets/scenes/ui/settings_hub.tscn")


func push_page(path: String) -> void:
	if not _stack.is_empty():
		_stack.back().visible = false
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("SettingsOverlay: failed to load %s" % path)
		return
	var page := packed.instantiate() as Control
	if page == null:
		push_error("SettingsOverlay: root is not Control: %s" % path)
		return
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	_stack.append(page)


func pop_page() -> void:
	if _stack.is_empty():
		close()
		return
	var top: Control = _stack.pop_back()
	top.queue_free()
	if _stack.is_empty():
		close()
		return
	_stack.back().visible = true


func close() -> void:
	_clear_stack()
	visible = false
	closed.emit()


func _clear_stack() -> void:
	for page: Control in _stack:
		if is_instance_valid(page):
			page.queue_free()
	_stack.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		pop_page()
		get_viewport().set_input_as_handled()
