extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("add_m16_ammo"):
		body.add_m16_ammo(45)
		queue_free()
		var parent = get_parent()
		if parent:
			parent.queue_free()
