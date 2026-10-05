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
var bulletCount = 0 
var max_Bullets = 5 
var canShoot = true 
var min_cooldown = 0.3
var max_cooldown = 1.2
var memory = false
var search_time_remaining: float = 0.0

const COMBAT_DISTANCE = 140.0  
const STANDING_DISTANCE = 120.0 
const RETREAT_DISTANCE = 80.0  
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 250

var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 3.0  

enum State {APPROACHING, COMBAT, RETREATING, INVESTIGATING, PATROLLING, COMBAT_ZOMBIE, SEARCHING, CHASE}
enum TargetType {NONE, PLAYER, ZOMBIE}
var current_target_type: TargetType = TargetType.PLAYER
var current_target: Node2D = null
var current_state = State.PATROLLING

enum PatrolState {TURNING_RIGHT, TURNING_LEFT}
var patrol_state: PatrolState = PatrolState.TURNING_RIGHT

@onready var cooldown = $Cooldown
# @onready var sight = $Sight # Ya no necesitamos el nodo RayCast2D, usaremos RayCasting interno (más rápido)

@export var angle: float = 60.0 # Asegúrate de que tenga un valor por defecto
@export var length: float = 200.0
@export var direction = Vector2.RIGHT
var half

var initial_position: Vector2
var patrol_timer: float = 0.0
const PATROL_TIME = 10.0
const PATROL_ROTATION_SPEED = 0.7  
var current_patrol_angle: float = 0.0
const MAX_PATROL_ANGLE = deg_to_rad(120)  

const PATROL_HURT_TIME = 4.0
const PATROL_HURT_ROTATION_SPEED = 3.0  
var current_hurt_rotation_angle: float = 0.0
const MAX_HURT_PATROL_ANGLE = deg_to_rad(180)

var alert_cooldown: float = 0.0
const ALERT_COOLDOWN_TIME = 6.0  

# --- VARIABLES DE OPTIMIZACIÓN (Sacadas de tu alpha) ---
var vision_timer: float = 0.0
const VISION_CHECK_INTERVAL = 0.25 # Revisa 4 veces por segundo
var nav_update_timer: float = 0.0
const NAV_UPDATE_INTERVAL = 0.3 # Actualiza la ruta de navegación 3 veces por segundo
var current_has_target: bool = false
var last_known_target_pos: Vector2

func _ready():
	initial_position = global_position
	half = deg_to_rad(angle / 2)
	
	target.shot_fired.connect(_on_player_shot_fired)
	EnemySignals.player_detected.connect(_on_enemy_player_detected)
	EnemySignals.zombie_detected.connect(_on_zombie_detected)

# --- SEÑALES ---
func _on_zombie_detected(zombie_pos: Vector2, detector_z_pos: Vector2, alert_radius_z: float):
	if current_target != null: return
	if global_position.distance_to(detector_z_pos) <= alert_radius_z:
		trigger_investigation(zombie_pos)

func _on_enemy_player_detected(player_pos: Vector2, detector_pos: Vector2, alert_radius: float):
	if current_target != null: return
	if global_position.distance_to(detector_pos) <= alert_radius:
		trigger_investigation(player_pos)

func _on_player_shot_fired():
	if current_target != null: return
	# Verificamos si lo escuchamos y NO lo estamos viendo
	if global_position.distance_to(target.global_position) <= HEAR_DISTANCE and not current_has_target:
		trigger_investigation(target.global_position)

func trigger_investigation(pos: Vector2):
	last_heard_position = pos
	current_target = null
	current_target_type = TargetType.NONE
	current_state = State.INVESTIGATING
	investigating = true
	investigation_timer = INVESTIGATION_TIME
	nav_update_timer = 0.0 # Forzar actualización de ruta inmediata

