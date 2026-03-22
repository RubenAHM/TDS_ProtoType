extends CharacterBody2D

@export var angle: float
@export var length: float
@export var direction = Vector2.RIGHT
@onready var target = get_tree().get_first_node_in_group("Player")

const SPEED = 50.0
var half
@onready var nav = $NavigationAgent2D
func _ready():
	half = deg_to_rad(angle / 2)

func _draw():
	var left_dir = direction.rotated(-half) * length
	var right_dir = direction.rotated(half) * length
	
	draw_line(Vector2.ZERO, left_dir, Color.YELLOW, 5.0)
	draw_line(Vector2.ZERO, right_dir, Color.YELLOW, 5.0)

func _physics_process(delta: float) -> void:
	var direction = to_local(nav.get_next_path_position()).normalized()
	velocity = direction * SPEED
	move_and_slide()



func _on_timer_timeout() -> void:
	nav.target_position = target.global_position
