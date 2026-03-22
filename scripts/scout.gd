extends CharacterBody2D
@onready var target = get_tree().get_first_node_in_group("Player")
@onready var nav = $NavigationAgent2D
@onready var nav2 = $NavigationAgent2D2
var bullet = preload("res://scenes/enemy_bullet.tscn")
const SPEED = 50.0
var hitbox = false
var life = 500
var bulletCount = 0 #Variable para validar la cantidad de balas que se disparan
var max_Bullets = 5 #Variable que indica cuántas balas se pueden disparar
var canShoot = true #Variable bandera que activa el uso de las balas
var min_cooldown = 0.3
var max_cooldown = 1.2
var memory = false
var search_time_remaining: float = 0.0
const COMBAT_DISTANCE = 160.0  # Distancia de combate
const STANDING_DISTANCE = 120.0  # Distancia de combate sin moverse
const RETREAT_DISTANCE = 80.0  # Distancia para retroceder
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 250


var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 3.0  # Tiempo que investiga antes de volver a patrullar


enum State {APPROACHING, COMBAT, RETREATING, INVESTIGATING, PATROLLING}
var current_state = State.PATROLLING

enum PatrolState {TURNING_RIGHT, TURNING_LEFT}
var patrol_state: PatrolState = PatrolState.TURNING_RIGHT

#enum State {APPROACHING, COMBAT, RETREATING, STANDING}
#var current_state = State.APPROACHING

#var MIN_DISTANCE = 100.0  # Distancia mínima
#var IDEAL_DISTANCE = 200.0  # Distancia ideal para disparar
#const APPROACH_SPEED = 0.5  # Suavizado de movimiento
@onready var ray = $RayCast2D
@onready var cooldown = $Cooldown
@onready var sight = $Sight
@export var angle: float
@export var length: float
@export var direction = Vector2.RIGHT
var half

var initial_position: Vector2
var patrol_timer: float = 0.0
const PATROL_TIME = 10.0
var patrol_direction: float = 1.0  # 1 para derecha, -1 para izquierda
const PATROL_ROTATION_SPEED = 0.7  # Velocidad de rotación en radianes/segundo
var current_rotation_angle: float = 0.0
const MAX_PATROL_ANGLE = deg_to_rad(180)  # 180 grados máximo cada lado
var current_patrol_angle: float = 0.0



func _ready():
	# Guardar posición inicial
	initial_position = global_position
	
	half = deg_to_rad(angle / 2)
	
	target.shot_fired.connect(_on_player_shot_fired)
	




func _on_player_shot_fired():
	var distance_to_player = global_position.distance_to(target.global_position)
	# Verificar si el jugador está dentro del rango de audición y si no está viendo al jugador
	# se verifica si no lo ve para evitar conflictos a la hora de que el enemigo decida su acción
	if distance_to_player <= HEAR_DISTANCE and not (is_in_cone() and has_line_of_sight()):
		last_heard_position = target.global_position
		investigating = true
		investigation_timer = INVESTIGATION_TIME
		#current_state = State.INVESTIGATING


func _draw():
	#mero debug esta monda
	var left_dir = direction.rotated(-half) * length
	var right_dir = direction.rotated(half) * length
	
	draw_line(Vector2.ZERO, left_dir, Color.YELLOW, 2.0)
	draw_line(Vector2.ZERO, right_dir, Color.YELLOW, 2.0)


func is_in_cone():
	#En esta función se crean un cono, el cual es la visión del enemigo
	#Se obtiene la posición del jugador y mediante ella se hacen los respectivos calculos
	#Si la distancia entre el jugador y el enemigo es mayor que la del cono, entonces no lo detecta
	var player_local = to_local(target.global_position)
	var angle_to_player = direction.angle_to(player_local)
	var distance = player_local.length()
	
	if distance > length:
		return false
	#Por ultimo, acá se regresa el valor absoluto del angulo en el que se encuentra el jugador, y
	#si éste ángulo se encuentra dentro de los de el cono
	return abs(angle_to_player) <= half
	
	
	#Otra forma de hacerlo
	#if abs(angle_to_player) <= half:
		#return true
	#else:
		#return false

