extends CharacterBody2D

@onready var target = get_tree().get_first_node_in_group("Player")
@onready var nav = $NavigationAgent2D
@onready var nav2 = $NavigationAgent2D2
@onready var atked = $atked
@onready var atked2 = $atked2
var bullet = preload("res://scenes/enemy_bullet.tscn")
const SPEED = 50.0
const damage = 5
const sound = 1
var hitbox = false
var life = 300
var bulletCount = 0 #Variable para validar la cantidad de balas que se disparan
var max_Bullets = 5 #Variable que indica cuántas balas se pueden disparar
var canShoot = true #Variable bandera que activa el uso de las balas
var min_cooldown = 0.3
var max_cooldown = 1.2
var memory = false
var search_time_remaining: float = 0.0
const COMBAT_DISTANCE = 140.0  # Distancia de combate
const STANDING_DISTANCE = 120.0  # Distancia de combate sin moverse
const RETREAT_DISTANCE = 80.0  # Distancia para retroceder
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 250


var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 3.0  # Tiempo que investiga antes de volver a patrullar


enum State {APPROACHING, COMBAT, RETREATING, INVESTIGATING, PATROLLING, COMBAT_ZOMBIE, SEARCHING, CHASE}
#Esta puta mierda que está acá determina el perro objetivo del soldado del coño este, no tocar coñodelamadre
enum TargetType {NONE, PLAYER, ZOMBIE}
var current_target_type: TargetType = TargetType.PLAYER
var current_target: Node2D = null
var current_state = State.PATROLLING

enum PatrolState {TURNING_RIGHT, TURNING_LEFT}
var patrol_state: PatrolState = PatrolState.TURNING_RIGHT

#enum State {APPROACHING, COMBAT, RETREATING, STANDING}
#var current_state = State.APPROACHING

#var MIN_DISTANCE = 100.0  # Distancia mínima
#var IDEAL_DISTANCE = 200.0  # Distancia ideal para disparar
#const APPROACH_SPEED = 0.5  # Suavizado de movimiento
#@onready var ray = $RayCast2D
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
const MAX_PATROL_ANGLE = deg_to_rad(120)  # 120 grados máximo cada lado
var current_patrol_angle: float = 0.0
const PATROL_HURT_TIME = 4.0
const PATROL_HURT_ROTATION_SPEED = 3.0  # Velocidad de rotación en radianes/segundo
var current_hurt_rotation_angle: float = 0.0
const MAX_HURT_PATROL_ANGLE = deg_to_rad(180)
var alert_cooldown: float = 0.0
const ALERT_COOLDOWN_TIME = 6.0  # Tiempo entre alertas para no spam

var vision_timer: float = 0.0
const VISION_CHECK_INTERVAL = 0.35 # Revisará objetivos cada 0.25 segundos (4 veces por seg)
var current_has_target: bool = false


func _ready():
	# Guardar posición inicial
	initial_position = global_position
	
	half = deg_to_rad(angle / 2)
	
	target.shot_fired.connect(_on_player_shot_fired)
	EnemySignals.player_detected.connect(_on_enemy_player_detected)
	EnemySignals.zombie_detected.connect(_on_zombie_detected)

func _on_zombie_detected(zombie_pos: Vector2, detector_z_pos: Vector2, alert_radius_z: float):
	# Ignorar si ya estamos en combate
	if current_target != null:
		return
	
	# Calcular distancia al detector
	var distance_to_detector = global_position.distance_to(detector_z_pos)
	
	# Si estamos dentro del radio de alerta
	if distance_to_detector <= alert_radius_z:
		# Si no tenemos objetivo o nuestro objetivo actual no es el jugador
		if current_target == null or current_target_type != TargetType.ZOMBIE:
			# Ir a la última posición conocida del jugador
			last_heard_position = zombie_pos
			current_target = null
			current_target_type = TargetType.NONE
			current_state = State.INVESTIGATING
			investigating = true
			investigation_timer = INVESTIGATION_TIME
			#print("¡Alerta recibida! Investigando posición: ", player_pos)

