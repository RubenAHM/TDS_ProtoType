extends CharacterBody2D

const SPEED = 100.0
const Mag_Capacity = {
	1: 12,
	2: 30,
	3: 45,
	4: 7
}
# This enum lists all the possible states the character can be in.
enum States {IDLE, WALKING, RUNNING, GUN, MP5, M16, SHTGUN}

# This variable keeps track of the character's current state.
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
#@onready var mp5 = $mp5
#@onready var m16 = $m16
#var shoot_sound
var shooting = false
var canShoot = true
var dmg
var hitbox = false
var dead = false
var invul = true
var dmg_tkn = 0
var reloading = false

func _ready() -> void:
	$HUD/Health.points[1].x = Global.life

func add_m16_ammo(amount):
	Global.mg_amm3 += amount
	if Global.current_weapon == 3:
		Global.total = Global.mg_amm3
		$HUD/Ammo.text = "Ammo: " + str(Global.mag) + " / " + str(Global.total)
		
func add_9mm_ammo(amount):
	Global.mg_amm12 += amount
	if Global.current_weapon == 1 or Global.current_weapon == 2:
		Global.total = Global.mg_amm12
		$HUD/Ammo.text = "Ammo: " + str(Global.mag) + " / " + str(Global.total)
		

func add_gauge_ammo(amount):
	Global.mg_amm4 += amount
	if Global.current_weapon == 4:
		Global.total = Global.mg_amm4
		$HUD/Ammo.text = "Ammo: " + str(Global.mag) + " / " + str(Global.total)

func die():
	print("quit successfully")
	get_tree().quit()

func take_dmg():
	if not dead:
		$HUD/Health.points[1].x -= dmg_tkn
		#player.play()
		if $HUD/Health.points[1].x == 0:
			dead = true
			die()
		$Invul.start()
		await $Invul.timeout
		if !invul:
			hitbox = true

func take_dmg_ranged(amount):
	if not dead:
		$HUD/Health.points[1].x -= amount
		if randi_range(0, 8) == 2:
			grunt.play()
		player2.play()
		if $HUD/Health.points[1].x == 0:
			dead = true
			die()

func take_dmg_melee(amount):
	if not dead:
		$HUD/Health.points[1].x -= amount
		if randi_range(0, 8) == 2:
			grunt.play()
		player.play()
		if $HUD/Health.points[1].x == 0:
			dead = true
			die()

func _physics_process(delta: float) -> void:
	c_weapon()
	c_weapon_amm()
	c_dmg()
	look_at_mouse()
	set_state()
	var mouse_pos = get_global_mouse_position()
	var direction_to_mouse = (mouse_pos - global_position).normalized()
	if Global.change:
		Global.mag = c_weapon_amm()
		Global.total = c_weapon()
		$HUD/Ammo.text = "Ammo: " + str(Global.mag) + " / " + str(Global.total)
	Global.change = false
	
	
	var palante = direction_to_mouse
	var patra = -direction_to_mouse
	var left = Vector2(palante.y, -palante.x)
	var right = -left
	
	
	
	var input_vector = Vector2.ZERO
	
	if Input.is_action_pressed("Up"):
		if canShoot and (Global.mg1 or Global.mg2):
			state = States.WALKING
		else:
			choose_idle()
		input_vector += palante
	if Input.is_action_pressed("Down"):
		if canShoot and (Global.mg1 or Global.mg2):
			state = States.WALKING
		else:
			choose_idle()
		input_vector += patra
	if Input.is_action_pressed("Left"):
		if canShoot and (Global.mg1 or Global.mg2):
			state = States.WALKING
		else:
			choose_idle()
		input_vector += left
	if Input.is_action_pressed("Right"):
		if canShoot and (Global.mg1 or Global.mg2):
			state = States.WALKING
		else:
			choose_idle()
		input_vector += right
	if Input.is_action_just_released("Run"):
		$Timer.start()
		await $Timer.timeout
		canShoot = true
	
	if input_vector.length()>0:
		if Input.is_action_pressed("Run"):
			canShoot = false
			input_vector = input_vector.normalized() * (SPEED * 2)
			state = States.RUNNING
		else:
			input_vector = input_vector.normalized() * SPEED
	else:
		choose_idle()
		
		
	velocity = velocity.lerp(input_vector, 0.1)
	move_and_slide()

	if Input.is_action_pressed("Shoot") and canShoot:
		canShoot = false
		shootSequence()
	if Input.is_action_just_pressed("reload") and not reloading:
		canShoot = false
		reloading = true
		reload()
		
	if hitbox:
		hitbox = false
		take_dmg()
		#$HUD/Health.points[1].x -= dmg_tkn







