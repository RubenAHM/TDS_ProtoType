extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("add_9mm_ammo"):
		body.add_9mm_ammo(60)
		queue_free()
		var parent = get_parent()
		if parent:
			parent.queue_free()