func _on_enemy_player_detected(player_pos: Vector2, detector_pos: Vector2, alert_radius: float):
	# Ignorar si ya estamos en combate
	if current_target != null:
		return
	
	# Calcular distancia al detector
	var distance_to_detector = global_position.distance_to(detector_pos)
	
	# Si estamos dentro del radio de alerta
	if distance_to_detector <= alert_radius:
		# Si no tenemos objetivo o nuestro objetivo actual no es el jugador
		if current_target == null or current_target_type != TargetType.PLAYER:
			# Ir a la última posición conocida del jugador
			last_heard_position = player_pos
			current_target = null
			current_target_type = TargetType.NONE
			current_state = State.INVESTIGATING
			investigating = true
			investigation_timer = INVESTIGATION_TIME
			#print("¡Alerta recibida! Investigando posición: ", player_pos)


func _on_player_shot_fired():
	if current_target != null:
		return
	var distance_to_player = global_position.distance_to(target.global_position)
	# Verificar si el jugador está dentro del rango de audición y si no está viendo al jugador
	# se verifica si no lo ve para evitar conflictos a la hora de que el enemigo decida su acción
	if distance_to_player <= HEAR_DISTANCE and not (is_in_cone() and has_line_of_sight()):
		last_heard_position = target.global_position
		investigating = true
		investigation_timer = INVESTIGATION_TIME
		#current_state = State.INVESTIGATING



func find_any_target() -> bool:
	#verificar si el jugador está visible (prioridad máxima)
	if is_player_visible(target):
		current_target = target
		current_target_type = TargetType.PLAYER
		if alert_cooldown <= 0:
			EnemySignals.player_detected.emit(target.global_position, global_position, 600.0)
			alert_cooldown = ALERT_COOLDOWN_TIME
		return true
	
	# Si no ve al jugador, buscar zombies visibles
	var zombies = get_tree().get_nodes_in_group("Enemyz")
	for zombie in zombies:
		if is_zombie_visible(zombie):
			current_target = zombie
			current_target_type = TargetType.ZOMBIE
			if alert_cooldown <= 0:
				EnemySignals.zombie_detected.emit(zombie.global_position, global_position, 600.0)
				alert_cooldown = ALERT_COOLDOWN_TIME
			return true
	
	current_target = null
	current_target_type = TargetType.NONE
	return false


func is_player_visible(player: Node2D) -> bool:
	if player == null:
		return false
	var player_local = to_local(player.global_position)
	var angle_to_player = direction.angle_to(player_local)
	var distance = player_local.length()
	
	if distance > length:
		return false
	if abs(angle_to_player) > half:
		return false
	
	sight.target_position = to_local(player.position).normalized() * (length - 30)
	
	
	#sight.target_position = to_local(player.position)
	var collider = sight.get_collider()
	
	if not collider:
		return false
	
	
	return collider.is_in_group("Player")



# 3. Función auxiliar para ver zombies (usa tus mismas funciones)
func is_zombie_visible(zombie: Node2D) -> bool:
	#Verificar si el zombie está en el cono de visión
	if zombie == null:
		return false
	var zombie_local = to_local(zombie.global_position)
	var angle_to_zombie = direction.angle_to(zombie_local)
	var distance = zombie_local.length()
	
	if distance > length:
		return false
	if abs(angle_to_zombie) > half:
		return false
	
	sight.target_position = to_local(zombie.position).normalized() * (length - 30)
	var collider = sight.get_collider()
	
	if not collider:
		return false
	
	return collider.is_in_group("Enemyz")


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
	var distance_to_current_target = 50
	if current_target != null:
		distance_to_current_target = position.distance_to(current_target.position)
	if distance_to_target <= REACT_DISTANCE: #and (is_in_cone() and has_line_of_sight()):
		#look_at(target.position)
		var target_angle = (target.global_position - global_position).angle()
		rotation = lerp_angle(rotation, target_angle, 0.1) # 0.1 es la velocidad de giro
	elif hitbox and (current_target == null or distance_to_current_target > 25):
		#print("herido")
		current_state = State.SEARCHING
		hitbox = false

