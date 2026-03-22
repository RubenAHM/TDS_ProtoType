extends CharacterBody2D

@onready var target = get_tree().get_first_node_in_group("Player")
@onready var nav = $NavigationAgent2D
@onready var nav2 = $NavigationAgent2D2
@onready var cooldown = $Cooldown
var attack = preload("res://scenes/zattack.tscn")
const SPEED = 60.0
var hitbox = false
var attackCount = 0 #Variable para validar la cantidad de balas que se disparan
var max_attacks = 2 #Variable que indica cuántas balas se pueden disparar
var memory = false
var search_time_remaining: float = 0.0
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 250
const COMBAT_DISTANCE = 28
var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 6.0  # Tiempo que investiga antes de volver a patrullar

var min_cooldown = 0.5
var max_cooldown = 1.2


enum State {APPROACHING, COMBAT, INVESTIGATING, COMBAT_SOLDIER, STANDING, SEARCHING}
#Esta puta mierda que está acá determina el perro objetivo del soldado del coño este, no tocar coñodelamadre
enum TargetType {NONE, PLAYER, SOLDIER}
var current_target_type: TargetType = TargetType.PLAYER
var current_target: Node2D = null
var current_state = State.STANDING


enum PatrolState {TURNING_RIGHT, TURNING_LEFT}
var patrol_state: PatrolState = PatrolState.TURNING_RIGHT
var patrol_timer: float = 0.0
const PATROL_TIME = 4.0
var patrol_direction: float = 1.0  # 1 para derecha, -1 para izquierda
const PATROL_ROTATION_SPEED = 3.2  # Velocidad de rotación en radianes/segundo
var current_rotation_angle: float = 0.0
const MAX_PATROL_ANGLE = deg_to_rad(180)  # 120 grados máximo cada lado
var current_patrol_angle: float = 0.0

@onready var sight = $Sight
@export var angle: float
@export var length: float
@export var direction = Vector2.RIGHT
var half

var canAttack = false

var life = 250

var alert_cooldown: float = 0.0
const ALERT_COOLDOWN_TIME = 3.0  #Tiempo entre alertas para no spam entre las señales de detección

func _ready():
	#Guardar posición inicial
	
	half = deg_to_rad(angle / 2)
	
	target.shot_fired.connect(_on_player_shot_fired)
	EnemySignals.soldier_shot_fired.connect(_on_soldier_shot_fired)

func _on_soldier_shot_fired(shot_position: Vector2, shooter_position: Vector2, alert_radius: float):
	#ignorar si el zombi come webos éste está en cooldown o simplemente es sendo mrc y no quiere servir
	if alert_cooldown > 0:
		return
	
	#Calcular distancia al disparo
	var distance_to_shot = global_position.distance_to(shot_position)
	
	#Si estam dentro del radio de alerta
	if distance_to_shot <= alert_radius:
		#Si no tiene objetivo actual
		if current_target == null:
			#Ir a la posición del disparo que no sirve, seeeeeeeeeeeh :D
			last_heard_position = shot_position
			current_target = null
			current_target_type = TargetType.NONE
			current_state = State.INVESTIGATING
			investigating = true
			investigation_timer = INVESTIGATION_TIME
			
			# Activar cooldown
			alert_cooldown = ALERT_COOLDOWN_TIME
			print("Zombie escuchó un disparo en: ", shot_position)


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

func _draw():
	#mero debug esta monda
	var left_dir = direction.rotated(-half) * length
	var right_dir = direction.rotated(half) * length
	
	draw_line(Vector2.ZERO, left_dir, Color.YELLOW, 2.0)
	draw_line(Vector2.ZERO, right_dir, Color.YELLOW, 2.0)

func find_any_target() -> bool:
	#verificar si el jugador está visible (prioridad máxima)
	#if is_in_cone() and has_line_of_sight():
		#current_target = target
		#current_target_type = TargetType.PLAYER
		#return true
	
	
	
	# Si no ve al jugador, buscar zombies visibles
	var soldiers = get_tree().get_nodes_in_group("Soldier")
	for soldier in soldiers:
		if is_soldier_visible(soldier):
			current_target = soldier
			current_target_type = TargetType.SOLDIER
			return true
	
	if is_player_visible(target):
		current_target = target
		current_target_type = TargetType.PLAYER
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
func is_soldier_visible(soldier: Node2D) -> bool:
	#Verificar si el zombie está en el cono de visión
	if soldier == null:
		return false
	var soldier_local = to_local(soldier.global_position)
	var angle_to_soldier = direction.angle_to(soldier_local)
	var distance = soldier_local.length()
	
	if distance > length:
		return false
	if abs(angle_to_soldier) > half:
		return false
	
	sight.target_position = to_local(soldier.position).normalized() * (length - 30)
	var collider = sight.get_collider()
	
	if not collider:
		return false
	
	return collider.is_in_group("Soldier")


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
	elif hitbox and current_target == null:
		current_state = State.SEARCHING
		hitbox = false


