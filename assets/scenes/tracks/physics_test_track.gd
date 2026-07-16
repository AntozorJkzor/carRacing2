extends Node3D


func _ready() -> void:
	GraphicsConfig.load_from_disk()
	# After scene nodes (WorldEnvironment / Sun) are ready.
	call_deferred("_apply_graphics")
	GameAudio.restart_music()


func _apply_graphics() -> void:
	GraphicsConfig.apply_all(get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")
