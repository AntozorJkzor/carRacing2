extends CanvasLayer

## Pause overlay on the track. Class: PauseMenu → CanvasLayer.
## Scene: res://assets/scenes/ui/pause_menu.tscn
## Signals connected in _ready().

signal resumed
signal exit_to_menu
signal quit_requested

const SETTINGS_OVERLAY_SCENE := preload("res://assets/scenes/ui/settings_overlay.tscn")

@onready var _root: Control = %Root
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _menu_button: Button = %MenuButton
@onready var _exit_button: Button = %ExitButton

var _settings_overlay: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_continue_button.grab_focus()


func close() -> void:
	if _settings_overlay != null and _settings_overlay.has_method("is_open") and _settings_overlay.is_open():
		_settings_overlay.close()
	visible = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _settings_overlay != null and _settings_overlay.has_method("is_open") and _settings_overlay.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_continue_pressed() -> void:
	close()


func _on_settings_pressed() -> void:
	_root.visible = false
	if _settings_overlay == null:
		_settings_overlay = SETTINGS_OVERLAY_SCENE.instantiate()
		add_child(_settings_overlay)
		_settings_overlay.closed.connect(_on_settings_closed)
	_settings_overlay.open()


func _on_settings_closed() -> void:
	if not visible:
		return
	_root.visible = true
	_settings_button.grab_focus()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	exit_to_menu.emit()
	get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().paused = false
	quit_requested.emit()
	get_tree().quit()
