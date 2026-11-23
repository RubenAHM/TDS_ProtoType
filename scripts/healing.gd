extends Area2D

const MAX_LIFE = 100

@onready var player = get_tree().get_first_node_in_group("Player")
@onready var life_bar = player.get_node("HUD/Health") if player != null else null

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	
	if life_bar == null:
		return

	var current_life = life_bar.points[1].x
	if current_life >= MAX_LIFE:
		return  

	var amount_to_add = MAX_LIFE - current_life
	life_bar.points[1].x = MAX_LIFE

	Global.health_picked_up.emit(amount_to_add)
	queue_free()
	var parent = get_parent()
	if parent:
		parent.queue_free()
