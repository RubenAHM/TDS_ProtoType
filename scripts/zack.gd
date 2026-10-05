extends CharacterBody2D

const SPEED = 100.0

# 1. DICCIONARIO MAESTRO DE ARMAS
const WEAPONS_DATA = {
	1: {"name": "GUN", "mag_cap": 12, "dmg": 50, "anim": "aim_gun", "ammo_type": "9mm", "is_light": true},
	2: {"name": "MP5", "mag_cap": 30, "dmg": 45, "anim": "aim_mp5", "ammo_type": "9mm", "is_light": true},
	3: {"name": "M16", "mag_cap": 45, "dmg": 100, "anim": "aim_m16", "ammo_type": "m16", "is_light": false},
	4: {"name": "SHTGUN", "mag_cap": 7, "dmg": 85, "anim": "aim_shtgn", "ammo_type": "gauge", "is_light": false}
}

enum States {IDLE, WALKING, RUNNING, GUN, MP5, M16, SHTGUN}
var state: States = States.IDLE

signal shot_fired
var bullet = preload("res://scenes/bullet.tscn")
var Spray_Shtgn = preload("res://scenes/shtgn_spray.tscn")

@onready var player = $atked
@onready var player2 = $atked2
@onready var grunt = $grunt
@onready var reload_sound = $reload_23
@onready var reload_shtgn = $reload_4
@onready var cweapon = $c_weapon
@onready var pck_ammo = $pck_ammo
@onready var heal_sound = $heal_sound 
@onready var footstep_sound_default = $ftsteps_default

var shooting = false
var canShoot = true
var dmg
var hitbox = false
var dead = false
var invul = true
var dmg_tkn = 0
var reloading = false

# VARIABLES PARA SONIDO DE PASOS
var is_moving = false
var footstep_timer: float = 0.0
var walk_step_interval = 0.45
var run_step_interval = 0.35
var current_step_interval = 0.45

# Variable para controlar si está disparando (para mostrar animación de apuntar)
var is_shooting_animation = false


@onready var Zack_panting = $Zack_panting
var stamina_recovered_since_last_panting = 0.0
var is_panting = false
const STAMINA_RECOVER_THRESHOLD = 30.0  # Puntos a recuperar para resetear
const MIN_PANT_STAMINA = 50.0  # Stamina mínima para empezar a jadear

func _ready() -> void:
	$HUD/Health.points[1].x = Global.life
	Global.health_picked_up.connect(_on_health_picked_up)
	sync_weapon_data()
	update_hud()

func _on_health_picked_up(heal_amount: int):
	if heal_sound:
		heal_sound.play()

func add_m16_ammo(amount):
	Global.mg_amm3 += amount
	pck_ammo.play()
	update_hud()
		
func add_9mm_ammo(amount):
	Global.mg_amm12 += amount
	pck_ammo.play()
	update_hud()

func add_gauge_ammo(amount):
	Global.mg_amm4 += amount
	pck_ammo.play()
	update_hud()

func die():
	get_tree().quit()

func take_dmg():
	if not dead:
		$HUD/Health.points[1].x -= dmg_tkn
		if $HUD/Health.points[1].x <= 0:
			dead = true
			die()
		$Invul.start()
		await $Invul.timeout
		if !invul:
			hitbox = true

func take_dmg_ranged(amount):
	if not dead:
		$HUD/Health.points[1].x -= amount
		if randi_range(0, 8) == 2: grunt.play()
		player2.play()
		if $HUD/Health.points[1].x <= 0:
			dead = true
			die()

func take_dmg_melee(amount):
	if not dead:
		$HUD/Health.points[1].x -= amount
		if randi_range(0, 8) == 2: grunt.play()
		player.play()
		if $HUD/Health.points[1].x <= 0:
			dead = true
			die()

