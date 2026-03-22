extends CharacterBody2D


var SPEED = 700
var MAX_DISTANCE = 500  # Distancia máxima en píxeles
var damage = 1
var direction = Vector2.RIGHT  # Variable para almacenar la dirección
@onready var gun = $M4A1
@onready var gun2 = $Sniper
@onready var gun3 = $Shotgun
var parent
var sprite
var colision
var hitbox
var distance_traveled = 0.0
var spawn_position: Vector2
var sound_c = 1

func _ready() -> void:
	spawn_position = global_position
	if sound_c == 1:
		gun.play()
	elif sound_c == 2:
		gun2.play()
	elif sound_c == 3:
		gun3.play()
		
	sprite = get_node("Sprite2D")
	colision = get_node("CollisionShape2D")
	hitbox = get_node("HitBoxArea/CollisionShape2D")


func _physics_process(delta: float) -> void:
	velocity = direction * SPEED
	var collision = move_and_collide(velocity * delta)
	
	distance_traveled = global_position.distance_to(spawn_position)
	if distance_traveled > MAX_DISTANCE:
		destroy_bullet()
		return
	
	
	if collision:
		var collider = collision.get_collider()
		if collider:
			if collider.is_in_group("Player"):
				#print("funciona")
				#meti a todos los enemigos en el grupo enemy para detectar cuando la bala colisione con uno de ellos
				if collider.has_method("take_dmg_ranged"):
					collider.take_dmg_ranged(damage)
				destroy_bullet()
				#queue_free()
				#collider.queue_free()
				#hitbox es una variable bool que le permite al juego determinar si debe morir el enemigo o no, accedo a ella mediante el collider ya que hitbox se encuentra en los scripts de enemigos
			elif collider.is_in_group("Enemyz"):
				#print("funciona")
				#meti a todos los enemigos en el grupo enemy para detectar cuando la bala colisione con uno de ellos
				if collider.has_method("take_damage"):
					var dmg_to_z = damage * 8
					collider.hitbox = true
					collider.take_damage(dmg_to_z)
				destroy_bullet()
			else:
				#queue_free()
				destroy_bullet()


func destroy_bullet():
	sprite.hide()
	if is_instance_valid(colision):
		colision.queue_free()
	if is_instance_valid(hitbox):
		hitbox.queue_free()


func _on_audio_finished():
	queue_free()