# --- SISTEMA DE VISIÓN OPTIMIZADO ---
func find_any_target() -> bool:
	# Prioridad 1: Jugador
	if is_node_visible(target):
		current_target = target
		current_target_type = TargetType.PLAYER
		last_known_target_pos = target.global_position
		if alert_cooldown <= 0:
			EnemySignals.player_detected.emit(target.global_position, global_position, 600.0)
			alert_cooldown = ALERT_COOLDOWN_TIME
		return true
	
	# Prioridad 2: Zombies (Iterar todos los zombies solo si no ve al jugador)
	var zombies = get_tree().get_nodes_in_group("Enemyz")
	for zombie in zombies:
		if is_node_visible(zombie):
			current_target = zombie
			current_target_type = TargetType.ZOMBIE
			last_known_target_pos = zombie.global_position
			if alert_cooldown <= 0:
				EnemySignals.zombie_detected.emit(zombie.global_position, global_position, 600.0)
				alert_cooldown = ALERT_COOLDOWN_TIME
			return true
	
	# Si no ve a nadie pero tenía un target, activamos la pérdida de objetivo
	if current_target != null:
		current_target = null
		current_target_type = TargetType.NONE
	return false

# Esta función reemplaza is_player_visible y is_zombie_visible
func is_node_visible(node: Node2D) -> bool:
	if node == null: return false
	
	# 1. Filtro barato: Distancia (Evita raycasts innecesarios si está muy lejos)
	var distance = global_position.distance_to(node.global_position)
	if distance > length: return false
	
	# 2. Filtro barato: Cono de visión
	var node_local = to_local(node.global_position)
	var angle_to_node = direction.angle_to(node_local)
	if abs(angle_to_node) > half: return false
	
	# 3. Filtro caro: Raycast físico (Solo se ejecuta si pasó los dos filtros anteriores)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, node.global_position)
	query.exclude = [self]
	# Opcional: query.collision_mask = ... (Para que solo choque con paredes y cuerpos)
	var result = space_state.intersect_ray(query)
	
	return result and result.collider == node

func reaction():
	if current_target != null: return
	var distance_to_target = position.distance_to(target.position)
	if distance_to_target <= REACT_DISTANCE: 
		var target_angle = (target.global_position - global_position).angle()
		rotation = lerp_angle(rotation, target_angle, 0.1) 
	elif hitbox:
		current_state = State.SEARCHING
		hitbox = false

func _physics_process(delta: float) -> void:
	if life <= 0:
		queue_free()
		return

	if alert_cooldown > 0: alert_cooldown -= delta
	if investigation_timer > 0: investigation_timer -= delta
	
	reaction()
	
	# --- THROTTLING DE VISIÓN ---
	vision_timer -= delta
	if vision_timer <= 0:
		current_has_target = find_any_target()
		# El randf_range evita "lag spikes" distribuyendo los raycasts de los enemigos en diferentes frames
		vision_timer = VISION_CHECK_INTERVAL + randf_range(0.0, 0.05)

	# --- THROTTLING DE NAVEGACIÓN ---
	nav_update_timer -= delta
	if nav_update_timer <= 0:
		update_navigation_paths()
		nav_update_timer = NAV_UPDATE_INTERVAL + randf_range(0.0, 0.05)

	# --- LÓGICA DE ESTADOS ---
	if investigating and current_state != State.INVESTIGATING and not current_has_target:
		current_state = State.INVESTIGATING
	elif current_has_target and current_target != null and is_instance_valid(current_target):
		investigating = false
		var target_angle = (current_target.global_position - global_position).angle()
		rotation = lerp_angle(rotation, target_angle, 0.1)
		
		if current_target_type == TargetType.PLAYER:
			if current_state in [State.PATROLLING, State.INVESTIGATING, State.COMBAT_ZOMBIE, State.SEARCHING]:
				current_state = State.APPROACHING
		elif current_target_type == TargetType.ZOMBIE:
			if current_state in [State.PATROLLING, State.INVESTIGATING, State.APPROACHING]:
				current_state = State.COMBAT_ZOMBIE

	if hitbox: hitbox = false

	# Ejecutar el comportamiento según el estado actual
	match current_state:
		State.INVESTIGATING: investigate_behavior()
		State.APPROACHING, State.COMBAT, State.RETREATING: combat_behavior()
		State.COMBAT_ZOMBIE: combat_zombie_behavior()
		State.PATROLLING: patrol_behavior() 
		State.SEARCHING: hurt_behavior()

