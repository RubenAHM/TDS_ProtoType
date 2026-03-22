extends CharacterBody2D

@onready var select = get_tree().get_first_node_in_group("Player")
const SPEED = 2000
var MAX_DISTANCE = 1000  # Distancia máxima en píxeles
@onready var hgun = $hgun
@onready var mp5 = $mp5
@onready var m16 = $m16
@onready var shtgn = $shtgn
var parent
var sprite
var colision
var hitbox
var distance_traveled = 0.0
var spawn_position: Vector2

func _ready() -> void:
	if Global.current_weapon == 1:
		hgun.play()
		MAX_DISTANCE = 550
	elif Global.current_weapon == 2:
		mp5.play()
		MAX_DISTANCE = 600
	elif Global.current_weapon == 3:
		m16.play()
		MAX_DISTANCE = 700
	else:
		shtgn.play()
		MAX_DISTANCE = 120
	
	spawn_position = global_position
	sprite = get_node("Sprite2D")
	colision = get_node("CollisionShape2D")
	hitbox = get_node("HitBoxArea/CollisionShape2D")


func _physics_process(delta: float) -> void:
	var collision = move_and_collide(velocity.normalized() * delta * SPEED)
	
	# Verificar distancia recorrida
	distance_traveled = global_position.distance_to(spawn_position)
	if distance_traveled > MAX_DISTANCE:
		destroy_bullet()
		return
	
	
	if collision:
		var collider = collision.get_collider()
		if collider:
			if collider.is_in_group("Enemy"):
				#print("funciona")
				#meti a todos los enemigos en el grupo enemy para detectar cuando la bala colisione con uno de ellos
				collider.hitbox = true
				if collider.has_method("take_damage"):
					collider.take_damage(select.dmg)
				destroy_bullet()
				#queue_free()
				#collider.queue_free()
				#hitbox es una variable bool que le permite al juego determinar si debe morir el enemigo o no, accedo a ella mediante el collider ya que hitbox se encuentra en los scripts de enemigos
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
