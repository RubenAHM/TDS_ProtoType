extends CharacterBody2D

@onready var target = get_tree().get_first_node_in_group("Player")
@onready var nav = $NavigationAgent2D
@onready var nav2 = $NavigationAgent2D2
@onready var cooldown = $Cooldown
var attack = preload("res://scenes/zattack.tscn")
const SPEED = 60.0
var hitbox = false
var attackCount = 0 #Variable para validar la cantidad de ataques que se realizan
var max_attacks = 2 #Variable que indica cuántos ataques se pueden realizar
var memory = false
var search_time_remaining: float = 0.0
const REACT_DISTANCE = 60
const HEAR_DISTANCE = 250
const COMBAT_DISTANCE = 28
var last_heard_position: Vector2
var investigating = false
var investigation_timer: float = 0.0
const INVESTIGATION_TIME = 6.0  # Tiempo que investiga antes de volver a patrullar

var min_cooldown = 1.2
var max_cooldown = 2.3

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

# --- VARIABLES DE OPTIMIZACIÓN ---
var vision_timer: float = 0.0
const VISION_CHECK_INTERVAL = 0.25 # Revisa 4 veces por segundo
var nav_update_timer: float = 0.0
const NAV_UPDATE_INTERVAL = 0.3 # Actualiza la ruta de navegación 3 veces por segundo
var current_has_target: bool = false
var last_known_target_pos: Vector2

# --- NUEVO: Sistema de amenaza soldado ---
var soldier_threat_timer: float = 0.0
const SOLDIER_THREAT_TIME = 2.0  # Segundos que un soldado se considera amenaza tras detectarlo cerca
const SOLDIER_THREAT_DISTANCE = 100.0  # Distancia máxima para considerar soldado como amenaza inmediata

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
	if distance_to_player <= HEAR_DISTANCE and not current_has_target:
		last_heard_position = target.global_position
		investigating = true
		investigation_timer = INVESTIGATION_TIME
		current_state = State.INVESTIGATING

func _draw():
	#mero debug esta monda
	var left_dir = direction.rotated(-half) * length
	var right_dir = direction.rotated(half) * length
	
	draw_line(Vector2.ZERO, left_dir, Color.YELLOW, 2.0)
	draw_line(Vector2.ZERO, right_dir, Color.YELLOW, 2.0)

# --- SISTEMA DE VISIÓN OPTIMIZADO ---
func find_any_target() -> bool:
	# --- PRIORIDAD 1: Soldados amenazantes (cerca o atacando recientemente) ---
	var soldiers = get_tree().get_nodes_in_group("Soldier")
	var nearby_soldier = null
	for soldier in soldiers:
		if is_node_visible(soldier):
			var dist = global_position.distance_to(soldier.global_position)
			# Si está muy cerca o el timer de amenaza está activo
			if dist <= SOLDIER_THREAT_DISTANCE or soldier_threat_timer > 0:
				nearby_soldier = soldier
				break

	if nearby_soldier != null:
		current_target = nearby_soldier
		current_target_type = TargetType.SOLDIER
		last_known_target_pos = nearby_soldier.global_position
		soldier_threat_timer = SOLDIER_THREAT_TIME
		if alert_cooldown <= 0:
			EnemySignals.soldier_shot_fired.emit(nearby_soldier.global_position, global_position, 600.0)
			alert_cooldown = ALERT_COOLDOWN_TIME
		return true

	# --- PRIORIDAD 2: Jugador (solo si no hay soldado amenazante) ---
	if is_node_visible(target):
		current_target = target
		current_target_type = TargetType.PLAYER
		last_known_target_pos = target.global_position
		return true

	# --- PRIORIDAD 3: Cualquier otro soldado en visión (sin amenaza inmediata) ---
	for soldier in soldiers:
		if is_node_visible(soldier):
			current_target = soldier
			current_target_type = TargetType.SOLDIER
			last_known_target_pos = soldier.global_position
			if alert_cooldown <= 0:
				EnemySignals.soldier_shot_fired.emit(soldier.global_position, global_position, 600.0)
				alert_cooldown = ALERT_COOLDOWN_TIME
			return true

	# --- Nada en visión ---
	if current_target != null:
		current_target = null
		current_target_type = TargetType.NONE
	return false

# Esta función reemplaza is_player_visible y is_soldier_visible
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
	elif hitbox and current_target == null:
		current_state = State.SEARCHING
		hitbox = false

