extends CharacterBody2D

@onready var target = get_tree().get_first_node_in_group("Player")
@onready var nav = $NavigationAgent2D
@onready var nav2 = $NavigationAgent2D2
@onready var atked = $atked
@onready var atked2 = $atked2
var bullet = preload("res://scenes/enemy_bullet.tscn")
const SPEED = 55.0
const damage = 5
const sound = 3
var hitbox = false
var life = 1400
var bulletCount = 0 #Variable para validar la cantidad de balas que se disparan
var max_Bullets = 1 #Variable que indica cuántas balas se pueden disparar
var canShoot = true #Variable bandera que activa el uso de las balas
var min_cooldown = 0.8
var max_cooldown = 1.8
var memory = false
var search_time_remaining: float = 0.0
const COMBAT_DISTANCE = 80.0  # Distancia de combate
const STANDING_DISTANCE = 50.0  # Distancia de combate sin moverse
const RETREAT_DISTANCE = 0.0  # Distancia para retroceder
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 260

var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 5.0  # Tiempo que investiga antes de volver a patrullar

enum State {APPROACHING, COMBAT, RETREATING, INVESTIGATING, PATROLLING, COMBAT_ZOMBIE, SEARCHING}
#Esta puta mierda que está acá determina el perro objetivo del soldado del coño este, no tocar coñodelamadre
enum TargetType {NONE, PLAYER, ZOMBIE}
var current_target_type: TargetType = TargetType.PLAYER
var current_target: Node2D = null
var current_state = State.PATROLLING

enum PatrolState {TURNING_RIGHT, TURNING_LEFT}
var patrol_state: PatrolState = PatrolState.TURNING_RIGHT

@onready var cooldown = $Cooldown
@onready var spawn_points = [
	$Sprite2D/Spawn_bullet,
	$Sprite2D/Spawn_bullet2,
	$Sprite2D/Spawn_bullet3
]
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

# --- VARIABLES DE OPTIMIZACIÓN ---
var vision_timer: float = 0.0
const VISION_CHECK_INTERVAL = 0.25 # Revisa 4 veces por segundo
var nav_update_timer: float = 0.0
const NAV_UPDATE_INTERVAL = 0.3 # Actualiza la ruta de navegación 3 veces por segundo
var current_has_target: bool = false
var last_known_target_pos: Vector2

# --- NUEVO: Sistema de amenaza zombie ---
var zombie_threat_timer: float = 0.0
const ZOMBIE_THREAT_TIME = 2.0  # Segundos que un zombie se considera amenaza tras detectarlo cerca
const ZOMBIE_THREAT_DISTANCE = 100.0  # Distancia máxima para considerar zombie como amenaza inmediata

func _ready():
	# Guardar posición inicial
	initial_position = global_position

	half = deg_to_rad(angle / 2)

	target.shot_fired.connect(_on_player_shot_fired)
	EnemySignals.player_detected.connect(_on_enemy_player_detected)
	EnemySignals.zombie_detected.connect(_on_zombie_detected)

# --- SEÑALES ---
func _on_zombie_detected(zombie_pos: Vector2, detector_z_pos: Vector2, alert_radius_z: float):
	# Ignorar si ya estamos en combate
	if current_target != null:
		return

	# Calcular distancia al detector
	var distance_to_detector = global_position.distance_to(detector_z_pos)

	# Si estamos dentro del radio de alerta
	if distance_to_detector <= alert_radius_z:
		trigger_investigation(zombie_pos)

func _on_enemy_player_detected(player_pos: Vector2, detector_pos: Vector2, alert_radius: float):
	if current_target != null:
		return
	if global_position.distance_to(detector_pos) <= alert_radius:
		trigger_investigation(player_pos)