func has_line_of_sight():
	#Un raycast bastante parecido al de "aim", solo que éste sirve para detectar si el jugador
	#está en el rango de visión del enemigo :D
	sight.target_position = to_local(target.position)
	var collider = sight.get_collider()
	
	if not collider:
		return 
	
	return collider.is_in_group("Player")


func reaction():
	var distance_to_target = position.distance_to(target.position)
	if distance_to_target <= REACT_DISTANCE: #and (is_in_cone() and has_line_of_sight()):
		look_at(target.position)
	elif hitbox:
		look_at(target.position)

func _physics_process(delta: float) -> void:
	reaction()
	
	# Actualizar timer de investigación
	if investigating:
		investigation_timer -= delta
		if investigation_timer <= 0:
			investigating = false
			current_state = State.PATROLLING
	
	#if has_line_of_sight():
		#print("linea de visión funcionando")
	
	if hitbox:
		#hit_sound()
		#take_damage()
		hitbox = false
	
	if randi_range(0, 10) == 0:
		return
	
	
	
	#if is_in_cone() and has_line_of_sight():
		#aim()
		#look_at(target.position)
	#elif investigating:
		#investigate_sound()
	
	
	
	# PRIORIDAD: Si está investigando, cambiar estado
	if investigating and current_state != State.INVESTIGATING and not (is_in_cone() and has_line_of_sight()):
		current_state = State.INVESTIGATING
	elif is_in_cone() and has_line_of_sight(): #and current_state != State.INVESTIGATING:
		investigating = false
		if current_state == State.PATROLLING or current_state == State.INVESTIGATING:
			current_state = State.APPROACHING
		look_at(target.position)
		aim()
	
	
	
	check_player_collision()
	
	if life > 0:
		# LÓGICA SEPARADA POR ESTADO
		match current_state:
			State.INVESTIGATING:
				investigate_behavior()
			State.APPROACHING, State.COMBAT, State.RETREATING:
				combat_behavior()
			State.PATROLLING:
				patrol_behavior()  # O simplemente velocity = Vector2.ZERO
	else:
		queue_free()
		


func investigate_behavior():
	# Comportamiento exclusivo para investigación
	nav.target_position = last_heard_position
	look_at(last_heard_position)
	
	var global_next_pos = nav.get_next_path_position()
	var direction = (global_next_pos - global_position).normalized()
	velocity = direction * SPEED
	
	# Si llega a la posición o ve al jugador, cambiar estado
	var distance_to_sound = global_position.distance_to(last_heard_position)
	
	if distance_to_sound < 30.0:
		# Llegó al lugar del sonido
		if is_in_cone() and has_line_of_sight():
			current_state = State.APPROACHING  # Cambiar a combate si ve al jugador
		else:
			investigating = false
			current_state = State.PATROLLING
	
	move_and_slide()

func combat_behavior():
	var last_seen_position
	last_seen_position = target.global_position
	if is_in_cone() and has_line_of_sight():
		search_time_remaining = 8.0  # Resetear tiempo de búsqueda
		memory = true
		var global_next_pos = nav.get_next_path_position()
		var direction = (global_next_pos - global_position).normalized()
		var direction1 = (target.position - position).normalized()
		var distance_to_target = position.distance_to(target.position)
		
		match current_state:
			State.APPROACHING:
				if distance_to_target <= COMBAT_DISTANCE:
					current_state = State.COMBAT
				else:
					velocity = direction * SPEED
			
			State.COMBAT:
				if distance_to_target < RETREAT_DISTANCE:
					current_state = State.RETREATING
				elif distance_to_target > COMBAT_DISTANCE * 1.2:
					current_state = State.APPROACHING
				else:
					velocity = Vector2.ZERO
			
			State.RETREATING:
				if distance_to_target >= COMBAT_DISTANCE:
					current_state = State.COMBAT
				else:
					velocity = -direction1 * SPEED * 1.4
		move_and_slide()
	else:
		if memory and search_time_remaining > 0: #(memory and search_time_remaining > 0) and not has_line_of_sight():
			search_time_remaining -= get_physics_process_delta_time()
			nav2.target_position = last_seen_position
			var global_next_pos = nav2.get_next_path_position()
			var direction = (global_next_pos - global_position).normalized()
			look_at(global_next_pos)
			velocity = direction * (SPEED / 1.75)
			move_and_slide()
			
			# Verificar si llegó a la posición o si se acabó el tiempo
			var distance_to_last_seen = global_position.distance_to(last_seen_position)
			if distance_to_last_seen < 10.0 or search_time_remaining <= 0:
				if is_in_cone() and has_line_of_sight():
					current_state = State.APPROACHING
				else:
					current_state = State.PATROLLING
					memory = false