func update_navigation_paths():
	if current_state == State.INVESTIGATING:
		nav.target_position = last_heard_position
	elif current_has_target and current_target != null:
		nav.target_position = current_target.global_position
	elif memory and search_time_remaining > 0:
		nav2.target_position = last_known_target_pos

# --- COMPORTAMIENTOS ---
func investigate_behavior():
	var global_next_pos = nav.get_next_path_position()
	var dir = (global_next_pos - global_position).normalized()
	look_at(last_heard_position)
	velocity = dir * SPEED
	move_and_slide()
	
	if global_position.distance_to(last_heard_position) < 30.0:
		if investigation_timer <= 0:
			investigating = false
			current_state = State.PATROLLING

func combat_behavior():
	if current_has_target and current_target != null:
		search_time_remaining = 8.0 
		memory = true
		var global_next_pos = nav.get_next_path_position()
		var dir = (global_next_pos - global_position).normalized()
		var dir_to_target = (current_target.global_position - global_position).normalized()
		var dist = global_position.distance_to(current_target.global_position)
		
		match current_state:
			State.APPROACHING:
				if dist <= COMBAT_DISTANCE: current_state = State.COMBAT
				else: velocity = dir * SPEED
			State.COMBAT:
				if dist < RETREAT_DISTANCE: current_state = State.RETREATING
				elif dist > COMBAT_DISTANCE * 1.3: current_state = State.APPROACHING
				else: velocity = Vector2.ZERO
			State.RETREATING:
				if dist >= COMBAT_DISTANCE: current_state = State.COMBAT
				else: velocity = -dir_to_target * SPEED * 1.4
		move_and_slide()
		
		# Disparar si puede
		if cooldown.is_stopped() and canShoot:
			cooldown.start() # Llama a _on_cooldown_timeout()
			
	else:
		# LÓGICA DE MEMORIA (Cuando pierde de vista al jugador)
		if memory and search_time_remaining > 0:
			search_time_remaining -= get_physics_process_delta_time()
			var global_next_pos = nav2.get_next_path_position()
			var dir = (global_next_pos - global_position).normalized()
			look_at(global_next_pos)
			velocity = dir * (SPEED / 1.75)
			move_and_slide()
			
			if global_position.distance_to(last_known_target_pos) < 10.0 or search_time_remaining <= 0:
				current_state = State.PATROLLING
				memory = false

func combat_zombie_behavior():
	if not current_has_target or current_target_type != TargetType.ZOMBIE or not is_instance_valid(current_target):
		current_state = State.PATROLLING
		return
		
	memory = false
	var global_next_pos = nav.get_next_path_position()
	var dir = (global_next_pos - global_position).normalized()
	var dist = global_position.distance_to(current_target.global_position)
	
	if dist > COMBAT_DISTANCE * 0.8: velocity = dir * SPEED
	elif dist < RETREAT_DISTANCE: velocity = -dir * (SPEED * 1.8)
	else: velocity = Vector2.ZERO
		
	move_and_slide()
	
	if cooldown.is_stopped() and canShoot:
		cooldown.start()

