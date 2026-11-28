extends StaticBody2D

# Ítems que ya existen en el proyecto (todos pertenecen al grupo "Items").
const ITEM_SCENES = {
	"heal": preload("res://scenes/healing.tscn"),
	"pistol": preload("res://scenes/ammo_9_mm.tscn"),
	"shotgun": preload("res://scenes/ammo_12_gauge.tscn"),
	"m16": preload("res://scenes/ammo_m_16.tscn"),
}

# Se llama desde bullet.gd cuando la bala del jugador impacta la caja.
# La caja se destruye de un solo disparo y suelta un ítem según probabilidad:
#   50% botiquín / 50% balas
#   Si son balas: 60% pistola, 30% escopeta, 10% M16
func hit():
	var item_scene

	var roll = randf()
	if roll < 0.5:
		item_scene = ITEM_SCENES["heal"]
	else:
		var ammo_roll = randf()
		if ammo_roll < 0.6:
			item_scene = ITEM_SCENES["pistol"]
		elif ammo_roll < 0.9:
			item_scene = ITEM_SCENES["shotgun"]
		else:
			item_scene = ITEM_SCENES["m16"]

	var item = item_scene.instantiate()
	item.global_position = global_position
	get_parent().add_child(item)

	queue_free()
