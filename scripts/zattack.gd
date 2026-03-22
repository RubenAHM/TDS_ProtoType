extends CharacterBody2D
var SPEED = 0
var direction = Vector2.RIGHT  # Variable para almacenar la dirección
var parent
var sprite
var colision
var hitbox
var spawn_position: Vector2
var cooldown = 0.2
#@onready var melee = $atked

func _ready() -> void:
	#print("atacado")
	spawn_position = global_position
	sprite = get_node("Sprite2D")
	colision = get_node("CollisionShape2D")
	hitbox = get_node("HitBoxArea/CollisionShape2D")
	
	#melee.play()


func _physics_process(delta: float) -> void:
	velocity = direction * SPEED
	var collision = move_and_collide(velocity * delta)
	
	
	
	if collision:
		var collider = collision.get_collider()
		if collider:
			if collider.is_in_group("Player"):
				#print("funciona")
				#meti a todos los enemigos en el grupo enemy para detectar cuando la bala colisione con uno de ellos
				if collider.has_method("take_dmg_melee"):
					collider.take_dmg_ranged(5)
				destroy_bullet()
				#queue_free()
				#collider.queue_free()
				#hitbox es una variable bool que le permite al juego determinar si debe morir el enemigo o no, accedo a ella mediante el collider ya que hitbox se encuentra en los scripts de enemigos
			elif collider.is_in_group("Soldier"):
				#print("funciona")
				#meti a todos los enemigos en el grupo enemy para detectar cuando la bala colisione con uno de ellos
				if collider.has_method("take_damage_z"):
					var dmg_to_s = 30
					collider.hitbox = true
					if collider.is_in_group("Tanks"):
						collider.take_damage(dmg_to_s/2)
					else:
						collider.take_damage(dmg_to_s)
				destroy_bullet()
			else:
				#queue_free()
				destroy_bullet()
	else:
		await get_tree().create_timer(cooldown).timeout
		queue_free()
	

func destroy_bullet():
	sprite.hide()
	if is_instance_valid(colision):
		colision.queue_free()
	if is_instance_valid(hitbox):
		hitbox.queue_free()
	queue_free()