func _physics_process(delta: float) -> void:
	#print(life)
	# Actualizar cooldown de alerta
	if alert_cooldown > 0:
		alert_cooldown -= delta
	reaction()
	if investigating:
		investigation_timer -= delta
		if investigation_timer <= 0:
			investigating = false
			current_state = State.PATROLLING
	
	if hitbox:
		#hit_sound()
		#take_damage()
		hitbox = false
	
	#if randi_range(0, 10) == 0:
		#return
	
	vision_timer -= delta
	if vision_timer <= 0:
		current_has_target = find_any_target()
		# Le sumamos un pequeño valor aleatorio para que no todos los enemigos 
		# calculen la visión en el mismo exacto frame y causen un micro-lag
		vision_timer = VISION_CHECK_INTERVAL + randf_range(0.0, 0.05) 

	# Usamos la variable guardada en lugar de llamar a la función de nuevo
	var has_target = current_has_target
	
	#var has_target = find_any_target()
	
	# PRIORIDAD: Si está investigando, cambiar estado
	if investigating and current_state != State.INVESTIGATING and not has_target:
		current_state = State.INVESTIGATING
	elif has_target:
		investigating = false
		if current_target_type == TargetType.PLAYER:
			if current_state == State.PATROLLING or current_state == State.INVESTIGATING or current_state == State.COMBAT_ZOMBIE:
				current_state = State.APPROACHING
			#look_at(current_target.position)
			# En lugar de look_at(target.position)
			var target_angle = (current_target.global_position - global_position).angle()
			rotation = lerp_angle(rotation, target_angle, 0.1) # 0.1 es la velocidad de giro
			#aim()  
		elif current_target_type == TargetType.ZOMBIE:
			if current_state == State.PATROLLING or current_state == State.INVESTIGATING or current_state == State.APPROACHING:
				current_state = State.COMBAT_ZOMBIE
			#look_at(current_target.position)
			#aim()  
			# En lugar de look_at(target.position)
		var target_angle = (current_target.global_position - global_position).angle()
		rotation = lerp_angle(rotation, target_angle, 0.1) # 0.1 es la velocidad de giro
	
	
	
	check_player_collision()
	
	if life > 0:
		#LÓGICA SEPARADA POR ESTADO
		match current_state:
			State.INVESTIGATING:
				investigate_behavior()
			State.APPROACHING, State.COMBAT, State.RETREATING:
				combat_behavior()
			State.COMBAT_ZOMBIE:
				combat_zombie_behavior()
			State.PATROLLING:
				patrol_behavior() 
			State.SEARCHING:
				hurt_behavior()
	else:
		queue_free()
		


func investigate_behavior():
	#Comportamiento exclusivo para investigación
	nav.target_position = last_heard_position
	look_at(last_heard_position)
	
	var global_next_pos = nav.get_next_path_position()
	var direction = (global_next_pos - global_position).normalized()
	velocity = direction * SPEED
	
	#Si llega a la posición o ve al jugador, cambiar estado
	var distance_to_sound = global_position.distance_to(last_heard_position)
	
	if distance_to_sound < 30.0:
		if is_in_cone() and has_line_of_sight():
			current_state = State.APPROACHING  #Cambiar a combate si ve al jugador
		else:
			investigating = false
			current_state = State.PATROLLING
	
	move_and_slide()

func combat_behavior():
	#if current_target_type != TargetType.PLAYER:
		#return
	#var last_seen_position
	#last_seen_position = target.global_position
	if is_player_visible(current_target):
		search_time_remaining = 8.0  #Resetear tiempo de búsqueda
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
				elif distance_to_target > COMBAT_DISTANCE * 1.3:
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
		if memory and search_time_remaining > 0 and not is_zombie_visible(current_target): #(memory and search_time_remaining > 0) and not has_line_of_sight():
			search_time_remaining -= get_physics_process_delta_time()
			#nav2.target_position = last_seen_position
			var global_next_pos = nav2.get_next_path_position()
			var direction = (global_next_pos - global_position).normalized()
			look_at(global_next_pos)
			velocity = direction * (SPEED / 1.75)
			move_and_slide()
			
			#Verificar si llegó a la posición o si se acabó el tiempo
			var distance_to_last_seen = global_position.distance_to(global_next_pos) #last_seen_position
			if distance_to_last_seen < 10.0 or search_time_remaining <= 0:
				if is_player_visible(current_target):
					current_state = State.APPROACHING
				else:
					current_state = State.PATROLLING
					memory = false

func patrol_behavior():
	#Comportamiento cuando no hay nada que hacer
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
		if distance_from_initial > 20.0:  #Si se alejó más de 20 píxeles
			#Regresar a posición inicial
			nav2.target_position = initial_position
			var return_pos = nav2.get_next_path_position()
			var return_direction = (return_pos - global_position).normalized()
			velocity = return_direction * (SPEED / 2)
			look_at(initial_position)
			
			#Si llegó cerca de la posición inicial, resetear timer
			if distance_from_initial < 10.0:
				patrol_timer = 0.0
				direction = Vector2.RIGHT
		else:
			#Ya está en posición, resetear timer
			patrol_timer = 0.0
	
	
	move_and_slide()