#new_state: int
func set_state() -> void:
	if state == States.IDLE:
		$Sprite2D.visible = true
		$gunz.visible = false
		$run.visible = false
		$AnimationPlayer.play("idle")
	elif state == States.WALKING:
		$Sprite2D.visible = true
		$gunz.visible = false
		$run.visible = false
		$AnimationPlayer.play("walk")
	elif state == States.RUNNING:
		$Sprite2D.visible = false
		$gunz.visible = false
		$run.visible = true
		$AnimationPlayer.play("run")
	elif state == States.GUN:
		$Sprite2D.visible = false
		$gunz.visible = true
		$run.visible = false
		$AnimationPlayer.play("aim_gun")
	elif state == States.MP5:
		$Sprite2D.visible = false
		$gunz.visible = true
		$run.visible = false
		$AnimationPlayer.play("aim_mp5")
	elif state == States.M16:
		$Sprite2D.visible = false
		$gunz.visible = true
		$run.visible = false
		$AnimationPlayer.play("aim_m16")
	elif state == States.SHTGUN:
		$Sprite2D.visible = false
		$gunz.visible = true
		$run.visible = false
		$AnimationPlayer.play("aim_shtgn")

func choose_idle():
	if Global.mg1:
		state = States.GUN
	elif Global.mg2:
		state = States.MP5
	elif Global.mg3:
		state = States.M16
	elif Global.mg4:
		state = States.SHTGUN
	else:
		state = States.IDLE




func reload():
	var max_mag = Mag_Capacity[Global.current_weapon]
	Global.mag = c_weapon_amm()
	Global.total = c_weapon()
	
	var needed = max_mag - Global.mag
	var available = min(needed, Global.total)
	
	if available > 0:
		
		if Global.current_weapon == 4:
			reload_shtgn.play()
		else:
			reload_sound.play()
		$Reload_time.start()
		await $Reload_time.timeout
		canShoot = true
		Global.mag = set_current_mag(Global.mag + available)
		Global.total = set_current_total_ammo(Global.total - available)
	reloading = false









func set_current_mag(value):
	match Global.current_weapon:
		1: Global.mg_mag1 = value
		2: Global.mg_mag2 = value
		3: Global.mg_mag3 = value
		4: Global.mg_mag4 = value
	var test = value
	Global.change = true
	return test










func set_current_total_ammo(value):
	match Global.current_weapon:
		1, 2: Global.mg_amm12 = value
		3: Global.mg_amm3 = value
		4: Global.mg_amm4 = value
	var test = value
	return test













func shootSequence():
	if Input.is_action_pressed("Shoot"): #and bulletCount < maxBullets:
		if Global.mag > 0:
			Global.mag -= 1
			shoot()
			Global.change = true
			#$AudioStreamPlayer.play()
			#bulletCount += 1
			if Global.mg1:
				Global.mg_mag1 = Global.mag
				$AnimationPlayer.play("aim_gun")
				$Hg_fr.start()
				await $Hg_fr.timeout
				shootSequence()
			elif Global.mg2:
				Global.mg_mag2 = Global.mag
				$Mp5_fr.start()
				await $Mp5_fr.timeout
				shootSequence()
			elif Global.mg3:
				Global.mg_mag3 = Global.mag
				$M16_fr.start()
				await $M16_fr.timeout
				shootSequence()
			elif Global.mg4:
				Global.mg_mag4 = Global.mag
				$Shotgun_fr.start()
				await $Shotgun_fr.timeout
				shootSequence()
		else:
			print("Reload!")
			canShoot = true
		#Al entrar, se va acumulando el contador, usando nuestra función para disparar (utilizando el nodo) y empezando el timer para controlar cada disparo
	else:
		$Timer.start()
		await $Timer.timeout
		canShoot = true
		#Cuando se llena el contador, volveremos arriba a repetir el mismo ciclo










