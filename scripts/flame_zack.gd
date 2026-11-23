extends CharacterBody2D

const DAMAGE = 50
const LIFE_TIME = 5.0
const DAMAGE_INTERVAL = 0.1

@onready var hitbox_area = $HitBoxArea
@onready var animation_player = $AnimationPlayer

var bodies_in_area: Array = []
var damage_timer: float = 0.0

func _ready() -> void:
	if animation_player:
		animation_player.play("flames")
	if hitbox_area:
		hitbox_area.monitoring = true
		hitbox_area.monitorable = true
		hitbox_area.body_entered.connect(_on_body_entered)
		hitbox_area.body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	damage_timer += delta
	if damage_timer >= DAMAGE_INTERVAL:
		damage_timer = 0.0
		_apply_damage_to_bodies()

func _on_body_entered(body: Node2D) -> void:
	if body == self or body.is_in_group("Player"):
		return
	if (body.is_in_group("Enemy") or body.is_in_group("Soldier") or body.is_in_group("Enemyz")) and not bodies_in_area.has(body):
		bodies_in_area.append(body)

func _on_body_exited(body: Node2D) -> void:
	if bodies_in_area.has(body):
		bodies_in_area.erase(body)

func _apply_damage_to_bodies() -> void:
	var to_clean: Array = []
	for body in bodies_in_area:
		if not is_instance_valid(body):
			to_clean.append(body)
			continue
		if body.has_method("take_damage_fire"):
			body.take_damage_fire(DAMAGE)
		elif body.has_method("take_damage"):
			body.take_damage(DAMAGE)
	for invalid_body in to_clean:
		bodies_in_area.erase(invalid_body)
