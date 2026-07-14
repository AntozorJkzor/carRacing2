extends Node3D


func _ready() -> void:
	GameAudio.restart_music()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")
