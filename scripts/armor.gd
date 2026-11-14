extends Area2D

const MAX_ARMOR = 100

@onready var player = get_tree().get_first_node_in_group("Player")
@onready var armor_bar = player.get_node("HUD/Armor") if player != null else null

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	
	if armor_bar == null:
		return

	var current_armor = armor_bar.points[1].x
	if current_armor >= MAX_ARMOR:
		return  # Ya tiene armadura máxima

	var amount_to_add = MAX_ARMOR - current_armor
	armor_bar.points[1].x = MAX_ARMOR

	Global.armor_picked_up.emit(amount_to_add)
	queue_free()
	var parent = get_parent()
	if parent:
		parent.queue_free()
