class_name Npc2Behavior
extends NpcBehavior

## Random wander + jump. Chases and fights when the player gets close.

@export var react_distance: float = 8.0
@export var fight_distance: float = 1.8
@export var chase_speed_mult: float = 1.15


func physics_tick(npc: NpcController, delta: float) -> void:
	var player := npc.get_player()
	if player != null and npc.distance_to_node(player) <= react_distance:
		var dist := npc.distance_to_node(player)
		npc.face_towards(player.global_position)
		if dist <= fight_distance:
			npc.stop_moving()
			npc.play_anim(npc.anim_fight)
		else:
			npc.move_towards(player.global_position, npc.run_speed * chase_speed_mult)
			npc.play_anim(npc.anim_run)
		npc.tick_gravity_and_slide(delta)
		return

	npc.tick_wander(delta)
	if npc.is_moving_horizontally():
		npc.play_anim(npc.anim_run)
	else:
		npc.play_anim(npc.anim_run)