func c_weapon():
	if Input.is_action_just_pressed("mg3"):
		Global.mg1 = false
		Global.mg2 = false
		Global.mg3 = true
		Global.mg4 = false
		Global.current_weapon = 3
		cweapon.play()
		Global.change = true
		#shoot_sound = m16
		return Global.mg_amm3
	elif Input.is_action_just_pressed("mg2"):
		Global.mg1 = false
		Global.mg2 = true
		Global.mg3 = false
		Global.mg4 = false
		Global.current_weapon = 2
		cweapon.play()
		Global.change = true
		#shoot_sound = mp5
		return Global.mg_amm12
	elif Input.is_action_just_pressed("mg4"):
		Global.mg1 = false
		Global.mg2 = false
		Global.mg3 = false
		Global.mg4 = true
		Global.current_weapon = 4
		cweapon.play()
		Global.change = true
		#shoot_sound = hgun
		return Global.mg_amm4
	elif Input.is_action_just_pressed("mg1") or Global.mg1:
		Global.mg1 = true
		Global.mg2 = false
		Global.mg3 = false
		Global.mg4 = false
		Global.current_weapon = 1
		Global.change = true
		#shoot_sound = hgun
		return Global.mg_amm12
	else:
		return Global.total










func c_weapon_amm():
	if Input.is_action_just_pressed("mg3"):
		return Global.mg_mag3
	elif Input.is_action_just_pressed("mg2"):
		return Global.mg_mag2
	elif Input.is_action_just_pressed("mg1") or Global.mg1:
		return Global.mg_mag1
	elif Input.is_action_just_pressed("mg4"):
		return Global.mg_mag4
	else:
		return Global.mag





func c_dmg():
	if Global.mg1:
		dmg = 50
	elif Global.mg2:
		dmg = 45
	elif Global.mg3:
		dmg = 100
	elif Global.mg4:
		dmg = 60




func look_at_mouse():
	var mouse_pos = get_global_mouse_position()
	look_at(mouse_pos)
	#get_node("CollisionShape2D").look_at(mouse_pos)
	#get_node("Area2D/CollisionShape2D").look_at(mouse_pos)
	#get_node("Sprite2D").look_at(mouse_pos)
	#get_node("gunz").look_at(mouse_pos)
	#get_node("run").look_at(mouse_pos)
	
func shoot():
	# EMITIR SEÑAL DE DISPARO
	shot_fired.emit()
	#shoot_sound.play()
	var newBullet = bullet.instantiate()
	var direction = (get_global_mouse_position() - $Sprite2D/SpawnPoint.global_position)
	newBullet.position = $Sprite2D/SpawnPoint.global_position
	newBullet.rotation = direction.angle()
	#newBullet.rotation = $Sprite2D/SpawnPoint.rotation
	newBullet.velocity = get_global_mouse_position() - newBullet.position
	get_parent().add_child(newBullet)
	if Global.mg4:
		var newSpray = Spray_Shtgn.instantiate()
		var newSpray1 = Spray_Shtgn.instantiate()
		var newSpray2 = Spray_Shtgn.instantiate()
		var newSpray3 = Spray_Shtgn.instantiate()
		var direction2 = (get_global_mouse_position() - $Sprite2D/SpawnPoint2.global_position)
		var direction3 = (get_global_mouse_position() - $Sprite2D/SpawnPoint3.global_position)
		var direction4 = (get_global_mouse_position() - $Sprite2D/SpawnPoint4.global_position)
		var direction5 = (get_global_mouse_position() - $Sprite2D/SpawnPoint5.global_position)
		newSpray.position = $Sprite2D/SpawnPoint2.global_position
		newSpray1.position = $Sprite2D/SpawnPoint3.global_position
		newSpray2.position = $Sprite2D/SpawnPoint4.global_position
		newSpray3.position = $Sprite2D/SpawnPoint5.global_position
		newSpray.rotation = direction2.angle()
		newSpray1.rotation = direction3.angle()
		newSpray2.rotation = direction4.angle()
		newSpray3.rotation = direction5.angle()
		newSpray.velocity = get_global_mouse_position() - newSpray.position
		newSpray1.velocity = get_global_mouse_position() - newSpray1.position
		newSpray2.velocity = get_global_mouse_position() - newSpray2.position
		newSpray3.velocity = get_global_mouse_position() - newSpray3.position
		get_parent().add_child(newSpray)
		get_parent().add_child(newSpray1)
		get_parent().add_child(newSpray2)
		get_parent().add_child(newSpray3)
	
	