func _physics_process(delta: float) -> void:
	handle_weapon_selection()
	look_at_mouse()
	recovering()
	update_panting()
	
	# 1. MOVIMIENTO GLOBAL (Estilo Hotline Miami)
	# Input.get_vector lee las direcciones globales y las devuelve normalizadas.
	var input_vector = Input.get_vector("Left", "Right", "Up", "Down")
	
	if Input.is_action_just_released("Run"):
		$Timer.start()
		await $Timer.timeout
		canShoot = true
	
	if input_vector.length() > 0:
		is_moving = true
		if Input.is_action_pressed("Run") and $HUD/Stamina.points[1].x > 1 :
			$HUD/Stamina.points[1].x -= 0.3
			if Input.is_action_pressed("Shoot"):
				return
			canShoot = false
			# Aplicamos la velocidad de correr (el vector ya está normalizado)
			input_vector = input_vector * (SPEED * 2)
			state = States.RUNNING
			current_step_interval = run_step_interval
		else:
			# Aplicamos la velocidad de caminar normal
			input_vector = input_vector * SPEED
			current_step_interval = walk_step_interval
			
			var weapon_data = WEAPONS_DATA[Global.current_weapon]
			if weapon_data.is_light and not is_shooting_animation and not reloading:
				state = States.WALKING
			elif not is_shooting_animation and not reloading:
				state = States.get(weapon_data.name)
	else:
		is_moving = false
		if not is_shooting_animation and not reloading:
			var weapon_data = WEAPONS_DATA[Global.current_weapon]
			state = States.get(weapon_data.name)
		if footstep_sound_default.playing:
			footstep_sound_default.stop()
		
	# 2. FÍSICAS RESPONSIVAS (Cero patinaje)
	# Reemplazamos el 'lerp' por asignación directa de velocidad.
	velocity = input_vector
	move_and_slide()
	
	handle_footsteps(delta)
	
	if is_shooting_animation:
		var weapon_data = WEAPONS_DATA[Global.current_weapon]
		state = States.get(weapon_data.name)
	
	set_state()
	
	if Input.is_action_pressed("Shoot") and canShoot and not reloading:
		canShoot = false
		is_shooting_animation = true
		shootSequence()
		
	if Input.is_action_just_pressed("reload") and not reloading:
		reloading = true
		reload()
		
	if hitbox:
		hitbox = false
		take_dmg()

func handle_footsteps(delta: float):
	if is_moving:
		footstep_timer -= delta
		if footstep_timer <= 0:
			play_footstep()
			footstep_timer = current_step_interval
	else:
		footstep_timer = 0.0

func recovering():
	if $HUD/Stamina.points[1].x < 100 and state != States.RUNNING:
		var previous_stamina = $HUD/Stamina.points[1].x
		$HUD/Stamina.points[1].x += 0.25
		var recovered_amount = $HUD/Stamina.points[1].x - previous_stamina
		
		# Acumular la stamina recuperada
		if recovered_amount > 0 and is_panting:
			stamina_recovered_since_last_panting += recovered_amount
			
			# Si se ha recuperado suficiente stamina, detener el jadeo
			if stamina_recovered_since_last_panting >= STAMINA_RECOVER_THRESHOLD:
				stop_panting()

func update_panting():
	var current_stamina = $HUD/Stamina.points[1].x
	
	# Verificar si debería estar jadeando
	if current_stamina <= MIN_PANT_STAMINA and state != States.RUNNING:
		if not is_panting:
			start_panting()
		# Actualizar volumen según la stamina (más baja stamina = más alto)
		update_pant_volume()
	elif is_panting and current_stamina > MIN_PANT_STAMINA: #or state == States.RUNNING):
		# Si la stamina subió por encima del umbral o está corriendo, detener jadeo
		stop_panting()

func start_panting():
	if Zack_panting and not is_panting:
		is_panting = true
		stamina_recovered_since_last_panting = 0.0
		Zack_panting.playing = true
		update_pant_volume()

func stop_panting():
	if Zack_panting and is_panting:
		is_panting = false
		Zack_panting.playing = false
		stamina_recovered_since_last_panting = 0.0

func update_pant_volume():
	if not Zack_panting:
		return
	
	var current_stamina = $HUD/Stamina.points[1].x
	
	# Calcular volumen: entre -30 dB (stamina alta) y 0 dB (stamina 0)
	# Fórmula: cuanto menos stamina, más volumen
	var stamina_ratio = clamp(current_stamina / MIN_PANT_STAMINA, 0.0, 1.0)
	# Invertir ratio: 0 stamina = ratio 0, 50 stamina = ratio 1
	var inverted_ratio = 1.0 - stamina_ratio
	
	# Mapear a dB: entre -25 dB y 0 dB
	var volume_db = -5.0 + (inverted_ratio * 25.0)
	
	# Limitar entre -30 dB y 0 dB
	volume_db = clamp(volume_db, -30.0, 0.0)
	
	Zack_panting.volume_db = volume_db

func play_footstep():
	if footstep_sound_default and footstep_sound_default.stream:
		footstep_sound_default.pitch_scale = randf_range(0.9, 1.1)
		footstep_sound_default.play()

func handle_weapon_selection():
	var prev_weapon = Global.current_weapon
	
	if Input.is_action_just_pressed("mg1"): Global.current_weapon = 1
	elif Input.is_action_just_pressed("mg2"): Global.current_weapon = 2
	elif Input.is_action_just_pressed("mg3"): Global.current_weapon = 3
	elif Input.is_action_just_pressed("mg4"): Global.current_weapon = 4
	
	if prev_weapon != Global.current_weapon:
		cweapon.play()
		sync_weapon_data()
		update_hud()

func sync_weapon_data():
	var data = WEAPONS_DATA[Global.current_weapon]
	dmg = data.dmg
	Global.mag = get_current_mag()
	Global.total = get_current_total_ammo()