func _physics_process(delta: float) -> void:
	if current_state != State.STANDING:
		$AnimationPlayer.play("Z_Stand")
	if life <= 0:
		queue_free()
		return

	if alert_cooldown > 0: alert_cooldown -= delta
	if investigation_timer > 0: investigation_timer -= delta
	if soldier_threat_timer > 0: soldier_threat_timer -= delta

	reaction()

	# --- THROTTLING DE VISIÓN ---
	vision_timer -= delta
	if vision_timer <= 0:
		current_has_target = find_any_target()
		# El randf_range evita "lag spikes" distribuyendo los raycasts de los enemigos en diferentes frames
		vision_timer = VISION_CHECK_INTERVAL + randf_range(0.0, 0.05)

	check_player_collision()
	
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
			if current_state in [State.STANDING, State.INVESTIGATING, State.COMBAT_SOLDIER]:
				current_state = State.APPROACHING
		elif current_target_type == TargetType.SOLDIER:
			if current_state in [State.STANDING, State.INVESTIGATING, State.APPROACHING]:
				current_state = State.COMBAT_SOLDIER

	if hitbox: hitbox = false

	# Ejecutar el comportamiento según el estado actual
	match current_state:
		State.INVESTIGATING: investigate_behavior()
		State.APPROACHING, State.COMBAT: combat_behavior()
		State.COMBAT_SOLDIER: combat_soldier_behavior()
		State.STANDING: velocity = Vector2.ZERO
		State.SEARCHING: patrol_behavior()

func update_navigation_paths():
	if current_state == State.INVESTIGATING:
		nav.target_position = last_heard_position
	elif current_has_target and current_target != null and is_instance_valid(current_target):
		nav.target_position = current_target.global_position
	elif memory and search_time_remaining > 0:
		nav2.target_position = last_known_target_pos

# --- COMPORTAMIENTOS ---
func investigate_behavior():
	#Comportamiento exclusivo para investigación
	var global_next_pos = nav.get_next_path_position()
	var dir = (global_next_pos - global_position).normalized()
	look_at(last_heard_position)
	velocity = dir * SPEED * 2
	move_and_slide()

	#Si llega a la posición o ve al jugador, cambiar estado
	var distance_to_sound = global_position.distance_to(last_heard_position)

	if distance_to_sound < 30.0:
		if is_node_visible(current_target):
			current_state = State.APPROACHING  #Cambiar a combate si ve al jugador
		else:
			investigating = false
			current_state = State.STANDING

func combat_behavior():
	if current_has_target and current_target != null and is_instance_valid(current_target):
		search_time_remaining = 12.0  #Resetear tiempo de búsqueda
		memory = true
		var global_next_pos = nav.get_next_path_position()
		var direction = (global_next_pos - global_position).normalized()
		var direction1 = (current_target.global_position - global_position).normalized()
		var distance_to_target = position.distance_to(current_target.position)
	
		match current_state:
			State.APPROACHING:
				if distance_to_target <= COMBAT_DISTANCE:
					current_state = State.COMBAT
				else:
					velocity = direction * SPEED * 2.0

			State.COMBAT:
				if distance_to_target > COMBAT_DISTANCE:
					current_state = State.APPROACHING
				else:
					velocity = Vector2.ZERO
	
		move_and_slide()
	else:
		if memory and search_time_remaining > 0:
			search_time_remaining -= get_physics_process_delta_time()
			var global_next_pos = nav2.get_next_path_position()
			var direction = (global_next_pos - global_position).normalized()
			look_at(global_next_pos)
			velocity = direction * SPEED * 2.0
			move_and_slide()

			var distance_to_last_seen = global_position.distance_to(global_next_pos)
			if distance_to_last_seen < 10.0 or search_time_remaining <= 0:
				if is_node_visible(current_target):
					current_state = State.APPROACHING
				else:
					current_state = State.STANDING
					memory = false

func combat_soldier_behavior():
	if current_target_type != TargetType.SOLDIER:
		current_state = State.STANDING
		return
	memory = false
	# Proteger contra targets destruidos (soldado murió)
	if current_target == null or not is_instance_valid(current_target):
		current_state = State.STANDING
		current_target = null
		current_target_type = TargetType.NONE
		return
	if is_node_visible(current_target):
		var global_next_pos = nav.get_next_path_position()
		var direction = (global_next_pos - global_position).normalized()
		var distance_to_target = position.distance_to(current_target.position)
	
		if distance_to_target > COMBAT_DISTANCE:
			velocity = direction * SPEED * 2.0
		else:
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

func take_damage_z(amount):
	life -= amount
	# El soldado que nos atacó es una amenaza inmediata
	soldier_threat_timer = SOLDIER_THREAT_TIME

# --- DETECCIÓN DE ATAQUE (Restaurada y optimizada) ---
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
	var random_cooldown = randf_range(min_cooldown, max_cooldown)
	await get_tree().create_timer(random_cooldown).timeout
	if current_target != null and is_instance_valid(current_target):
		var distance_to_target = position.distance_to(current_target.position)
		if distance_to_target <= COMBAT_DISTANCE:
			attackSequence()

func attackSequence():
	if attackCount < max_attacks and life > 0:
		attacking()
		attackCount += 1
		$Timer.start()
		await $Timer.timeout
		attackSequence()
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
	if target != null:
		nav2.target_position = target.global_position

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
