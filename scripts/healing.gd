extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		var player_scene = get_tree().get_nodes_in_group("Player")[0]
		if player_scene:
			var healed_amount = 0
			if player_scene.get_node("HUD/Health").points[1].x <= 80:
				player_scene.get_node("HUD/Health").points[1].x +=20
				healed_amount = 20
				#queue_free()
			elif player_scene.get_node("HUD/Health").points[1].x == 90:
				player_scene.get_node("HUD/Health").points[1].x +=10
				healed_amount = 10
				#queue_free()
			else:
				player_scene.get_node("HUD/Health").points[1].x +=0
				healed_amount = 0
			if healed_amount > 0:
				Global.health_picked_up.emit(healed_amount)
				queue_free()
				var parent = get_parent()
				if parent:
					parent.queue_free()