func set_state() -> void:
	match state:
		States.IDLE:
			toggle_sprites(true, false, false)
			$AnimationPlayer.play("idle")
		States.WALKING:
			toggle_sprites(true, false, false)
			$AnimationPlayer.play("walk")
		States.RUNNING:
			toggle_sprites(false, false, true)
			$AnimationPlayer.play("run")
		States.GUN:
			toggle_sprites(false, true, false)
			$AnimationPlayer.play("aim_gun")
		States.MP5:
			toggle_sprites(false, true, false)
			$AnimationPlayer.play("aim_mp5")
		States.M16:
			toggle_sprites(false, true, false)
			$AnimationPlayer.play("aim_m16")
		States.SHTGUN:
			toggle_sprites(false, true, false)
			$AnimationPlayer.play("aim_shtgn")

func toggle_sprites(s2d, gnz, run):
	$Sprite2D.visible = s2d
	$gunz.visible = gnz
	$run.visible = run

func update_hud():
	$HUD/Ammo.text = "Ammo: " + str(get_current_mag()) + " / " + str(get_current_total_ammo())

func reload():
	var data = WEAPONS_DATA[Global.current_weapon]
	var max_mag = data.mag_cap
	var current_mag = get_current_mag()
	var total_ammo = get_current_total_ammo()
	
	var needed = max_mag - current_mag
	var available = min(needed, total_ammo)
	
	if available > 0:
		if Global.current_weapon == 4: reload_shtgn.play()
		else: reload_sound.play()
		
		$Reload_time.start()
		await $Reload_time.timeout
		
		set_current_mag(current_mag + available)
		set_current_total_ammo(total_ammo - available)
		canShoot = true
		update_hud()
	reloading = false

func get_current_mag():
	match Global.current_weapon:
		1: return Global.mg_mag1
		2: return Global.mg_mag2
		3: return Global.mg_mag3
		4: return Global.mg_mag4
	return 0

func get_current_total_ammo():
	match WEAPONS_DATA[Global.current_weapon].ammo_type:
		"9mm": return Global.mg_amm12
		"m16": return Global.mg_amm3
		"gauge": return Global.mg_amm4
	return 0

func set_current_mag(val):
	match Global.current_weapon:
		1: Global.mg_mag1 = val
		2: Global.mg_mag2 = val
		3: Global.mg_mag3 = val
		4: Global.mg_mag4 = val

func set_current_total_ammo(val):
	match WEAPONS_DATA[Global.current_weapon].ammo_type:
		"9mm": Global.mg_amm12 = val
		"m16": Global.mg_amm3 = val
		"gauge": Global.mg_amm4 = val

func shootSequence():
	var current_mag = get_current_mag()
	if Input.is_action_pressed("Shoot") and current_mag > 0 and not reloading:
		set_current_mag(current_mag - 1)
		shoot()
		update_hud()
		
		var timer_name = ""
		match Global.current_weapon:
			1: timer_name = "Hg_fr"
			2: timer_name = "Mp5_fr"
			3: timer_name = "M16_fr"
			4: timer_name = "Shotgun_fr"
			
		var timer = get_node(timer_name)
		timer.start()
		await timer.timeout
		shootSequence()
	else:
		if current_mag <= 0: 
			print("Reload!")
		$Timer.start()
		await $Timer.timeout
		canShoot = true
		is_shooting_animation = false  # Terminó de disparar, volver a animación normal

func look_at_mouse():
	look_at(get_global_mouse_position())

func shoot():
	shot_fired.emit()
	var mouse_pos = get_global_mouse_position()
	var newBullet = bullet.instantiate()
	var spawn_pos = $Sprite2D/SpawnPoint
	var sp = spawn_pos.global_position
	var direction = (mouse_pos - global_position).normalized() #(get_global_mouse_position() - spawn_pos)
	var is_mouse_behind = direction.dot(transform.x) < 30
	
	if is_mouse_behind:
		# Forzar spawn en la dirección opuesta o usar un spawn point alternativo
		sp = global_position + direction * 30
	newBullet.position = sp
	newBullet.rotation = direction.angle()
	newBullet.velocity = direction
	get_parent().add_child(newBullet)
	
	if Global.current_weapon == 4:
		for i in range(2, 4):
			var spawn = get_node("Sprite2D/SpawnPoint" + str(i))
			var sp2 = spawn.global_position
			var newSpray = Spray_Shtgn.instantiate()
			var dir_spray = (mouse_pos - global_position).normalized() #(get_global_mouse_position() - spawn.global_position)
			if is_mouse_behind:
				# Forzar spawn en la dirección opuesta o usar un spawn point alternativo
				sp = global_position + direction * 30
			newSpray.position = sp2
			newSpray.rotation = dir_spray.angle()
			newSpray.velocity = dir_spray
			get_parent().add_child(newSpray)
	
