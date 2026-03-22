extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("add_gauge_ammo"):
		body.add_gauge_ammo(7)
		queue_free()
		var parent = get_parent()
		if parent:
			parent.queue_free()
