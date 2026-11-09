extends Area2D

# Daño que inflige el ataque
const DAMAGE_PLAYER = 5
const DAMAGE_SOLDIER = 30
const DAMAGE_TANK = 15  # La mitad para tanques

# Tiempo de vida del ataque si no golpea nada
const LIFE_TIME = 0.3

# Dirección del ataque (para orientar el sprite y el collider)
var direction = Vector2.RIGHT
var spawn_position: Vector2

@onready var audio_player = $atked
@onready var sprite = $Sprite2D

func _ready() -> void:
	spawn_position = global_position
	
	# Configurar capas de colisión: capa 1 (jugador) y capa 7 (soldados/enemigos)
	#collision_layer = 1 | 2 | 3 | 4 | 5 | 6 | 7 
	#collision_mask = 1 | 2 | 3 | 4 | 5 | 6 | 7  # Detecta jugador y soldados (hgunner, soldier_1, tank, sniper)
	
	# Asegurar que el Area2D esté monitoreando
	monitoring = true
	monitorable = true
	
	# Reproducir sonido de ataque al iniciar (como bullet)
	if audio_player:
		audio_player.play()
	
	# Conectar la señal de detección del propio Area2D
	body_entered.connect(_on_body_entered)
	
	# Si no golpea nada en LIFE_TIME, autodestruirse
	get_tree().create_timer(LIFE_TIME).timeout.connect(func():
		queue_free()
	)

func _on_body_entered(body: Node2D) -> void:
	# Jugador (como bullet detecta grupo "Enemy", aquí detectamos "Player")
	if body.is_in_group("Player"):
		if body.has_method("take_dmg_ranged"):
			body.take_dmg_ranged(DAMAGE_PLAYER)
		queue_free()
		return

	# Soldados (incluyendo tanques)
	if body.is_in_group("Soldier"):
		if body.has_method("take_damage_z"):
			body.hitbox = true
			if body.is_in_group("Tanks"):
				body.take_damage(DAMAGE_TANK)
			else:
				body.take_damage(DAMAGE_SOLDIER)
		queue_free()
		return

	# Zombies (daño entre zombies, si aplica)
	if body.is_in_group("Enemyz"):
		if body.has_method("take_damage_z"):
			body.take_damage_z(DAMAGE_SOLDIER)
		queue_free()
		return