func patrol_behavior():
	# Comportamiento cuando no hay nada que hacer
	velocity = Vector2.ZERO
	
	patrol_timer += get_physics_process_delta_time()
	
	match patrol_state:
		PatrolState.TURNING_RIGHT:
			rotate(PATROL_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle += PATROL_ROTATION_SPEED * get_physics_process_delta_time()
			
			if current_patrol_angle >= MAX_PATROL_ANGLE:
				patrol_state = PatrolState.TURNING_LEFT
		
		PatrolState.TURNING_LEFT:
			rotate(-PATROL_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle -= PATROL_ROTATION_SPEED * get_physics_process_delta_time()
			
			if current_patrol_angle <= -MAX_PATROL_ANGLE:
				patrol_state = PatrolState.TURNING_RIGHT
	
	if patrol_timer >= PATROL_TIME:
		var distance_from_initial = global_position.distance_to(initial_position)
		if distance_from_initial > 20.0:  # Si se alejó más de 20 píxeles
			# Regresar a posición inicial
			nav2.target_position = initial_position
			var return_pos = nav2.get_next_path_position()
			var return_direction = (return_pos - global_position).normalized()
			velocity = return_direction * (SPEED / 2)
			look_at(initial_position)
			
			# Si llegó cerca de la posición inicial, resetear timer
			if distance_from_initial < 10.0:
				patrol_timer = 0.0
				direction = Vector2.RIGHT
		else:
			# Ya está en posición, resetear timer
			patrol_timer = 0.0
	
	
	move_and_slide()




func take_damage(amount):
	life -= amount
	#print(life)
	#print(amount)

func aim():
	ray.target_position = to_local(target.position)


func check_player_collision():
	if ray.get_collider() == target and cooldown.is_stopped():
		cooldown.start()
	elif ray.get_collider() != target and not cooldown.is_stopped():
		cooldown.stop()

func _on_cooldown_timeout() -> void:
	if  canShoot:
		canShoot = false
		bulletCount = 0
		var random_cooldown = randf_range(min_cooldown, max_cooldown)
		await get_tree().create_timer(random_cooldown).timeout
		shootSequence()
	
func shootSequence():
	if  bulletCount < max_Bullets and life>0:
		shoot()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		if is_in_cone(): #and has_line_of_sight():
			shootSequence()
		else:
			bulletCount = 0
			canShoot = true
		#Al entrar, se va acumulando el contador, usando nuestra función para disparar (utilizando el nodo) y empezando el timer para controlar cada disparo
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true
		#Cuando se llena el contador, volveremos arriba a repetir el mismo ciclo





func shoot():
	var newBullet = bullet.instantiate()
	#newBullet.position = global_position
	newBullet.position = $Sprite2D/Spawn_bullet.global_position
	# Dirección base hacia el jugador
	var base_direction = (target.global_position - global_position).normalized()
	
	# Agregar dispersión/error
	var spread_angle = deg_to_rad(10)  # 10 grados de dispersión
	var random_angle = randf_range(-spread_angle, spread_angle)
	var final_direction = base_direction.rotated(random_angle)
	newBullet.direction = final_direction
	newBullet.rotation = final_direction.angle()
	#var direction = to_local(target.position)
	#newBullet.direction = (raycast.target_position).normalized()
	#var direction = (target.position - $Sprite2D/Spawn_bullet.global_position).normalized()
	#newBullet.direction = direction
	#newBullet.position = $Sprite2D/Spawn_bullet.global_position
	#newBullet.rotation = direction.angle()
	#newBullet.rotation = $Sprite2D/SpawnPoint.rotation
	#newBullet.velocity = direction - newBullet.position
	#todas las weas comentadas fueron intentos cagados mios de hacer que la bala fuera hasta el jugador
	#hasta que encontré la cuestion del deg_to_rad que hasta lo dispersa
	get_parent().add_child(newBullet)


func _on_nv_timer_timeout() -> void:
	nav.target_position = target.global_position