func patrol_behavior():
	# Si aún no es hora de regresar, nos aseguramos de que no camine
	if patrol_timer < PATROL_TIME:
		velocity = Vector2.ZERO
		
	patrol_timer += get_physics_process_delta_time()
	
	match patrol_state:
		PatrolState.TURNING_RIGHT:
			rotate(PATROL_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle += PATROL_ROTATION_SPEED * get_physics_process_delta_time()
			if current_patrol_angle >= MAX_PATROL_ANGLE: patrol_state = PatrolState.TURNING_LEFT
		PatrolState.TURNING_LEFT:
			rotate(-PATROL_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle -= PATROL_ROTATION_SPEED * get_physics_process_delta_time()
			if current_patrol_angle <= -MAX_PATROL_ANGLE: patrol_state = PatrolState.TURNING_RIGHT
	
	# Ya pasaron los 10 segundos, toca regresar a su base
	if patrol_timer >= PATROL_TIME:
		var dist_initial = global_position.distance_to(initial_position)
		
		# Simplificamos la distancia a 10.0 para evitar que se queden en el limbo
		if dist_initial > 10.0:  
			
			# ¡EL ARREGLO DE OPTIMIZACIÓN ESTÁ AQUÍ!
			# Solo actualizamos el target_position si no lo hemos asignado previamente.
			if nav2.target_position != initial_position:
				nav2.target_position = initial_position
			
			var next_pos = nav2.get_next_path_position()
			var return_dir = (next_pos - global_position).normalized()
			velocity = return_dir * (SPEED / 2)
			
			# Opcional pero recomendado: que mire hacia donde está dando el siguiente paso 
			# en la ruta, en lugar de mirar su destino a través de los muros.
			look_at(global_position + velocity) 
			
		else:
			# Ya llegó a su destino, reseteamos todo
			patrol_timer = 0.0
			velocity = Vector2.ZERO
			
			# Si quieres que vuelvan a mirar hacia la derecha al llegar:
			# rotation = 0 
			
	move_and_slide()

func hurt_behavior():
	velocity = Vector2.ZERO
	patrol_timer += get_physics_process_delta_time()
	
	match patrol_state:
		PatrolState.TURNING_RIGHT:
			rotate(PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle += PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time()
			if current_patrol_angle >= MAX_HURT_PATROL_ANGLE: patrol_state = PatrolState.TURNING_LEFT
		PatrolState.TURNING_LEFT:
			rotate(-PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time())
			current_patrol_angle -= PATROL_HURT_ROTATION_SPEED * get_physics_process_delta_time()
			if current_patrol_angle <= -MAX_HURT_PATROL_ANGLE: patrol_state = PatrolState.TURNING_RIGHT
	
	if patrol_timer >= PATROL_HURT_TIME:
		current_state = State.PATROLLING
		patrol_timer = 0.0
	move_and_slide()

# --- FUNCIONES DE DAÑO Y DISPARO ---
func take_damage(amount):
	life -= amount
	atked.play()

func take_damage_z(amount):
	life -= amount
	atked2.play()

func _on_cooldown_timeout() -> void:
	if canShoot and current_has_target:
		canShoot = false
		bulletCount = 0
		var random_cd = randf_range(min_cooldown, max_cooldown)
		await get_tree().create_timer(random_cd).timeout
		
		if current_target_type == TargetType.PLAYER: shootSequence()
		elif current_target_type == TargetType.ZOMBIE: shootSequence_z()

func shootSequence():
	if bulletCount < max_Bullets and life > 0:
		shoot()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		if current_has_target: 
			shootSequence()
		else:
			bulletCount = 0
			canShoot = true
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true

func shootSequence_z():
	if bulletCount < max_Bullets and life > 0:
		shoot()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		shootSequence_z()
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true

const SHOT_ALERT_RADIUS = 400.0  
func shoot():
	var newBullet = bullet.instantiate()
	newBullet.damage = damage
	newBullet.sound_c = sound
	newBullet.position = $Sprite2D/Spawn_bullet.global_position
	
	EnemySignals.soldier_shot_fired.emit(global_position, global_position, SHOT_ALERT_RADIUS)
	
	if current_target != null:
		var base_direction = (current_target.global_position - global_position).normalized()
		var spread_angle = deg_to_rad(10) 
		var random_angle = randf_range(-spread_angle, spread_angle)
		var final_direction = base_direction.rotated(random_angle)
		newBullet.direction = final_direction
		newBullet.rotation = final_direction.angle()
		get_parent().add_child(newBullet)
