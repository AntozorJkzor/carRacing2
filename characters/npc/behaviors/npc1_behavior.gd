class_name Npc1Behavior
extends NpcBehavior

## Random wander + jump. Sits when the player gets close.

@export var react_distance: float = 5.0


func physics_tick(npc: NpcController, delta: float) -> void:
	var player := npc.get_player()
	if player != null and npc.distance_to_node(player) <= react_distance:
		npc.stop_moving()
		npc.face_towards(player.global_position)
		npc.play_anim(npc.anim_sit)
		npc.tick_gravity_and_slide(delta)
		return

	npc.tick_wander(delta)
	if npc.is_moving_horizontally():
		npc.play_anim(npc.anim_run)
	else:
		npc.play_anim(npc.anim_sit)
