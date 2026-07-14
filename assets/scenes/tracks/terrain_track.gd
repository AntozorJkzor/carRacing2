extends Node3D

## Fun-mode map: Terrain3D demo landscape with Volga.


func _ready() -> void:
	GameAudio.restart_music()
	await get_tree().process_frame
	var player := get_node_or_null("Player") as PlayerController
	var car := get_node_or_null("Car") as CarController
	if player != null and car != null:
		player.force_enter_car(car)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://assets/scenes/ui/main_menu.tscn")