func combat_zombie_behavior():
	if current_target_type != TargetType.ZOMBIE:
		current_state = State.PATROLLING
		return
	memory = false
	if is_zombie_visible(current_target):
		
		var global_next_pos = nav.get_next_path_position()
		var direction = (global_next_pos - global_position).normalized()
		#var direction1 = (current_target.position - position).normalized()
		var distance_to_target = position.distance_to(current_target.position)
		if distance_to_target > COMBAT_DISTANCE * 0.8:
			velocity = direction * SPEED
		elif distance_to_target < RETREAT_DISTANCE:
			velocity = -direction * (SPEED * 1.8)
		else:
			velocity = Vector2.ZERO
			
		move_and_slide()



func hurt_behavior():
	#Comportamiento cuando no hay nada que hacer
	velocity = Vector2.ZERO
	patrol_timer += get_physics_process_delta_time()
	if current_target != null:
		current_state = State.APPROACHING
		patrol_timer = 0.0
	match patrol_state:
		PatrolState.TURNING_RIGHT:
			rotate(PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle += PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time()
			
			if current_patrol_angle >= MAX_HURT_PATROL_ANGLE:
				patrol_state = PatrolState.TURNING_LEFT
		
		PatrolState.TURNING_LEFT:
			rotate(-PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle -= PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time()
			
			if current_patrol_angle <= -MAX_HURT_PATROL_ANGLE:
				patrol_state = PatrolState.TURNING_RIGHT
	
	if patrol_timer >= PATROL_HURT_TIME:
		current_state = State.PATROLLING
		patrol_timer = 0.0
	
	
	move_and_slide()



func take_damage(amount):
	life -= amount
	atked.play()
	#print(life)
	#print(amount)

func take_damage_z(amount):
	life -= amount
	atked2.play()
	#print(life)
	#print(amount)

#func aim():
	#ray.target_position = to_local(current_target.position)


func check_player_collision():
	if sight.get_collider() == current_target and cooldown.is_stopped():
		cooldown.start()
	elif sight.get_collider() != current_target and not cooldown.is_stopped():
		cooldown.stop()


func _on_cooldown_timeout() -> void:
	if  canShoot:
		canShoot = false
		bulletCount = 0
		var random_cooldown = randf_range(min_cooldown, max_cooldown)
		await get_tree().create_timer(random_cooldown).timeout
		
		if current_target_type != TargetType.ZOMBIE:
			shootSequence()
		elif current_target_type != TargetType.PLAYER:
			shootSequence_z()
			#if current_target_type == TargetType.ZOMBIE:
				#shootSequence_z()
	
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


func shootSequence_z():
	if  bulletCount < max_Bullets and life>0:
		shoot()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		
		shootSequence_z()
		#Al entrar, se va acumulando el contador, usando nuestra función para disparar (utilizando el nodo) y empezando el timer para controlar cada disparo
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true
		#Cuando se llena el contador, volveremos arriba a repetir el mismo ciclo

const SHOT_ALERT_RADIUS = 400.0  #Radio en el que los zombies escuchan los disparos
func shoot():
	var newBullet = bullet.instantiate()
	newBullet.damage = damage
	newBullet.sound_c = sound
	#newBullet.position = global_position
	newBullet.position = $Sprite2D/Spawn_bullet.global_position
	#Dirección base hacia el jugador
	
	#emitir la puta perra desgraciada fokin señal esta que no quiere agarrar para que los zombies escuchen
	EnemySignals.soldier_shot_fired.emit(
		global_position,  #posición del disparo este todo choropo que por alguna perra razón no sirve coño
		global_position,  #posición del soldado pajuo
		SHOT_ALERT_RADIUS
	)
	
	if current_target != null:
		var base_direction = (current_target.global_position - global_position).normalized()
		
		#Agregar dispersión/error
		var spread_angle = deg_to_rad(10)  #10 grados de dispersión
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
	if current_target == null:
		return
	nav.target_position = current_target.global_position


func _on_memory_timer_timeout() -> void:
	nav2.target_position = target.global_position