func _physics_process(delta: float) -> void:
	
	reaction()
	if investigating:
		investigation_timer -= delta
		if investigation_timer <= 0:
			investigating = false
			current_state = State.STANDING
	
	
	#if hitbox:
		#hit_sound()
		#take_damage()
		#hitbox = false
	
	
	var has_target = find_any_target()
	
	if randi_range(0, 10) == 0:
		return
	
	
	
	#if is_in_cone() and has_line_of_sight():
		#aim()
		#look_at(target.position)
	#elif investigating:
		#investigate_sound()
	
	
	
	# PRIORIDAD: Si está investigando, cambiar estado
	if investigating and current_state != State.INVESTIGATING and not has_target:
		current_state = State.INVESTIGATING
	elif has_target:
		investigating = false
		if current_target_type == TargetType.PLAYER:
			if current_state == State.STANDING or current_state == State.INVESTIGATING or current_state == State.COMBAT_SOLDIER:
				current_state = State.APPROACHING
			look_at(current_target.position)
			#aim()
		elif current_target_type == TargetType.SOLDIER:
			if current_state == State.STANDING or current_state == State.INVESTIGATING or current_state == State.APPROACHING:
				current_state = State.COMBAT_SOLDIER
			look_at(current_target.position)
			#aim()
	
	
	check_player_collision()
	
	if life > 0:
		#LÓGICA SEPARADA POR ESTADO
		match current_state:
			State.INVESTIGATING:
				investigate_behavior()
			State.APPROACHING, State.COMBAT:
				combat_behavior()
			State.COMBAT_SOLDIER:
				combat_soldier_behavior()
			State.STANDING:
				velocity = Vector2.ZERO
			State.SEARCHING:
				patrol_behavior()
	else:
		queue_free()
	
	#if life > 0:
		#var direction = (target.position - position).normalized()
		#velocity = direction * SPEED
		#look_at(target.position)
		#move_and_slide()
	#else:
		#queue_free()



func investigate_behavior():
	#Comportamiento exclusivo para investigación
	nav.target_position = last_heard_position
	look_at(last_heard_position)
	
	var global_next_pos = nav.get_next_path_position()
	var direction = (global_next_pos - global_position).normalized()
	velocity = direction * SPEED * 2
	
	#Si llega a la posición o ve al jugador, cambiar estado
	var distance_to_sound = global_position.distance_to(last_heard_position)
	
	if distance_to_sound < 30.0:
		if is_in_cone() and has_line_of_sight():
			current_state = State.APPROACHING  #Cambiar a combate si ve al jugador
		else:
			investigating = false
			current_state = State.STANDING
	
	move_and_slide()

func combat_behavior():
	#if current_target_type != TargetType.PLAYER:
		#return
	#var last_seen_position
	#last_seen_position = target.global_position
	#if is_in_cone() and has_line_of_sight():
	if is_player_visible(current_target):
		#print("atacando")
		search_time_remaining = 12.0  #Resetear tiempo de búsqueda
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
					velocity = direction * SPEED * 1.5
			
			State.COMBAT:
				if distance_to_target > COMBAT_DISTANCE:
					current_state = State.APPROACHING
					#canAttack = false
				else:
					#canAttack = true
					velocity = Vector2.ZERO
		move_and_slide()
	else:
		if (memory and search_time_remaining > 0) and not is_soldier_visible(current_target): #(memory and search_time_remaining > 0) and not has_line_of_sight():
			#print("buscando")
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
				#if is_in_cone() and has_line_of_sight():
				if is_player_visible(current_target):
					current_state = State.APPROACHING
				else:
					current_state = State.STANDING
					memory = false


func combat_soldier_behavior():
	if current_target_type != TargetType.SOLDIER:
		return
	memory = false
	if is_soldier_visible(current_target):
		
		var global_next_pos = nav.get_next_path_position()
		var direction = (global_next_pos - global_position).normalized()
		var distance_to_target = position.distance_to(current_target.position)
		
		if distance_to_target > COMBAT_DISTANCE:
			#canAttack = false
			velocity = direction * SPEED * 2.0
		else:
			#canAttack = true
			velocity = Vector2.ZERO
			
		move_and_slide()


func patrol_behavior():
	#Comportamiento cuando no hay nada que hacer
	velocity = Vector2.ZERO
	patrol_timer += get_physics_process_delta_time()
	if current_target != null:
		current_state = State.APPROACHING
		patrol_timer = 0.0
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
		current_state = State.STANDING
		patrol_timer = 0.0
	
	
	move_and_slide()



func take_damage(amount):
	life -= amount
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
	#if  canAttack:
		#print("puede atacar")
		#canAttack = false
	var random_cooldown = randf_range(min_cooldown, max_cooldown)
	await get_tree().create_timer(random_cooldown).timeout
	#var distance_to_target = position.distance_to(current_target.position)
	if current_target != null:
		var distance_to_target = position.distance_to(current_target.position)
		#print(distance_to_target)
		if distance_to_target <= COMBAT_DISTANCE:
			#print("puede atacar")
			attackSequence()

func attackSequence():
	if  attackCount < max_attacks and life>0:
		attacking()
		attackCount += 1
		$Timer.start()
		await $Timer.timeout
		#if is_in_cone(): #and has_line_of_sight():
		attackSequence()
		#else:
			#attackCount = 0
			#canAttack = true
		#Al entrar, se va acumulando el contador, usando nuestra función para disparar (utilizando el nodo) y empezando el timer para controlar cada disparo
	else:
		attackCount = 0
		$Timer.start()
		await $Timer.timeout
		canAttack = true
		#Cuando se llena el contador, volveremos arriba a repetir el mismo ciclo


func attacking():
	var newAttack = attack.instantiate()
	#newBullet.position = global_position
	newAttack.position = $Sprite2D/Spawn_bullet.global_position
	if current_target != null:
		var base_direction = (current_target.global_position - global_position).normalized()
		newAttack.direction = base_direction
		newAttack.rotation = base_direction.angle()
	get_parent().add_child(newAttack)


func _on_nv_timer_timeout() -> void:
	if current_target == null:
		return
	nav.target_position = current_target.global_position
	

func _on_memory_timer_timeout() -> void:
	nav2.target_position = target.global_position