func _on_player_shot_fired():
	if current_target != null:
		return
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
	# --- PRIORIDAD 1: Zombies amenazantes (cerca o atacando recientemente) ---
	var zombies = get_tree().get_nodes_in_group("Enemyz")
	var nearby_zombie = null
	for zombie in zombies:
		if is_node_visible(zombie):
			var dist = global_position.distance_to(zombie.global_position)
			# Si está muy cerca o el timer de amenaza está activo
			if dist <= ZOMBIE_THREAT_DISTANCE or zombie_threat_timer > 0:
				nearby_zombie = zombie
				break

	if nearby_zombie != null:
		current_target = nearby_zombie
		current_target_type = TargetType.ZOMBIE
		last_known_target_pos = nearby_zombie.global_position
		zombie_threat_timer = ZOMBIE_THREAT_TIME
		if alert_cooldown <= 0:
			EnemySignals.zombie_detected.emit(nearby_zombie.global_position, global_position, 600.0)
			alert_cooldown = ALERT_COOLDOWN_TIME
		return true

	# --- PRIORIDAD 2: Jugador (solo si no hay zombie amenazante) ---
	if is_node_visible(target):
		current_target = target
		current_target_type = TargetType.PLAYER
		last_known_target_pos = target.global_position
		if alert_cooldown <= 0:
			EnemySignals.player_detected.emit(target.global_position, global_position, 600.0)
			alert_cooldown = ALERT_COOLDOWN_TIME
		return true

	# --- PRIORIDAD 3: Cualquier otro zombie en visión (sin amenaza inmediata) ---
	for zombie in zombies:
		if is_node_visible(zombie):
			current_target = zombie
			current_target_type = TargetType.ZOMBIE
			last_known_target_pos = zombie.global_position
			if alert_cooldown <= 0:
				EnemySignals.zombie_detected.emit(zombie.global_position, global_position, 600.0)
				alert_cooldown = ALERT_COOLDOWN_TIME
				return true

	# --- Nada en visión ---
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
	if zombie_threat_timer > 0: zombie_threat_timer -= delta

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
		State.APPROACHING, State.COMBAT: combat_behavior()
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
	# El zombie que nos atacó es una amenaza inmediata
	zombie_threat_timer = ZOMBIE_THREAT_TIME

func check_player_collision():
	if current_target == null:
		if cooldown.is_stopped() == false:
			cooldown.stop()
		return

	# Solo verificar visibilidad del target actual (un raycast por frame máximo)
	if is_node_visible(current_target):
		if cooldown.is_stopped():
			cooldown.start()
	elif not cooldown.is_stopped():
		cooldown.stop()

func _on_cooldown_timeout() -> void:
	if canShoot:
		canShoot = false
		bulletCount = 0
		var random_cooldown = randf_range(min_cooldown, max_cooldown)
		await get_tree().create_timer(random_cooldown).timeout

		if current_target_type != TargetType.ZOMBIE:
			shootSequence()
		elif current_target_type != TargetType.PLAYER:
			shootSequence_z()

func shootSequence():
	if bulletCount < max_Bullets and life > 0:
		shoot_shotgun()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		if is_in_cone():
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
		shoot_shotgun()
		bulletCount += 1
		$Timer.start()
		await $Timer.timeout
		shootSequence_z()
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true

const SHOT_ALERT_RADIUS = 400.0  #Radio en el que los zombies escuchan los disparos

func shoot_shotgun():
	if current_target == null:
		return

	# El spread_angle define qué tan abierto es el abanico
	# En este enfoque, el "centro" ya es la rotación del Sprite
	var spread_angle = deg_to_rad(25)

	for i in range(spawn_points.size()):
		var newBullet = bullet.instantiate()
		newBullet.damage = damage
		newBullet.sound_c = sound

		# 1. Posición inicial: la posición global del spawn point
		newBullet.global_position = spawn_points[i].global_position

		# 3. Dirección: Tomamos la rotación GLOBAL del spawn point y le sumamos el offset
		var final_rotation = spawn_points[i].global_rotation

		# 4. Convertimos esa rotación final en un Vector2 de dirección
		newBullet.direction = Vector2.RIGHT.rotated(final_rotation)
		newBullet.rotation = final_rotation # Para que la bala mire adelante

		get_parent().add_child(newBullet)

func shoot():
	var newBullet = bullet.instantiate()
	newBullet.damage = damage
	newBullet.sound_c = sound
	newBullet.position = $Sprite2D/Spawn_bullet.global_position

	#Emitir señal para que los zombies escuchen el disparo
	EnemySignals.soldier_shot_fired.emit(
		global_position,  #posición del disparo
		global_position,  #posición del soldado
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
		get_parent().add_child(newBullet)

func is_in_cone():
	if target == null:
		return false
	var player_local = to_local(target.global_position)
	var angle_to_player = direction.angle_to(player_local)
	var distance = player_local.length()

	if distance > length:
		return false
	return abs(angle_to_player) <= half

func has_line_of_sight():
	if target == null:
		return false
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result and result.collider == target

func _on_nv_timer_timeout() -> void:
	if current_target == null:
		return
	nav.target_position = current_target.global_position

func _on_memory_timer_timeout() -> void:
	if target != null:
		nav2.target_position = target.global_position
